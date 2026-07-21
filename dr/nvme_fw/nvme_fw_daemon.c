// SPDX-License-Identifier: GPL-2.0
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#include "nvme_fw_regs.h"

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
#define ADMIN_NAMESPACE_MANAGEMENT          0x0d
#define ADMIN_FIRMWARE_ACTIVATE             0x10
#define ADMIN_FIRMWARE_IMAGE_DOWNLOAD       0x11
#define ADMIN_DEVICE_SELF_TEST              0x14
#define ADMIN_NAMESPACE_ATTACHMENT          0x15
#define ADMIN_KEEP_ALIVE                    0x18
#define ADMIN_DIRECTIVE_SEND                0x19
#define ADMIN_DIRECTIVE_RECEIVE             0x1a
#define ADMIN_VIRTUALIZATION_MANAGEMENT     0x1c
#define ADMIN_NVME_MI_SEND                  0x1d
#define ADMIN_NVME_MI_RECEIVE               0x1e
#define ADMIN_CAPACITY_MANAGEMENT           0x20
#define ADMIN_LOCKDOWN                      0x24
#define ADMIN_DOORBELL_BUFFER_CONFIG        0x7c
#define ADMIN_FORMAT_NVM                    0x80
#define ADMIN_SECURITY_SEND                 0x81
#define ADMIN_SECURITY_RECEIVE              0x82
#define ADMIN_SANITIZE                      0x84
#define ADMIN_GET_LBA_STATUS                0x86
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

#define FW_SHUTDOWN_REARM_NS                100000000ull
#define FW_DEFAULT_POLL_US                  100u
#define FW_DEFAULT_MGMT_DEV_ADDR            0x5000200000ull
#define FW_NVME_STORAGE_BYTES              (63ull * 1024ull * 1024ull * 1024ull)
#define FW_NVME_BLOCK_BYTES                4096ull
#define FW_NVME_BLOCKS                     (FW_NVME_STORAGE_BYTES / FW_NVME_BLOCK_BYTES)

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
	FW_TASK_SHUTDOWN,
	FW_TASK_WAIT_RESET,
};

struct fw_state {
	int fd;
	unsigned int poll_us;
	unsigned int iosq_alloc;
	unsigned int iocq_alloc;
	unsigned int io_sq_cq_idx[NVME_FW_MAX_IO_QUEUES];
	unsigned int io_cq_irq_vector[NVME_FW_MAX_IO_QUEUES];
	unsigned int pf0_msi_vector;
	unsigned int cache_en;
	unsigned int observed_disabled;
	int auto_ready;
	int complete_unsupported;
	int enable_pf0_msi;
	int enable_dma_data;
	int enable_io_dma_data;
	int status_once;
	int run;
	uint64_t mgmt_dev_addr;
	uint64_t stage_dma_addr;
	uint32_t stage_size;
	int last_status_valid;
	unsigned int last_cc_en;
	unsigned int last_cc_shn;
	enum fw_task_state task;
	uint64_t wait_reset_start_ns;
};

static volatile sig_atomic_t stop;
static int verbose;

#define FW_LOG(fmt, ...) \
	do { \
		if (verbose) \
			printf(fmt, ##__VA_ARGS__); \
	} while (0)

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

static uint64_t now_ns(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) < 0)
		return 0;
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static void sleep_us(unsigned int usec)
{
	struct timespec ts = {
		.tv_sec = usec / 1000000u,
		.tv_nsec = (long)(usec % 1000000u) * 1000L,
	};

	while (nanosleep(&ts, &ts) < 0 && errno == EINTR && !stop)
		;
}

static uint16_t nvme_status_word(unsigned int sct, unsigned int sc, unsigned int dnr)
{
	return (uint16_t)((sc & 0xffu) << 1 |
			  ((sct & 0x7u) << 9) |
			  ((dnr & 0x1u) << 15));
}

static uint16_t cpl_success(void)
{
	return nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_SUCCESSFUL_COMPLETION, 0);
}

static uint16_t cpl_invalid_opcode(void)
{
	return nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_INVALID_COMMAND_OPCODE, 1);
}

static uint16_t cpl_invalid_field(void)
{
	return nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_INVALID_FIELD_IN_COMMAND, 1);
}

static uint16_t cpl_internal_error(void)
{
	return nvme_status_word(SCT_GENERIC_COMMAND_STATUS,
				       SC_INTERNAL_DEVICE_ERROR, 1);
}

static uint16_t cpl_invalid_qid(void)
{
	return nvme_status_word(SCT_COMMAND_SPECIFIC_STATUS,
				       SC_INVALID_QUEUE_IDENTIFIER, 1);
}

static uint16_t cpl_invalid_log_page(void)
{
	return nvme_status_word(SCT_COMMAND_SPECIFIC_STATUS,
				       SC_INVALID_LOG_PAGE, 1);
}

static uint16_t cmd_cid(const struct nvme_fw_cmd *cmd)
{
	return (cmd->dword[0] >> 16) & 0xffffu;
}

static uint8_t cmd_opcode(const struct nvme_fw_cmd *cmd)
{
	return cmd->dword[0] & 0xffu;
}

static uint64_t cmd_prp1(const struct nvme_fw_cmd *cmd)
{
	return ((uint64_t)cmd->dword[7] << 32) | cmd->dword[6];
}

static uint64_t cmd_prp2(const struct nvme_fw_cmd *cmd)
{
	return ((uint64_t)cmd->dword[9] << 32) | cmd->dword[8];
}

static int reg_read32(struct fw_state *fw, uint32_t offset, uint32_t *value)
{
	struct nvme_fw_reg_io reg = {
		.offset = offset,
	};

	if (ioctl(fw->fd, NVME_FW_IOC_READ32, &reg) < 0)
		return -1;
	*value = reg.value;
	return 0;
}

