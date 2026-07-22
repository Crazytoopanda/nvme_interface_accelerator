#include "auto_fw.h"
#include "auto_hw_regs.h"
#include "../memory_map.h"

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#ifdef __MICROBLAZE__
#include "xil_cache.h"
#include "xil_printf.h"
#include "xil_types.h"
#else
#define xil_printf(...) ((void)0)
#endif

#ifndef AUTO_FW_STORAGE_BYTES
#define AUTO_FW_STORAGE_BYTES               (63ULL * 1024ULL * 1024ULL * 1024ULL)
#endif

#ifndef AUTO_FW_BLOCK_BYTES
#define AUTO_FW_BLOCK_BYTES                 4096ULL
#endif

#ifndef AUTO_FW_DMA_WAIT_LIMIT
#define AUTO_FW_DMA_WAIT_LIMIT              10000000U
#endif

#ifndef AUTO_FW_MAX_CMDS_PER_SERVICE
#define AUTO_FW_MAX_CMDS_PER_SERVICE        32U
#endif

#ifndef AUTO_FW_USE_S1_AXI_CMD_WINDOW
#define AUTO_FW_USE_S1_AXI_CMD_WINDOW       1U
#endif

#ifndef AUTO_FW_TRACE_ADMIN
#define AUTO_FW_TRACE_ADMIN                 1U
#endif

#ifndef AUTO_FW_TRACE_AUTO
#define AUTO_FW_TRACE_AUTO                  1U
#endif

#ifndef AUTO_FW_TRACE_AUTO_EARLY_CMDS
#define AUTO_FW_TRACE_AUTO_EARLY_CMDS       32U
#endif

#ifndef AUTO_FW_TRACE_AUTO_PERIOD
#define AUTO_FW_TRACE_AUTO_PERIOD           1024U
#endif

#ifndef AUTO_FW_CQ_IRQ_RETRY_ENABLE
#define AUTO_FW_CQ_IRQ_RETRY_ENABLE         1U
#endif

#ifndef AUTO_FW_CQ_IRQ_RETRY_DELAY_SERVICE
#define AUTO_FW_CQ_IRQ_RETRY_DELAY_SERVICE  4096U
#endif

#ifndef AUTO_FW_CQ_IRQ_RETRY_MAX
#define AUTO_FW_CQ_IRQ_RETRY_MAX            3U
#endif

#define AUTO_FW_STAGE_SIZE                  4096U
#define AUTO_FW_BLOCKS                      (AUTO_FW_STORAGE_BYTES / AUTO_FW_BLOCK_BYTES)

#define ADMIN_DELETE_IO_SQ                  0x00U
#define ADMIN_CREATE_IO_SQ                  0x01U
#define ADMIN_GET_LOG_PAGE                  0x02U
#define ADMIN_DELETE_IO_CQ                  0x04U
#define ADMIN_CREATE_IO_CQ                  0x05U
#define ADMIN_IDENTIFY                      0x06U
#define ADMIN_ABORT                         0x08U
#define ADMIN_SET_FEATURES                  0x09U
#define ADMIN_GET_FEATURES                  0x0aU
#define ADMIN_ASYNC_EVENT_REQUEST           0x0cU
#define ADMIN_KEEP_ALIVE                    0x18U
#define ADMIN_FORMAT_NVM                    0x80U
#define ADMIN_VENDOR_LIBNVM                 0xc0U

#define IO_NVM_FLUSH                        0x00U
#define IO_NVM_WRITE                        0x01U
#define IO_NVM_READ                         0x02U

#define FEAT_ARBITRATION                    0x01U
#define FEAT_POWER_MANAGEMENT               0x02U
#define FEAT_LBA_RANGE_TYPE                 0x03U
#define FEAT_TEMPERATURE_THRESHOLD          0x04U
#define FEAT_VOLATILE_WRITE_CACHE           0x06U
#define FEAT_NUMBER_OF_QUEUES               0x07U
#define FEAT_INTERRUPT_COALESCING           0x08U
#define FEAT_ASYNC_EVENT_CONFIG             0x0bU
#define FEAT_POWER_STATE_TRANSITION         0x0cU
#define FEAT_TIMESTAMP                      0x0eU
#define FEAT_SOFTWARE_PROGRESS_MARKER       0x80U

#define SCT_GENERIC_COMMAND_STATUS          0U
#define SCT_COMMAND_SPECIFIC_STATUS         1U
#define SC_SUCCESSFUL_COMPLETION            0x00U
#define SC_INVALID_COMMAND_OPCODE           0x01U
#define SC_INVALID_FIELD_IN_COMMAND         0x02U
#define SC_INTERNAL_DEVICE_ERROR            0x06U
#define SC_INVALID_QUEUE_IDENTIFIER         0x01U
#define SC_INVALID_LOG_PAGE                 0x09U

enum auto_fw_task_state {
	AUTO_FW_TASK_IDLE = 0,
	AUTO_FW_TASK_WAIT_CC_EN,
	AUTO_FW_TASK_RUNNING,
	AUTO_FW_TASK_WAIT_RESET,
};

struct auto_fw_cmd {
	uint32_t qid;
	uint32_t slot;
	uint32_t seq;
	uint32_t dword[16];
};

struct auto_fw_state {
	enum auto_fw_task_state task;
	uint32_t observed_disabled;
	uint32_t cache_en;
	uint32_t num_io_sq_alloc;
	uint32_t num_io_cq_alloc;
	uint32_t io_sq_cq_idx[AUTO_MAX_IO_QUEUES];
	uint32_t io_cq_irq_vector[AUTO_MAX_IO_QUEUES];
	uint8_t direct_tx_tail;
	uint8_t direct_rx_tail;
	uint8_t auto_tx_tail;
	uint8_t auto_rx_tail;
	uint32_t last_status_valid;
	uint32_t last_cc_en;
	uint32_t last_cc_shn;
	uint32_t last_auto_trace_valid;
	uint32_t last_auto_status;
	uint32_t last_auto_error;
	uint32_t last_auto_cmd_count;
	uint32_t last_auto_dma_submit_count;
	uint32_t last_auto_dma_done_count;
	uint32_t last_auto_cq_write_count;
	uint32_t last_auto_unsupported_count;
	uint32_t last_auto_last_qid_slot;
	uint32_t last_auto_last_opcode;
	uint32_t last_auto_last_cqe_dw2;
	uint32_t last_auto_last_cqe_dw3;
	uint32_t cq_irq_retry_cq_write_count;
	uint32_t cq_irq_retry_cqe_dw2;
	uint32_t cq_irq_retry_cqe_dw3;
	uint32_t cq_irq_retry_cqid;
	uint32_t cq_irq_retry_age;
	uint32_t cq_irq_retry_count;
};

static struct auto_fw_state g_auto_fw;

static void auto_fw_write64(uint64_t lo_reg, uint64_t value)
{
	auto_reg_write(lo_reg, (uint32_t)value);
	auto_reg_write(lo_reg + 4U, (uint32_t)(value >> 32));
}

static uint32_t auto_fw_lower32(uint64_t value)
{
	return (uint32_t)(value & 0xffffffffULL);
}

static uint32_t auto_fw_upper32(uint64_t value)
{
	return (uint32_t)(value >> 32);
}

static uint32_t auto_fw_dma_head_word(void)
{
	return auto_reg_read(AUTO_HOST_DMA_FIFO_CNT);
}

static uint8_t auto_fw_head_direct_rx(uint32_t word)
{
	return (uint8_t)(word & 0xffU);
}

