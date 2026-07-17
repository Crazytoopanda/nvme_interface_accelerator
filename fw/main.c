//////////////////////////////////////////////////////////////////////////////////
// main.c for Cosmos+ OpenSSD
// Copyright (c) 2016 Hanyang University ENC Lab.
// Contributed by Yong Ho Song <yhsong@enc.hanyang.ac.kr>
//				  Youngjin Jo <yjjo@enc.hanyang.ac.kr>
//				  Sangjin Lee <sjlee@enc.hanyang.ac.kr>
//				  Jaewook Kwak <jwkwak@enc.hanyang.ac.kr>
//				  Kibin Park <kbpark@enc.hanyang.ac.kr>
//
// This file is part of Cosmos+ OpenSSD.
//
// Cosmos+ OpenSSD is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3, or (at your option)
// any later version.
//
// Cosmos+ OpenSSD is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Cosmos+ OpenSSD; see the file COPYING.
// If not, see <http://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////
// Company: ENC Lab. <http://enc.hanyang.ac.kr>
// Engineer: Sangjin Lee <sjlee@enc.hanyang.ac.kr>
//			 Jaewook Kwak <jwkwak@enc.hanyang.ac.kr>
//			 Kibin Park <kbpark@enc.hanyang.ac.kr>
//
// Project Name: Cosmos+ OpenSSD
// Design Name: Cosmos+ Firmware
// Module Name: Main
// File Name: main.c
//
// Version: v1.0.2
//
// Description:
//   - initializes caches, MMU, exception handler
//   - calls nvme_main function
//////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////
// Revision History:
//
// * v1.0.2
//   - An address region (0x0020_0000 ~ 0x179F_FFFF) is used to uncached & nonbuffered region
//   - An address region (0x1800_0000 ~ 0x3FFF_FFFF) is used to cached & buffered region
//
// * v1.0.1
//   - Paging table setting is modified for QSPI or SD card boot mode
//     * An address region (0x0010_0000 ~ 0x001F_FFFF) is used to place code, data, heap and stack sections
//     * An address region (0x0010_0000 ~ 0x001F_FFFF) is setted a cached&bufferd region
//
// * v1.0.0
//   - First draft
//////////////////////////////////////////////////////////////////////////////////



#include "kernel_config.h"
#include "xil_cache.h"
#include "xil_exception.h"
#if NVME_KERNEL_HAS_A53_MMU_TABLE
#include "xil_mmu.h"
#endif
#if NVME_USE_GIC_INTERRUPTS
#include "xparameters_ps.h"
#include "xscugic_hw.h"
#include "xscugic.h"
#endif
#if NVME_USE_AXI_INTC_INTERRUPTS
#include "xparameters.h"
#include "xintc.h"
#endif
#include "xil_printf.h"
#include "xil_types.h"
#include "nvme/debug.h"

#include "nvme/nvme.h"
#include "nvme/nvme_main.h"
#include "nvme/host_lld.h"
#include "nvme/nvme_smp.h"

#include "memory_map.h"

#if NVME_USE_AXI_INTC_INTERRUPTS
#ifndef NVME_AXI_INTC_DEVICE_ID
#if defined(XPAR_MICROBLAZE_0_AXI_INTC_DEVICE_ID)
#define NVME_AXI_INTC_DEVICE_ID XPAR_MICROBLAZE_0_AXI_INTC_DEVICE_ID
#elif defined(XPAR_INTC_0_DEVICE_ID)
#define NVME_AXI_INTC_DEVICE_ID XPAR_INTC_0_DEVICE_ID
#else
#define NVME_AXI_INTC_DEVICE_ID 0
#endif
#endif

#ifndef NVME_DEV_IRQ_INTR_ID
#if defined(XPAR_MICROBLAZE_0_AXI_INTC_NVME_CTRL_0_DEV_IRQ_ASSERT_INTR)
#define NVME_DEV_IRQ_INTR_ID XPAR_MICROBLAZE_0_AXI_INTC_NVME_CTRL_0_DEV_IRQ_ASSERT_INTR
#else
#define NVME_DEV_IRQ_INTR_ID 0
#endif
#endif
#endif

#if NVME_USE_GIC_INTERRUPTS
XScuGic GicInstance;
#endif
#if NVME_USE_AXI_INTC_INTERRUPTS
XIntc AxiIntcInstance;

static void dev_irq_xintc_handler(void *callbackRef)
{
	(void)callbackRef;
	dev_irq_handler();
}
#endif

#if NVME_INIT_ECC_MEMORY
#ifndef NVME_ECC_INIT_BASE_ADDR
#define NVME_ECC_INIT_BASE_ADDR DRAM_START_ADDR
#endif
#if NVME_KERNEL_MICROBLAZE
#ifndef NVME_MICROBLAZE_ECC_INIT_BYTES
#define NVME_MICROBLAZE_ECC_INIT_BYTES (4ULL * 1024ULL * 1024ULL * 1024ULL)
#endif
#endif
#ifndef NVME_ECC_INIT_END_ADDR
#if NVME_KERNEL_MICROBLAZE
#define NVME_ECC_INIT_END_ADDR (NVME_ECC_INIT_BASE_ADDR + NVME_MICROBLAZE_ECC_INIT_BYTES - 1ULL)
#else
#define NVME_ECC_INIT_END_ADDR DRAM_END_ADDR
#endif
#endif
#ifndef NVME_ECC_INIT_CHUNK_SIZE
#define NVME_ECC_INIT_CHUNK_SIZE (256ULL * 1024ULL * 1024ULL)
#endif