static int reg_write32(struct fw_state *fw, uint32_t offset, uint32_t value)
{
	struct nvme_fw_reg_io reg = {
		.offset = offset,
		.value = value,
	};

	return ioctl(fw->fd, NVME_FW_IOC_WRITE32, &reg);
}

static int set_nvme_status_fields(struct fw_state *fw, unsigned int rdy,
					  unsigned int shst)
{
	uint32_t value = ((shst & 0x3u) << NVME_STATUS_CSTS_SHST_SHIFT) |
			 ((rdy & 0x1u) ? NVME_STATUS_CSTS_RDY : 0u);

	if (reg_write32(fw, NVME_FW_REG_NVME_STATUS, value) < 0) {
		perror("write NVME_STATUS");
		return -1;
	}

	FW_LOG("nvme_fw_daemon: CSTS.RDY=%u CSTS.SHST=%u\n", rdy & 1u, shst & 3u);
	return 0;
}

static int set_nvme_csts_rdy(struct fw_state *fw, unsigned int rdy)
{
	uint32_t status = 0;
	unsigned int shst = 0;

	if (reg_read32(fw, NVME_FW_REG_NVME_STATUS, &status) == 0)
		shst = (status >> NVME_STATUS_CSTS_SHST_SHIFT) & 0x3u;
	return set_nvme_status_fields(fw, rdy, shst);
}

static int set_nvme_csts_shst(struct fw_state *fw, unsigned int shst)
{
	uint32_t status = 0;
	unsigned int rdy = 0;

	if (reg_read32(fw, NVME_FW_REG_NVME_STATUS, &status) == 0)
		rdy = !!(status & NVME_STATUS_CSTS_RDY);
	return set_nvme_status_fields(fw, rdy, shst);
}

static int set_nvme_admin_queue(struct fw_state *fw, unsigned int sq_valid,
					unsigned int cq_valid, unsigned int cq_irq_en)
{
	uint32_t value = ((cq_irq_en & 1u) << 2) |
			 ((sq_valid & 1u) << 1) |
			 (cq_valid & 1u);

	if (reg_write32(fw, NVME_FW_REG_ADMIN_QUEUE, value) < 0) {
		perror("write ADMIN_QUEUE");
		return -1;
	}

	FW_LOG("nvme_fw_daemon: ADMIN_QUEUE sq=%u cq=%u irq=%u raw=0x%08x\n",
	       sq_valid & 1u, cq_valid & 1u, cq_irq_en & 1u, value);
	return 0;
}

static int set_io_sq(struct fw_state *fw, unsigned int idx, unsigned int valid,
		     unsigned int cq_vector, unsigned int qsize, uint64_t pcie_base)
{
	uint32_t off = NVME_FW_REG_IO_SQ_BASE + idx * 8u;
	uint32_t hi = ((uint32_t)(pcie_base >> 32) & 0xffffu) |
		      ((valid & 1u) << 16) |
		      ((cq_vector & 0xfu) << 17) |
		      ((qsize & 0xffu) << 24);

	if (reg_write32(fw, off, (uint32_t)pcie_base) < 0 ||
	    reg_write32(fw, off + 4u, hi) < 0) {
		perror("write IO_SQ");
		return -1;
	}
	return 0;
}

static int set_io_cq(struct fw_state *fw, unsigned int idx, unsigned int valid,
		     unsigned int irq_en, unsigned int irq_vector,
		     unsigned int qsize, uint64_t pcie_base)
{
	uint32_t off = NVME_FW_REG_IO_CQ_BASE + idx * 8u;
	uint32_t hi = ((uint32_t)(pcie_base >> 32) & 0xffffu) |
		      ((valid & 1u) << 16) |
		      ((irq_vector & 0x7u) << 17) |
		      ((irq_en & 1u) << 20) |
		      ((qsize & 0xffu) << 24);

	if (reg_write32(fw, off, (uint32_t)pcie_base) < 0 ||
	    reg_write32(fw, off + 4u, hi) < 0) {
		perror("write IO_CQ");
		return -1;
	}
	return 0;
}

static int clear_io_queues(struct fw_state *fw)
{
	unsigned int qid;

	for (qid = 0; qid < NVME_FW_MAX_IO_QUEUES; qid++) {
		fw->io_sq_cq_idx[qid] = 0;
		fw->io_cq_irq_vector[qid] = 0;
		if (set_io_cq(fw, qid, 0, 0, 0, 0, 0) < 0 ||
		    set_io_sq(fw, qid, 0, 0, 0, 0) < 0)
			return -1;
	}
	return 0;
}

static int trigger_pf0_msi(struct fw_state *fw)
{
	if (ioctl(fw->fd, NVME_FW_IOC_TRIGGER_PF0_MSI) < 0) {
		perror("TRIGGER_PF0_MSI");
		return -1;
	}
	return 0;
}

static int config_pf0_msi_vector(struct fw_state *fw, unsigned int vector)
{
	struct nvme_fw_msi_config cfg = {
		.enable = 1,
		.vector = vector & 0x7u,
		.threshold = 1,
	};

	if (!fw->enable_pf0_msi)
		return 0;
	if (fw->pf0_msi_vector == cfg.vector)
		return 0;
	if (ioctl(fw->fd, NVME_FW_IOC_CONFIG_PF0_MSI, &cfg) < 0) {
		perror("CONFIG_PF0_MSI");
		return -1;
	}
	fw->pf0_msi_vector = cfg.vector;
	FW_LOG("nvme_fw_daemon: PF0 manual MSI vector=%u\n", cfg.vector);
	return 0;
}

static int config_pf0_msi(struct fw_state *fw)
{
	fw->pf0_msi_vector = ~0u;
	return config_pf0_msi_vector(fw, 0);
}