static uint8_t auto_fw_head_direct_tx(uint32_t word)
{
	return (uint8_t)((word >> 8) & 0xffU);
}

static uint8_t auto_fw_head_auto_rx(uint32_t word)
{
	return (uint8_t)((word >> 16) & 0xffU);
}

static uint8_t auto_fw_head_auto_tx(uint32_t word)
{
	return (uint8_t)((word >> 24) & 0xffU);
}

static void auto_fw_sync_dma_tails(void)
{
	uint32_t head = auto_fw_dma_head_word();

	g_auto_fw.direct_rx_tail = auto_fw_head_direct_rx(head);
	g_auto_fw.direct_tx_tail = auto_fw_head_direct_tx(head);
	g_auto_fw.auto_rx_tail = auto_fw_head_auto_rx(head);
	g_auto_fw.auto_tx_tail = auto_fw_head_auto_tx(head);
}

static uint32_t auto_fw_dma_credit(uint8_t head, uint8_t tail)
{
	return (uint32_t)((head - tail - 1U) & 0xffU);
}

static int auto_fw_wait_auto_dma_credit(uint32_t dir)
{
	uint32_t i;

	for(i = 0; i < AUTO_FW_DMA_WAIT_LIMIT; i++) {
		uint32_t head = auto_fw_dma_head_word();

		if(dir == AUTO_DMA_DIR_TX) {
			if(auto_fw_dma_credit(auto_fw_head_auto_tx(head), g_auto_fw.auto_tx_tail) != 0U)
				return 0;
		} else {
			if(auto_fw_dma_credit(auto_fw_head_auto_rx(head), g_auto_fw.auto_rx_tail) != 0U)
				return 0;
		}
	}

	return -1;
}

static int auto_fw_wait_direct_tx_done(void)
{
	uint32_t i;

	for(i = 0; i < AUTO_FW_DMA_WAIT_LIMIT; i++) {
		uint32_t head = auto_fw_dma_head_word();

		if(auto_fw_head_direct_tx(head) == g_auto_fw.direct_tx_tail)
			return 0;
	}

	return -1;
}

static void auto_fw_clean_dma_buffer(uint64_t addr, uint32_t size)
{
#ifdef __MICROBLAZE__
	Xil_DCacheFlushRange((UINTPTR)(unsigned long)addr, (UINTPTR)size);
#else
	(void)addr;
	(void)size;
#endif
}

static void auto_fw_write_dma_cmd(uint64_t dev_addr, uint32_t pcie_hi,
					  uint32_t pcie_lo, uint32_t ctrl,
					  uint32_t slot)
{
	auto_reg_write(AUTO_HOST_DMA_CMD_FIFO + 0U, auto_fw_lower32(dev_addr));
	auto_reg_write(AUTO_HOST_DMA_CMD_FIFO + 20U, auto_fw_upper32(dev_addr));
	auto_reg_write(AUTO_HOST_DMA_CMD_FIFO + 4U, pcie_hi);
	auto_reg_write(AUTO_HOST_DMA_CMD_FIFO + 8U, pcie_lo);
	auto_reg_write(AUTO_HOST_DMA_CMD_FIFO + 12U, ctrl);
	auto_reg_write(AUTO_HOST_DMA_CMD_FIFO + 16U, slot);
	auto_reg_write(AUTO_HOST_DMA_CMD_FIFO_TRIG, 1U);
}

static int auto_fw_submit_direct_tx_dma(uint64_t dev_addr, uint64_t pcie_addr,
						uint32_t len)
{
	uint32_t ctrl;

	if(len == 0U || len > AUTO_FW_STAGE_SIZE || ((pcie_addr & 0x3ULL) != 0ULL))
		return -1;

	ctrl = (AUTO_DMA_TYPE_DIRECT << 31) |
	       (AUTO_DMA_DIR_TX << 30) |
	       (len & 0x1fffU);
	auto_fw_write_dma_cmd(dev_addr, auto_fw_upper32(pcie_addr),
			       auto_fw_lower32(pcie_addr), ctrl, 0U);
	g_auto_fw.direct_tx_tail++;
	return auto_fw_wait_direct_tx_done();
}

static int auto_fw_submit_auto_dma(uint32_t slot, uint32_t segment,
					   uint64_t dev_addr, uint32_t dir,
					   uint32_t auto_completion)
{
	uint32_t ctrl;

	if(segment >= 256U)
		return -1;
	if(auto_fw_wait_auto_dma_credit(dir) != 0)
		return -1;

	ctrl = (AUTO_DMA_TYPE_AUTO << 31) |
	       ((dir & 1U) << 30) |
	       ((segment & 0x1ffU) << 14) |
	       ((auto_completion & 1U) << 13);
	auto_fw_write_dma_cmd(dev_addr, 0U, 0U, ctrl, slot & AUTO_CMD_FIFO_SLOT_MASK);
	if(dir == AUTO_DMA_DIR_TX)
		g_auto_fw.auto_tx_tail++;
	else
		g_auto_fw.auto_rx_tail++;
	return 0;
}

static uint16_t auto_fw_cpl_status(uint32_t sct, uint32_t sc, uint32_t dnr)
{
	return (uint16_t)(((sc & 0xffU) << 1) |
			  ((sct & 0x7U) << 9) |
			  ((dnr & 0x1U) << 15));
}

static uint16_t auto_fw_cpl_success(void)
{
	return auto_fw_cpl_status(SCT_GENERIC_COMMAND_STATUS, SC_SUCCESSFUL_COMPLETION, 0U);
}

static uint16_t auto_fw_cpl_invalid_opcode(void)
{
	return auto_fw_cpl_status(SCT_GENERIC_COMMAND_STATUS, SC_INVALID_COMMAND_OPCODE, 1U);
}

static uint16_t auto_fw_cpl_invalid_field(void)
{
	return auto_fw_cpl_status(SCT_GENERIC_COMMAND_STATUS, SC_INVALID_FIELD_IN_COMMAND, 1U);
}

static uint16_t auto_fw_cpl_internal_error(void)
{
	return auto_fw_cpl_status(SCT_GENERIC_COMMAND_STATUS, SC_INTERNAL_DEVICE_ERROR, 1U);
}

static uint16_t auto_fw_cpl_invalid_qid(void)
{
	return auto_fw_cpl_status(SCT_COMMAND_SPECIFIC_STATUS, SC_INVALID_QUEUE_IDENTIFIER, 1U);
}

static uint16_t auto_fw_cpl_invalid_log_page(void)
{
	return auto_fw_cpl_status(SCT_COMMAND_SPECIFIC_STATUS, SC_INVALID_LOG_PAGE, 1U);
}

static uint32_t auto_fw_cmd_opcode(const struct auto_fw_cmd *cmd)
{
	return cmd->dword[0] & 0xffU;
}

static uint32_t auto_fw_cmd_cid(const struct auto_fw_cmd *cmd)
{
	return (cmd->dword[0] >> 16) & 0xffffU;
}

static uint64_t auto_fw_cmd_prp1(const struct auto_fw_cmd *cmd)
{
	return ((uint64_t)cmd->dword[7] << 32) | cmd->dword[6];
}

static uint64_t auto_fw_cmd_prp2(const struct auto_fw_cmd *cmd)
{
	return ((uint64_t)cmd->dword[9] << 32) | cmd->dword[8];
}

