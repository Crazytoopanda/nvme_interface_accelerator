// SPDX-License-Identifier: GPL-2.0
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/idr.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/kthread.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/version.h>
#include <linux/wait.h>
#include <linux/jiffies.h>

#include "nvme_fw_regs.h"

#ifndef NVME_FW_DEBUG
#define NVME_FW_DEBUG 0
#endif

static bool debug = NVME_FW_DEBUG;
module_param(debug, bool, 0644);
MODULE_PARM_DESC(debug, "enable verbose nvme_fw driver logs");

static int target_function = NVME_FW_PCI_FUNCTION;
module_param(target_function, int, 0644);
MODULE_PARM_DESC(target_function, "PCI function to bind, default 1; set -1 to allow any");

static bool use_msi;
module_param(use_msi, bool, 0644);
MODULE_PARM_DESC(use_msi, "allocate/request PF1 MSI during probe");

static bool enable_busmaster;
module_param(enable_busmaster, bool, 0644);
MODULE_PARM_DESC(enable_busmaster, "set PCI bus master during probe");

static bool probe_check_magic;
module_param(probe_check_magic, bool, 0644);
MODULE_PARM_DESC(probe_check_magic, "read BAR2 status/magic registers during probe");

static int probe_test_level;
module_param(probe_test_level, int, 0644);
MODULE_PARM_DESC(probe_test_level, "BAR2 probe test: 0 none, 1 local debug window, 2 s0 status regs, 3 DMA ring regs");

static bool auto_enable_pf1_msi;
module_param(auto_enable_pf1_msi, bool, 0644);
MODULE_PARM_DESC(auto_enable_pf1_msi, "enable PF1 DMA-done MSI during probe");

static bool auto_enable_pf0_msi;
module_param(auto_enable_pf0_msi, bool, 0644);
MODULE_PARM_DESC(auto_enable_pf0_msi, "enable PF0 manual MSI trigger register during probe");

static ushort msi_threshold = 1;
module_param(msi_threshold, ushort, 0644);
MODULE_PARM_DESC(msi_threshold, "PF1 DMA-done MSI completion threshold");


static bool run_firmware = true;
module_param(run_firmware, bool, 0644);
MODULE_PARM_DESC(run_firmware, "run firmware emulation in the PF1 kernel driver");

static uint fw_poll_us = 1;
module_param(fw_poll_us, uint, 0644);
MODULE_PARM_DESC(fw_poll_us, "firmware worker idle poll interval in microseconds");

static bool fw_enable_pf0_msi = true;
module_param(fw_enable_pf0_msi, bool, 0644);
MODULE_PARM_DESC(fw_enable_pf0_msi, "firmware worker triggers PF0 MSI after completions");

static bool fw_enable_dma_data = true;
module_param(fw_enable_dma_data, bool, 0644);
MODULE_PARM_DESC(fw_enable_dma_data, "firmware worker uses DMA to fill admin data buffers");

static bool fw_enable_io_dma_data = true;
module_param(fw_enable_io_dma_data, bool, 0644);
MODULE_PARM_DESC(fw_enable_io_dma_data, "firmware worker uses DMA to fill IO read buffers");

static bool fw_auto_io_cpl = true;
module_param(fw_auto_io_cpl, bool, 0644);
MODULE_PARM_DESC(fw_auto_io_cpl, "use hardware auto-DMA completion for IO commands");

static bool fw_verbose_io;
module_param(fw_verbose_io, bool, 0644);
MODULE_PARM_DESC(fw_verbose_io, "print per-command firmware worker details");

static unsigned long long fw_mgmt_dev_addr = 0x5000200000ull;
module_param(fw_mgmt_dev_addr, ullong, 0644);
MODULE_PARM_DESC(fw_mgmt_dev_addr, "card DDR address used as firmware DMA staging area");


#define ADMIN_DELETE_IO_SQ                  0x00
#define ADMIN_CREATE_IO_SQ                  0x01
#define ADMIN_GET_LOG_PAGE                  0x02
#define ADMIN_DELETE_IO_CQ                  0x04
#define ADMIN_CREATE_IO_CQ                  0x05
#define ADMIN_IDENTIFY                      0x06
#define ADMIN_ABORT                         0x08
#define ADMIN_SET_FEATURES                  0x09
#define ADMIN_GET_FEATURES                  0x0a
#define ADMIN_ASYNC_EVENT_REQUEST           0x0c
#define ADMIN_KEEP_ALIVE                    0x18
#define ADMIN_FORMAT_NVM                    0x80
#define ADMIN_VENDOR_LIBNVM                 0xc0

#define IO_NVM_FLUSH                        0x00
#define IO_NVM_WRITE                        0x01
#define IO_NVM_READ                         0x02

#define FEAT_ARBITRATION                    0x01
#define FEAT_POWER_MANAGEMENT               0x02
#define FEAT_LBA_RANGE_TYPE                 0x03
#define FEAT_TEMPERATURE_THRESHOLD          0x04
#define FEAT_VOLATILE_WRITE_CACHE           0x06
#define FEAT_NUMBER_OF_QUEUES               0x07
#define FEAT_INTERRUPT_COALESCING           0x08
#define FEAT_ASYNC_EVENT_CONFIG             0x0b
#define FEAT_POWER_STATE_TRANSITION         0x0c
#define FEAT_TIMESTAMP                      0x0e
#define FEAT_SOFTWARE_PROGRESS_MARKER       0x80

#define NVME_STATUS_CC_EN                   0x00000001u
#define NVME_STATUS_CC_SHN_MASK             0x00000006u
#define NVME_STATUS_CC_SHN_SHIFT            1
#define NVME_STATUS_CSTS_RDY                0x00000010u
#define NVME_STATUS_CSTS_SHST_SHIFT         5

#define FW_SHUTDOWN_REARM_MS                100u
#define FW_DMA_WAIT_TIMEOUT_MS              2000u
#define FW_NVME_STORAGE_BYTES               (63ull * 1024ull * 1024ull * 1024ull)
#define FW_NVME_BLOCK_BYTES                 4096ull
#define FW_NVME_BLOCKS                      (FW_NVME_STORAGE_BYTES / FW_NVME_BLOCK_BYTES)

#define SCT_GENERIC_COMMAND_STATUS          0u
#define SCT_COMMAND_SPECIFIC_STATUS         1u
#define SC_SUCCESSFUL_COMPLETION            0x00u
#define SC_INVALID_COMMAND_OPCODE           0x01u
#define SC_INVALID_FIELD_IN_COMMAND         0x02u
#define SC_INTERNAL_DEVICE_ERROR            0x06u
#define SC_INVALID_QUEUE_IDENTIFIER         0x01u
#define SC_INVALID_LOG_PAGE                 0x09u

enum fw_task_state {
	FW_TASK_IDLE = 0,
	FW_TASK_WAIT_CC_EN,
	FW_TASK_RUNNING,
	FW_TASK_WAIT_RESET,
};

