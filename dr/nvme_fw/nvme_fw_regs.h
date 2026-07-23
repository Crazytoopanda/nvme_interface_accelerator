/* SPDX-License-Identifier: GPL-2.0 */
#ifndef NVME_FW_REGS_H
#define NVME_FW_REGS_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define NVME_FW_NAME                   "nvme_fw"
#define NVME_FW_PCI_VENDOR_ID          0x10ee
#define NVME_FW_PCI_DEVICE_ID_PF1      0x923f
#define NVME_FW_BAR2_NR                2
#define NVME_FW_PCI_FUNCTION           1
#define NVME_FW_BAR2_SIZE              0x40000u
#define NVME_FW_LAYOUT_VERSION         2u
#define NVME_FW_MAX_MINORS             32
#define NVME_FW_MAX_BATCH              64
#define NVME_FW_RING_DEPTH             256u
#define NVME_FW_SLOT_TAG_WIDTH         10u
#define NVME_FW_MAX_CMD_SLOTS          (1u << NVME_FW_SLOT_TAG_WIDTH)
#define NVME_FW_SQE_BYTES              64u
#define NVME_FW_MAX_IO_QUEUES          8u
#define NVME_FW_STAGE_SIZE              0x1000u

/* BAR2 direct s0_axi-compatible register window. */
#define NVME_FW_CTRL_BASE              0x00000u
#define NVME_FW_CTRL_SIZE              0x10000u
#define NVME_FW_REG_DEV_IRQ_MASK       0x004u
#define NVME_FW_REG_DEV_IRQ_CLEAR      0x008u
#define NVME_FW_REG_DEV_IRQ_STATUS     0x00cu
#define NVME_FW_REG_PCIE_STATUS        0x100u
#define NVME_FW_REG_PCIE_FUNC          0x104u
#define NVME_FW_REG_NVME_STATUS        0x200u
#define NVME_FW_REG_DMA_FIFO_CNT       0x204u
#define NVME_FW_REG_ADMIN_QUEUE        0x21cu
#define NVME_FW_REG_IO_SQ_BASE         0x220u
#define NVME_FW_REG_IO_CQ_BASE         0x260u
#define NVME_FW_REG_CMD_FIFO           0x300u
#define NVME_FW_REG_CPL_FIFO           0x304u
#define NVME_FW_REG_DMA_CMD_FIFO       0x310u
#define NVME_FW_REG_DMA_CMD_TRIG       0x330u
#define NVME_FW_REG_CPL_FIFO_TRIG      0x340u
#define NVME_FW_REG_CMD_FIFO_PEEK      0x344u