static void auto_fw_put_le16(uint8_t *buf, size_t off, uint16_t value)
{
	buf[off] = (uint8_t)(value & 0xffU);
	buf[off + 1U] = (uint8_t)((value >> 8) & 0xffU);
}

static void auto_fw_put_le32(uint8_t *buf, size_t off, uint32_t value)
{
	auto_fw_put_le16(buf, off, (uint16_t)(value & 0xffffU));
	auto_fw_put_le16(buf, off + 2U, (uint16_t)(value >> 16));
}

static void auto_fw_put_le64(uint8_t *buf, size_t off, uint64_t value)
{
	auto_fw_put_le32(buf, off, (uint32_t)value);
	auto_fw_put_le32(buf, off + 4U, (uint32_t)(value >> 32));
}

static void auto_fw_put_ascii_padded(uint8_t *buf, size_t off, size_t len,
					     const char *s)
{
	size_t i;

	memset(buf + off, ' ', len);
	for(i = 0; i < len && s[i] != '\0'; i++)
		buf[off + i] = (uint8_t)s[i];
}

static void auto_fw_fill_identify_controller(uint8_t *buf)
{
	memset(buf, 0, AUTO_FW_STAGE_SIZE);
	auto_fw_put_le16(buf, 0, 0x1edcU);
	auto_fw_put_le16(buf, 2, 0x1edcU);
	auto_fw_put_ascii_padded(buf, 4, 20, "S970SIM0001");
	auto_fw_put_ascii_padded(buf, 24, 40, "Samsung SSD 970 PRO");
	auto_fw_put_ascii_padded(buf, 64, 8, "SIM9701");
	buf[73] = 0xe4U;
	buf[74] = 0xd2U;
	buf[75] = 0x5cU;
	buf[77] = 0x8U;
	auto_fw_put_le16(buf, 78, 0x9U);
	auto_fw_put_le64(buf, 280, AUTO_FW_STORAGE_BYTES);
	buf[258] = 0x3U;
	buf[259] = 0x3U;
	buf[260] = 0x3U;
	buf[262] = 0x8U;
	buf[512] = 0x66U;
	buf[513] = 0x44U;
	auto_fw_put_le32(buf, 516, 1U);
	buf[525] = 0x1U;
	auto_fw_put_le16(buf, 2048, 0x09c4U);
}

static void auto_fw_fill_identify_namespace(uint8_t *buf)
{
	memset(buf, 0, AUTO_FW_STAGE_SIZE);
	auto_fw_put_le64(buf, 0, AUTO_FW_BLOCKS);
	auto_fw_put_le64(buf, 8, AUTO_FW_BLOCKS);
	auto_fw_put_le64(buf, 16, AUTO_FW_BLOCKS);
	buf[25] = 0x0U;
	buf[26] = 0x0U;
	auto_fw_put_le16(buf, 128, 0x0U);
	buf[130] = 0x0cU;
	buf[131] = 0x2U;
}

static int auto_fw_dma_stage_to_prp(uint32_t len, uint64_t prp1, uint64_t prp2)
{
	uint64_t stage = (uint64_t)NVME_MANAGEMENT_START_ADDR;
	uint32_t first_len;

	if(len == 0U || len > AUTO_FW_STAGE_SIZE || ((prp1 & 0x3ULL) != 0ULL) ||
	   ((prp2 & 0x3ULL) != 0ULL))
		return -1;

	auto_fw_clean_dma_buffer(stage, AUTO_FW_STAGE_SIZE);
	first_len = AUTO_FW_STAGE_SIZE - (uint32_t)(prp1 & 0xfffULL);
	if(first_len > len)
		first_len = len;
	if(auto_fw_submit_direct_tx_dma(stage, prp1, first_len) != 0)
		return -1;
	if(first_len < len) {
		if(prp2 == 0ULL)
			return -1;
		if(auto_fw_submit_direct_tx_dma(stage + first_len, prp2,
						    len - first_len) != 0)
			return -1;
	}
	return 0;
}

static void auto_fw_set_status_fields(uint32_t rdy, uint32_t shst)
{
	uint32_t value = ((shst & 0x3U) << AUTO_NVME_STATUS_CSTS_SHST_SHIFT) |
			 ((rdy != 0U) ? AUTO_NVME_STATUS_CSTS_RDY : 0U);

	auto_reg_write(AUTO_NVME_STATUS, value);
}

static void auto_fw_set_csts_rdy(uint32_t rdy)
{
	uint32_t status = auto_reg_read(AUTO_NVME_STATUS);
	uint32_t shst = (status >> AUTO_NVME_STATUS_CSTS_SHST_SHIFT) & 0x3U;

	auto_fw_set_status_fields(rdy, shst);
}

static void auto_fw_set_csts_shst(uint32_t shst)
{
	uint32_t status = auto_reg_read(AUTO_NVME_STATUS);
	uint32_t rdy = (status & AUTO_NVME_STATUS_CSTS_RDY) != 0U;

	auto_fw_set_status_fields(rdy, shst);
}

static void auto_fw_set_admin_queue(uint32_t sq_valid, uint32_t cq_valid,
					    uint32_t cq_irq_en)
{
	uint32_t value = ((cq_valid & 1U) ? AUTO_ADMIN_QUEUE_CQ_VALID : 0U) |
			 ((sq_valid & 1U) ? AUTO_ADMIN_QUEUE_SQ_VALID : 0U) |
			 ((cq_irq_en & 1U) ? AUTO_ADMIN_QUEUE_CQ_IRQ_EN : 0U);

	auto_reg_write(AUTO_ADMIN_QUEUE, value);
}

static void auto_fw_set_io_sq(uint32_t idx, uint32_t valid, uint32_t cq_vector,
				      uint32_t qsize, uint64_t pcie_base)
{
	uint64_t addr = AUTO_IO_SQ_BASE + ((uint64_t)idx * 8ULL);
	uint32_t hi = (auto_fw_upper32(pcie_base) & 0xffffU) |
		      ((valid & 1U) << 16) |
		      ((cq_vector & 0xfU) << 17) |
		      ((qsize & 0xffU) << 24);

	auto_reg_write(addr, auto_fw_lower32(pcie_base));
	auto_reg_write(addr + 4U, hi);
}

static void auto_fw_set_io_cq(uint32_t idx, uint32_t valid, uint32_t irq_en,
				      uint32_t irq_vector, uint32_t qsize,
				      uint64_t pcie_base)
{
	uint64_t addr = AUTO_IO_CQ_BASE + ((uint64_t)idx * 8ULL);
	uint32_t hi = (auto_fw_upper32(pcie_base) & 0xffffU) |
		      ((valid & 1U) << 16) |
		      ((irq_vector & 0x7U) << 17) |
		      ((irq_en & 1U) << 20) |
		      ((qsize & 0xffU) << 24);

	auto_reg_write(addr, auto_fw_lower32(pcie_base));
	auto_reg_write(addr + 4U, hi);
}

static void auto_fw_clear_io_queues(void)
{
	uint32_t i;

	for(i = 0; i < AUTO_MAX_IO_QUEUES; i++) {
		auto_fw_set_io_cq(i, 0U, 0U, 0U, 0U, 0ULL);
		auto_fw_set_io_sq(i, 0U, 0U, 0U, 0ULL);
		g_auto_fw.io_sq_cq_idx[i] = 0U;
		g_auto_fw.io_cq_irq_vector[i] = 0U;
	}
}

