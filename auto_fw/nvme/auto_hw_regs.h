#ifndef AUTO_FW_AUTO_HW_REGS_H
#define AUTO_FW_AUTO_HW_REGS_H

#include "io_access.h"

#define AUTO_HOST_IP_ADDR                  0xA0000000ULL

#define AUTO_DEV_IRQ_MASK                  (AUTO_HOST_IP_ADDR + 0x004)
#define AUTO_DEV_IRQ_CLEAR                 (AUTO_HOST_IP_ADDR + 0x008)
#define AUTO_DEV_IRQ_STATUS                (AUTO_HOST_IP_ADDR + 0x00c)

#define AUTO_PCIE_STATUS                   (AUTO_HOST_IP_ADDR + 0x104)
#define AUTO_NVME_STATUS                   (AUTO_HOST_IP_ADDR + 0x200)
#define AUTO_ADMIN_QUEUE                   (AUTO_HOST_IP_ADDR + 0x21c)
#define AUTO_IO_SQ_BASE                    (AUTO_HOST_IP_ADDR + 0x220)
#define AUTO_IO_CQ_BASE                    (AUTO_HOST_IP_ADDR + 0x260)
#define AUTO_CMD_FIFO                      (AUTO_HOST_IP_ADDR + 0x300)
#define AUTO_CMD_FIFO_PEEK                 (AUTO_HOST_IP_ADDR + 0x344)
#define AUTO_CPL_FIFO                      (AUTO_HOST_IP_ADDR + 0x304)
#define AUTO_CPL_FIFO_TRIG                 (AUTO_HOST_IP_ADDR + 0x340)

#define AUTO_HOST_DMA_FIFO_CNT              (AUTO_HOST_IP_ADDR + 0x204)
#define AUTO_HOST_DMA_CMD_FIFO              (AUTO_HOST_IP_ADDR + 0x310)
#define AUTO_HOST_DMA_CMD_FIFO_TRIG         (AUTO_HOST_IP_ADDR + 0x330)
#define AUTO_NVME_CMD_SRAM                  (AUTO_HOST_IP_ADDR + 0x10000)
#define AUTO_NVME_CMD_SQE_WINDOW            0xB0000000ULL
#define AUTO_NVME_CMD_SQE_SIZE              64U
#define AUTO_MAX_IO_QUEUES                  8U
#define AUTO_P_SLOT_TAG_WIDTH               10U

#define AUTO_NVME_STATUS_CC_EN              0x00000001U
#define AUTO_NVME_STATUS_CC_SHN_MASK        0x00000006U
#define AUTO_NVME_STATUS_CC_SHN_SHIFT       1U
#define AUTO_NVME_STATUS_CSTS_RDY           0x00000010U
#define AUTO_NVME_STATUS_CSTS_SHST_SHIFT    5U

#define AUTO_ADMIN_QUEUE_CQ_VALID           (1U << 0)
#define AUTO_ADMIN_QUEUE_SQ_VALID           (1U << 1)
#define AUTO_ADMIN_QUEUE_CQ_IRQ_EN          (1U << 2)

#define AUTO_CMD_FIFO_QID_MASK              0x0000000fU
#define AUTO_CMD_FIFO_SLOT_SHIFT            5U
#define AUTO_CMD_FIFO_SLOT_MASK             ((1U << AUTO_P_SLOT_TAG_WIDTH) - 1U)
#define AUTO_CMD_FIFO_SEQ_SHIFT             16U
#define AUTO_CMD_FIFO_SEQ_MASK              0xffU
#define AUTO_CMD_FIFO_VALID                 0x80000000U

#define AUTO_CPL_TYPE_ONLY                  0U
#define AUTO_CPL_TYPE_AUTO                  1U
#define AUTO_CPL_TYPE_SLOT_RELEASE          2U

#define AUTO_DMA_TYPE_AUTO                  0U
#define AUTO_DMA_TYPE_DIRECT                1U
#define AUTO_DMA_DIR_RX                     0U
#define AUTO_DMA_DIR_TX                     1U

/*
 * New automation register region.  The hardware block should decode these
 * offsets inside the same 0xA0000000 s0_axi window.
 */