static unsigned int completion_msi_vector(const struct fw_state *fw, unsigned int sqid)
{
	unsigned int cq_idx;

	if (sqid == 0 || sqid > NVME_FW_MAX_IO_QUEUES)
		return 0;
	cq_idx = fw->io_sq_cq_idx[sqid - 1u];
	if (cq_idx >= NVME_FW_MAX_IO_QUEUES)
		return 0;
	return fw->io_cq_irq_vector[cq_idx] & 0x7u;
}

static int post_completion(struct fw_state *fw, const struct nvme_fw_cpl *cpl,
				   int notify_pf0, unsigned int msi_vector)
{
	if (ioctl(fw->fd, NVME_FW_IOC_COMPLETE, cpl) < 0) {
		perror("COMPLETE");
		return -1;
	}
	if (notify_pf0 && fw->enable_pf0_msi) {
		if (config_pf0_msi_vector(fw, msi_vector) < 0)
			return -1;
		FW_LOG("nvme_fw_daemon: trigger PF0 MSI vector=%u sqid=%u cid=%u\n",
		       msi_vector & 0x7u, cpl->sqid, cpl->cid);
		return trigger_pf0_msi(fw);
	}
	return 0;
}

static int set_auto_nvme_cpl(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			     uint32_t specific, uint16_t status)
{
	struct nvme_fw_cpl cpl = {
		.type = NVME_FW_CPL_AUTO,
		.slot = cmd->slot,
		.specific = specific,
		.status = status,
	};

	return post_completion(fw, &cpl, 1, completion_msi_vector(fw, cmd->qid));
}

static int set_nvme_slot_release(struct fw_state *fw, const struct nvme_fw_cmd *cmd)
{
	struct nvme_fw_cpl cpl = {
		.type = NVME_FW_CPL_SLOT_RELEASE,
		.slot = cmd->slot,
	};

	return post_completion(fw, &cpl, 0, 0);
}

static int set_nvme_cpl(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			uint32_t specific, uint16_t status)
{
	struct nvme_fw_cpl cpl = {
		.type = NVME_FW_CPL_ONLY,
		.sqid = cmd->qid,
		.cid = cmd_cid(cmd),
		.slot = cmd->slot,
		.specific = specific,
		.status = status,
	};

	return post_completion(fw, &cpl, 1, completion_msi_vector(fw, cmd->qid));
}

static uint32_t set_num_of_queue(struct fw_state *fw, uint32_t cdw11)
{
	unsigned int nsqr = cdw11 & 0xffffu;
	unsigned int ncqr = (cdw11 >> 16) & 0xffffu;

	fw->iosq_alloc = nsqr >= NVME_FW_MAX_IO_QUEUES ?
		NVME_FW_MAX_IO_QUEUES : nsqr + 1u;
	fw->iocq_alloc = ncqr >= NVME_FW_MAX_IO_QUEUES ?
		NVME_FW_MAX_IO_QUEUES : ncqr + 1u;

	FW_LOG("nvme_fw_daemon: queues requested nsqr=%u ncqr=%u allocated iosq=%u iocq=%u\n",
	       nsqr, ncqr, fw->iosq_alloc, fw->iocq_alloc);
	return ((fw->iocq_alloc - 1u) << 16) | (fw->iosq_alloc - 1u);
}

static uint32_t get_num_of_queue(struct fw_state *fw)
{
	return ((fw->iocq_alloc - 1u) << 16) | (fw->iosq_alloc - 1u);
}

static void admin_success(uint32_t *specific, uint16_t *status)
{
	*specific = 0;
	*status = cpl_success();
}

static int handle_set_features(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			       uint32_t *specific, uint16_t *status)
{
	uint32_t fid = cmd->dword[10] & 0xffu;

	admin_success(specific, status);
	switch (fid) {
	case FEAT_NUMBER_OF_QUEUES:
		*specific = set_num_of_queue(fw, cmd->dword[11]);
		break;
	case FEAT_INTERRUPT_COALESCING:
	case FEAT_ARBITRATION:
	case FEAT_ASYNC_EVENT_CONFIG:
	case FEAT_POWER_MANAGEMENT:
	case FEAT_TIMESTAMP:
	case FEAT_SOFTWARE_PROGRESS_MARKER:
		break;
	case FEAT_VOLATILE_WRITE_CACHE:
		fw->cache_en = cmd->dword[11] & 0x1u;
		FW_LOG("nvme_fw_daemon: Set VWC=%u\n", fw->cache_en);
		break;
	default:
		fprintf(stderr, "nvme_fw_daemon: unsupported Set Features FID=0x%x\n", fid);
		*status = cpl_invalid_field();
		break;
	}
	return 0;
}

static int handle_get_features(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			       uint32_t *specific, uint16_t *status)
{
	uint32_t fid = cmd->dword[10] & 0xffu;

	admin_success(specific, status);
	switch (fid) {
	case FEAT_NUMBER_OF_QUEUES:
		*specific = get_num_of_queue(fw);
		break;
	case FEAT_LBA_RANGE_TYPE:
		*status = cpl_invalid_field();
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
		fprintf(stderr, "nvme_fw_daemon: unsupported Get Features FID=0x%x\n", fid);
		*status = cpl_invalid_field();
		break;
	}
	return 0;
}

static int handle_create_io_sq(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffu;
	uint32_t qsize = (cmd->dword[10] >> 16) & 0xffffu;
	uint32_t cqid = cmd->dword[11] & 0xffffu;
	uint64_t prp1 = cmd_prp1(cmd);

	admin_success(specific, status);
	FW_LOG("nvme_fw_daemon: Create IO SQ qid=%u cqid=%u qsize=%u prp1=0x%llx\n",
	       qid, cqid, qsize, (unsigned long long)prp1);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES || qsize >= 0x100u ||
	    !cqid || cqid > NVME_FW_MAX_IO_QUEUES) {
		*status = cpl_invalid_qid();
		return 0;
	}
	if ((prp1 & 0x3ull) || (prp1 >> 48)) {
		*status = cpl_invalid_field();
		return 0;
	}
	if (set_io_sq(fw, qid - 1u, 1, cqid, qsize, prp1) < 0)
		return -1;
	fw->io_sq_cq_idx[qid - 1u] = cqid - 1u;
	FW_LOG("nvme_fw_daemon: IO SQ qid=%u uses CQ qid=%u index=%u MSI vector=%u\n",
	       qid, cqid, cqid - 1u, fw->io_cq_irq_vector[cqid - 1u] & 0x7u);
	return 0;
}