#if NVME_KERNEL_CORTEX_A53
static void a53_dcache_clean_range(UINTPTR addr, UINTPTR size)
{
	const UINTPTR cacheLineSize = 64U;
	UINTPTR a = addr & ~(cacheLineSize - 1U);
	UINTPTR endAddr = (addr + size + cacheLineSize - 1U) & ~(cacheLineSize - 1U);

	for(; a < endAddr; a += cacheLineSize)
		__asm__ volatile("dc cvac, %0" :: "r"(a) : "memory");
	__asm__ volatile("dsb sy" ::: "memory");
}
#endif

static void flush_ecc_mem_range(UINTPTR addr, UINTPTR size)
{
	const UINTPTR flushChunkSize = (UINTPTR)NVME_ECC_INIT_CHUNK_SIZE;
	UINTPTR endAddr = addr + size;
	UINTPTR chunkBase;

#if NVME_KERNEL_CORTEX_A53
	const UINTPTR cacheLineSize = 64U;
	UINTPTR alignedAddr = addr & ~(cacheLineSize - 1U);

	endAddr = (endAddr + cacheLineSize - 1U) & ~(cacheLineSize - 1U);
	for(chunkBase = alignedAddr; chunkBase < endAddr; chunkBase += flushChunkSize)
	{
		UINTPTR chunkEnd = chunkBase + flushChunkSize;
		UINTPTR a;

		if(chunkEnd > endAddr)
			chunkEnd = endAddr;

		__asm__ volatile("dsb sy" ::: "memory");
		for(a = chunkBase; a < chunkEnd; a += cacheLineSize)
			__asm__ volatile("dc zva, %0" :: "r"(a) : "memory");
		__asm__ volatile("dsb sy" ::: "memory");

		a53_dcache_clean_range(chunkBase, chunkEnd - chunkBase);
		__asm__ volatile("dsb sy" ::: "memory");
	}
#else
	const UINTPTR writeStride = sizeof(unsigned long long);
	UINTPTR alignedAddr = addr & ~(writeStride - 1U);

	endAddr = (endAddr + writeStride - 1U) & ~(writeStride - 1U);
	for(chunkBase = alignedAddr; chunkBase < endAddr; chunkBase += flushChunkSize)
	{
		UINTPTR chunkEnd = chunkBase + flushChunkSize;
		UINTPTR a;

		if(chunkEnd > endAddr)
			chunkEnd = endAddr;

#if NVME_KERNEL_MICROBLAZE
		xil_printf("ECC MB init chunk: %08X_%08X - %08X_%08X\r\n",
				(unsigned int)(chunkBase >> 32), (unsigned int)chunkBase,
				(unsigned int)((chunkEnd - 1U) >> 32), (unsigned int)(chunkEnd - 1U));
#endif
		for(a = chunkBase; a < chunkEnd; a += writeStride)
			*((volatile unsigned long long *)a) = 0ULL;
	}
#endif
}

static void init_ecc_memory(void)
{
	const UINTPTR eccInitBase = (UINTPTR)NVME_ECC_INIT_BASE_ADDR;
	const UINTPTR eccInitEnd = (UINTPTR)NVME_ECC_INIT_END_ADDR;
	const UINTPTR eccInitSize = eccInitEnd - eccInitBase + 1U;

	xil_printf("Initialize ECC memory: %08X_%08X - %08X_%08X\r\n",
			(unsigned int)(eccInitBase >> 32), (unsigned int)eccInitBase,
			(unsigned int)(eccInitEnd >> 32), (unsigned int)eccInitEnd);
	flush_ecc_mem_range(eccInitBase, eccInitSize);
	xil_printf("ECC memory initialized.\r\n");
}
#endif

#ifndef NVME_MICROBLAZE_DDR_PROBE
#define NVME_MICROBLAZE_DDR_PROBE 0
#endif

#if NVME_KERNEL_MICROBLAZE && NVME_MICROBLAZE_DDR_PROBE
static void mb_ddr_probe(void)
{
	volatile u32 *probePtr = (volatile u32 *)DRAM_START_ADDR;
	u32 before;
	u32 after;

	xil_printf("MB DDR probe: %08X_%08X\r\n",
			(unsigned int)(DRAM_START_ADDR >> 32),
			(unsigned int)DRAM_START_ADDR);

	before = probePtr[0];
	xil_printf("MB DDR probe read before: %08X\r\n", before);

	probePtr[0] = 0x12345678U;
	Xil_DCacheFlushRange((UINTPTR)probePtr, sizeof(u32));
	Xil_DCacheInvalidateRange((UINTPTR)probePtr, sizeof(u32));

	after = probePtr[0];
	xil_printf("MB DDR probe read after: %08X\r\n", after);
}
#endif