static void auto_fw_complete_auto(uint32_t slot, uint32_t specific,
					  uint16_t status)
{
	uint32_t dw1 = specific;
	uint32_t dw2 = (slot & AUTO_CMD_FIFO_SLOT_MASK) |
		       (AUTO_CPL_TYPE_AUTO << 14) |
		       ((uint32_t)status << 16);

	auto_reg_write(AUTO_CPL_FIFO + 4U, dw1);
	auto_reg_write(AUTO_CPL_FIFO + 8U, dw2);
	auto_reg_write(AUTO_CPL_FIFO_TRIG, 1U);
}

static void auto_fw_complete_only(const struct auto_fw_cmd *cmd,
					  uint32_t specific, uint16_t status)
{
	uint32_t dw0 = (auto_fw_cmd_cid(cmd) & 0xffffU) |
		       ((cmd->qid & 0xfU) << 16);
	uint32_t dw2 = (cmd->slot & AUTO_CMD_FIFO_SLOT_MASK) |
		       (AUTO_CPL_TYPE_ONLY << 14) |
		       ((uint32_t)status << 16);

	auto_reg_write(AUTO_CPL_FIFO, dw0);
	auto_reg_write(AUTO_CPL_FIFO + 4U, specific);
	auto_reg_write(AUTO_CPL_FIFO + 8U, dw2);
	auto_reg_write(AUTO_CPL_FIFO_TRIG, 1U);
}

static void auto_fw_release_slot(uint32_t slot)
{
	uint32_t dw2 = (slot & AUTO_CMD_FIFO_SLOT_MASK) |
		       (AUTO_CPL_TYPE_SLOT_RELEASE << 14);

	auto_reg_write(AUTO_CPL_FIFO + 8U, dw2);
	auto_reg_write(AUTO_CPL_FIFO_TRIG, 1U);
}

static uint32_t auto_fw_cmd_raw_qid(uint32_t raw)
{
	return raw & AUTO_CMD_FIFO_QID_MASK;
}

static int auto_fw_cmd_hw_owned(uint32_t raw)
{
	uint32_t qid = auto_fw_cmd_raw_qid(raw);
	uint32_t ctrl = auto_reg_read(AUTO_REG_CTRL);
	uint32_t mask = auto_reg_read(AUTO_REG_IO_ENABLE_MASK);

	return ((ctrl & AUTO_CTRL_ENABLE) != 0U) &&
	       (qid != 0U) && (qid <= AUTO_MAX_IO_QUEUES) &&
	       ((mask & (1U << qid)) != 0U);
}

static int auto_fw_auto_busy(void)
{
	return ((auto_reg_read(AUTO_REG_CTRL) & AUTO_CTRL_ENABLE) != 0U) &&
	       ((auto_fw_status() & AUTO_STATUS_BUSY) != 0U);
}

static int auto_fw_fetch_cmd(struct auto_fw_cmd *cmd)
{
	uint32_t raw = auto_reg_read(AUTO_CMD_FIFO_PEEK);
	uint32_t i;

	if((raw & AUTO_CMD_FIFO_VALID) == 0U)
		return 0;
	if(auto_fw_cmd_hw_owned(raw) != 0)
		return 0;
	if(auto_fw_auto_busy() != 0)
		return 0;

	raw = auto_reg_read(AUTO_CMD_FIFO);
	if((raw & AUTO_CMD_FIFO_VALID) == 0U)
		return 0;

	cmd->qid = auto_fw_cmd_raw_qid(raw);
	cmd->slot = (raw >> AUTO_CMD_FIFO_SLOT_SHIFT) & AUTO_CMD_FIFO_SLOT_MASK;
	cmd->seq = (raw >> AUTO_CMD_FIFO_SEQ_SHIFT) & AUTO_CMD_FIFO_SEQ_MASK;
	for(i = 0; i < 16U; i++) {
		uint64_t base = (AUTO_FW_USE_S1_AXI_CMD_WINDOW != 0U) ?
				AUTO_NVME_CMD_SQE_WINDOW : AUTO_NVME_CMD_SRAM;
		uint64_t addr = base +
				((uint64_t)cmd->slot * AUTO_NVME_CMD_SQE_SIZE) +
				((uint64_t)i * sizeof(uint32_t));
		cmd->dword[i] = auto_reg_read(addr);
	}
	return 1;
}

static uint32_t auto_fw_set_num_of_queue(uint32_t dword11)
{
	uint32_t nsqr = dword11 & 0xffffU;
	uint32_t ncqr = (dword11 >> 16) & 0xffffU;

	g_auto_fw.num_io_sq_alloc = (nsqr >= AUTO_MAX_IO_QUEUES) ?
		AUTO_MAX_IO_QUEUES : nsqr + 1U;
	g_auto_fw.num_io_cq_alloc = (ncqr >= AUTO_MAX_IO_QUEUES) ?
		AUTO_MAX_IO_QUEUES : ncqr + 1U;
	return ((g_auto_fw.num_io_sq_alloc - 1U) << 16) |
	       (g_auto_fw.num_io_cq_alloc - 1U);
}

static uint32_t auto_fw_get_num_of_queue(void)
{
	return ((g_auto_fw.num_io_sq_alloc - 1U) << 16) |
	       (g_auto_fw.num_io_cq_alloc - 1U);
}

static int auto_fw_handle_set_features(const struct auto_fw_cmd *cmd,
					       uint32_t *specific, uint16_t *status)
{
	uint32_t fid = cmd->dword[10] & 0xffU;

	*specific = 0U;
	*status = auto_fw_cpl_success();
	switch(fid) {
	case FEAT_NUMBER_OF_QUEUES:
		*specific = auto_fw_set_num_of_queue(cmd->dword[11]);
		break;
	case FEAT_VOLATILE_WRITE_CACHE:
		g_auto_fw.cache_en = cmd->dword[11] & 1U;
		break;
	case FEAT_INTERRUPT_COALESCING:
	case FEAT_ARBITRATION:
	case FEAT_ASYNC_EVENT_CONFIG:
	case FEAT_POWER_MANAGEMENT:
	case FEAT_TIMESTAMP:
	case FEAT_SOFTWARE_PROGRESS_MARKER:
		break;
	default:
		*status = auto_fw_cpl_invalid_field();
		break;
	}
	return 0;
}

static int auto_fw_handle_get_features(const struct auto_fw_cmd *cmd,
					       uint32_t *specific, uint16_t *status)
{
	uint32_t fid = cmd->dword[10] & 0xffU;

	*specific = 0U;
	*status = auto_fw_cpl_success();
	switch(fid) {
	case FEAT_NUMBER_OF_QUEUES:
		*specific = auto_fw_get_num_of_queue();
		break;
	case FEAT_LBA_RANGE_TYPE:
		*status = auto_fw_cpl_invalid_field();
		break;
	case FEAT_TEMPERATURE_THRESHOLD:
		*specific = cmd->dword[11];
		break;
	case FEAT_VOLATILE_WRITE_CACHE:
		*specific = g_auto_fw.cache_en;
		break;
	case FEAT_POWER_MANAGEMENT:
	case FEAT_POWER_STATE_TRANSITION:
	case FEAT_SOFTWARE_PROGRESS_MARKER:
	case 0xd0U:
		break;
	default:
		*status = auto_fw_cpl_invalid_field();
		break;
	}
	return 0;
}

