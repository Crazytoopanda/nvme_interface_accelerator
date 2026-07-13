#include "xil_printf.h"

#include "nvme_smp.h"
#include "nvme_smp_boot.h"
#include "ssd_config.h"

#define ZYNQMP_APU_RVBARADDR_BASE	0xFD5C0040ULL
#define ZYNQMP_APU_RVBARADDR_STRIDE	0x8ULL
#define ZYNQMP_APU_PWRCTL_ADDR		0xFD5C0090ULL

static inline void smp_write32(unsigned long long addr, unsigned int value)
{
	*(volatile unsigned int *)(unsigned long)addr = value;
	__asm__ volatile("dsb sy" ::: "memory");
}

static inline unsigned int smp_read32(unsigned long long addr)
{
	unsigned int value;

	value = *(volatile unsigned int *)(unsigned long)addr;
	__asm__ volatile("dsb sy" ::: "memory");
	return value;
}

static void nvme_smp_set_rvbar(unsigned int coreId, unsigned long long entry)
{
	unsigned long long regBase;

	regBase = ZYNQMP_APU_RVBARADDR_BASE +
		  ((unsigned long long)coreId * ZYNQMP_APU_RVBARADDR_STRIDE);

	smp_write32(regBase, (unsigned int)(entry & 0xFFFFFFFFULL));
	smp_write32(regBase + 4, (unsigned int)((entry >> 32) & 0xFFULL));
}

static void nvme_smp_clear_powerdown_req(unsigned int coreId)
{
	unsigned int pwrctl;

	if(coreId >= NVME_SMP_NUM_CORES)
		return;

	pwrctl = smp_read32(ZYNQMP_APU_PWRCTL_ADDR);
	pwrctl &= ~(1U << coreId);
	smp_write32(ZYNQMP_APU_PWRCTL_ADDR, pwrctl);
}

static void nvme_smp_signal_event(void)
{
	__asm__ volatile("dsb sy\n\tsev\n\tisb" ::: "memory");
}

void nvme_smp_worker_trampoline1(void);
void nvme_smp_worker_trampoline2(void);
void nvme_smp_worker_trampoline3(void);

__asm__(
	".align 7\n"
	".global nvme_smp_worker_trampoline1\n"
	"nvme_smp_worker_trampoline1:\n"
	"mov x0, #1\n"
	"adrp x1, g_nvmeSmpWorkerStack\n"
	"add x1, x1, :lo12:g_nvmeSmpWorkerStack\n"
	"add x2, x0, #1\n"
	"lsl x2, x2, #14\n"
	"add x1, x1, x2\n"
	"and x1, x1, #0xfffffffffffffff0\n"
	"msr daifset, #0xf\n"
	"mov sp, x1\n"
	"b nvme_smp_worker_entry\n"

	".align 7\n"
	".global nvme_smp_worker_trampoline2\n"
	"nvme_smp_worker_trampoline2:\n"
	"mov x0, #2\n"
	"adrp x1, g_nvmeSmpWorkerStack\n"
	"add x1, x1, :lo12:g_nvmeSmpWorkerStack\n"
	"add x2, x0, #1\n"
	"lsl x2, x2, #14\n"
	"add x1, x1, x2\n"
	"and x1, x1, #0xfffffffffffffff0\n"
	"msr daifset, #0xf\n"
	"mov sp, x1\n"
	"b nvme_smp_worker_entry\n"

	".align 7\n"
	".global nvme_smp_worker_trampoline3\n"
	"nvme_smp_worker_trampoline3:\n"
	"mov x0, #3\n"
	"adrp x1, g_nvmeSmpWorkerStack\n"
	"add x1, x1, :lo12:g_nvmeSmpWorkerStack\n"
	"add x2, x0, #1\n"
	"lsl x2, x2, #14\n"
	"add x1, x1, x2\n"
	"and x1, x1, #0xfffffffffffffff0\n"
	"msr daifset, #0xf\n"
	"mov sp, x1\n"
	"b nvme_smp_worker_entry\n"
);

static unsigned long long nvme_smp_worker_entry_addr(unsigned int coreId)
{
	switch(coreId)
	{
		case 1:
			return (unsigned long long)(unsigned long)nvme_smp_worker_trampoline1;
		case 2:
			return (unsigned long long)(unsigned long)nvme_smp_worker_trampoline2;
		case 3:
			return (unsigned long long)(unsigned long)nvme_smp_worker_trampoline3;
		default:
			return 0;
	}
}

void nvme_smp_boot_configured_worker(void)
{
#if SSD_MODEL_POLL_CORE != 0
	unsigned int coreId = SSD_MODEL_POLL_CORE;
	unsigned long long entry;

	if(coreId >= NVME_SMP_NUM_CORES)
	{
		xil_printf("[SMP] invalid SSD_MODEL_POLL_CORE=%u\r\n", coreId);
		return;
	}

	entry = nvme_smp_worker_entry_addr(coreId);
	if(entry == 0)
		return;

	nvme_smp_set_rvbar(coreId, entry);
	nvme_smp_clear_powerdown_req(coreId);
	nvme_smp_signal_event();

	xil_printf("[SMP] requested core%u SSD model worker at 0x%08X_%08X\r\n",
		   coreId, (unsigned int)(entry >> 32), (unsigned int)entry);
#endif
}
