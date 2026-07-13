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
	".global nvme_smp_worker_el3_init\n"
	"nvme_smp_worker_el3_init:\n"
	"msr daifset, #0xf\n"
	"adrp x3, _vector_table\n"
	"add x3, x3, :lo12:_vector_table\n"
	"msr vbar_el3, x3\n"
	"mov x3, #0x400\n"
	"msr cptr_el3, x3\n"
	"isb\n"
	"mov x3, #0xc0e\n"
	"msr scr_el3, x3\n"
	"movz x3, #0xa000\n"
	"movk x3, #0x080c, lsl #16\n"
	"movk x3, #0x1000, lsl #32\n"
	"msr s3_1_c15_c2_0, x3\n"
	"mrs x3, s3_1_c15_c2_1\n"
	"orr x3, x3, #0x40\n"
	"msr s3_1_c15_c2_1, x3\n"
	"movz x3, #0x9f08\n"
	"movk x3, #0x01fc, lsl #16\n"
	"msr cntfrq_el0, x3\n"
	"tlbi alle3\n"
	"ic iallu\n"
	"dsb sy\n"
	"isb\n"
	"adrp x3, MMUTableL0\n"
	"add x3, x3, :lo12:MMUTableL0\n"
	"msr ttbr0_el3, x3\n"
	"movz x3, #0xff44\n"
	"movk x3, #0x0400, lsl #16\n"
	"movk x3, #0x00bb, lsl #32\n"
	"msr mair_el3, x3\n"
	"movz x3, #0x3518\n"
	"movk x3, #0x8082, lsl #16\n"
	"msr tcr_el3, x3\n"
	"isb\n"
	"mov x3, #0x100d\n"
	"msr sctlr_el3, x3\n"
	"dsb sy\n"
	"isb\n"
	"ret\n"
	".align 7\n"
	".global nvme_smp_worker_trampoline1\n"
	"nvme_smp_worker_trampoline1:\n"
	"mov x0, #1\n"
	"adrp x4, g_nvmeSmpWorkerDebug\n"
	"add x4, x4, :lo12:g_nvmeSmpWorkerDebug\n"
	"mov w5, #0x1\n"
	"str w5, [x4, #4]\n"
	"adrp x1, g_nvmeSmpWorkerStack\n"
	"add x1, x1, :lo12:g_nvmeSmpWorkerStack\n"
	"add x2, x0, #1\n"
	"lsl x2, x2, #14\n"
	"add x1, x1, x2\n"
	"and x1, x1, #0xfffffffffffffff0\n"
	"msr daifset, #0xf\n"
	"mov sp, x1\n"
	"mov w5, #0x2\n"
	"str w5, [x4, #4]\n"
	"bl nvme_smp_worker_el3_init\n"
	"mov w5, #0x3\n"
	"str w5, [x4, #4]\n"
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
	"bl nvme_smp_worker_el3_init\n"
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
	"bl nvme_smp_worker_el3_init\n"
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
#if NVME_SMP_NUM_CORES > 1
	unsigned int coreId;

	for(coreId = 1; coreId < NVME_SMP_NUM_CORES; coreId++)
	{
		unsigned long long entry;

		entry = nvme_smp_worker_entry_addr(coreId);
		if(entry == 0)
			continue;

		nvme_smp_set_rvbar(coreId, entry);
		nvme_smp_clear_powerdown_req(coreId);
	}

	nvme_smp_signal_event();
#endif
}