/* Hardware I/O automation and SSD latency-model registers. */
#define NVME_FW_REG_AUTO_BASE               0x400u
#define NVME_FW_REG_AUTO_MAGIC              0x400u
#define NVME_FW_REG_AUTO_CTRL               0x404u
#define NVME_FW_REG_AUTO_STATUS             0x408u
#define NVME_FW_REG_AUTO_ERROR              0x40cu
#define NVME_FW_REG_AUTO_DDR_BASE_LO        0x410u
#define NVME_FW_REG_AUTO_DDR_BASE_HI        0x414u
#define NVME_FW_REG_AUTO_DDR_LIMIT_LO       0x418u
#define NVME_FW_REG_AUTO_DDR_LIMIT_HI       0x41cu
#define NVME_FW_REG_AUTO_IO_ENABLE_MASK     0x420u
#define NVME_FW_REG_AUTO_PF0_MSI_CTRL       0x424u
#define NVME_FW_REG_AUTO_CQ_MODE            0x428u
#define NVME_FW_REG_AUTO_CMD_COUNT          0x430u
#define NVME_FW_REG_AUTO_DMA_SUBMIT_COUNT   0x434u
#define NVME_FW_REG_AUTO_DMA_DONE_COUNT     0x438u
#define NVME_FW_REG_AUTO_CQ_WRITE_COUNT     0x43cu
#define NVME_FW_REG_AUTO_LAST_CQE_DW3       0x440u
#define NVME_FW_REG_AUTO_UNSUPPORTED_COUNT  0x444u
#define NVME_FW_REG_AUTO_LAST_QID_SLOT      0x448u
#define NVME_FW_REG_AUTO_LAST_OPCODE        0x44cu
#define NVME_FW_REG_AUTO_LAST_ERROR_INFO    0x450u
#define NVME_FW_REG_AUTO_LAST_CQE_DW2       0x454u
#define NVME_FW_REG_AUTO_CQ_IRQ_RETRY       0x458u
#define NVME_FW_REG_AUTO_SW_DOORBELL        0x45cu
#define NVME_FW_REG_AUTO_RETRY_CYCLES       0x460u
#define NVME_FW_REG_SSD_MODEL_CTRL          0x464u
#define NVME_FW_REG_SSD_READ_LSB_CYCLES     0x468u
#define NVME_FW_REG_SSD_READ_MSB_CYCLES     0x46cu
#define NVME_FW_REG_SSD_PROGRAM_CYCLES      0x470u
#define NVME_FW_REG_SSD_FW_READ_CYCLES      0x474u
#define NVME_FW_REG_SSD_FW_WRITE_CYCLES     0x478u
#define NVME_FW_REG_SSD_CH_XFER_4K_CYCLES   0x47cu
#define NVME_FW_REG_SSD_MODEL_STATUS        0x480u
#define NVME_FW_REG_SSD_MODEL_SUBMIT_COUNT  0x484u
#define NVME_FW_REG_SSD_MODEL_RELEASE_COUNT 0x488u

#define NVME_FW_AUTO_MAGIC_VALUE             0xa710f001u
#define NVME_FW_AUTO_CTRL_ENABLE             (1u << 0)
#define NVME_FW_AUTO_CTRL_RESET              (1u << 1)
#define NVME_FW_AUTO_CTRL_READ_ENABLE        (1u << 8)
#define NVME_FW_AUTO_CTRL_WRITE_ENABLE       (1u << 9)
#define NVME_FW_AUTO_CTRL_CQ_ENABLE          (1u << 10)
#define NVME_FW_AUTO_CTRL_MSI_ENABLE         (1u << 11)
#define NVME_FW_AUTO_STATUS_ENABLED          (1u << 0)
#define NVME_FW_AUTO_STATUS_IDLE             (1u << 1)
#define NVME_FW_AUTO_STATUS_ERROR            (1u << 8)
#define NVME_FW_AUTO_STATUS_UNSUPPORTED      (1u << 9)
#define NVME_FW_AUTO_STATUS_DMA_STALLED      (1u << 10)
#define NVME_FW_AUTO_STATUS_BUSY             (1u << 16)
#define NVME_FW_AUTO_STATUS_MSI_ENABLED      (1u << 17)
#define NVME_FW_AUTO_STATUS_STATE_SHIFT      20
#define NVME_FW_AUTO_STATUS_STATE_MASK       (0x1fu << NVME_FW_AUTO_STATUS_STATE_SHIFT)
#define NVME_FW_SSD_MODEL_ENABLE             (1u << 0)
#define NVME_FW_SSD_MODEL_RESET              (1u << 1)

/* BAR2 host command/SQE mirror. */
#define NVME_FW_SQE_BASE               0x10000u
#define NVME_FW_SQE_SIZE               0x10000u

/* BAR2 DMA command ring. */
#define NVME_FW_RING_DESC_BASE         0x20000u
#define NVME_FW_RING_DESC_SIZE         32u
#define NVME_FW_RING_CTRL_BASE         0x22000u
#define NVME_FW_RING_MAGIC_VALUE       0xd2c00002u