#define fw_dbg(fw, fmt, ...) \
	do { \
		if (debug) \
			dev_info(&(fw)->pdev->dev, "nvme_fw: " fmt, ##__VA_ARGS__); \
	} while (0)

struct nvme_fw_dev {
	struct pci_dev *pdev;
	void __iomem *bar2;
	resource_size_t bar2_start;
	resource_size_t bar2_len;
	struct cdev cdev;
	struct device *chardev;
	int minor;
	int irq;
	atomic_t irq_count;
	wait_queue_head_t waitq;
	struct mutex ring_lock;
	struct mutex stage_lock;
	void *stage_virt;
	dma_addr_t stage_dma;
	u32 stage_size;
	u32 last_pid_done;
	u32 last_done_count;
	struct task_struct *fw_thread;
	u32 iosq_alloc;
	u32 iocq_alloc;
	u32 io_sq_cq_idx[NVME_FW_MAX_IO_QUEUES];
	u32 io_cq_irq_vector[NVME_FW_MAX_IO_QUEUES];
	u32 pf0_msi_vector;
	u32 cache_en;
	bool observed_disabled;
	bool last_status_valid;
	u32 last_cc_en;
	u32 last_cc_shn;
	enum fw_task_state task;
	unsigned long wait_reset_deadline;
	bool zero_page_ready;
};

static dev_t nvme_fw_devt;
static struct class *nvme_fw_class;
static DEFINE_IDA(nvme_fw_minors);

static inline u32 fw_readl(struct nvme_fw_dev *fw, u32 off)
{
	u32 val = ioread32(fw->bar2 + off);

	fw_dbg(fw, "read32 off=0x%05x val=0x%08x\n", off, val);
	return val;
}

static inline void fw_writel(struct nvme_fw_dev *fw, u32 off, u32 val)
{
	fw_dbg(fw, "write32 off=0x%05x val=0x%08x\n", off, val);
	iowrite32(val, fw->bar2 + off);
}

static inline u32 fw_ctrl_off(u32 reg)
{
	return NVME_FW_CTRL_BASE + reg;
}

static inline u32 fw_ring_off(u32 reg)
{
	return NVME_FW_RING_CTRL_BASE + reg;
}

static inline u32 fw_desc_off(u8 index, u32 dword_off)
{
	return NVME_FW_RING_DESC_BASE + index * NVME_FW_RING_DESC_SIZE + dword_off;
}

static int fw_check_range(u32 off, u32 len)
{
	if ((off & 0x3) || len > NVME_FW_BAR2_SIZE || off > NVME_FW_BAR2_SIZE - len)
		return -EINVAL;
	return 0;
}

static inline bool fw_pid_reached(u32 done_pid, u32 target_pid)
{
	return (s32)(done_pid - target_pid) >= 0;
}

static int fw_ensure_stage(struct nvme_fw_dev *fw)
{
	int ret;

	if (fw->stage_virt)
		return 0;

	mutex_lock(&fw->stage_lock);
	if (fw->stage_virt) {
		mutex_unlock(&fw->stage_lock);
		return 0;
	}

	ret = dma_set_mask_and_coherent(&fw->pdev->dev, DMA_BIT_MASK(64));
	if (ret)
		ret = dma_set_mask_and_coherent(&fw->pdev->dev, DMA_BIT_MASK(32));
	if (ret) {
		mutex_unlock(&fw->stage_lock);
		return ret;
	}

	fw->stage_size = NVME_FW_STAGE_SIZE;
	fw->stage_virt = dma_alloc_coherent(&fw->pdev->dev, fw->stage_size,
					       &fw->stage_dma, GFP_KERNEL);
	if (!fw->stage_virt) {
		fw->stage_size = 0;
		mutex_unlock(&fw->stage_lock);
		return -ENOMEM;
	}
	memset(fw->stage_virt, 0, fw->stage_size);
	dev_info(&fw->pdev->dev, "allocated PF1 stage buffer dma=%pad size=0x%x\n",
		 &fw->stage_dma, fw->stage_size);
	mutex_unlock(&fw->stage_lock);
	return 0;
}

static u32 fw_msi_ctrl_word(const struct nvme_fw_msi_config *cfg)
{
	u32 vector_onehot;

	vector_onehot = 1u << cfg->vector;
	return (cfg->enable ? 1u : 0u) | (vector_onehot << 8);
}

static int fw_validate_msi_config(const struct nvme_fw_msi_config *cfg)
{
	if (cfg->vector > 8)
		return -EINVAL;
	return 0;
}

static void fw_config_pf1_msi(struct nvme_fw_dev *fw, bool enable,
			      u8 vector, u16 threshold)
{
	struct nvme_fw_msi_config cfg = {
		.enable = enable,
		.vector = vector,
		.threshold = threshold ? threshold : 1,
	};

	fw_writel(fw, fw_ring_off(NVME_FW_RING_PF1_MSI_CTRL), fw_msi_ctrl_word(&cfg));
	fw_writel(fw, fw_ring_off(NVME_FW_RING_PF1_MSI_THRESHOLD), cfg.threshold);
}

static void fw_config_pf0_msi(struct nvme_fw_dev *fw, bool enable, u8 vector)
{
	struct nvme_fw_msi_config cfg = {
		.enable = enable,
		.vector = vector,
	};

	fw_writel(fw, fw_ring_off(NVME_FW_RING_PF0_MSI_CTRL), fw_msi_ctrl_word(&cfg));
}

static void fw_probe_read_test(struct nvme_fw_dev *fw, const char *name, u32 off)
{
	u32 val;

	dev_info(&fw->pdev->dev, "BAR2 probe test: about to read %-18s off=0x%05x\n",
		 name, off);
	val = fw_readl(fw, off);
	dev_info(&fw->pdev->dev, "BAR2 probe test: read %-18s off=0x%05x val=0x%08x\n",
		 name, off, val);
}

static void fw_probe_bar2_test(struct nvme_fw_dev *fw)
{
	int level = probe_test_level;

	if (probe_check_magic && level < 3)
		level = 3;
	if (level <= 0)
		return;

	dev_info(&fw->pdev->dev, "BAR2 probe test: begin level=%d\n", level);
	fw_probe_read_test(fw, "local_debug_magic", NVME_FW_BAR2_DEBUG_MAGIC);
	fw_probe_read_test(fw, "local_debug_counts", NVME_FW_BAR2_DEBUG_COUNTS);
	fw_probe_read_test(fw, "local_last_addr", NVME_FW_BAR2_DEBUG_LAST_ADDR);
	fw_probe_read_test(fw, "local_req_count", NVME_FW_BAR2_DEBUG_REQ_COUNT);

	if (level >= 2) {
		fw_probe_read_test(fw, "nvme_status", fw_ctrl_off(NVME_FW_REG_NVME_STATUS));
		fw_probe_read_test(fw, "admin_queue", fw_ctrl_off(NVME_FW_REG_ADMIN_QUEUE));
		fw_probe_read_test(fw, "cmd_fifo", fw_ctrl_off(NVME_FW_REG_CMD_FIFO));
	}

	if (level >= 3) {
		fw_probe_read_test(fw, "ring_magic", fw_ring_off(NVME_FW_RING_MAGIC));
		fw_probe_read_test(fw, "ring_status", fw_ring_off(NVME_FW_RING_STATUS));
		fw_probe_read_test(fw, "ring_info", fw_ring_off(NVME_FW_RING_INFO));
		fw_probe_read_test(fw, "pid_done", fw_ring_off(NVME_FW_RING_PID_DONE));
		fw_probe_read_test(fw, "done_count", fw_ring_off(NVME_FW_RING_DONE_COUNT));
	}
	dev_info(&fw->pdev->dev, "BAR2 probe test: end level=%d\n", level);
}

static void fw_read_sqe(struct nvme_fw_dev *fw, u16 slot, u32 dword[16])
{
	u32 off = NVME_FW_SQE_BASE + slot * NVME_FW_SQE_BYTES;
	int i;

	for (i = 0; i < 16; i++)
		dword[i] = fw_readl(fw, off + i * sizeof(u32));
}

static void fw_fetch_cmd(struct nvme_fw_dev *fw, struct nvme_fw_cmd *cmd)
{
	u32 reg = fw_readl(fw, fw_ctrl_off(NVME_FW_REG_CMD_FIFO));

	memset(cmd, 0, sizeof(*cmd));
	cmd->valid = (reg >> 31) & 0x1;
	if (!cmd->valid)
		return;

	cmd->qid = reg & 0xf;
	cmd->slot = (reg >> 5) & (NVME_FW_MAX_CMD_SLOTS - 1);
	cmd->seq = (reg >> 16) & 0xff;
	fw_read_sqe(fw, cmd->slot, cmd->dword);
}

static int fw_complete(struct nvme_fw_dev *fw, const struct nvme_fw_cpl *cpl)
{
	u32 d0 = 0;
	u32 d1 = cpl->specific;
	u32 d2;

	if (cpl->type > NVME_FW_CPL_SLOT_RELEASE ||
	    cpl->slot >= NVME_FW_MAX_CMD_SLOTS ||
	    cpl->sqid > 0xf)
		return -EINVAL;

	d2 = (cpl->slot & (NVME_FW_MAX_CMD_SLOTS - 1)) |
	     ((u32)cpl->type << 14) |
	     ((u32)cpl->status << 16);

	if (cpl->type == NVME_FW_CPL_ONLY) {
		d0 = (cpl->cid & 0xffffu) | ((u32)(cpl->sqid & 0xfu) << 16);
		fw_writel(fw, fw_ctrl_off(NVME_FW_REG_CPL_FIFO) + 0, d0);
		fw_writel(fw, fw_ctrl_off(NVME_FW_REG_CPL_FIFO) + 4, d1);
		fw_writel(fw, fw_ctrl_off(NVME_FW_REG_CPL_FIFO) + 8, d2);
	} else if (cpl->type == NVME_FW_CPL_AUTO) {
		fw_writel(fw, fw_ctrl_off(NVME_FW_REG_CPL_FIFO) + 4, d1);
		fw_writel(fw, fw_ctrl_off(NVME_FW_REG_CPL_FIFO) + 8, d2);
	} else {
		fw_writel(fw, fw_ctrl_off(NVME_FW_REG_CPL_FIFO) + 8, d2);
	}

	fw_writel(fw, fw_ctrl_off(NVME_FW_REG_CPL_FIFO_TRIG), 1);
	return 0;
}

static int fw_validate_dma_desc(const struct nvme_fw_dma_desc *d)
{
	if (d->slot >= NVME_FW_MAX_CMD_SLOTS ||
	    d->cmd_4k_offset > NVME_FW_DMA_4K_OFFSET_MASK ||
	    d->direction > 1 || d->type > 1 || d->auto_completion > 1 ||
	    d->len == 0 || d->len > 0x1000 || (d->len & 0x3) ||
	    (d->dev_addr & 0x3) || (d->pcie_addr & 0x3))
		return -EINVAL;
	return 0;
}

static void fw_write_dma_desc(struct nvme_fw_dev *fw, u8 index,
			      const struct nvme_fw_dma_desc *d)
{
	u32 ctrl;

	ctrl = ((u32)(d->type & 1) << NVME_FW_DMA_TYPE_SHIFT) |
	       ((u32)(d->direction & 1) << NVME_FW_DMA_DIR_SHIFT) |
	       ((u32)(d->cmd_4k_offset & NVME_FW_DMA_4K_OFFSET_MASK) << NVME_FW_DMA_4K_OFFSET_SHIFT) |
	       ((u32)(d->auto_completion & 1) << NVME_FW_DMA_AUTO_CPL_SHIFT) |
	       (d->len & NVME_FW_DMA_LEN_MASK);

	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW0), lower_32_bits(d->dev_addr) & ~0x3u);
	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW1), upper_32_bits(d->dev_addr));
	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW2), lower_32_bits(d->pcie_addr) & ~0x3u);
	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW3), upper_32_bits(d->pcie_addr));
	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW4), ctrl);
	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW5), d->slot);
	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW6), d->cid);
	fw_writel(fw, fw_desc_off(index, NVME_FW_RING_DESC_DW7), 0);
}