static int auto_fw_handle_create_io_sq(const struct auto_fw_cmd *cmd,
					       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffU;
	uint32_t qsize = (cmd->dword[10] >> 16) & 0xffffU;
	uint32_t cqid = (cmd->dword[11] >> 16) & 0xffffU;
	uint64_t prp1 = auto_fw_cmd_prp1(cmd);

	*specific = 0U;
	*status = auto_fw_cpl_success();
	if(qid == 0U || qid > AUTO_MAX_IO_QUEUES || qsize >= 0x100U ||
	   cqid == 0U || cqid > AUTO_MAX_IO_QUEUES) {
		*status = auto_fw_cpl_invalid_qid();
		return 0;
	}
	if((prp1 & 0x3ULL) != 0ULL || (prp1 >> 48) != 0ULL) {
		*status = auto_fw_cpl_invalid_field();
		return 0;
	}
	if(AUTO_FW_TRACE_ADMIN != 0U)
		xil_printf("auto_fw: create_io_sq qid=%u cqid=%u qsize=%u prp1=%08x_%08x\r\n",
			   qid, cqid, qsize, auto_fw_upper32(prp1), auto_fw_lower32(prp1));
	auto_fw_set_io_sq(qid - 1U, 1U, cqid, qsize, prp1);
	g_auto_fw.io_sq_cq_idx[qid - 1U] = cqid - 1U;
	return 0;
}

static int auto_fw_handle_create_io_cq(const struct auto_fw_cmd *cmd,
					       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffU;
	uint32_t qsize = (cmd->dword[10] >> 16) & 0xffffU;
	uint32_t irq_en = (cmd->dword[11] >> 1) & 0x1U;
	uint32_t irq_vector = (cmd->dword[11] >> 16) & 0xffffU;
	uint64_t prp1 = auto_fw_cmd_prp1(cmd);

	*specific = 0U;
	*status = auto_fw_cpl_success();
	if(qid == 0U || qid > AUTO_MAX_IO_QUEUES || qsize >= 0x100U) {
		*status = auto_fw_cpl_invalid_qid();
		return 0;
	}
	if(irq_vector >= 8U || (prp1 & 0x3ULL) != 0ULL || (prp1 >> 48) != 0ULL) {
		*status = auto_fw_cpl_invalid_field();
		return 0;
	}
	if(AUTO_FW_TRACE_ADMIN != 0U)
		xil_printf("auto_fw: create_io_cq qid=%u qsize=%u irq_en=%u iv=%u prp1=%08x_%08x\r\n",
			   qid, qsize, irq_en, irq_vector, auto_fw_upper32(prp1), auto_fw_lower32(prp1));
	auto_fw_set_io_cq(qid - 1U, 1U, irq_en, irq_vector, qsize, prp1);
	g_auto_fw.io_cq_irq_vector[qid - 1U] = irq_vector;
	return 0;
}

static int auto_fw_handle_delete_io_sq(const struct auto_fw_cmd *cmd,
					       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffU;

	*specific = 0U;
	*status = auto_fw_cpl_success();
	if(qid == 0U || qid > AUTO_MAX_IO_QUEUES) {
		*status = auto_fw_cpl_invalid_qid();
		return 0;
	}
	auto_fw_set_io_sq(qid - 1U, 0U, 0U, 0U, 0ULL);
	g_auto_fw.io_sq_cq_idx[qid - 1U] = 0U;
	return 0;
}

static int auto_fw_handle_delete_io_cq(const struct auto_fw_cmd *cmd,
					       uint32_t *specific, uint16_t *status)
{
	uint32_t qid = cmd->dword[10] & 0xffffU;

	*specific = 0U;
	*status = auto_fw_cpl_success();
	if(qid == 0U || qid > AUTO_MAX_IO_QUEUES) {
		*status = auto_fw_cpl_invalid_qid();
		return 0;
	}
	auto_fw_set_io_cq(qid - 1U, 0U, 0U, 0U, 0U, 0ULL);
	g_auto_fw.io_cq_irq_vector[qid - 1U] = 0U;
	return 0;
}

static int auto_fw_handle_identify(const struct auto_fw_cmd *cmd,
					   uint32_t *specific, uint16_t *status)
{
	uint32_t cns = cmd->dword[10] & 0xffU;
	uint8_t *stage = (uint8_t *)(unsigned long)NVME_MANAGEMENT_START_ADDR;

	*specific = 0U;
	*status = auto_fw_cpl_success();
	switch(cns) {
	case 1U:
	case 6U:
		auto_fw_fill_identify_controller(stage);
		break;
	case 0U:
	case 5U:
		auto_fw_fill_identify_namespace(stage);
		break;
	case 2U:
	case 7U:
		memset(stage, 0, AUTO_FW_STAGE_SIZE);
		auto_fw_put_le32(stage, 0, 1U);
		break;
	case 3U:
		memset(stage, 0, AUTO_FW_STAGE_SIZE);
		break;
	default:
		*status = auto_fw_cpl_invalid_field();
		return 0;
	}
	if(auto_fw_dma_stage_to_prp(AUTO_FW_STAGE_SIZE, auto_fw_cmd_prp1(cmd),
				      auto_fw_cmd_prp2(cmd)) != 0)
		*status = auto_fw_cpl_internal_error();
	return 0;
}

static int auto_fw_handle_get_log_page(const struct auto_fw_cmd *cmd,
					       uint32_t *specific, uint16_t *status)
{
	uint32_t lid = cmd->dword[10] & 0xffU;
	uint32_t numd = ((cmd->dword[11] & 0xffffU) << 16) |
			 ((cmd->dword[10] >> 16) & 0xffffU);
	uint32_t len = (numd + 1U) * sizeof(uint32_t);
	uint8_t *stage = (uint8_t *)(unsigned long)NVME_MANAGEMENT_START_ADDR;

	*specific = 0U;
	*status = auto_fw_cpl_success();
	if(len == 0U || len > AUTO_FW_STAGE_SIZE) {
		*status = auto_fw_cpl_invalid_field();
		return 0;
	}
	memset(stage, 0, AUTO_FW_STAGE_SIZE);
	switch(lid) {
	case 0x01U:
		break;
	case 0x02U:
		stage[1] = 0x2cU;
		stage[2] = 0x01U;
		stage[3] = 100U;
		stage[4] = 10U;
		break;
	case 0x03U:
		stage[0] = 0x01U;
		break;
	default:
		*status = auto_fw_cpl_invalid_log_page();
		return 0;
	}
	if(auto_fw_dma_stage_to_prp(len, auto_fw_cmd_prp1(cmd),
				      auto_fw_cmd_prp2(cmd)) != 0)
		*status = auto_fw_cpl_internal_error();
	return 0;
}