#define NVME_FW_RING_MAGIC             0x00u
#define NVME_FW_RING_STATUS            0x04u
#define NVME_FW_RING_INFO              0x08u
#define NVME_FW_RING_SUBMIT_COUNT      0x0cu
#define NVME_FW_RING_DOORBELL_COUNT    0x10u
#define NVME_FW_RING_BACKPRESSURE      0x14u
#define NVME_FW_RING_PID_SUBMIT        0x18u
#define NVME_FW_RING_PID_DONE          0x1cu
#define NVME_FW_RING_LAST_SUBMIT       0x20u
#define NVME_FW_RING_LAST_DONE         0x24u
#define NVME_FW_RING_PF1_MSI_CTRL      0x28u
#define NVME_FW_RING_PF1_MSI_THRESHOLD 0x2cu
#define NVME_FW_RING_PF1_MSI_COUNT     0x30u
#define NVME_FW_RING_DONE_COUNT        0x34u
#define NVME_FW_RING_INFLIGHT          0x38u
#define NVME_FW_RING_DONE_PENDING      0x3cu
#define NVME_FW_RING_PF0_MSI_CTRL      0x40u
#define NVME_FW_RING_PF0_MSI_COUNT     0x44u

#define NVME_FW_RING_STATUS_HEAD_MASK  0x000000ffu
#define NVME_FW_RING_STATUS_TAIL_MASK  0x0000ff00u
#define NVME_FW_RING_STATUS_EMPTY      0x00010000u
#define NVME_FW_RING_STATUS_BUSY       0x00020000u
#define NVME_FW_RING_STATUS_PID_FULL   0x00040000u
#define NVME_FW_RING_INFO_USED_MASK    0x000000ffu

#define NVME_FW_RING_DESC_DW0          0x00u /* dev_addr[31:2] */
#define NVME_FW_RING_DESC_DW1          0x04u /* dev_addr high */
#define NVME_FW_RING_DESC_DW2          0x08u /* pcie_addr[31:2] */
#define NVME_FW_RING_DESC_DW3          0x0cu /* pcie_addr high */
#define NVME_FW_RING_DESC_DW4          0x10u /* type/dir/offset/auto/len */
#define NVME_FW_RING_DESC_DW5          0x14u /* slot tag */
#define NVME_FW_RING_DESC_DW6          0x18u /* cid */
#define NVME_FW_RING_DESC_DW7          0x1cu /* reserved */

#define NVME_FW_DMA_TYPE_SHIFT         31
#define NVME_FW_DMA_DIR_SHIFT          30
#define NVME_FW_DMA_4K_OFFSET_SHIFT    14
#define NVME_FW_DMA_AUTO_CPL_SHIFT     13
#define NVME_FW_DMA_LEN_MASK           0x00001ffcu
#define NVME_FW_DMA_4K_OFFSET_MASK     0x000001ffu
#define NVME_FW_DMA_DIRECT_TYPE        1u
#define NVME_FW_DMA_AUTO_TYPE          0u
#define NVME_FW_DMA_TX_DIRECTION       1u
#define NVME_FW_DMA_RX_DIRECTION       0u

/* Local BAR2 debug/status registers at the end of the 256 KiB aperture. */
#define NVME_FW_BAR2_DEBUG_MAGIC       0x3ffe0u
#define NVME_FW_BAR2_DEBUG_COUNTS      0x3ffe4u
#define NVME_FW_BAR2_DEBUG_LAST_ADDR   0x3ffe8u
#define NVME_FW_BAR2_DEBUG_LAST_WDATA  0x3ffecu
#define NVME_FW_BAR2_DEBUG_REQ_COUNT   0x3fff0u
#define NVME_FW_BAR2_DEBUG_MAGIC_VALUE 0xb2020002u

#define NVME_FW_CPL_ONLY               0u
#define NVME_FW_CPL_AUTO               1u
#define NVME_FW_CPL_SLOT_RELEASE       2u

#define NVME_FW_IOC_MAGIC              'f'

struct nvme_fw_info {
	__u16 vendor;
	__u16 device;
	__u8 bar;
	__u8 irq_vector;
	__u16 reserved0;
	__u64 bar_start;
	__u64 bar_len;
	__u32 mapped_len;
	__u32 layout_version;
	__u32 ring_magic;
	__u32 debug_magic;
};

struct nvme_fw_reg_io {
	__u32 offset;
	__u32 value;
};

struct nvme_fw_cmd {
	__u8 valid;
	__u8 qid;
	__u16 slot;
	__u32 seq;
	__u32 dword[16];
};