static int fw_submit_batch(struct nvme_fw_dev *fw, const struct nvme_fw_dma_batch *batch)
{
	u32 status;
	u32 info;
	u8 tail;
	u8 used;
	u32 i;
	int ret = 0;

	if (!batch->count || batch->count > NVME_FW_MAX_BATCH)
		return -EINVAL;

	for (i = 0; i < batch->count; i++) {
		ret = fw_validate_dma_desc(&batch->desc[i]);
		if (ret)
			return ret;
	}

	pci_set_master(fw->pdev);
	mutex_lock(&fw->ring_lock);
	status = fw_readl(fw, fw_ring_off(NVME_FW_RING_STATUS));
	info = fw_readl(fw, fw_ring_off(NVME_FW_RING_INFO));
	tail = (status & NVME_FW_RING_STATUS_TAIL_MASK) >> 8;
	used = info & NVME_FW_RING_INFO_USED_MASK;

	if ((status & NVME_FW_RING_STATUS_PID_FULL) || used + batch->count >= NVME_FW_RING_DEPTH) {
		ret = -ENOSPC;
		goto out;
	}

	for (i = 0; i < batch->count; i++)
		fw_write_dma_desc(fw, (u8)(tail + i), &batch->desc[i]);

	wmb();
	fw_writel(fw, fw_ring_off(NVME_FW_RING_MAGIC), (u8)(tail + batch->count));
	fw_dbg(fw, "submitted %u DMA descriptors tail %u->%u\n",
	       batch->count, tail, (u8)(tail + batch->count));
out:
	mutex_unlock(&fw->ring_lock);
	return ret;
}

static void fw_get_ring_status(struct nvme_fw_dev *fw, struct nvme_fw_ring_status *st)
{
	memset(st, 0, sizeof(*st));
	st->status = fw_readl(fw, fw_ring_off(NVME_FW_RING_STATUS));
	st->info = fw_readl(fw, fw_ring_off(NVME_FW_RING_INFO));
	st->submit_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_SUBMIT_COUNT));
	st->doorbell_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_DOORBELL_COUNT));
	st->backpressure_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_BACKPRESSURE));
	st->pid_submit = fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_SUBMIT));
	st->pid_done = fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE));
	st->last_submit = fw_readl(fw, fw_ring_off(NVME_FW_RING_LAST_SUBMIT));
	st->last_done = fw_readl(fw, fw_ring_off(NVME_FW_RING_LAST_DONE));
	st->pf1_msi_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_PF1_MSI_COUNT));
	st->done_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_DONE_COUNT));
	st->inflight = fw_readl(fw, fw_ring_off(NVME_FW_RING_INFLIGHT));
	st->done_pending = fw_readl(fw, fw_ring_off(NVME_FW_RING_DONE_PENDING));
	st->pf0_msi_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_PF0_MSI_COUNT));
}


static u16 fw_nvme_status_word(u32 sct, u32 sc, u32 dnr)
{
	return (u16)(((sc & 0xffu) << 1) |
		     ((sct & 0x7u) << 9) |
		     ((dnr & 0x1u) << 15));
}

static u16 fw_cpl_success(void)
{
	return fw_nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_SUCCESSFUL_COMPLETION, 0);
}

static u16 fw_cpl_invalid_opcode(void)
{
	return fw_nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_INVALID_COMMAND_OPCODE, 1);
}

static u16 fw_cpl_invalid_field(void)
{
	return fw_nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_INVALID_FIELD_IN_COMMAND, 1);
}

static u16 fw_cpl_internal_error(void)
{
	return fw_nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_INTERNAL_DEVICE_ERROR, 1);
}

static u16 fw_cpl_invalid_qid(void)
{
	return fw_nvme_status_word(SCT_COMMAND_SPECIFIC_STATUS,
				       SC_INVALID_QUEUE_IDENTIFIER, 1);
}

static u16 fw_cpl_invalid_log_page(void)
{
	return fw_nvme_status_word(SCT_COMMAND_SPECIFIC_STATUS,
				       SC_INVALID_LOG_PAGE, 1);
}

static u16 fw_cmd_cid(const struct nvme_fw_cmd *cmd)
{
	return (cmd->dword[0] >> 16) & 0xffffu;
}

static u8 fw_cmd_opcode(const struct nvme_fw_cmd *cmd)
{
	return cmd->dword[0] & 0xffu;
}

static u64 fw_cmd_prp1(const struct nvme_fw_cmd *cmd)
{
	return ((u64)cmd->dword[7] << 32) | cmd->dword[6];
}

static u64 fw_cmd_prp2(const struct nvme_fw_cmd *cmd)
{
	return ((u64)cmd->dword[9] << 32) | cmd->dword[8];
}

static void fw_put_le16(u8 *buf, size_t off, u16 v)
{
	buf[off] = v & 0xffu;
	buf[off + 1] = (v >> 8) & 0xffu;
}

static void fw_put_le32(u8 *buf, size_t off, u32 v)
{
	fw_put_le16(buf, off, v & 0xffffu);
	fw_put_le16(buf, off + 2, v >> 16);
}

static void fw_put_le64(u8 *buf, size_t off, u64 v)
{
	fw_put_le32(buf, off, v & 0xffffffffu);
	fw_put_le32(buf, off + 4, v >> 32);
}

static void fw_put_ascii_padded(u8 *buf, size_t off, size_t len, const char *s)
{
	size_t i;

	memset(buf + off, ' ', len);
	for (i = 0; i < len && s[i]; i++)
		buf[off + i] = s[i];
}

static void fw_fill_identify_controller(u8 *buf)
{
	memset(buf, 0, NVME_FW_STAGE_SIZE);
	fw_put_le16(buf, 0, 0x1edc);
	fw_put_le16(buf, 2, 0x1edc);
	fw_put_ascii_padded(buf, 4, 20, "S970SIM0001");
	fw_put_ascii_padded(buf, 24, 40, "Samsung SSD 970 PRO");
	fw_put_ascii_padded(buf, 64, 8, "SIM9701");
	buf[73] = 0xe4;
	buf[74] = 0xd2;
	buf[75] = 0x5c;
	buf[77] = 0x8;
	fw_put_le16(buf, 78, 0x9);
	fw_put_le64(buf, 280, FW_NVME_STORAGE_BYTES);
	buf[258] = 0x3;
	buf[259] = 0x3;
	buf[260] = 0x3;
	buf[262] = 0x8;
	buf[512] = 0x66;
	buf[513] = 0x44;
	fw_put_le32(buf, 516, 1);
	buf[525] = 0x1;
	fw_put_le16(buf, 2048, 0x09c4);
}

static void fw_fill_identify_namespace(u8 *buf)
{
	memset(buf, 0, NVME_FW_STAGE_SIZE);
	fw_put_le64(buf, 0, FW_NVME_BLOCKS);
	fw_put_le64(buf, 8, FW_NVME_BLOCKS);
	fw_put_le64(buf, 16, FW_NVME_BLOCKS);
	buf[25] = 0x0;
	buf[26] = 0x0;
	fw_put_le16(buf, 128, 0x0);
	buf[130] = 0x0c;
	buf[131] = 0x2;
}

static void fw_admin_success(u32 *specific, u16 *status)
{
	*specific = 0;
	*status = fw_cpl_success();
}

static int fw_set_status_fields(struct nvme_fw_dev *fw, u32 rdy, u32 shst)
{
	u32 value = ((shst & 0x3u) << NVME_STATUS_CSTS_SHST_SHIFT) |
		    (rdy ? NVME_STATUS_CSTS_RDY : 0u);

	fw_writel(fw, fw_ctrl_off(NVME_FW_REG_NVME_STATUS), value);
	return 0;
}

static int fw_set_csts_rdy(struct nvme_fw_dev *fw, u32 rdy)
{
	u32 status = fw_readl(fw, fw_ctrl_off(NVME_FW_REG_NVME_STATUS));
	u32 shst = (status >> NVME_STATUS_CSTS_SHST_SHIFT) & 0x3u;

	return fw_set_status_fields(fw, rdy, shst);
}

static int fw_set_csts_shst(struct nvme_fw_dev *fw, u32 shst)
{
	u32 status = fw_readl(fw, fw_ctrl_off(NVME_FW_REG_NVME_STATUS));
	u32 rdy = !!(status & NVME_STATUS_CSTS_RDY);

	return fw_set_status_fields(fw, rdy, shst);
}

static int fw_set_admin_queue(struct nvme_fw_dev *fw, u32 sq_valid,
			      u32 cq_valid, u32 cq_irq_en)
{
	u32 value = ((cq_irq_en & 1u) << 2) |
		    ((sq_valid & 1u) << 1) |
		    (cq_valid & 1u);

	fw_writel(fw, fw_ctrl_off(NVME_FW_REG_ADMIN_QUEUE), value);
	return 0;
}

static int fw_set_io_sq(struct nvme_fw_dev *fw, u32 idx, u32 valid,
			u32 cq_vector, u32 qsize, u64 pcie_base)
{
	u32 off = NVME_FW_REG_IO_SQ_BASE + idx * 8u;
	u32 hi = ((u32)(pcie_base >> 32) & 0xffffu) |
		 ((valid & 1u) << 16) |
		 ((cq_vector & 0xfu) << 17) |
		 ((qsize & 0xffu) << 24);

	fw_writel(fw, fw_ctrl_off(off), lower_32_bits(pcie_base));
	fw_writel(fw, fw_ctrl_off(off + 4u), hi);
	return 0;
}