static int handle_create_io_cq(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffu;
	uint32_t qsize = (cmd->dword[10] >> 16) & 0xffffu;
	uint32_t irq_en = (cmd->dword[11] >> 1) & 0x1u;
	uint32_t irq_vector = (cmd->dword[11] >> 16) & 0xffffu;
	uint64_t prp1 = cmd_prp1(cmd);

	admin_success(specific, status);
	FW_LOG("nvme_fw_daemon: Create IO CQ qid=%u iv=%u ien=%u qsize=%u prp1=0x%llx\n",
	       qid, irq_vector, irq_en, qsize, (unsigned long long)prp1);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES || qsize >= 0x100u) {
		*status = cpl_invalid_qid();
		return 0;
	}
	if (irq_vector >= 8 || (prp1 & 0x3ull) || (prp1 >> 48)) {
		*status = cpl_invalid_field();
		return 0;
	}
	if (set_io_cq(fw, qid - 1u, 1, irq_en, irq_vector, qsize, prp1) < 0)
		return -1;
	fw->io_cq_irq_vector[qid - 1u] = irq_vector & 0x7u;
	FW_LOG("nvme_fw_daemon: IO CQ qid=%u index=%u irq_en=%u MSI vector=%u\n",
	       qid, qid - 1u, irq_en, fw->io_cq_irq_vector[qid - 1u]);
	return 0;
}

static int handle_delete_io_sq(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffu;

	admin_success(specific, status);
	FW_LOG("nvme_fw_daemon: Delete IO SQ qid=%u\n", qid);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES) {
		*status = cpl_invalid_qid();
		return 0;
	}
	if (set_io_sq(fw, qid - 1u, 0, 0, 0, 0) < 0)
		return -1;
	fw->io_sq_cq_idx[qid - 1u] = 0;
	return 0;
}

static int handle_delete_io_cq(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffu;

	admin_success(specific, status);
	FW_LOG("nvme_fw_daemon: Delete IO CQ qid=%u\n", qid);
	if (!qid || qid > NVME_FW_MAX_IO_QUEUES) {
		*status = cpl_invalid_qid();
		return 0;
	}
	if (set_io_cq(fw, qid - 1u, 0, 0, 0, 0, 0) < 0)
		return -1;
	fw->io_cq_irq_vector[qid - 1u] = 0;
	return 0;
}

static void put_le16(uint8_t *buf, size_t off, uint16_t v)
{
	buf[off + 0] = v & 0xffu;
	buf[off + 1] = (v >> 8) & 0xffu;
}

static void put_le32(uint8_t *buf, size_t off, uint32_t v)
{
	put_le16(buf, off, v & 0xffffu);
	put_le16(buf, off + 2, v >> 16);
}

static void put_le64(uint8_t *buf, size_t off, uint64_t v)
{
	put_le32(buf, off, v & 0xffffffffu);
	put_le32(buf, off + 4, v >> 32);
}

static void put_ascii_padded(uint8_t *buf, size_t off, size_t len, const char *s)
{
	size_t i;

	memset(buf + off, ' ', len);
	for (i = 0; i < len && s[i]; i++)
		buf[off + i] = (uint8_t)s[i];
}

static void fill_identify_controller(uint8_t *buf)
{
	memset(buf, 0, NVME_FW_STAGE_SIZE);
	put_le16(buf, 0, 0x1edc);
	put_le16(buf, 2, 0x1edc);
	put_ascii_padded(buf, 4, 20, "S970SIM0001");
	put_ascii_padded(buf, 24, 40, "Samsung SSD 970 PRO");
	put_ascii_padded(buf, 64, 8, "SIM9701");
	buf[73] = 0xe4;
	buf[74] = 0xd2;
	buf[75] = 0x5c;
	buf[77] = 0x8;
	put_le16(buf, 78, 0x9);
	put_le64(buf, 280, FW_NVME_STORAGE_BYTES);
	buf[258] = 0x3;
	buf[259] = 0x3;
	buf[260] = 0x3;
	buf[262] = 0x8;
	buf[512] = 0x66;
	buf[513] = 0x44;
	put_le32(buf, 516, 1);
	buf[525] = 0x1;
	put_le16(buf, 2048, 0x09c4);
}

static void fill_identify_namespace(uint8_t *buf)
{
	memset(buf, 0, NVME_FW_STAGE_SIZE);
	put_le64(buf, 0, FW_NVME_BLOCKS);
	put_le64(buf, 8, FW_NVME_BLOCKS);
	put_le64(buf, 16, FW_NVME_BLOCKS);
	buf[25] = 0x0;
	buf[26] = 0x0;
	put_le16(buf, 128, 0x0);
	buf[130] = 0x0c;
	buf[131] = 0x2;
}

static int get_stage_info(struct fw_state *fw)
{
	struct nvme_fw_stage_info info;

	if (fw->stage_dma_addr && fw->stage_size)
		return 0;
	if (ioctl(fw->fd, NVME_FW_IOC_GET_STAGE_INFO, &info) < 0) {
		perror("GET_STAGE_INFO");
		return -1;
	}
	fw->stage_dma_addr = info.dma_addr;
	fw->stage_size = info.size;
	if (fw->stage_size < NVME_FW_STAGE_SIZE) {
		fprintf(stderr, "nvme_fw_daemon: stage buffer too small: 0x%x\n", fw->stage_size);
		return -1;
	}
	FW_LOG("nvme_fw_daemon: stage dma=0x%llx size=0x%x\n",
	       (unsigned long long)fw->stage_dma_addr, fw->stage_size);
	return 0;
}