static int auto_fw_handle_admin_cmd(const struct auto_fw_cmd *cmd)
{
	uint32_t specific = 0U;
	uint16_t status = auto_fw_cpl_success();
	uint32_t opc = auto_fw_cmd_opcode(cmd);
	uint32_t need_cpl = 1U;
	uint32_t release_only = 0U;
	int ret = 0;

	if(AUTO_FW_TRACE_ADMIN != 0U)
		xil_printf("auto_fw: admin q=%u slot=%u cid=%u opc=0x%02x dw0=0x%08x dw10=0x%08x dw11=0x%08x prp1=%08x_%08x\r\n",
			   cmd->qid, cmd->slot, auto_fw_cmd_cid(cmd), opc, cmd->dword[0],
			   cmd->dword[10], cmd->dword[11], cmd->dword[7], cmd->dword[6]);

	switch(opc) {
	case ADMIN_SET_FEATURES:
		ret = auto_fw_handle_set_features(cmd, &specific, &status);
		break;
	case ADMIN_CREATE_IO_CQ:
		ret = auto_fw_handle_create_io_cq(cmd, &specific, &status);
		break;
	case ADMIN_CREATE_IO_SQ:
		ret = auto_fw_handle_create_io_sq(cmd, &specific, &status);
		break;
	case ADMIN_IDENTIFY:
		ret = auto_fw_handle_identify(cmd, &specific, &status);
		break;
	case ADMIN_GET_FEATURES:
		ret = auto_fw_handle_get_features(cmd, &specific, &status);
		break;
	case ADMIN_DELETE_IO_CQ:
		ret = auto_fw_handle_delete_io_cq(cmd, &specific, &status);
		break;
	case ADMIN_DELETE_IO_SQ:
		ret = auto_fw_handle_delete_io_sq(cmd, &specific, &status);
		break;
	case ADMIN_ASYNC_EVENT_REQUEST:
		need_cpl = 0U;
		release_only = 1U;
		break;
	case ADMIN_GET_LOG_PAGE:
		ret = auto_fw_handle_get_log_page(cmd, &specific, &status);
		break;
	case ADMIN_KEEP_ALIVE:
	case ADMIN_FORMAT_NVM:
	case ADMIN_VENDOR_LIBNVM:
	case ADMIN_ABORT:
		break;
	default:
		status = auto_fw_cpl_invalid_opcode();
		break;
	}
	if(ret != 0)
		return ret;
	if(need_cpl != 0U)
		auto_fw_complete_auto(cmd->slot, specific, status);
	else if(release_only != 0U)
		auto_fw_release_slot(cmd->slot);
	else
		auto_fw_complete_only(cmd, specific, status);
	return 0;
}

static int auto_fw_handle_io_cmd(const struct auto_fw_cmd *cmd)
{
	uint32_t opc = auto_fw_cmd_opcode(cmd);
	uint32_t blocks = (cmd->dword[12] & 0xffffU) + 1U;
	uint64_t start_lba = ((uint64_t)cmd->dword[11] << 32) | cmd->dword[10];
	uint64_t dev_addr = (uint64_t)DATA_BUFFER_BASE_ADDR +
			    (start_lba * AUTO_FW_BLOCK_BYTES);
	uint64_t last_addr = dev_addr + ((uint64_t)blocks * AUTO_FW_BLOCK_BYTES) - 1ULL;
	uint32_t i;

	switch(opc) {
	case IO_NVM_FLUSH:
		auto_fw_complete_only(cmd, 0U, auto_fw_cpl_success());
		auto_fw_release_slot(cmd->slot);
		return 0;
	case IO_NVM_READ:
	case IO_NVM_WRITE:
		if(blocks > 256U || last_addr < dev_addr || last_addr > AUTO_FW_DDR_LIMIT) {
			auto_fw_complete_auto(cmd->slot, 0U, auto_fw_cpl_internal_error());
			return -1;
		}
		for(i = 0; i < blocks; i++) {
			uint32_t last = (i + 1U) == blocks;
			uint32_t dir = (opc == IO_NVM_READ) ? AUTO_DMA_DIR_TX : AUTO_DMA_DIR_RX;
			if(auto_fw_submit_auto_dma(cmd->slot, i,
						  dev_addr + ((uint64_t)i * AUTO_FW_BLOCK_BYTES),
						  dir, last) != 0) {
				auto_fw_complete_auto(cmd->slot, 0U, auto_fw_cpl_internal_error());
				return -1;
			}
		}
		return 0;
	default:
		auto_fw_complete_auto(cmd->slot, 0U, auto_fw_cpl_invalid_opcode());
		return 0;
	}
}

int auto_fw_hw_present(void)
{
	return auto_reg_read(AUTO_REG_MAGIC) == AUTO_MAGIC_VALUE;
}

static void auto_hw_reset(void)
{
	auto_reg_write(AUTO_REG_CTRL, AUTO_CTRL_RESET);
	auto_reg_write(AUTO_REG_CTRL, 0U);
	auto_reg_write(AUTO_REG_ERROR, 0xffffffffU);
}

static void auto_hw_configure(void)
{
	uint64_t base = AUTO_FW_DDR_BASE;
	uint64_t limit = AUTO_FW_DDR_LIMIT;

	auto_fw_write64(AUTO_REG_DDR_BASE_LO, base);
	auto_fw_write64(AUTO_REG_DDR_LIMIT_LO, limit);
	auto_reg_write(AUTO_REG_IO_ENABLE_MASK, 0x000001feU);
	auto_reg_write(AUTO_REG_PF0_MSI_CTRL, 0x00000101U);
	auto_reg_write(AUTO_REG_CQ_MODE, AUTO_CQ_MODE_HW);
}

static void auto_fw_clear_for_rearm(void)
{
	auto_hw_reset();
	auto_fw_set_status_fields(0U, 0U);
	auto_fw_set_admin_queue(0U, 0U, 0U);
	auto_fw_clear_io_queues();
	auto_fw_sync_dma_tails();
	g_auto_fw.cache_en = 0U;
	g_auto_fw.observed_disabled = 1U;
	g_auto_fw.last_auto_trace_valid = 0U;
	g_auto_fw.cq_irq_retry_cq_write_count = 0U;
	g_auto_fw.cq_irq_retry_cqe_dw2 = 0U;
	g_auto_fw.cq_irq_retry_cqe_dw3 = 0U;
	g_auto_fw.cq_irq_retry_cqid = 0U;
	g_auto_fw.cq_irq_retry_age = 0U;
	g_auto_fw.cq_irq_retry_count = 0U;
	g_auto_fw.task = AUTO_FW_TASK_IDLE;
}

void auto_fw_init(void)
{
	memset(&g_auto_fw, 0, sizeof(g_auto_fw));
	g_auto_fw.task = AUTO_FW_TASK_IDLE;
	g_auto_fw.observed_disabled = 1U;
	g_auto_fw.num_io_sq_alloc = 1U;
	g_auto_fw.num_io_cq_alloc = 1U;
	auto_hw_reset();
	auto_hw_configure();
	auto_fw_clear_for_rearm();
}

void auto_fw_enable_io(void)
{
	uint32_t ctrl = AUTO_CTRL_ENABLE |
			AUTO_CTRL_IO_READ_ENABLE |
			AUTO_CTRL_IO_WRITE_ENABLE |
			AUTO_CTRL_AUTO_CQ_ENABLE |
			AUTO_CTRL_AUTO_MSI_ENABLE;

	auto_reg_write(AUTO_REG_ERROR, 0xffffffffU);
	auto_reg_write(AUTO_REG_CTRL, ctrl);
}

void auto_fw_shutdown(void)
{
	auto_hw_reset();
}

unsigned int auto_fw_status(void)
{
	return auto_reg_read(AUTO_REG_STATUS);
}

unsigned int auto_fw_error(void)
{
	return auto_reg_read(AUTO_REG_ERROR);
}

void auto_fw_clear_errors(unsigned int mask)
{
	auto_reg_write(AUTO_REG_ERROR, mask);
}

void auto_fw_retry_cq_irq(unsigned int cqid)
{
	auto_reg_write(AUTO_REG_CQ_IRQ_RETRY, ((cqid & 0xfU) << 4) | 1U);
}

static uint32_t auto_fw_cqid_from_sqid(uint32_t sqid)
{
	if(sqid == 0U)
		return 0U;
	if(sqid > AUTO_MAX_IO_QUEUES)
		return 0xffffffffU;
	return g_auto_fw.io_sq_cq_idx[sqid - 1U] + 1U;
}