static int fw_set_io_cq(struct nvme_fw_dev *fw, u32 idx, u32 valid,
			u32 irq_en, u32 irq_vector, u32 qsize, u64 pcie_base)
{
	u32 off = NVME_FW_REG_IO_CQ_BASE + idx * 8u;
	u32 hi = ((u32)(pcie_base >> 32) & 0xffffu) |
		 ((valid & 1u) << 16) |
		 ((irq_vector & 0x7u) << 17) |
		 ((irq_en & 1u) << 20) |
		 ((qsize & 0xffu) << 24);

	fw_writel(fw, fw_ctrl_off(off), lower_32_bits(pcie_base));
	fw_writel(fw, fw_ctrl_off(off + 4u), hi);
	return 0;
}

static int fw_clear_io_queues(struct nvme_fw_dev *fw)
{
	u32 qid;

	for (qid = 0; qid < NVME_FW_MAX_IO_QUEUES; qid++) {
		fw->io_sq_cq_idx[qid] = 0;
		fw->io_cq_irq_vector[qid] = 0;
		fw_set_io_cq(fw, qid, 0, 0, 0, 0, 0);
		fw_set_io_sq(fw, qid, 0, 0, 0, 0);
	}
	return 0;
}

static u32 fw_completion_msi_vector(struct nvme_fw_dev *fw, u32 sqid)
{
	u32 cq_idx;

	if (!sqid || sqid > NVME_FW_MAX_IO_QUEUES)
		return 0;
	cq_idx = fw->io_sq_cq_idx[sqid - 1u];
	if (cq_idx >= NVME_FW_MAX_IO_QUEUES)
		return 0;
	return fw->io_cq_irq_vector[cq_idx] & 0x7u;
}

static int fw_config_pf0_msi_vector(struct nvme_fw_dev *fw, u32 vector)
{
	vector &= 0x7u;
	if (!fw_enable_pf0_msi)
		return 0;
	if (fw->pf0_msi_vector == vector)
		return 0;
	fw_config_pf0_msi(fw, true, vector);
	fw->pf0_msi_vector = vector;
	return 0;
}

static int fw_post_completion(struct nvme_fw_dev *fw,
			      const struct nvme_fw_cpl *cpl,
			      bool notify_pf0, u32 vector)
{
	int ret;

	ret = fw_complete(fw, cpl);
	if (ret)
		return ret;
	if (notify_pf0 && fw_enable_pf0_msi) {
		ret = fw_config_pf0_msi_vector(fw, vector);
		if (ret)
			return ret;
		fw_writel(fw, fw_ring_off(NVME_FW_RING_PF0_MSI_COUNT), 1);
	}
	return 0;
}

static int fw_set_auto_cpl(struct nvme_fw_dev *fw,
			   const struct nvme_fw_cmd *cmd,
			   u32 specific, u16 status)
{
	struct nvme_fw_cpl cpl = {
		.type = NVME_FW_CPL_AUTO,
		.slot = cmd->slot,
		.specific = specific,
		.status = status,
	};

	return fw_post_completion(fw, &cpl, true,
				  fw_completion_msi_vector(fw, cmd->qid));
}

static int fw_set_slot_release(struct nvme_fw_dev *fw,
			       const struct nvme_fw_cmd *cmd)
{
	struct nvme_fw_cpl cpl = {
		.type = NVME_FW_CPL_SLOT_RELEASE,
		.slot = cmd->slot,
	};

	return fw_post_completion(fw, &cpl, false, 0);
}

static int fw_set_cpl(struct nvme_fw_dev *fw, const struct nvme_fw_cmd *cmd,
		      u32 specific, u16 status)
{
	struct nvme_fw_cpl cpl = {
		.type = NVME_FW_CPL_ONLY,
		.sqid = cmd->qid,
		.cid = fw_cmd_cid(cmd),
		.slot = cmd->slot,
		.specific = specific,
		.status = status,
	};

	return fw_post_completion(fw, &cpl, true,
				  fw_completion_msi_vector(fw, cmd->qid));
}

static int fw_submit_batch_wait(struct nvme_fw_dev *fw,
				struct nvme_fw_dma_batch *batch)
{
	struct nvme_fw_ring_status st;
	u32 target_pid, done_pid;
	unsigned long deadline;
	int ret;

	if (!batch->count)
		return 0;
	fw_get_ring_status(fw, &st);
	target_pid = st.pid_submit + batch->count;
	ret = fw_submit_batch(fw, batch);
	if (ret)
		return ret;

	deadline = jiffies + msecs_to_jiffies(FW_DMA_WAIT_TIMEOUT_MS);
	do {
		done_pid = fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE));
		if (fw_pid_reached(done_pid, target_pid))
			return 0;
		if (fw->irq >= 0) {
			ret = wait_event_interruptible_timeout(fw->waitq,
				fw_pid_reached(fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE)), target_pid),
				msecs_to_jiffies(1));
			if (ret < 0)
				return ret;
		} else {
			usleep_range(50, 100);
		}
	} while (time_before(jiffies, deadline));

	return -ETIMEDOUT;
}


static int fw_submit_batch_nowait(struct nvme_fw_dev *fw,
				  struct nvme_fw_dma_batch *batch)
{
	if (!batch->count)
		return 0;
	return fw_submit_batch(fw, batch);
}

static int fw_dma_stage_to_card_at(struct nvme_fw_dev *fw, u64 dev_addr, u32 len)
{
	struct nvme_fw_dma_batch *batch;
	struct nvme_fw_dma_desc *d;
	int ret;

	batch = kzalloc(sizeof(*batch), GFP_KERNEL);
	if (!batch)
		return -ENOMEM;
	d = &batch->desc[0];
	batch->count = 1;
	d->type = NVME_FW_DMA_DIRECT_TYPE;
	d->direction = NVME_FW_DMA_RX_DIRECTION;
	d->len = len;
	d->dev_addr = dev_addr;
	d->pcie_addr = fw->stage_dma;
	ret = fw_submit_batch_wait(fw, batch);
	kfree(batch);
	return ret;
}

static int fw_dma_stage_to_card(struct nvme_fw_dev *fw, u32 len)
{
	return fw_dma_stage_to_card_at(fw, fw_mgmt_dev_addr, len);
}

static int fw_dma_card_to_prp_from(struct nvme_fw_dev *fw, u64 dev_addr,
				   u64 prp1, u64 prp2, u32 len)
{
	struct nvme_fw_dma_batch *batch;
	u32 first_len;
	int ret;

	if (!len || len > NVME_FW_STAGE_SIZE || (prp1 & 0x3ull) || (prp2 & 0x3ull))
		return -EINVAL;
	batch = kzalloc(sizeof(*batch), GFP_KERNEL);
	if (!batch)
		return -ENOMEM;

	first_len = 0x1000u - (u32)(prp1 & 0xfffu);
	if (first_len > len)
		first_len = len;

	batch->desc[0].type = NVME_FW_DMA_DIRECT_TYPE;
	batch->desc[0].direction = NVME_FW_DMA_TX_DIRECTION;
	batch->desc[0].len = first_len;
	batch->desc[0].dev_addr = dev_addr;
	batch->desc[0].pcie_addr = prp1;
	batch->count = 1;

	if (first_len < len) {
		batch->desc[1].type = NVME_FW_DMA_DIRECT_TYPE;
		batch->desc[1].direction = NVME_FW_DMA_TX_DIRECTION;
		batch->desc[1].len = len - first_len;
		batch->desc[1].dev_addr = dev_addr + first_len;
		batch->desc[1].pcie_addr = prp2;
		batch->count = 2;
	}
	ret = fw_submit_batch_wait(fw, batch);
	kfree(batch);
	return ret;
}


static int fw_submit_auto_io_dma(struct nvme_fw_dev *fw,
				 const struct nvme_fw_cmd *cmd,
				 u64 dev_addr, u32 len, bool tx)
{
	struct nvme_fw_dma_batch *batch;
	struct nvme_fw_dma_desc *d;
	int ret;

	if (!len || len > NVME_FW_STAGE_SIZE || (len & 0x3u))
		return -EINVAL;
	batch = kzalloc(sizeof(*batch), GFP_KERNEL);
	if (!batch)
		return -ENOMEM;

	d = &batch->desc[0];
	batch->count = 1;
	d->type = NVME_FW_DMA_AUTO_TYPE;
	d->direction = tx ? NVME_FW_DMA_TX_DIRECTION : NVME_FW_DMA_RX_DIRECTION;
	d->auto_completion = 1;
	d->slot = cmd->slot;
	d->cid = fw_cmd_cid(cmd);
	d->len = len;
	d->cmd_4k_offset = 0;
	d->dev_addr = dev_addr;
	d->pcie_addr = 0;
	ret = fw_submit_batch_nowait(fw, batch);
	kfree(batch);
	return ret;
}

static int fw_dma_card_to_prp(struct nvme_fw_dev *fw, u64 prp1, u64 prp2, u32 len)
{
	return fw_dma_card_to_prp_from(fw, fw_mgmt_dev_addr, prp1, prp2, len);
}

static int fw_stage_and_dma_to_prp(struct nvme_fw_dev *fw, u32 len,
				   u64 prp1, u64 prp2)
{
	int ret;

	ret = fw_dma_stage_to_card(fw, NVME_FW_STAGE_SIZE);
	if (ret)
		return ret;
	return fw_dma_card_to_prp(fw, prp1, prp2, len);
}