static int stage_write(struct fw_state *fw, const uint8_t *buf, uint32_t len)
{
	struct nvme_fw_stage_write wr = {
		.user_ptr = (uintptr_t)buf,
		.offset = 0,
		.len = len,
	};

	if (get_stage_info(fw) < 0)
		return -1;
	if (ioctl(fw->fd, NVME_FW_IOC_STAGE_WRITE, &wr) < 0) {
		perror("STAGE_WRITE");
		return -1;
	}
	return 0;
}

static int submit_dma_and_wait(struct fw_state *fw, struct nvme_fw_dma_batch *batch)
{
	struct nvme_fw_ring_status st;
	struct nvme_fw_wait_pid wait = { 0 };

	if (!batch->count)
		return 0;
	if (ioctl(fw->fd, NVME_FW_IOC_RING_STATUS, &st) < 0) {
		perror("RING_STATUS");
		return -1;
	}
	wait.target_pid = st.pid_submit + batch->count;
	wait.timeout_ms = 2000;
	if (ioctl(fw->fd, NVME_FW_IOC_SUBMIT_BATCH, batch) < 0) {
		perror("SUBMIT_BATCH");
		return -1;
	}
	if (ioctl(fw->fd, NVME_FW_IOC_WAIT_PID, &wait) < 0) {
		perror("WAIT_PID");
		return -1;
	}
	return 0;
}

static int dma_stage_to_card(struct fw_state *fw, uint32_t len)
{
	struct nvme_fw_dma_batch batch = { 0 };
	struct nvme_fw_dma_desc *d = &batch.desc[0];

	batch.count = 1;
	d->type = NVME_FW_DMA_DIRECT_TYPE;
	d->direction = NVME_FW_DMA_RX_DIRECTION;
	d->len = len;
	d->dev_addr = fw->mgmt_dev_addr;
	d->pcie_addr = fw->stage_dma_addr;
	return submit_dma_and_wait(fw, &batch);
}

static int dma_card_to_prp(struct fw_state *fw, uint64_t prp1, uint64_t prp2, uint32_t len)
{
	struct nvme_fw_dma_batch batch = { 0 };
	uint32_t first_len;

	if (!len || len > NVME_FW_STAGE_SIZE || (prp1 & 0x3ull) || (prp2 & 0x3ull))
		return -1;
	first_len = 0x1000u - (uint32_t)(prp1 & 0xfffu);
	if (first_len > len)
		first_len = len;

	batch.desc[0].type = NVME_FW_DMA_DIRECT_TYPE;
	batch.desc[0].direction = NVME_FW_DMA_TX_DIRECTION;
	batch.desc[0].len = first_len;
	batch.desc[0].dev_addr = fw->mgmt_dev_addr;
	batch.desc[0].pcie_addr = prp1;
	batch.count = 1;

	if (first_len < len) {
		batch.desc[1].type = NVME_FW_DMA_DIRECT_TYPE;
		batch.desc[1].direction = NVME_FW_DMA_TX_DIRECTION;
		batch.desc[1].len = len - first_len;
		batch.desc[1].dev_addr = fw->mgmt_dev_addr + first_len;
		batch.desc[1].pcie_addr = prp2;
		batch.count = 2;
	}
	return submit_dma_and_wait(fw, &batch);
}

static int stage_and_dma_to_prp(struct fw_state *fw, const uint8_t *buf,
				uint32_t len, uint64_t prp1, uint64_t prp2)
{
	if (stage_write(fw, buf, NVME_FW_STAGE_SIZE) < 0)
		return -1;
	if (dma_stage_to_card(fw, NVME_FW_STAGE_SIZE) < 0)
		return -1;
	return dma_card_to_prp(fw, prp1, prp2, len);
}

static int handle_identify(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			   uint32_t *specific, uint16_t *status)
{
	uint8_t buf[NVME_FW_STAGE_SIZE];
	uint32_t cns = cmd->dword[10] & 0xffu;

	admin_success(specific, status);
	switch (cns) {
	case 1:
	case 6:
		fill_identify_controller(buf);
		break;
	case 0:
	case 5:
		fill_identify_namespace(buf);
		break;
	case 2:
	case 7:
		memset(buf, 0, sizeof(buf));
		put_le32(buf, 0, 1);
		break;
	case 3:
		memset(buf, 0, sizeof(buf));
		break;
	default:
		*status = cpl_invalid_field();
		return 0;
	}
	if (!fw->enable_dma_data) {
		fprintf(stderr,
			"nvme_fw_daemon: Identify CNS=0x%x decoded, DMA disabled by default; use --enable-dma-data after BAR2/DMA smoke tests\n",
			cns);
		*status = cpl_invalid_field();
		return 0;
	}
	FW_LOG("nvme_fw_daemon: Identify CNS=0x%x DMA PRP1=0x%llx PRP2=0x%llx\n",
	       cns, (unsigned long long)cmd_prp1(cmd), (unsigned long long)cmd_prp2(cmd));
	if (stage_and_dma_to_prp(fw, buf, NVME_FW_STAGE_SIZE, cmd_prp1(cmd), cmd_prp2(cmd)) < 0)
		*status = cpl_internal_error();
	return 0;
}