/* This is a lost-MSI fallback.  Precise host-consumed detection needs CQ
 * head doorbell counters exposed from hardware into this register window.
 */
static void auto_fw_cq_irq_retry_watchdog(uint32_t status)
{
#if AUTO_FW_CQ_IRQ_RETRY_ENABLE != 0U
	uint32_t cq_write_count;
	uint32_t cqe_dw2;
	uint32_t cqe_dw3;
	uint32_t sqid;
	uint32_t cqid;

	if(g_auto_fw.task != AUTO_FW_TASK_RUNNING ||
	   (status & AUTO_STATUS_ENABLED) == 0U) {
		g_auto_fw.cq_irq_retry_age = 0U;
		g_auto_fw.cq_irq_retry_count = 0U;
		return;
	}

	cq_write_count = auto_reg_read(AUTO_REG_CQ_WRITE_COUNT);
	if(cq_write_count == 0U)
		return;

	cqe_dw2 = auto_reg_read(AUTO_REG_LAST_CQE_DW2);
	cqe_dw3 = auto_reg_read(AUTO_REG_LAST_CQE_DW3);
	sqid = (cqe_dw2 >> 16U) & 0xffffU;
	cqid = auto_fw_cqid_from_sqid(sqid);

	if(cq_write_count != g_auto_fw.cq_irq_retry_cq_write_count ||
	   cqe_dw2 != g_auto_fw.cq_irq_retry_cqe_dw2 ||
	   cqe_dw3 != g_auto_fw.cq_irq_retry_cqe_dw3) {
		g_auto_fw.cq_irq_retry_cq_write_count = cq_write_count;
		g_auto_fw.cq_irq_retry_cqe_dw2 = cqe_dw2;
		g_auto_fw.cq_irq_retry_cqe_dw3 = cqe_dw3;
		g_auto_fw.cq_irq_retry_cqid = cqid;
		g_auto_fw.cq_irq_retry_age = 0U;
		g_auto_fw.cq_irq_retry_count = 0U;
		return;
	}

	if(g_auto_fw.cq_irq_retry_cqid > AUTO_MAX_IO_QUEUES ||
	   g_auto_fw.cq_irq_retry_count >= AUTO_FW_CQ_IRQ_RETRY_MAX)
		return;

	if(g_auto_fw.cq_irq_retry_age < 0xffffffffU)
		g_auto_fw.cq_irq_retry_age++;

	if(g_auto_fw.cq_irq_retry_age >= AUTO_FW_CQ_IRQ_RETRY_DELAY_SERVICE) {
		auto_fw_retry_cq_irq(g_auto_fw.cq_irq_retry_cqid);
		g_auto_fw.cq_irq_retry_age = 0U;
		g_auto_fw.cq_irq_retry_count++;
	}
#else
	(void)status;
#endif
}

static void auto_fw_enter_running(void)
{
	g_auto_fw.observed_disabled = 0U;
	auto_fw_set_admin_queue(1U, 1U, 1U);
	auto_fw_set_csts_rdy(1U);
	g_auto_fw.task = AUTO_FW_TASK_RUNNING;
	auto_fw_enable_io();
	xil_printf("auto_fw: NVMe ready\r\n");
}

static void auto_fw_enter_shutdown(void)
{
	auto_fw_set_csts_shst(1U);
	auto_hw_reset();
	auto_fw_clear_io_queues();
	auto_fw_set_admin_queue(0U, 0U, 0U);
	auto_fw_set_csts_shst(2U);
	g_auto_fw.task = AUTO_FW_TASK_WAIT_RESET;
	xil_printf("auto_fw: NVMe shutdown\r\n");
}

static void auto_fw_poll_lifecycle(void)
{
	uint32_t status = auto_reg_read(AUTO_NVME_STATUS);
	uint32_t cc_en = (status & AUTO_NVME_STATUS_CC_EN) != 0U;
	uint32_t cc_shn = (status & AUTO_NVME_STATUS_CC_SHN_MASK) >>
			   AUTO_NVME_STATUS_CC_SHN_SHIFT;
	uint32_t csts_rdy = (status & AUTO_NVME_STATUS_CSTS_RDY) != 0U;
	uint32_t csts_shst = (status >> AUTO_NVME_STATUS_CSTS_SHST_SHIFT) & 0x3U;

	if(g_auto_fw.last_status_valid == 0U ||
	   g_auto_fw.last_cc_en != cc_en || g_auto_fw.last_cc_shn != cc_shn) {
		xil_printf("auto_fw: NVME_STATUS=0x%08x CC.EN=%u CC.SHN=%u CSTS.RDY=%u CSTS.SHST=%u\r\n",
			   status, cc_en, cc_shn, csts_rdy, csts_shst);
		g_auto_fw.last_status_valid = 1U;
		g_auto_fw.last_cc_en = cc_en;
		g_auto_fw.last_cc_shn = cc_shn;
	}

	switch(g_auto_fw.task) {
	case AUTO_FW_TASK_IDLE:
		if(cc_en == 0U) {
			g_auto_fw.observed_disabled = 1U;
			if(csts_rdy != 0U || csts_shst != 0U)
				auto_fw_clear_for_rearm();
		} else if(cc_shn != 0U && csts_shst == 2U) {
			auto_fw_clear_for_rearm();
		} else if(g_auto_fw.observed_disabled != 0U && cc_shn == 0U) {
			g_auto_fw.task = AUTO_FW_TASK_WAIT_CC_EN;
		}
		break;
	case AUTO_FW_TASK_WAIT_CC_EN:
		if(cc_en == 0U) {
			g_auto_fw.observed_disabled = 1U;
			g_auto_fw.task = AUTO_FW_TASK_IDLE;
			if(csts_rdy != 0U || csts_shst != 0U)
				auto_fw_clear_for_rearm();
		} else if(cc_shn != 0U && csts_shst == 2U) {
			auto_fw_clear_for_rearm();
		} else if(cc_shn == 0U) {
			auto_fw_enter_running();
		}
		break;
	case AUTO_FW_TASK_RUNNING:
		if(cc_shn != 0U)
			auto_fw_enter_shutdown();
		else if(cc_en == 0U)
			g_auto_fw.task = AUTO_FW_TASK_WAIT_RESET;
		break;
	case AUTO_FW_TASK_WAIT_RESET:
		if(cc_en == 0U)
			auto_fw_clear_for_rearm();
		else if(cc_shn == 0U && csts_shst == 0U && csts_rdy == 0U)
			g_auto_fw.task = AUTO_FW_TASK_WAIT_CC_EN;
		break;
	default:
		g_auto_fw.task = AUTO_FW_TASK_IDLE;
		break;
	}
}

static const char *auto_fw_auto_state_name(uint32_t state)
{
	switch(state) {
	case 0U: return "IDLE";
	case 1U: return "POP";
	case 2U: return "OP_ADDR";
	case 3U: return "OP_WAIT";
	case 4U: return "OP_DEC";
	case 5U: return "NLB_ADDR";
	case 6U: return "NLB_WAIT";
	case 7U: return "NLB_DEC";
	case 8U: return "SLBA_LO_ADDR";
	case 9U: return "SLBA_LO_WAIT";
	case 10U: return "SLBA_LO_CAP";
	case 11U: return "SLBA_HI_ADDR";
	case 12U: return "SLBA_HI_WAIT";
	case 13U: return "SLBA_HI_CAP";
	case 14U: return "RANGE";
	case 15U: return "SUBMIT";
	case 16U: return "NEXT_SEG";
	case 17U: return "ERROR";
	default: return "UNKNOWN";
	}
}