static int fw_ensure_zero_page(struct nvme_fw_dev *fw)
{
	int ret;

	if (fw->zero_page_ready)
		return 0;
	ret = fw_ensure_stage(fw);
	if (ret)
		return ret;
	mutex_lock(&fw->stage_lock);
	memset(fw->stage_virt, 0, NVME_FW_STAGE_SIZE);
	ret = fw_dma_stage_to_card_at(fw, fw_mgmt_dev_addr + NVME_FW_STAGE_SIZE,
					  NVME_FW_STAGE_SIZE);
	if (!ret)
		fw->zero_page_ready = true;
	mutex_unlock(&fw->stage_lock);
	return ret;
}

static u32 fw_set_num_of_queue(struct nvme_fw_dev *fw, u32 cdw11)
{
	u32 nsqr = cdw11 & 0xffffu;
	u32 ncqr = (cdw11 >> 16) & 0xffffu;

	fw->iosq_alloc = nsqr >= NVME_FW_MAX_IO_QUEUES ? NVME_FW_MAX_IO_QUEUES : nsqr + 1u;
	fw->iocq_alloc = ncqr >= NVME_FW_MAX_IO_QUEUES ? NVME_FW_MAX_IO_QUEUES : ncqr + 1u;
	return ((fw->iocq_alloc - 1u) << 16) | (fw->iosq_alloc - 1u);
}

static u32 fw_get_num_of_queue(struct nvme_fw_dev *fw)
{
	return ((fw->iocq_alloc - 1u) << 16) | (fw->iosq_alloc - 1u);
}

static int fw_handle_set_features(struct nvme_fw_dev *fw,
				  const struct nvme_fw_cmd *cmd,
				  u32 *specific, u16 *status)
{
	u32 fid = cmd->dword[10] & 0xffu;

	fw_admin_success(specific, status);
	switch (fid) {
	case FEAT_NUMBER_OF_QUEUES:
		*specific = fw_set_num_of_queue(fw, cmd->dword[11]);
		break;
	case FEAT_VOLATILE_WRITE_CACHE:
		fw->cache_en = cmd->dword[11] & 0x1u;
		break;
	case FEAT_INTERRUPT_COALESCING:
	case FEAT_ARBITRATION:
	case FEAT_ASYNC_EVENT_CONFIG:
	case FEAT_POWER_MANAGEMENT:
	case FEAT_TIMESTAMP:
	case FEAT_SOFTWARE_PROGRESS_MARKER:
		break;
	default:
		*status = fw_cpl_invalid_field();
		break;
	}
	return 0;
}

static int fw_handle_get_features(struct nvme_fw_dev *fw,
				  const struct nvme_fw_cmd *cmd,
				  u32 *specific, u16 *status)
{
	u32 fid = cmd->dword[10] & 0xffu;

	fw_admin_success(specific, status);
	switch (fid) {
	case FEAT_NUMBER_OF_QUEUES:
		*specific = fw_get_num_of_queue(fw);
		break;
	case FEAT_LBA_RANGE_TYPE:
		*status = fw_cpl_invalid_field();
		break;
	case FEAT_TEMPERATURE_THRESHOLD:
		*specific = cmd->dword[11];
		break;
	case FEAT_VOLATILE_WRITE_CACHE:
		*specific = fw->cache_en;
		break;
	case FEAT_POWER_MANAGEMENT:
	case FEAT_POWER_STATE_TRANSITION:
	case FEAT_SOFTWARE_PROGRESS_MARKER:
	case 0xd0:
		break;
	default:
		*status = fw_cpl_invalid_field();
		break;
	}
	return 0;
}

static int fw_handle_create_io_sq(struct nvme_fw_dev *fw,
				  const struct nvme_fw_cmd *cmd,
				  u32 *specific, u16 *status)
{
	u32 qid = cmd->dword[10] & 0xffffu;
	u32 qsize = (cmd->dword[10] >> 16) & 0xffffu;
	u32 cqid = cmd->dword[11] & 0xffffu;
	u64 prp1 = fw_cmd_prp1(cmd);

	fw_admin_success(specific, status);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES || qsize >= 0x100u ||
	    !cqid || cqid > NVME_FW_MAX_IO_QUEUES) {
		*status = fw_cpl_invalid_qid();
		return 0;
	}
	if ((prp1 & 0x3ull) || (prp1 >> 48)) {
		*status = fw_cpl_invalid_field();
		return 0;
	}
	fw_set_io_sq(fw, qid - 1u, 1, cqid, qsize, prp1);
	fw->io_sq_cq_idx[qid - 1u] = cqid - 1u;
	return 0;
}

static int fw_handle_create_io_cq(struct nvme_fw_dev *fw,
				  const struct nvme_fw_cmd *cmd,
				  u32 *specific, u16 *status)
{
	u32 qid = cmd->dword[10] & 0xffffu;
	u32 qsize = (cmd->dword[10] >> 16) & 0xffffu;
	u32 irq_en = (cmd->dword[11] >> 1) & 0x1u;
	u32 irq_vector = (cmd->dword[11] >> 16) & 0xffffu;
	u64 prp1 = fw_cmd_prp1(cmd);

	fw_admin_success(specific, status);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES || qsize >= 0x100u) {
		*status = fw_cpl_invalid_qid();
		return 0;
	}
	if (irq_vector >= 8 || (prp1 & 0x3ull) || (prp1 >> 48)) {
		*status = fw_cpl_invalid_field();
		return 0;
	}
	fw_set_io_cq(fw, qid - 1u, 1, irq_en, irq_vector, qsize, prp1);
	fw->io_cq_irq_vector[qid - 1u] = irq_vector & 0x7u;
	return 0;
}

static int fw_handle_delete_io_sq(struct nvme_fw_dev *fw,
				  const struct nvme_fw_cmd *cmd,
				  u32 *specific, u16 *status)
{
	u32 qid = cmd->dword[10] & 0xffffu;

	fw_admin_success(specific, status);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES) {
		*status = fw_cpl_invalid_qid();
		return 0;
	}
	fw_set_io_sq(fw, qid - 1u, 0, 0, 0, 0);
	fw->io_sq_cq_idx[qid - 1u] = 0;
	return 0;
}

static int fw_handle_delete_io_cq(struct nvme_fw_dev *fw,
				  const struct nvme_fw_cmd *cmd,
				  u32 *specific, u16 *status)
{
	u32 qid = cmd->dword[10] & 0xffffu;

	fw_admin_success(specific, status);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES) {
		*status = fw_cpl_invalid_qid();
		return 0;
	}
	fw_set_io_cq(fw, qid - 1u, 0, 0, 0, 0, 0);
	fw->io_cq_irq_vector[qid - 1u] = 0;
	return 0;
}

static int fw_handle_identify(struct nvme_fw_dev *fw,
			      const struct nvme_fw_cmd *cmd,
			      u32 *specific, u16 *status)
{
	u32 cns = cmd->dword[10] & 0xffu;
	int ret = 0;

	fw_admin_success(specific, status);
	if (!fw_enable_dma_data) {
		*status = fw_cpl_invalid_field();
		return 0;
	}
	ret = fw_ensure_stage(fw);
	if (ret) {
		*status = fw_cpl_internal_error();
		return 0;
	}

	mutex_lock(&fw->stage_lock);
	switch (cns) {
	case 1:
	case 6:
		fw_fill_identify_controller(fw->stage_virt);
		break;
	case 0:
	case 5:
		fw_fill_identify_namespace(fw->stage_virt);
		break;
	case 2:
	case 7:
		memset(fw->stage_virt, 0, NVME_FW_STAGE_SIZE);
		fw_put_le32(fw->stage_virt, 0, 1);
		break;
	case 3:
		memset(fw->stage_virt, 0, NVME_FW_STAGE_SIZE);
		break;
	default:
		*status = fw_cpl_invalid_field();
		goto out;
	}
	ret = fw_stage_and_dma_to_prp(fw, NVME_FW_STAGE_SIZE,
					fw_cmd_prp1(cmd), fw_cmd_prp2(cmd));
	if (ret)
		*status = fw_cpl_internal_error();
out:
	mutex_unlock(&fw->stage_lock);
	return 0;
}

static int fw_handle_get_log_page(struct nvme_fw_dev *fw,
				  const struct nvme_fw_cmd *cmd,
				  u32 *specific, u16 *status)
{
	u32 lid = cmd->dword[10] & 0xffu;
	u32 numd = ((cmd->dword[11] & 0xffffu) << 16) |
		   ((cmd->dword[10] >> 16) & 0xffffu);
	u32 len = (numd + 1u) * 4u;
	int ret = 0;

	fw_admin_success(specific, status);
	if (!len || len > NVME_FW_STAGE_SIZE) {
		*status = fw_cpl_invalid_field();
		return 0;
	}
	if (!fw_enable_dma_data) {
		*status = fw_cpl_invalid_field();
		return 0;
	}
	ret = fw_ensure_stage(fw);
	if (ret) {
		*status = fw_cpl_internal_error();
		return 0;
	}
	mutex_lock(&fw->stage_lock);
	memset(fw->stage_virt, 0, NVME_FW_STAGE_SIZE);
	switch (lid) {
	case 0x01:
		break;
	case 0x02:
		((u8 *)fw->stage_virt)[1] = 0x2c;
		((u8 *)fw->stage_virt)[2] = 0x01;
		((u8 *)fw->stage_virt)[3] = 100;
		((u8 *)fw->stage_virt)[4] = 10;
		break;
	case 0x03:
		((u8 *)fw->stage_virt)[0] = 0x01;
		break;
	default:
		*status = fw_cpl_invalid_log_page();
		goto out;
	}
	ret = fw_stage_and_dma_to_prp(fw, len, fw_cmd_prp1(cmd), fw_cmd_prp2(cmd));
	if (ret)
		*status = fw_cpl_internal_error();
out:
	mutex_unlock(&fw->stage_lock);
	return 0;
}