#define AUTO_REG_BASE                      (AUTO_HOST_IP_ADDR + 0x400)
#define AUTO_REG_MAGIC                     (AUTO_REG_BASE + 0x00)
#define AUTO_REG_CTRL                      (AUTO_REG_BASE + 0x04)
#define AUTO_REG_STATUS                    (AUTO_REG_BASE + 0x08)
#define AUTO_REG_ERROR                     (AUTO_REG_BASE + 0x0c)
#define AUTO_REG_DDR_BASE_LO               (AUTO_REG_BASE + 0x10)
#define AUTO_REG_DDR_BASE_HI               (AUTO_REG_BASE + 0x14)
#define AUTO_REG_DDR_LIMIT_LO              (AUTO_REG_BASE + 0x18)
#define AUTO_REG_DDR_LIMIT_HI              (AUTO_REG_BASE + 0x1c)
#define AUTO_REG_IO_ENABLE_MASK            (AUTO_REG_BASE + 0x20)
#define AUTO_REG_PF0_MSI_CTRL              (AUTO_REG_BASE + 0x24)
#define AUTO_REG_CQ_MODE                   (AUTO_REG_BASE + 0x28)
#define AUTO_REG_CMD_COUNT                 (AUTO_REG_BASE + 0x30)
#define AUTO_REG_DMA_SUBMIT_COUNT          (AUTO_REG_BASE + 0x34)
#define AUTO_REG_DMA_DONE_COUNT            (AUTO_REG_BASE + 0x38)
#define AUTO_REG_CQ_WRITE_COUNT            (AUTO_REG_BASE + 0x3c)
#define AUTO_REG_LAST_CQE_DW3              (AUTO_REG_BASE + 0x40)
#define AUTO_REG_UNSUPPORTED_COUNT         (AUTO_REG_BASE + 0x44)
#define AUTO_REG_LAST_QID_SLOT             (AUTO_REG_BASE + 0x48)
#define AUTO_REG_LAST_OPCODE               (AUTO_REG_BASE + 0x4c)
#define AUTO_REG_LAST_ERROR_INFO           (AUTO_REG_BASE + 0x50)
#define AUTO_REG_LAST_CQE_DW2              (AUTO_REG_BASE + 0x54)
#define AUTO_REG_CQ_IRQ_RETRY              (AUTO_REG_BASE + 0x58)
#define AUTO_REG_SW_DOORBELL               (AUTO_REG_BASE + 0x5c)
#define AUTO_REG_CQ_IRQ_RETRY_CYCLES       (AUTO_REG_BASE + 0x60)

#define AUTO_MAGIC_VALUE                   0xA710F001U

#define AUTO_CTRL_ENABLE                   (1U << 0)
#define AUTO_CTRL_RESET                    (1U << 1)
#define AUTO_CTRL_IO_READ_ENABLE           (1U << 8)
#define AUTO_CTRL_IO_WRITE_ENABLE          (1U << 9)
#define AUTO_CTRL_AUTO_CQ_ENABLE           (1U << 10)
#define AUTO_CTRL_AUTO_MSI_ENABLE          (1U << 11)

#define AUTO_STATUS_ENABLED                (1U << 0)
#define AUTO_STATUS_IDLE                   (1U << 1)
#define AUTO_STATUS_ERROR                  (1U << 8)
#define AUTO_STATUS_UNSUPPORTED_PENDING    (1U << 9)
#define AUTO_STATUS_DMA_STALLED            (1U << 10)
#define AUTO_STATUS_BUSY                   (1U << 16)
#define AUTO_STATUS_MSI_ENABLED            (1U << 17)
#define AUTO_STATUS_STATE_SHIFT            20U
#define AUTO_STATUS_STATE_MASK             (0x1fU << AUTO_STATUS_STATE_SHIFT)

#define AUTO_ERR_ADMIN_OR_MASKED_QID       (1U << 0)
#define AUTO_ERR_UNSUPPORTED_OPCODE        (1U << 1)
#define AUTO_ERR_DISABLED_OPCODE           (1U << 2)
#define AUTO_ERR_DDR_RANGE                 (1U << 3)
#define AUTO_ERR_AUTO_CQ_DISABLED          (1U << 4)
#define AUTO_ERR_CQ_MODE_UNSUPPORTED       (1U << 5)
#define AUTO_ERR_NLB_TOO_LARGE             (1U << 6)

#define AUTO_CQ_MODE_HW                    0U
#define AUTO_CQ_MODE_MB_ACK                1U

static inline void auto_reg_write(unsigned long long addr, unsigned int value)
{
	IO_WRITE32(addr, value);
}

static inline unsigned int auto_reg_read(unsigned long long addr)
{
	return IO_READ32(addr);
}

#endif