static int handle_get_log_page(struct fw_state *fw, const struct nvme_fw_cmd *cmd,
			       uint32_t *specific, uint16_t *status)
{
	uint8_t buf[NVME_FW_STAGE_SIZE];
	uint32_t lid = cmd->dword[10] & 0xffu;
	uint32_t numd = ((cmd->dword[11] & 0xffffu) << 16) |
			 ((cmd->dword[10] >> 16) & 0xffffu);
	uint32_t len = (numd + 1u) * 4u;

	admin_success(specific, status);
	if (!len || len > NVME_FW_STAGE_SIZE) {
		*status = cpl_invalid_field();
		return 0;
	}
	memset(buf, 0, sizeof(buf));
	switch (lid) {
	case 0x01:
		break;
	case 0x02:
		buf[1] = 0x2c;
		buf[2] = 0x01;
		buf[3] = 100;
		buf[4] = 10;
		break;
	case 0x03:
		buf[0] = 0x01;
		break;
	default:
		*status = cpl_invalid_log_page();
		return 0;
	}
	if (!fw->enable_dma_data) {
		fprintf(stderr,
			"nvme_fw_daemon: Get Log Page LID=0x%x decoded, DMA disabled by default; use --enable-dma-data after BAR2/DMA smoke tests\n",
			lid);
		*status = cpl_invalid_field();
		return 0;
	}
	FW_LOG("nvme_fw_daemon: Get Log Page LID=0x%x len=%u DMA\n", lid, len);
	if (stage_and_dma_to_prp(fw, buf, len, cmd_prp1(cmd), cmd_prp2(cmd)) < 0)
		*status = cpl_internal_error();
	return 0;
}

static int handle_nvme_admin_cmd(struct fw_state *fw, const struct nvme_fw_cmd *cmd)
{
	uint32_t specific = 0;
	uint16_t status = cpl_success();
	uint8_t opc = cmd_opcode(cmd);
	int need_cpl = 1;
	int need_slot_release = 0;
	int ret = 0;

	FW_LOG("nvme_fw_daemon: Admin q=%u slot=%u cid=%u opc=0x%02x dw10=0x%08x dw11=0x%08x prp1=0x%llx prp2=0x%llx\n",
	       cmd->qid, cmd->slot, cmd_cid(cmd), opc, cmd->dword[10], cmd->dword[11],
	       (unsigned long long)cmd_prp1(cmd), (unsigned long long)cmd_prp2(cmd));

	switch (opc) {
	case ADMIN_SET_FEATURES:
		ret = handle_set_features(fw, cmd, &specific, &status);
		break;
	case ADMIN_CREATE_IO_CQ:
		ret = handle_create_io_cq(fw, cmd, &specific, &status);
		break;
	case ADMIN_CREATE_IO_SQ:
		ret = handle_create_io_sq(fw, cmd, &specific, &status);
		break;
	case ADMIN_IDENTIFY:
		ret = handle_identify(fw, cmd, &specific, &status);
		break;
	case ADMIN_GET_FEATURES:
		ret = handle_get_features(fw, cmd, &specific, &status);
		break;
	case ADMIN_DELETE_IO_CQ:
		ret = handle_delete_io_cq(fw, cmd, &specific, &status);
		break;
	case ADMIN_DELETE_IO_SQ:
		ret = handle_delete_io_sq(fw, cmd, &specific, &status);
		break;
	case ADMIN_ASYNC_EVENT_REQUEST:
		need_cpl = 0;
		need_slot_release = 1;
		break;
	case ADMIN_GET_LOG_PAGE:
		ret = handle_get_log_page(fw, cmd, &specific, &status);
		break;
	case ADMIN_KEEP_ALIVE:
	case ADMIN_FORMAT_NVM:
	case ADMIN_VENDOR_LIBNVM:
		admin_success(&specific, &status);
		break;
	case ADMIN_ABORT:
		admin_success(&specific, &status);
		break;
	case ADMIN_SECURITY_SEND:
	case ADMIN_SECURITY_RECEIVE:
	case ADMIN_DOORBELL_BUFFER_CONFIG:
	case ADMIN_FIRMWARE_ACTIVATE:
	case ADMIN_FIRMWARE_IMAGE_DOWNLOAD:
	case ADMIN_DEVICE_SELF_TEST:
	case ADMIN_NAMESPACE_MANAGEMENT:
	case ADMIN_NAMESPACE_ATTACHMENT:
	case ADMIN_DIRECTIVE_SEND:
	case ADMIN_DIRECTIVE_RECEIVE:
	case ADMIN_VIRTUALIZATION_MANAGEMENT:
	case ADMIN_NVME_MI_SEND:
	case ADMIN_NVME_MI_RECEIVE:
	case ADMIN_CAPACITY_MANAGEMENT:
	case ADMIN_LOCKDOWN:
	case ADMIN_SANITIZE:
	case ADMIN_GET_LBA_STATUS:
	default:
		status = cpl_invalid_opcode();
		break;
	}
	if (ret < 0)
		return ret;

	if (need_cpl)
		return set_auto_nvme_cpl(fw, cmd, specific, status);
	if (need_slot_release)
		return set_nvme_slot_release(fw, cmd);
	return set_nvme_cpl(fw, cmd, specific, status);
}