static int fw_handle_admin_cmd(struct nvme_fw_dev *fw,
			       const struct nvme_fw_cmd *cmd)
{
	u32 specific = 0;
	u16 status = fw_cpl_success();
	u8 opc = fw_cmd_opcode(cmd);
	bool need_cpl = true;
	bool need_release_only = false;
	int ret = 0;

	if (fw_verbose_io)
		dev_info(&fw->pdev->dev,
			 "admin q=%u slot=%u cid=%u opc=0x%02x dw10=0x%08x dw11=0x%08x\n",
			 cmd->qid, cmd->slot, fw_cmd_cid(cmd), opc,
			 cmd->dword[10], cmd->dword[11]);

	switch (opc) {
	case ADMIN_SET_FEATURES:
		ret = fw_handle_set_features(fw, cmd, &specific, &status);
		break;
	case ADMIN_CREATE_IO_CQ:
		ret = fw_handle_create_io_cq(fw, cmd, &specific, &status);
		break;
	case ADMIN_CREATE_IO_SQ:
		ret = fw_handle_create_io_sq(fw, cmd, &specific, &status);
		break;
	case ADMIN_IDENTIFY:
		ret = fw_handle_identify(fw, cmd, &specific, &status);
		break;
	case ADMIN_GET_FEATURES:
		ret = fw_handle_get_features(fw, cmd, &specific, &status);
		break;
	case ADMIN_DELETE_IO_CQ:
		ret = fw_handle_delete_io_cq(fw, cmd, &specific, &status);
		break;
	case ADMIN_DELETE_IO_SQ:
		ret = fw_handle_delete_io_sq(fw, cmd, &specific, &status);
		break;
	case ADMIN_ASYNC_EVENT_REQUEST:
		need_cpl = false;
		need_release_only = true;
		break;
	case ADMIN_GET_LOG_PAGE:
		ret = fw_handle_get_log_page(fw, cmd, &specific, &status);
		break;
	case ADMIN_KEEP_ALIVE:
	case ADMIN_FORMAT_NVM:
	case ADMIN_VENDOR_LIBNVM:
	case ADMIN_ABORT:
		fw_admin_success(&specific, &status);
		break;
	default:
		status = fw_cpl_invalid_opcode();
		break;
	}
	if (ret)
		return ret;
	if (need_cpl)
		return fw_set_auto_cpl(fw, cmd, specific, status);
	if (need_release_only)
		return fw_set_slot_release(fw, cmd);
	return fw_set_cpl(fw, cmd, specific, status);
}

static int fw_handle_io_cmd(struct nvme_fw_dev *fw, const struct nvme_fw_cmd *cmd)
{
	u8 opc = fw_cmd_opcode(cmd);

	if (fw_verbose_io)
		dev_info(&fw->pdev->dev,
			 "io q=%u slot=%u cid=%u opc=0x%02x slba=0x%08x_%08x nlb=%u\n",
			 cmd->qid, cmd->slot, fw_cmd_cid(cmd), opc,
			 cmd->dword[11], cmd->dword[10], cmd->dword[12] & 0xffffu);

	switch (opc) {
	case IO_NVM_FLUSH:
		if (fw_set_cpl(fw, cmd, 0, fw_cpl_success()))
			return -EIO;
		return fw_set_slot_release(fw, cmd);
	case IO_NVM_READ: {
		u32 blocks = (cmd->dword[12] & 0xffffu) + 1u;
		u32 len = blocks * FW_NVME_BLOCK_BYTES;
		int ret = 0;

		if (len > NVME_FW_STAGE_SIZE) {
			if (fw_set_cpl(fw, cmd, 0, fw_cpl_internal_error()))
				return -EIO;
			return fw_set_slot_release(fw, cmd);
		}
		if (fw_enable_io_dma_data) {
			ret = fw_ensure_zero_page(fw);
			if (!ret && fw_auto_io_cpl)
				return fw_submit_auto_io_dma(fw, cmd,
					fw_mgmt_dev_addr + NVME_FW_STAGE_SIZE, len, true);
			if (!ret)
				ret = fw_dma_card_to_prp_from(fw,
					fw_mgmt_dev_addr + NVME_FW_STAGE_SIZE,
					fw_cmd_prp1(cmd), fw_cmd_prp2(cmd), len);
			if (ret) {
				if (fw_set_cpl(fw, cmd, 0, fw_cpl_internal_error()))
					return -EIO;
				return fw_set_slot_release(fw, cmd);
			}
		}
		if (fw_set_cpl(fw, cmd, 0, fw_cpl_success()))
			return -EIO;
		return fw_set_slot_release(fw, cmd);
	}
	case IO_NVM_WRITE:
		if (fw_set_cpl(fw, cmd, 0, fw_cpl_success()))
			return -EIO;
		return fw_set_slot_release(fw, cmd);
	default:
		if (fw_set_cpl(fw, cmd, 0, fw_cpl_invalid_opcode()))
			return -EIO;
		return fw_set_slot_release(fw, cmd);
	}
}

static int fw_firmware_enter_running(struct nvme_fw_dev *fw)
{
	fw_set_admin_queue(fw, 1, 1, 1);
	fw_set_csts_rdy(fw, 1);
	fw->task = FW_TASK_RUNNING;
	dev_info(&fw->pdev->dev, "firmware worker: NVMe ready\n");
	return 0;
}

static int fw_firmware_shutdown(struct nvme_fw_dev *fw)
{
	fw_set_csts_shst(fw, 1);
	fw_clear_io_queues(fw);
	fw_set_admin_queue(fw, 0, 0, 0);
	fw_set_csts_shst(fw, 2);
	fw->cache_en = 0;
	fw->wait_reset_deadline = jiffies + msecs_to_jiffies(FW_SHUTDOWN_REARM_MS);
	fw->task = FW_TASK_WAIT_RESET;
	dev_info(&fw->pdev->dev, "firmware worker: NVMe shutdown\n");
	return 0;
}

static int fw_firmware_clear_for_rearm(struct nvme_fw_dev *fw)
{
	fw_set_status_fields(fw, 0, 0);
	fw_set_admin_queue(fw, 0, 0, 0);
	fw_clear_io_queues(fw);
	fw->cache_en = 0;
	fw->observed_disabled = true;
	fw->wait_reset_deadline = 0;
	fw->task = FW_TASK_IDLE;
	dev_info(&fw->pdev->dev, "firmware worker: NVMe disabled/rearmed\n");
	return 0;
}

static int fw_firmware_poll(struct nvme_fw_dev *fw)
{
	u32 status = fw_readl(fw, fw_ctrl_off(NVME_FW_REG_NVME_STATUS));
	u32 cc_en = !!(status & NVME_STATUS_CC_EN);
	u32 cc_shn = (status & NVME_STATUS_CC_SHN_MASK) >> NVME_STATUS_CC_SHN_SHIFT;
	u32 csts_rdy = !!(status & NVME_STATUS_CSTS_RDY);
	u32 csts_shst = (status >> NVME_STATUS_CSTS_SHST_SHIFT) & 0x3u;
	int work = 0;

	if (!fw->last_status_valid || fw->last_cc_en != cc_en || fw->last_cc_shn != cc_shn) {
		dev_info(&fw->pdev->dev,
			 "firmware worker: NVME_STATUS=0x%08x CC.EN=%u CC.SHN=%u CSTS.RDY=%u CSTS.SHST=%u\n",
			 status, cc_en, cc_shn, csts_rdy, csts_shst);
		fw->last_status_valid = true;
		fw->last_cc_en = cc_en;
		fw->last_cc_shn = cc_shn;
	}

	switch (fw->task) {
	case FW_TASK_IDLE:
		if (!cc_en) {
			fw->observed_disabled = true;
			if (csts_rdy || csts_shst) {
				fw_firmware_clear_for_rearm(fw);
				work = 1;
			}
		} else if (cc_shn && csts_shst == 2) {
			/* Recover stale shutdown-complete state left by a previous driver unload. */
			fw_firmware_clear_for_rearm(fw);
			work = 1;
		} else if (fw->observed_disabled && !cc_shn) {
			fw->task = FW_TASK_WAIT_CC_EN;
		}
		break;
	case FW_TASK_WAIT_CC_EN:
		if (!cc_en) {
			fw->observed_disabled = true;
			fw->task = FW_TASK_IDLE;
			if (csts_rdy || csts_shst) {
				fw_firmware_clear_for_rearm(fw);
				work = 1;
			}
		} else if (cc_shn && csts_shst == 2) {
			fw_firmware_clear_for_rearm(fw);
			work = 1;
		} else if (!cc_shn) {
			fw->observed_disabled = false;
			fw_firmware_enter_running(fw);
			work = 1;
		}
		break;
	case FW_TASK_RUNNING:
		if (cc_shn) {
			fw_firmware_shutdown(fw);
			work = 1;
			break;
		}
		if (!cc_en) {
			fw->wait_reset_deadline = jiffies + msecs_to_jiffies(FW_SHUTDOWN_REARM_MS);
			fw->task = FW_TASK_WAIT_RESET;
			break;
		}
		while (!kthread_should_stop()) {
			struct nvme_fw_cmd cmd;

			fw_fetch_cmd(fw, &cmd);
			if (!cmd.valid)
				break;
			work = 1;
			if (cmd.qid == 0) {
				if (fw_handle_admin_cmd(fw, &cmd))
					return -EIO;
			} else {
				if (fw_handle_io_cmd(fw, &cmd))
					return -EIO;
			}
		}
		break;
	case FW_TASK_WAIT_RESET:
		if (!cc_en) {
			fw_firmware_clear_for_rearm(fw);
			work = 1;
		} else if (!cc_shn && fw->wait_reset_deadline &&
			   time_after_eq(jiffies, fw->wait_reset_deadline)) {
			/* Some host paths clear SHN without fully clearing EN. */
			fw_firmware_clear_for_rearm(fw);
			work = 1;
		}
		break;
	}
	return work;
}

