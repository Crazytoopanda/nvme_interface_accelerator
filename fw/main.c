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



#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_mmu.h"
#include "xparameters_ps.h"
#include "xscugic_hw.h"
#include "xscugic.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "nvme/debug.h"

#include "nvme/nvme.h"
#include "nvme/nvme_main.h"
#include "nvme/host_lld.h"
#include "nvme/nvme_smp.h"

#include "memory_map.h"

#ifndef NVME_USE_STATIC_MMU_TABLE
#define NVME_USE_STATIC_MMU_TABLE 1
#endif


XScuGic GicInstance;

static void flush_ecc_mem_range(UINTPTR addr, UINTPTR size)
{
	const UINTPTR cacheLineSize = 64;
	const UINTPTR flushChunkSize = 256ULL * 1024ULL * 1024ULL;
	UINTPTR alignedAddr = addr & ~(cacheLineSize - 1U);
	UINTPTR endAddr = (addr + size + cacheLineSize - 1U) & ~(cacheLineSize - 1U);
	UINTPTR chunkBase;

	for (chunkBase = alignedAddr; chunkBase < endAddr; chunkBase += flushChunkSize) {
		UINTPTR chunkEnd = chunkBase + flushChunkSize;
		UINTPTR a;

		if (chunkEnd > endAddr)
			chunkEnd = endAddr;

		__asm__ volatile("dsb sy" ::: "memory");
		for (a = chunkBase; a < chunkEnd; a += cacheLineSize)
			__asm__ volatile("dc zva, %0" :: "r"(a) : "memory");
		__asm__ volatile("dsb sy" ::: "memory");

		Xil_DCacheFlushRange(chunkBase, chunkEnd - chunkBase);
		__asm__ volatile("dsb sy" ::: "memory");
	}
}

static void init_ecc_memory(void)
{
	const UINTPTR eccInitBase = (UINTPTR)DRAM_START_ADDR;
	const UINTPTR eccInitSize = (UINTPTR)(DRAM_END_ADDR - DRAM_START_ADDR + 1ULL);

	xil_printf("Initialize ECC memory...\r\n");
	flush_ecc_mem_range(eccInitBase, eccInitSize);
	xil_printf("ECC memory initialized.\r\n");
}

int main()
{
#if !NVME_USE_STATIC_MMU_TABLE
	unsigned int u;
#endif
	unsigned int coreId;

	XScuGic_Config *IntcConfig;

	coreId = nvme_smp_get_core_id();
	if(coreId != 0)
		nvme_smp_start_worker(coreId);

	Xil_ICacheDisable();
	Xil_DCacheDisable();

	// Paging table set
	#define MMU_MB (1024ULL * 1024ULL)
#if !NVME_USE_STATIC_MMU_TABLE
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

	Xil_SetTlbAttributes(NVME_CMD_SQE_WINDOW_ADDR, NORM_WB_CACHE);
	Xil_SetTlbAttributes(HOST_DMA_PACKED_SUBMIT_ADDR, NORM_NONCACHE);

	for (u64 addr = DRAM_START_ADDR;
		addr <= DRAM_END_ADDR; addr += 2 * MMU_MB)
	{
		Xil_SetTlbAttributes(addr, NORM_WB_CACHE);
	}
#endif

	Xil_ICacheEnable();
	Xil_DCacheEnable();
	xil_printf("[!] MMU has been enabled.\r\n");
	init_ecc_memory();
	
	xil_printf("\r\n Hello DaisyPlus OpenSSD !!! \r\n");

	Xil_ExceptionInit();

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

	dev_irq_init();

	nvme_main();

	xil_printf("done\r\n");

	return 0;
}