struct nvme_fw_cpl {
	__u8 type;
	__u8 reserved0;
	__u16 sqid;
	__u16 cid;
	__u16 slot;
	__u32 specific;
	__u16 status;
	__u16 reserved1;
};

struct nvme_fw_dma_desc {
	__u8 type;
	__u8 direction;
	__u8 auto_completion;
	__u8 reserved0;
	__u16 slot;
	__u16 cid;
	__u16 len;
	__u16 cmd_4k_offset;
	__u64 dev_addr;
	__u64 pcie_addr;
};

struct nvme_fw_dma_batch {
	__u32 count;
	__u32 reserved0;
	struct nvme_fw_dma_desc desc[NVME_FW_MAX_BATCH];
};

struct nvme_fw_ring_status {
	__u32 status;
	__u32 info;
	__u32 submit_count;
	__u32 doorbell_count;
	__u32 backpressure_count;
	__u32 pid_submit;
	__u32 pid_done;
	__u32 last_submit;
	__u32 last_done;
	__u32 pf1_msi_count;
	__u32 done_count;
	__u32 inflight;
	__u32 done_pending;
	__u32 pf0_msi_count;
};

struct nvme_fw_msi_config {
	__u8 enable;
	__u8 vector;    /* MSI vector index 0..8; driver converts to one-hot. */
	__u16 threshold; /* PF1 only; zero means one. */
};

struct nvme_fw_wait_pid {
	__u32 target_pid;
	__u32 timeout_ms;
	__u32 done_pid;
	__u32 irq_count;
};

struct nvme_fw_stage_info {
	__u64 dma_addr;
	__u32 size;
	__u32 reserved0;
};

struct nvme_fw_stage_write {
	__u64 user_ptr;
	__u32 offset;
	__u32 len;
};

#define NVME_FW_IOC_GET_INFO           _IOR(NVME_FW_IOC_MAGIC, 0x00, struct nvme_fw_info)
#define NVME_FW_IOC_READ32             _IOWR(NVME_FW_IOC_MAGIC, 0x01, struct nvme_fw_reg_io)
#define NVME_FW_IOC_WRITE32            _IOW(NVME_FW_IOC_MAGIC, 0x02, struct nvme_fw_reg_io)
#define NVME_FW_IOC_FETCH_CMD          _IOR(NVME_FW_IOC_MAGIC, 0x03, struct nvme_fw_cmd)
#define NVME_FW_IOC_COMPLETE           _IOW(NVME_FW_IOC_MAGIC, 0x04, struct nvme_fw_cpl)
#define NVME_FW_IOC_SUBMIT_BATCH       _IOW(NVME_FW_IOC_MAGIC, 0x05, struct nvme_fw_dma_batch)
#define NVME_FW_IOC_RING_RESET         _IO(NVME_FW_IOC_MAGIC, 0x06)
#define NVME_FW_IOC_RING_STATUS        _IOR(NVME_FW_IOC_MAGIC, 0x07, struct nvme_fw_ring_status)
#define NVME_FW_IOC_CONFIG_PF1_MSI     _IOW(NVME_FW_IOC_MAGIC, 0x08, struct nvme_fw_msi_config)
#define NVME_FW_IOC_CONFIG_PF0_MSI     _IOW(NVME_FW_IOC_MAGIC, 0x09, struct nvme_fw_msi_config)
#define NVME_FW_IOC_TRIGGER_PF0_MSI    _IO(NVME_FW_IOC_MAGIC, 0x0a)
#define NVME_FW_IOC_WAIT_PID           _IOWR(NVME_FW_IOC_MAGIC, 0x0b, struct nvme_fw_wait_pid)
#define NVME_FW_IOC_GET_STAGE_INFO     _IOR(NVME_FW_IOC_MAGIC, 0x0c, struct nvme_fw_stage_info)
#define NVME_FW_IOC_STAGE_WRITE        _IOW(NVME_FW_IOC_MAGIC, 0x0d, struct nvme_fw_stage_write)

#endif /* NVME_FW_REGS_H */