static int fw_firmware_thread(void *data)
{
	struct nvme_fw_dev *fw = data;
	u32 poll_us;

	dev_info(&fw->pdev->dev,
		 "firmware worker: started poll_us=%u mgmt_dev_addr=0x%llx pf0_msi=%d dma_data=%d io_dma_data=%d auto_io_cpl=%d\n",
		 fw_poll_us, fw_mgmt_dev_addr, fw_enable_pf0_msi,
		 fw_enable_dma_data, fw_enable_io_dma_data, fw_auto_io_cpl);
	while (!kthread_should_stop()) {
		int work = fw_firmware_poll(fw);

		if (work < 0) {
			dev_err(&fw->pdev->dev, "firmware worker stopped after BAR2/command error\n");
			break;
		}
		if (!work) {
			poll_us = fw_poll_us ? fw_poll_us : 50;
			usleep_range(poll_us, poll_us * 2);
		}
	}
	dev_info(&fw->pdev->dev, "firmware worker: stopped\n");
	return 0;
}

static irqreturn_t fw_irq(int irq, void *data)
{
	struct nvme_fw_dev *fw = data;

	fw->last_pid_done = fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE));
	fw->last_done_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_DONE_COUNT));
	atomic_inc(&fw->irq_count);
	wake_up_all(&fw->waitq);
	fw_dbg(fw, "PF1 MSI irq=%d pid_done=%u done_count=%u irq_count=%d\n",
	       irq, fw->last_pid_done, fw->last_done_count, atomic_read(&fw->irq_count));
	return IRQ_HANDLED;
}

static int fw_open(struct inode *inode, struct file *filp)
{
	struct nvme_fw_dev *fw = container_of(inode->i_cdev, struct nvme_fw_dev, cdev);

	filp->private_data = fw;
	return 0;
}

static long fw_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	struct nvme_fw_dev *fw = filp->private_data;
	void __user *uarg = (void __user *)arg;

	switch (cmd) {
	case NVME_FW_IOC_GET_INFO: {
		struct nvme_fw_info info = {
			.vendor = fw->pdev->vendor,
			.device = fw->pdev->device,
			.bar = NVME_FW_BAR2_NR,
			.irq_vector = 0,
			.bar_start = fw->bar2_start,
			.bar_len = fw->bar2_len,
			.mapped_len = NVME_FW_BAR2_SIZE,
			.layout_version = NVME_FW_LAYOUT_VERSION,
			.ring_magic = fw_readl(fw, fw_ring_off(NVME_FW_RING_MAGIC)),
			.debug_magic = fw_readl(fw, NVME_FW_BAR2_DEBUG_MAGIC),
		};
		return copy_to_user(uarg, &info, sizeof(info)) ? -EFAULT : 0;
	}
	case NVME_FW_IOC_READ32: {
		struct nvme_fw_reg_io reg;
		int ret;

		if (copy_from_user(&reg, uarg, sizeof(reg)))
			return -EFAULT;
		ret = fw_check_range(reg.offset, sizeof(u32));
		if (ret)
			return ret;
		reg.value = fw_readl(fw, reg.offset);
		return copy_to_user(uarg, &reg, sizeof(reg)) ? -EFAULT : 0;
	}
	case NVME_FW_IOC_WRITE32: {
		struct nvme_fw_reg_io reg;
		int ret;

		if (copy_from_user(&reg, uarg, sizeof(reg)))
			return -EFAULT;
		ret = fw_check_range(reg.offset, sizeof(u32));
		if (ret)
			return ret;
		fw_writel(fw, reg.offset, reg.value);
		return 0;
	}
	case NVME_FW_IOC_FETCH_CMD: {
		struct nvme_fw_cmd c;

		fw_fetch_cmd(fw, &c);
		return copy_to_user(uarg, &c, sizeof(c)) ? -EFAULT : 0;
	}
	case NVME_FW_IOC_COMPLETE: {
		struct nvme_fw_cpl cpl;

		if (copy_from_user(&cpl, uarg, sizeof(cpl)))
			return -EFAULT;
		return fw_complete(fw, &cpl);
	}
	case NVME_FW_IOC_SUBMIT_BATCH: {
		struct nvme_fw_dma_batch *batch;
		int ret;

		batch = memdup_user(uarg, sizeof(*batch));
		if (IS_ERR(batch))
			return PTR_ERR(batch);
		ret = fw_submit_batch(fw, batch);
		kfree(batch);
		return ret;
	}
	case NVME_FW_IOC_RING_RESET:
		fw_writel(fw, fw_ring_off(NVME_FW_RING_STATUS), 1);
		return 0;
	case NVME_FW_IOC_RING_STATUS: {
		struct nvme_fw_ring_status st;

		fw_get_ring_status(fw, &st);
		return copy_to_user(uarg, &st, sizeof(st)) ? -EFAULT : 0;
	}
	case NVME_FW_IOC_CONFIG_PF1_MSI: {
		struct nvme_fw_msi_config cfg;
		int ret;

		if (copy_from_user(&cfg, uarg, sizeof(cfg)))
			return -EFAULT;
		ret = fw_validate_msi_config(&cfg);
		if (ret)
			return ret;
		fw_config_pf1_msi(fw, cfg.enable, cfg.vector, cfg.threshold);
		return 0;
	}
	case NVME_FW_IOC_CONFIG_PF0_MSI: {
		struct nvme_fw_msi_config cfg;
		int ret;

		if (copy_from_user(&cfg, uarg, sizeof(cfg)))
			return -EFAULT;
		ret = fw_validate_msi_config(&cfg);
		if (ret)
			return ret;
		fw_config_pf0_msi(fw, cfg.enable, cfg.vector);
		return 0;
	}
	case NVME_FW_IOC_TRIGGER_PF0_MSI:
		fw_writel(fw, fw_ring_off(NVME_FW_RING_PF0_MSI_COUNT), 1);
		return 0;
	case NVME_FW_IOC_WAIT_PID: {
		struct nvme_fw_wait_pid wait;
		u32 timeout_ms;
		u32 elapsed;
		u32 done_pid;
		long timeout;
		int ret;

		if (copy_from_user(&wait, uarg, sizeof(wait)))
			return -EFAULT;
		timeout_ms = wait.timeout_ms ? wait.timeout_ms : 1000;
		if (fw->irq < 0) {
			for (elapsed = 0; elapsed <= timeout_ms; elapsed++) {
				done_pid = fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE));
				if (fw_pid_reached(done_pid, wait.target_pid)) {
					wait.done_pid = done_pid;
					wait.irq_count = atomic_read(&fw->irq_count);
					return copy_to_user(uarg, &wait, sizeof(wait)) ? -EFAULT : 0;
				}
				usleep_range(50, 100);
			}
			return -ETIMEDOUT;
		}

		timeout = msecs_to_jiffies(timeout_ms);
		ret = wait_event_interruptible_timeout(fw->waitq,
				fw_pid_reached(fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE)), wait.target_pid),
				timeout);
		if (ret < 0)
			return ret;
		if (ret == 0)
			return -ETIMEDOUT;
		wait.done_pid = fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE));
		wait.irq_count = atomic_read(&fw->irq_count);
		return copy_to_user(uarg, &wait, sizeof(wait)) ? -EFAULT : 0;
	}
	case NVME_FW_IOC_GET_STAGE_INFO: {
		struct nvme_fw_stage_info info;
		int ret = fw_ensure_stage(fw);

		if (ret)
			return ret;
		info.dma_addr = fw->stage_dma;
		info.size = fw->stage_size;
		info.reserved0 = 0;
		return copy_to_user(uarg, &info, sizeof(info)) ? -EFAULT : 0;
	}
	case NVME_FW_IOC_STAGE_WRITE: {
		struct nvme_fw_stage_write wr;
		void __user *uptr;
		int ret = fw_ensure_stage(fw);

		if (ret)
			return ret;
		if (copy_from_user(&wr, uarg, sizeof(wr)))
			return -EFAULT;
		if (wr.offset > fw->stage_size || wr.len > fw->stage_size - wr.offset)
			return -EINVAL;
		uptr = (void __user *)(unsigned long)wr.user_ptr;
		if (copy_from_user(fw->stage_virt + wr.offset, uptr, wr.len))
			return -EFAULT;
		dma_sync_single_for_device(&fw->pdev->dev, fw->stage_dma + wr.offset,
					   wr.len, DMA_TO_DEVICE);
		return 0;
	}
	default:
		return -ENOTTY;
	}
}

static int fw_mmap(struct file *filp, struct vm_area_struct *vma)
{
	struct nvme_fw_dev *fw = filp->private_data;
	unsigned long size = vma->vm_end - vma->vm_start;
	unsigned long pgoff = vma->vm_pgoff << PAGE_SHIFT;
	resource_size_t phys;

	if (pgoff > NVME_FW_BAR2_SIZE || size > NVME_FW_BAR2_SIZE - pgoff)
		return -EINVAL;

	phys = fw->bar2_start + pgoff;
	vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
	return remap_pfn_range(vma, vma->vm_start, phys >> PAGE_SHIFT,
			       size, vma->vm_page_prot);
}

