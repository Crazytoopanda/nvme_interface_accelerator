#ifndef __SSD_CONFIG_H_
#define __SSD_CONFIG_H_

#define KB(x) ((x) * 1024ULL)
#define MB(x) (KB(x) * 1024ULL)
#define GB(x) (MB(x) * 1024ULL)

/* SSD Model */
#define INTEL_OPTANE 0
#define SAMSUNG_970PRO 1
#define ZNS_PROTOTYPE 2
#define KV_PROTOTYPE 3
#define WD_ZN540 4

/* SSD Type */
#define SSD_TYPE_NVM 0
#define SSD_TYPE_CONV 1
#define SSD_TYPE_ZNS 2
#define SSD_TYPE_KV 3

/* Cell Mode */
#define CELL_MODE_UNKNOWN 0
#define CELL_MODE_SLC 1
#define CELL_MODE_MLC 2
#define CELL_MODE_TLC 3
#define CELL_MODE_QLC 4

#ifndef BASE_SSD
#define BASE_SSD SAMSUNG_970PRO
#endif

#if (BASE_SSD == SAMSUNG_970PRO)
#define NR_NAMESPACES 1

#define NS_SSD_TYPE_0 SSD_TYPE_CONV
#define NS_CAPACITY_0 (0)
#define NS_SSD_TYPE_1 NS_SSD_TYPE_0
#define NS_CAPACITY_1 (0)
#define MDTS (6)
#define CELL_MODE (CELL_MODE_MLC)

#define SSD_PARTITIONS (1)
#define NAND_CHANNELS (8)
#define LUNS_PER_NAND_CH (32)
#define PLNS_PER_LUN (1)
#define FLASH_PAGE_SIZE KB(16)
#define ONESHOT_PAGE_SIZE (FLASH_PAGE_SIZE * 1)
#define BLKS_PER_PLN (8192)
#define BLK_SIZE (0)

#define MAX_CH_XFER_SIZE KB(16)
#define WRITE_UNIT_SIZE (512)

#define NAND_CHANNEL_BANDWIDTH (1200ULL)
#define PCIE_BANDWIDTH (16384ULL) /* kept for profile parity; firmware uses real PCIe DMA */

#define NAND_4KB_READ_LATENCY_LSB (35760ULL - 6000ULL)
#define NAND_4KB_READ_LATENCY_MSB (35760ULL + 6000ULL)
#define NAND_4KB_READ_LATENCY_CSB (0ULL)
#define NAND_READ_LATENCY_LSB (36013ULL - 6000ULL)
#define NAND_READ_LATENCY_MSB (36013ULL + 6000ULL)
#define NAND_READ_LATENCY_CSB (0ULL)
#define NAND_PROG_LATENCY (185000ULL)
#define NAND_ERASE_LATENCY (0ULL)

#define FW_4KB_READ_LATENCY (400ULL)
#define FW_READ_LATENCY (400ULL)
#define FW_WBUF_LATENCY0 (400ULL)
#define FW_WBUF_LATENCY1 (400ULL)
#define FW_CH_XFER_LATENCY (0ULL)
#define OP_AREA_PERCENT (7)

#define GLOBAL_WB_SIZE (NAND_CHANNELS * LUNS_PER_NAND_CH * ONESHOT_PAGE_SIZE * 2)
#define WRITE_EARLY_COMPLETION 0

#ifndef NVME_BOOT_ERASE_BYTES
#define NVME_BOOT_ERASE_BYTES (0ULL)
#endif

/*
 * A single ELF runs on all A53 cores. Role macros map work to cores.
 * With one core, every role maps to core0 and the firmware completes IO
 * end-to-end without cross-core queues. With three cores, core0 fetches NVMe
 * commands, core1 runs the SSD timing model, and core2 owns IO DMA/CPL.
 */
#ifndef NVME_SMP_NUM_CORES
#define NVME_SMP_NUM_CORES 3
#endif

#ifndef NVME_HOST_CORE
#define NVME_HOST_CORE 0
#endif

#ifndef SSD_MODEL_CORE
#if NVME_SMP_NUM_CORES > 1
#define SSD_MODEL_CORE 1
#else
#define SSD_MODEL_CORE 0
#endif
#endif

#ifndef NVME_DMA_CORE
#if NVME_SMP_NUM_CORES > 2
#define NVME_DMA_CORE 2
#else
#define NVME_DMA_CORE 0
#endif
#endif

#ifndef NVME_CPL_CORE
#define NVME_CPL_CORE NVME_DMA_CORE
#endif

#define SSD_MODEL_POLL_CORE SSD_MODEL_CORE

#if NVME_HOST_CORE >= NVME_SMP_NUM_CORES
#error "NVME_HOST_CORE must be less than NVME_SMP_NUM_CORES"
#endif
#if SSD_MODEL_CORE >= NVME_SMP_NUM_CORES
#error "SSD_MODEL_CORE must be less than NVME_SMP_NUM_CORES"
#endif
#if NVME_DMA_CORE >= NVME_SMP_NUM_CORES
#error "NVME_DMA_CORE must be less than NVME_SMP_NUM_CORES"
#endif
#if NVME_CPL_CORE != NVME_DMA_CORE
#error "Separate CPL core is not implemented yet; set NVME_CPL_CORE to NVME_DMA_CORE"
#endif

#define LBA_BITS (9)
#define LBA_SIZE (1 << LBA_BITS)
#else
#error "Only BASE_SSD=SAMSUNG_970PRO is supported by the firmware SSD model now."
#endif

#endif