static int handle_nvme_io_cmd(struct fw_state *fw, const struct nvme_fw_cmd *cmd)
{
	uint8_t opc = cmd_opcode(cmd);

	FW_LOG("nvme_fw_daemon: IO q=%u slot=%u cid=%u opc=0x%02x slba=0x%08x_%08x nlb=%u\n",
	       cmd->qid, cmd->slot, cmd_cid(cmd), opc, cmd->dword[11], cmd->dword[10],
	       cmd->dword[12] & 0xffffu);

	switch (opc) {
	case IO_NVM_FLUSH:
		if (set_nvme_cpl(fw, cmd, 0, cpl_success()) < 0)
			return -1;
		return set_nvme_slot_release(fw, cmd);
	case IO_NVM_READ: {
		uint8_t zero[NVME_FW_STAGE_SIZE];
		uint32_t blocks = (cmd->dword[12] & 0xffffu) + 1u;
		uint32_t len = blocks * FW_NVME_BLOCK_BYTES;

		if (len > NVME_FW_STAGE_SIZE) {
			fprintf(stderr,
				"nvme_fw_daemon: IO read len=0x%x exceeds staging buffer\n", len);
			if (set_nvme_cpl(fw, cmd, 0, cpl_internal_error()) < 0)
				return -1;
			return set_nvme_slot_release(fw, cmd);
		}

		memset(zero, 0, sizeof(zero));
		FW_LOG("nvme_fw_daemon: IO read zero-fill len=0x%x PRP1=0x%llx PRP2=0x%llx io_dma=%d\n",
		       len, (unsigned long long)cmd_prp1(cmd), (unsigned long long)cmd_prp2(cmd),
		       fw->enable_io_dma_data);
		if (fw->enable_io_dma_data) {
			FW_LOG("nvme_fw_daemon: IO read DMA start slot=%u cid=%u\n",
			       cmd->slot, cmd_cid(cmd));
			if (stage_and_dma_to_prp(fw, zero, len, cmd_prp1(cmd), cmd_prp2(cmd)) < 0) {
				fprintf(stderr, "nvme_fw_daemon: IO read DMA failed slot=%u cid=%u\n",
					cmd->slot, cmd_cid(cmd));
				if (set_nvme_cpl(fw, cmd, 0, cpl_internal_error()) < 0)
					return -1;
				return set_nvme_slot_release(fw, cmd);
			}
			FW_LOG("nvme_fw_daemon: IO read DMA done slot=%u cid=%u\n",
			       cmd->slot, cmd_cid(cmd));
		} else {
			FW_LOG("nvme_fw_daemon: IO read DMA skipped slot=%u cid=%u\n",
			       cmd->slot, cmd_cid(cmd));
		}
		FW_LOG("nvme_fw_daemon: IO read completion slot=%u qid=%u cid=%u\n",
		       cmd->slot, cmd->qid, cmd_cid(cmd));
		if (set_nvme_cpl(fw, cmd, 0, cpl_success()) < 0)
			return -1;
		return set_nvme_slot_release(fw, cmd);
	}
	case IO_NVM_WRITE:
		FW_LOG("nvme_fw_daemon: IO write discard completion slot=%u qid=%u cid=%u\n",
		       cmd->slot, cmd->qid, cmd_cid(cmd));
		if (set_nvme_cpl(fw, cmd, 0, cpl_success()) < 0)
			return -1;
		return set_nvme_slot_release(fw, cmd);
	default:
		if (!fw->complete_unsupported)
			return 0;
		if (set_nvme_cpl(fw, cmd, 0, cpl_invalid_opcode()) < 0)
			return -1;
		return set_nvme_slot_release(fw, cmd);
	}
}

static int get_nvme_cmd(struct fw_state *fw, struct nvme_fw_cmd *cmd)
{
	memset(cmd, 0, sizeof(*cmd));
	if (ioctl(fw->fd, NVME_FW_IOC_FETCH_CMD, cmd) < 0) {
		perror("FETCH_CMD");
		return -1;
	}
	return cmd->valid ? 1 : 0;
}

static int firmware_enter_running(struct fw_state *fw)
{
	if (set_nvme_admin_queue(fw, 1, 1, 1) < 0 ||
	    set_nvme_csts_rdy(fw, 1) < 0)
		return -1;
	fw->task = FW_TASK_RUNNING;
	FW_LOG("nvme_fw_daemon: NVMe ready\n");
	return 0;
}

static int firmware_shutdown(struct fw_state *fw)
{
	if (set_nvme_csts_shst(fw, 1) < 0 ||
	    clear_io_queues(fw) < 0 ||
	    set_nvme_admin_queue(fw, 0, 0, 0) < 0 ||
	    set_nvme_csts_shst(fw, 2) < 0)
		return -1;
	fw->cache_en = 0;
	fw->wait_reset_start_ns = now_ns();
	fw->task = FW_TASK_WAIT_RESET;
	FW_LOG("nvme_fw_daemon: NVMe shutdown\n");
	return 0;
}

static int firmware_clear_for_rearm(struct fw_state *fw)
{
	if (set_nvme_status_fields(fw, 0, 0) < 0 ||
	    set_nvme_admin_queue(fw, 0, 0, 0) < 0 ||
	    clear_io_queues(fw) < 0)
		return -1;
	fw->cache_en = 0;
	/* We just forced the controller-visible state to disabled.
	 * Accept the next CC.EN=1 as a fresh host initialization edge.
	 */
	fw->observed_disabled = 1;
	fw->wait_reset_start_ns = 0;
	fw->task = FW_TASK_IDLE;
	FW_LOG("nvme_fw_daemon: NVMe disabled/rearmed\n");
	return 0;
}

static int firmware_poll(struct fw_state *fw)
{
	uint32_t status = 0;
	unsigned int cc_en;
	unsigned int cc_shn;

	if (reg_read32(fw, NVME_FW_REG_NVME_STATUS, &status) < 0) {
		perror("read NVME_STATUS");
		return -1;
	}

	cc_en = !!(status & NVME_STATUS_CC_EN);
	cc_shn = (status & NVME_STATUS_CC_SHN_MASK) >> NVME_STATUS_CC_SHN_SHIFT;

	if (!fw->last_status_valid ||
	    fw->last_cc_en != cc_en || fw->last_cc_shn != cc_shn) {
		FW_LOG("nvme_fw_daemon: NVME_STATUS=0x%08x CC.EN=%u CC.SHN=%u CSTS.RDY=%u CSTS.SHST=%u\n",
		       status, cc_en, cc_shn, !!(status & NVME_STATUS_CSTS_RDY),
		       (status >> NVME_STATUS_CSTS_SHST_SHIFT) & 0x3u);
		fw->last_status_valid = 1;
		fw->last_cc_en = cc_en;
		fw->last_cc_shn = cc_shn;
	}

	switch (fw->task) {
	case FW_TASK_IDLE:
		if (!cc_en)
			fw->observed_disabled = 1;
		else if (fw->observed_disabled)
			fw->task = FW_TASK_WAIT_CC_EN;
		break;
	case FW_TASK_WAIT_CC_EN:
		if (!cc_en) {
			fw->observed_disabled = 1;
		} else if (fw->auto_ready) {
			fw->observed_disabled = 0;
			return firmware_enter_running(fw);
		}
		break;
	case FW_TASK_RUNNING:
		if (cc_shn) {
			fw->task = FW_TASK_SHUTDOWN;
			return firmware_shutdown(fw);
		}
		if (!cc_en) {
			fw->task = FW_TASK_WAIT_RESET;
			fw->wait_reset_start_ns = now_ns();
			break;
		}
		while (1) {
			struct nvme_fw_cmd cmd;
			int valid = get_nvme_cmd(fw, &cmd);

			if (valid < 0)
				return -1;
			if (!valid)
				break;
			if (cmd.qid == 0) {
				if (handle_nvme_admin_cmd(fw, &cmd) < 0)
					return -1;
			} else {
				if (handle_nvme_io_cmd(fw, &cmd) < 0)
					return -1;
			}
		}
		break;
	case FW_TASK_SHUTDOWN:
		return firmware_shutdown(fw);
	case FW_TASK_WAIT_RESET:
		if (!cc_en || (fw->wait_reset_start_ns &&
		    now_ns() - fw->wait_reset_start_ns >= FW_SHUTDOWN_REARM_NS))
			return firmware_clear_for_rearm(fw);
		break;
	}
	if (fw->status_once)
		stop = 1;
	return 0;
}