static const struct file_operations nvme_fw_fops = {
	.owner = THIS_MODULE,
	.open = fw_open,
	.unlocked_ioctl = fw_ioctl,
	.mmap = fw_mmap,
	.llseek = no_llseek,
};

static int nvme_fw_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct nvme_fw_dev *fw;
	dev_t devt;
	u32 ring_magic;
	u32 debug_magic;
	int ret;

	if (target_function >= 0 && PCI_FUNC(pdev->devfn) != target_function)
		return -ENODEV;

	ret = pci_enable_device_mem(pdev);
	if (ret)
		return ret;

	if (pci_resource_len(pdev, NVME_FW_BAR2_NR) < NVME_FW_BAR2_SIZE) {
		dev_err(&pdev->dev, "BAR2 is smaller than 256 KiB\n");
		ret = -ENODEV;
		goto disable;
	}

	ret = pci_request_region(pdev, NVME_FW_BAR2_NR, NVME_FW_NAME);
	if (ret)
		goto disable;

	fw = kzalloc(sizeof(*fw), GFP_KERNEL);
	if (!fw) {
		ret = -ENOMEM;
		goto release_region;
	}

	fw->pdev = pdev;
	fw->bar2_start = pci_resource_start(pdev, NVME_FW_BAR2_NR);
	fw->bar2_len = pci_resource_len(pdev, NVME_FW_BAR2_NR);
	fw->bar2 = pci_iomap(pdev, NVME_FW_BAR2_NR, NVME_FW_BAR2_SIZE);
	if (!fw->bar2) {
		ret = -ENOMEM;
		goto free_fw;
	}

	mutex_init(&fw->ring_lock);
	mutex_init(&fw->stage_lock);
	init_waitqueue_head(&fw->waitq);
	atomic_set(&fw->irq_count, 0);
	fw->irq = -1;
	fw->iosq_alloc = NVME_FW_MAX_IO_QUEUES;
	fw->iocq_alloc = NVME_FW_MAX_IO_QUEUES;
	fw->pf0_msi_vector = ~0u;
	fw->observed_disabled = true;
	fw->task = FW_TASK_IDLE;
	fw_probe_bar2_test(fw);
	if (probe_check_magic || probe_test_level >= 3) {
		fw->last_pid_done = fw_readl(fw, fw_ring_off(NVME_FW_RING_PID_DONE));
		fw->last_done_count = fw_readl(fw, fw_ring_off(NVME_FW_RING_DONE_COUNT));
	}

	if (use_msi) {
		ret = pci_alloc_irq_vectors(pdev, 1, 1, PCI_IRQ_MSI);
		if (ret < 0)
			goto unmap;
		fw->irq = pci_irq_vector(pdev, 0);

		ret = request_irq(fw->irq, fw_irq, 0, NVME_FW_NAME, fw);
		if (ret)
			goto free_irqs;
	}

	fw->minor = ida_alloc_max(&nvme_fw_minors, NVME_FW_MAX_MINORS - 1, GFP_KERNEL);
	if (fw->minor < 0) {
		ret = fw->minor;
		goto free_irq;
	}

	devt = MKDEV(MAJOR(nvme_fw_devt), fw->minor);
	cdev_init(&fw->cdev, &nvme_fw_fops);
	fw->cdev.owner = THIS_MODULE;
	ret = cdev_add(&fw->cdev, devt, 1);
	if (ret)
		goto free_minor;

	fw->chardev = device_create(nvme_fw_class, &pdev->dev, devt, fw,
				       "nvme_fw%d", fw->minor);
	if (IS_ERR(fw->chardev)) {
		ret = PTR_ERR(fw->chardev);
		goto del_cdev;
	}

	pci_set_drvdata(pdev, fw);
	if (enable_busmaster)
		pci_set_master(pdev);

	if (auto_enable_pf1_msi)
		fw_config_pf1_msi(fw, true, 0, msi_threshold ? msi_threshold : 1);
	if (auto_enable_pf0_msi)
		fw_config_pf0_msi(fw, true, 0);
	if (run_firmware) {
		if (fw_enable_pf0_msi)
			fw_config_pf0_msi_vector(fw, 0);
		fw->fw_thread = kthread_run(fw_firmware_thread, fw,
					    "nvme_fw/%s", pci_name(pdev));
		if (IS_ERR(fw->fw_thread)) {
			ret = PTR_ERR(fw->fw_thread);
			fw->fw_thread = NULL;
			goto destroy_device;
		}
	}

	ring_magic = 0;
	debug_magic = 0;
	if (probe_check_magic) {
		ring_magic = fw_readl(fw, fw_ring_off(NVME_FW_RING_MAGIC));
		debug_magic = fw_readl(fw, NVME_FW_BAR2_DEBUG_MAGIC);
		if (ring_magic != NVME_FW_RING_MAGIC_VALUE)
			dev_warn(&pdev->dev, "unexpected BAR2 ring magic 0x%08x\n", ring_magic);
		if (debug_magic != NVME_FW_BAR2_DEBUG_MAGIC_VALUE)
			dev_warn(&pdev->dev, "unexpected BAR2 debug magic 0x%08x\n", debug_magic);
	}

	dev_info(&pdev->dev, "mapped PF%d BAR2 at %pa, irq %d, busmaster=%d msi=%d probe_check_magic=%d probe_test_level=%d firmware=%d\n",
		 PCI_FUNC(pdev->devfn), &fw->bar2_start, fw->irq,
		 enable_busmaster, use_msi, probe_check_magic, probe_test_level, run_firmware);
	return 0;

 destroy_device:
	device_destroy(nvme_fw_class, devt);
 del_cdev:
	cdev_del(&fw->cdev);
 free_minor:
	ida_free(&nvme_fw_minors, fw->minor);
 free_irq:
	if (fw->irq >= 0)
		free_irq(fw->irq, fw);
 free_irqs:
	if (use_msi)
		pci_free_irq_vectors(pdev);
 unmap:
	pci_iounmap(pdev, fw->bar2);
 free_fw:
	kfree(fw);
 release_region:
	pci_release_region(pdev, NVME_FW_BAR2_NR);
 disable:
	pci_disable_device(pdev);
	return ret;
}

static void nvme_fw_remove(struct pci_dev *pdev)
{
	struct nvme_fw_dev *fw = pci_get_drvdata(pdev);
	dev_t devt;

	if (!fw)
		return;

	if (fw->fw_thread) {
		kthread_stop(fw->fw_thread);
		fw->fw_thread = NULL;
	}

	if (auto_enable_pf1_msi)
		fw_config_pf1_msi(fw, false, 0, 1);
	if (auto_enable_pf0_msi)
		fw_config_pf0_msi(fw, false, 0);
	if (enable_busmaster)
		pci_clear_master(pdev);

	devt = MKDEV(MAJOR(nvme_fw_devt), fw->minor);
	device_destroy(nvme_fw_class, devt);
	cdev_del(&fw->cdev);
	ida_free(&nvme_fw_minors, fw->minor);
	if (fw->irq >= 0)
		free_irq(fw->irq, fw);
	if (use_msi)
		pci_free_irq_vectors(pdev);
	if (fw->stage_virt)
		dma_free_coherent(&pdev->dev, fw->stage_size, fw->stage_virt, fw->stage_dma);
	pci_iounmap(pdev, fw->bar2);
	pci_release_region(pdev, NVME_FW_BAR2_NR);
	pci_disable_device(pdev);
	kfree(fw);
}

static const struct pci_device_id nvme_fw_pci_ids[] = {
	{ PCI_DEVICE(NVME_FW_PCI_VENDOR_ID, NVME_FW_PCI_DEVICE_ID_PF1) },
	{ 0, }
};
MODULE_DEVICE_TABLE(pci, nvme_fw_pci_ids);

static struct pci_driver nvme_fw_pci_driver = {
	.name = NVME_FW_NAME,
	.id_table = nvme_fw_pci_ids,
	.probe = nvme_fw_probe,
	.remove = nvme_fw_remove,
};

static int __init nvme_fw_init(void)
{
	int ret;

	ret = alloc_chrdev_region(&nvme_fw_devt, 0, NVME_FW_MAX_MINORS, NVME_FW_NAME);
	if (ret)
		return ret;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
	nvme_fw_class = class_create(NVME_FW_NAME);
#else
	nvme_fw_class = class_create(THIS_MODULE, NVME_FW_NAME);
#endif
	if (IS_ERR(nvme_fw_class)) {
		ret = PTR_ERR(nvme_fw_class);
		goto unregister_chrdev;
	}

	ret = pci_register_driver(&nvme_fw_pci_driver);
	if (ret)
		goto destroy_class;

	return 0;

 destroy_class:
	class_destroy(nvme_fw_class);
 unregister_chrdev:
	unregister_chrdev_region(nvme_fw_devt, NVME_FW_MAX_MINORS);
	return ret;
}

static void __exit nvme_fw_exit(void)
{
	pci_unregister_driver(&nvme_fw_pci_driver);
	class_destroy(nvme_fw_class);
	unregister_chrdev_region(nvme_fw_devt, NVME_FW_MAX_MINORS);
	ida_destroy(&nvme_fw_minors);
}

module_init(nvme_fw_init);
module_exit(nvme_fw_exit);

MODULE_AUTHOR("nvme_interface_accelerator");
MODULE_DESCRIPTION("PF1 BAR2 firmware/control driver for NVMe interface accelerator");
MODULE_LICENSE("GPL");
