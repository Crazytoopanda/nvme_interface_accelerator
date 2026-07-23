/* SPDX-License-Identifier: GPL-2.0 */
#ifndef NVME_ON_HOST_BAR0_REGS_H
#define NVME_ON_HOST_BAR0_REGS_H

/*
 * PF0 host NVMe function.
 *
 * This module is built from the local cloned NVMe PCI transport, but it must
 * only claim/map BAR0. Keep BAR0 register definitions here so driver code does
 * not hide MMIO offsets in .c files.
 */
#define NVME_ON_HOST_NAME              "nvme_on_host"
#define NVME_ON_HOST_PCI_VENDOR_ID     0x10ee
#define NVME_ON_HOST_PCI_DEVICE_ID     0x903f
#define NVME_ON_HOST_BAR0_NR           0
#define NVME_ON_HOST_PCI_FUNCTION      0
#define NVME_ON_HOST_BAR0_MIN_SIZE     0x2000u
#define NVME_ON_HOST_MAX_HW_SECTORS    8u /* one 4 KiB logical block */
#define NVME_ON_HOST_MAX_SEGMENTS      1u
#define NVME_ON_HOST_MAX_IO_QUEUES     8u
#define NVME_ON_HOST_IO_QUEUE_DEPTH    256u

#ifndef NVME_ON_HOST_DEBUG
#define NVME_ON_HOST_DEBUG 0
#endif

#if NVME_ON_HOST_DEBUG
#define NVME_ON_HOST_DBG(dev, fmt, ...) \
	dev_info((dev), "nvme_on_host: " fmt, ##__VA_ARGS__)
#else
#define NVME_ON_HOST_DBG(dev, fmt, ...) do { } while (0)
#endif

#define NVME_BAR0_CAP                  0x0000u /* Controller Capabilities, 64b */
#define NVME_BAR0_VS                   0x0008u /* Version */
#define NVME_BAR0_INTMS                0x000cu /* Interrupt Mask Set */
#define NVME_BAR0_INTMC                0x0010u /* Interrupt Mask Clear */
#define NVME_BAR0_CC                   0x0014u /* Controller Configuration */
#define NVME_BAR0_CSTS                 0x001cu /* Controller Status */
#define NVME_BAR0_NSSR                 0x0020u /* NVM Subsystem Reset */
#define NVME_BAR0_AQA                  0x0024u /* Admin Queue Attributes */
#define NVME_BAR0_ASQ                  0x0028u /* Admin SQ Base, 64b */
#define NVME_BAR0_ACQ                  0x0030u /* Admin CQ Base, 64b */
#define NVME_BAR0_CMBLOC               0x0038u
#define NVME_BAR0_CMBSZ                0x003cu
#define NVME_BAR0_BPINFO               0x0040u
#define NVME_BAR0_BPRSEL               0x0044u
#define NVME_BAR0_BPMBL                0x0048u /* 64b */
#define NVME_BAR0_CMBMSC               0x0050u /* 64b */
#define NVME_BAR0_CMBSTS               0x0058u
#define NVME_BAR0_PMRCAP               0x0e00u
#define NVME_BAR0_PMRCTL               0x0e04u
#define NVME_BAR0_PMRSTS               0x0e08u
#define NVME_BAR0_PMREBS               0x0e0cu
#define NVME_BAR0_PMRSWTP              0x0e10u
#define NVME_BAR0_DBS                  0x1000u /* Doorbell base */

#define NVME_BAR0_SQ0TDBL              (NVME_BAR0_DBS + 0x000u)
#define NVME_BAR0_CQ0HDBL              (NVME_BAR0_DBS + 0x004u)

static inline unsigned int nvme_bar0_sq_tail_doorbell(unsigned int qid,
						      unsigned int db_stride)
{
	return NVME_BAR0_DBS + qid * 2u * (4u << db_stride);
}

static inline unsigned int nvme_bar0_cq_head_doorbell(unsigned int qid,
						      unsigned int db_stride)
{
	return NVME_BAR0_DBS + (qid * 2u + 1u) * (4u << db_stride);
}

#endif /* NVME_ON_HOST_BAR0_REGS_H */