static void usage(const char *prog)
{
	fprintf(stderr,
		"usage: %s [-d /dev/nvme_fw0] [--run] [--open-only] [--poll-us N] [--status-once] [--verbose] [--enable-pf0-msi] [--disable-pf0-msi] [--enable-dma-data] [--disable-dma-data] [--disable-io-dma-data] [--no-auto-ready] [--no-complete-unsupported] [--mgmt-dev-addr ADDR]\n",
		prog);
}

static unsigned long long parse_ull(const char *s, const char *name)
{
	char *end = NULL;
	unsigned long long v;

	errno = 0;
	v = strtoull(s, &end, 0);
	if (errno || !end || *end) {
		fprintf(stderr, "invalid %s: %s\n", name, s);
		exit(2);
	}
	return v;
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/nvme_fw0";
	struct fw_state fw = {
		.poll_us = FW_DEFAULT_POLL_US,
		.iosq_alloc = NVME_FW_MAX_IO_QUEUES,
		.iocq_alloc = NVME_FW_MAX_IO_QUEUES,
		.observed_disabled = 1,
		.auto_ready = 1,
		.complete_unsupported = 1,
		.enable_pf0_msi = 1,
		.enable_dma_data = 1,
		.enable_io_dma_data = 1,
		.status_once = 0,
		.run = 1,
		.mgmt_dev_addr = FW_DEFAULT_MGMT_DEV_ADDR,
		.task = FW_TASK_IDLE,
	};
	int argi;

	for (argi = 1; argi < argc; argi++) {
		if (!strcmp(argv[argi], "--run")) {
			fw.run = 1;
		} else if (!strcmp(argv[argi], "--open-only")) {
			fw.run = 0;
		} else if (!strcmp(argv[argi], "-d") && argi + 1 < argc) {
			dev = argv[++argi];
		} else if (!strcmp(argv[argi], "--poll-us") && argi + 1 < argc) {
			fw.poll_us = (unsigned int)parse_ull(argv[++argi], "poll_us");
		} else if (!strcmp(argv[argi], "--no-auto-ready")) {
			fw.auto_ready = 0;
		} else if (!strcmp(argv[argi], "--no-complete-unsupported")) {
			fw.complete_unsupported = 0;
		} else if (!strcmp(argv[argi], "--enable-pf0-msi")) {
			fw.enable_pf0_msi = 1;
		} else if (!strcmp(argv[argi], "--disable-pf0-msi")) {
			fw.enable_pf0_msi = 0;
		} else if (!strcmp(argv[argi], "--enable-dma-data")) {
			fw.enable_dma_data = 1;
		} else if (!strcmp(argv[argi], "--disable-dma-data")) {
			fw.enable_dma_data = 0;
			fw.enable_io_dma_data = 0;
		} else if (!strcmp(argv[argi], "--disable-io-dma-data")) {
			fw.enable_io_dma_data = 0;
		} else if (!strcmp(argv[argi], "--status-once")) {
			fw.status_once = 1;
			fw.run = 1;
			fw.auto_ready = 0;
		} else if (!strcmp(argv[argi], "--verbose")) {
			verbose = 1;
		} else if (!strcmp(argv[argi], "--mgmt-dev-addr") && argi + 1 < argc) {
			fw.mgmt_dev_addr = parse_ull(argv[++argi], "mgmt_dev_addr");
		} else {
			usage(argv[0]);
			return 2;
		}
	}

	fw.fd = open(dev, O_RDWR);
	if (fw.fd < 0) {
		perror(dev);
		return 1;
	}

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	if (fw.enable_pf0_msi && config_pf0_msi(&fw) < 0) {
		close(fw.fd);
		return 1;
	}

	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);
	FW_LOG("nvme_fw_daemon: opened %s poll_us=%u mgmt_dev_addr=0x%llx pf0_msi=%d dma_data=%d io_dma_data=%d run=%d\n",
	       dev, fw.poll_us, (unsigned long long)fw.mgmt_dev_addr,
	       fw.enable_pf0_msi, fw.enable_dma_data, fw.enable_io_dma_data, fw.run);
	if (!fw.run) {
		FW_LOG("nvme_fw_daemon: safe open-only mode; pass --run to start BAR2 polling\n");
		close(fw.fd);
		return 0;
	}
	while (!stop) {
		if (firmware_poll(&fw) < 0) {
			close(fw.fd);
			return 1;
		}
		sleep_us(fw.poll_us);
	}

	close(fw.fd);
	return 0;
}