int main()
{
#if NVME_KERNEL_HAS_A53_MMU_TABLE && !NVME_USE_STATIC_MMU_TABLE
	unsigned int u;
#endif
#if NVME_KERNEL_HAS_SMP_BOOT
	unsigned int coreId;
#endif
#if NVME_USE_GIC_INTERRUPTS
	XScuGic_Config *IntcConfig;
#endif
#if NVME_USE_AXI_INTC_INTERRUPTS
	int intcStatus;
#endif

#if NVME_KERNEL_HAS_SMP_BOOT
	coreId = nvme_smp_get_core_id();
	if(coreId != 0)
		nvme_smp_start_worker(coreId);
#endif

	Xil_ICacheDisable();
	Xil_DCacheDisable();

	// Paging table set
	#define MMU_MB (1024ULL * 1024ULL)
#if NVME_KERNEL_HAS_A53_MMU_TABLE && !NVME_USE_STATIC_MMU_TABLE
	for (u = 0; u < 4096; u+=2)
	{
		if (u < 0x2)
			Xil_SetTlbAttributes(u * MMU_MB, NORM_WB_CACHE);
		else if (u < 0x180)
			Xil_SetTlbAttributes(u * MMU_MB, NORM_NONCACHE);
		else if (u < 0x400)
			Xil_SetTlbAttributes(u * MMU_MB, NORM_WB_CACHE);
		else if (u < 0x800)
			Xil_SetTlbAttributes(u * MMU_MB, NORM_NONCACHE);
		else
			Xil_SetTlbAttributes(u * MMU_MB, STRONG_ORDERED);
	}

#if NVME_USE_S1_AXI_CMD_WINDOW
	Xil_SetTlbAttributes(NVME_CMD_SQE_WINDOW_ADDR, NORM_WB_CACHE);
#endif
#if NVME_USE_S1_AXI_PACKED_DMA_SUBMIT
	Xil_SetTlbAttributes(HOST_DMA_PACKED_SUBMIT_ADDR, NORM_NONCACHE);
#endif

	for (u64 addr = DRAM_START_ADDR;
		addr <= DRAM_END_ADDR; addr += 2 * MMU_MB)
	{
		Xil_SetTlbAttributes(addr, NORM_WB_CACHE);
	}
#endif

	Xil_ICacheEnable();
	Xil_DCacheEnable();

#if NVME_KERNEL_HAS_A53_MMU_TABLE
	xil_printf("[!] MMU has been enabled.\r\n");
#else
	xil_printf("[!] MicroBlaze kernel init: single-core, no A53 MMU.\r\n");
#endif

#if NVME_INIT_ECC_MEMORY 
	init_ecc_memory();
#endif
#if NVME_KERNEL_MICROBLAZE && NVME_MICROBLAZE_DDR_PROBE
	mb_ddr_probe();
#endif

	xil_printf("\r\n Hello DaisyPlus OpenSSD !!! \r\n");

	Xil_ExceptionInit();

#if NVME_USE_GIC_INTERRUPTS
	IntcConfig = XScuGic_LookupConfig(XPAR_SCUGIC_SINGLE_DEVICE_ID);
	XScuGic_CfgInitialize(&GicInstance, IntcConfig, IntcConfig->CpuBaseAddress);
	Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
								(Xil_ExceptionHandler)XScuGic_InterruptHandler,
								&GicInstance);

	XScuGic_Connect(&GicInstance, XPS_FPGA0_INT_ID,
					(Xil_ExceptionHandler)dev_irq_handler,
					(void *)0);

	XScuGic_Enable(&GicInstance, XPS_FPGA0_INT_ID);

	// Enable interrupts in the Processor.
	Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
	Xil_ExceptionEnable();
#endif
#if NVME_USE_AXI_INTC_INTERRUPTS
	intcStatus = XIntc_Initialize(&AxiIntcInstance, NVME_AXI_INTC_DEVICE_ID);
	if(intcStatus != XST_SUCCESS)
	{
		xil_printf("AXI INTC init failed: %d\r\n", intcStatus);
	}
	else
	{
		intcStatus = XIntc_Connect(&AxiIntcInstance, NVME_DEV_IRQ_INTR_ID,
						(XInterruptHandler)dev_irq_xintc_handler,
						(void *)0);
		if(intcStatus != XST_SUCCESS)
		{
			xil_printf("AXI INTC connect failed: %d\r\n", intcStatus);
		}
		else
		{
			XIntc_Start(&AxiIntcInstance, XIN_REAL_MODE);
			XIntc_Enable(&AxiIntcInstance, NVME_DEV_IRQ_INTR_ID);
			Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
							(Xil_ExceptionHandler)XIntc_InterruptHandler,
							&AxiIntcInstance);
			Xil_ExceptionEnable();
			xil_printf("AXI INTC enabled, dev_irq intr id %d\r\n",
				   NVME_DEV_IRQ_INTR_ID);
		}
	}
#endif

	dev_irq_init();

	nvme_main();

	xil_printf("done\r\n");

	return 0;
}