static void auto_fw_trace_auto_engine(uint32_t status)
{
#if AUTO_FW_TRACE_AUTO != 0U
	uint32_t state = (status & AUTO_STATUS_STATE_MASK) >> AUTO_STATUS_STATE_SHIFT;
	uint32_t last_state = (g_auto_fw.last_auto_status & AUTO_STATUS_STATE_MASK) >> AUTO_STATUS_STATE_SHIFT;
	uint32_t error = auto_reg_read(AUTO_REG_ERROR);
	uint32_t pcie_status = auto_reg_read(AUTO_PCIE_STATUS);
	uint32_t cmd_count = auto_reg_read(AUTO_REG_CMD_COUNT);
	uint32_t dma_submit_count = auto_reg_read(AUTO_REG_DMA_SUBMIT_COUNT);
	uint32_t dma_done_count = auto_reg_read(AUTO_REG_DMA_DONE_COUNT);
	uint32_t cq_write_count = auto_reg_read(AUTO_REG_CQ_WRITE_COUNT);
	uint32_t unsupported_count = auto_reg_read(AUTO_REG_UNSUPPORTED_COUNT);
	uint32_t last_qid_slot = auto_reg_read(AUTO_REG_LAST_QID_SLOT);
	uint32_t last_opcode = auto_reg_read(AUTO_REG_LAST_OPCODE);
	uint32_t cqe_dw2 = auto_reg_read(AUTO_REG_LAST_CQE_DW2);
	uint32_t cqe_dw3 = auto_reg_read(AUTO_REG_LAST_CQE_DW3);
	uint32_t qid = last_qid_slot & AUTO_CMD_FIFO_QID_MASK;
	uint32_t slot = (last_qid_slot >> 4U) & AUTO_CMD_FIFO_SLOT_MASK;
	uint32_t seq = (last_qid_slot >> (4U + AUTO_P_SLOT_TAG_WIDTH)) & AUTO_CMD_FIFO_SEQ_MASK;
	uint32_t cqe_sqid = (cqe_dw2 >> 16U) & 0xffffU;
	uint32_t cqe_sqhd = cqe_dw2 & 0xffffU;
	uint32_t cqe_cid = cqe_dw3 & 0xffffU;
	uint32_t cqe_phase = (cqe_dw3 >> 16U) & 0x1U;
	uint32_t cqe_status = cqe_dw3 >> 17U;
	uint32_t print = 0U;

	(void)qid;
	(void)slot;
	(void)seq;
	(void)cqe_sqid;
	(void)cqe_sqhd;
	(void)cqe_cid;
	(void)cqe_phase;
	(void)cqe_status;
	(void)pcie_status;

	if(g_auto_fw.last_auto_trace_valid == 0U)
		print = 1U;
	if(state != last_state)
		print = 1U;
	if((status & (AUTO_STATUS_ERROR | AUTO_STATUS_UNSUPPORTED_PENDING |
	              AUTO_STATUS_DMA_STALLED)) != 0U || error != 0U)
		print = 1U;
	if(cmd_count != g_auto_fw.last_auto_cmd_count &&
	   (cmd_count <= AUTO_FW_TRACE_AUTO_EARLY_CMDS ||
	    (AUTO_FW_TRACE_AUTO_PERIOD != 0U &&
	     (cmd_count % AUTO_FW_TRACE_AUTO_PERIOD) == 0U)))
		print = 1U;
	if(dma_submit_count != g_auto_fw.last_auto_dma_submit_count &&
	   dma_submit_count <= AUTO_FW_TRACE_AUTO_EARLY_CMDS)
		print = 1U;
	if(dma_done_count != g_auto_fw.last_auto_dma_done_count &&
	   cmd_count <= AUTO_FW_TRACE_AUTO_EARLY_CMDS)
		print = 1U;
	if(cq_write_count != g_auto_fw.last_auto_cq_write_count &&
	   cmd_count <= AUTO_FW_TRACE_AUTO_EARLY_CMDS)
		print = 1U;
	if(cqe_dw2 != g_auto_fw.last_auto_last_cqe_dw2 ||
	   cqe_dw3 != g_auto_fw.last_auto_last_cqe_dw3)
		print = 1U;
	if(unsupported_count != g_auto_fw.last_auto_unsupported_count)
		print = 1U;

	if(print != 0U)
		xil_printf("auto_fw: auto state=%s(%u) status=0x%08x err=0x%08x pcie=0x%08x cmd=%u dma_submit=%u dma_done=0x%08x cq=%u unsup=%u last_seq=%u slot=%u qid=%u opc=0x%02x cqe_sqid=%u cqe_sqhd=%u cqe_cid=%u cqe_phase=%u cqe_st=0x%x\r\n",
			   auto_fw_auto_state_name(state), state, status, error, pcie_status,
			   cmd_count, dma_submit_count, dma_done_count, cq_write_count,
			   unsupported_count, seq, slot, qid, last_opcode & 0xffU,
			   cqe_sqid, cqe_sqhd, cqe_cid, cqe_phase, cqe_status);

	g_auto_fw.last_auto_trace_valid = 1U;
	g_auto_fw.last_auto_status = status;
	g_auto_fw.last_auto_error = error;
	g_auto_fw.last_auto_cmd_count = cmd_count;
	g_auto_fw.last_auto_dma_submit_count = dma_submit_count;
	g_auto_fw.last_auto_dma_done_count = dma_done_count;
	g_auto_fw.last_auto_cq_write_count = cq_write_count;
	g_auto_fw.last_auto_unsupported_count = unsupported_count;
	g_auto_fw.last_auto_last_qid_slot = last_qid_slot;
	g_auto_fw.last_auto_last_opcode = last_opcode;
	g_auto_fw.last_auto_last_cqe_dw2 = cqe_dw2;
	g_auto_fw.last_auto_last_cqe_dw3 = cqe_dw3;
#else
	(void)status;
#endif
}

int auto_fw_service(void)
{
	uint32_t work;
	uint32_t auto_status;

	auto_fw_poll_lifecycle();
	if(g_auto_fw.task == AUTO_FW_TASK_RUNNING) {
		for(work = 0; work < AUTO_FW_MAX_CMDS_PER_SERVICE; work++) {
			struct auto_fw_cmd cmd;

			if(auto_fw_fetch_cmd(&cmd) == 0)
				break;
			if(cmd.qid == 0U) {
				if(auto_fw_handle_admin_cmd(&cmd) != 0)
					return -1;
			} else {
				if(auto_fw_handle_io_cmd(&cmd) != 0)
					return -1;
			}
		}
	}

	auto_status = auto_fw_status();
	auto_fw_trace_auto_engine(auto_status);
	auto_fw_cq_irq_retry_watchdog(auto_status);
	if((auto_status & (AUTO_STATUS_ERROR | AUTO_STATUS_UNSUPPORTED_PENDING)) != 0U) {
		uint32_t error = auto_fw_error();
		xil_printf("auto_fw: automation fault status=0x%08x error=0x%08x last_qid_slot=0x%08x last_op=0x%08x\r\n",
			   auto_status, error,
			   auto_reg_read(AUTO_REG_LAST_QID_SLOT),
			   auto_reg_read(AUTO_REG_LAST_OPCODE));
		auto_fw_clear_errors(error);
		return -1;
	}

	return 0;
}

void auto_fw_run(void)
{
	auto_fw_enable_io();
}
