//////////////////////////////////////////////////////////////////////////////////
// nvme_main.c for Cosmos+ OpenSSD
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
// Module Name: NVMe Main
// File Name: nvme_main.c
//
// Version: v1.2.0
//
// Description:
//   - initializes FTL and NAND
//   - handles NVMe controller
//////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////
// Revision History:
//
// * v1.2.0
//   - header file for buffer is changed from "ia_lru_buffer.h" to "lru_buffer.h"
//   - Low level scheduler execution is allowed when there is no i/o command
//
// * v1.1.0
//   - DMA status initialization is added
//
// * v1.0.0
//   - First draft
//////////////////////////////////////////////////////////////////////////////////

#include <string.h>

#include "xil_printf.h"
#include "debug.h"
#include "io_access.h"

#include "nvme.h"
#include "host_lld.h"
#include "nvme_main.h"
#include "nvme_admin_cmd.h"
#include "nvme_io_cmd.h"
#include "ssd_model.h"
#include "ssd_config.h"
#include "nvme_smp.h"
#include "nvme_smp_boot.h"

#include "../memory_map.h"

volatile NVME_CONTEXT g_nvmeTask;
volatile unsigned int g_nvmeWaitCcObservedDisabled;

#define NVME_SHUTDOWN_REARM_DELAY_NS	100000000ULL

static unsigned long long nvme_main_now_ns(void)
{
	unsigned long long cnt;
	unsigned long long freq;
	unsigned long long sec;
	unsigned long long rem;

	__asm__ volatile("mrs %0, cntvct_el0" : "=r"(cnt));
	__asm__ volatile("mrs %0, cntfrq_el0" : "=r"(freq));
	if(freq == 0)
		return 0;

	sec = cnt / freq;
	rem = cnt % freq;
	return (sec * 1000000000ULL) + ((rem * 1000000000ULL) / freq);
}

static void clear_nvme_status_for_rearm(void)
{
	NVME_STATUS_REG nvmeReg;

	nvmeReg.dword = IO_READ32(NVME_STATUS_REG_ADDR);
	nvmeReg.ccEn = 0;
	nvmeReg.ccShn = 0;
	nvmeReg.cstsRdy = 0;
	nvmeReg.cstsShst = 0;
	IO_WRITE32(NVME_STATUS_REG_ADDR, nvmeReg.dword);
}

void nvme_main()
{
	unsigned int rstCnt = 0;
	unsigned long long waitResetStartNs = 0;
#if NVME_BOOT_ERASE_BYTES != 0
	unsigned char *p_storage = (unsigned char *)DATA_BUFFER_BASE_ADDR;
	memset(p_storage, 0xFF, NVME_BOOT_ERASE_BYTES);
#endif
	nvme_smp_init();
	g_nvmeWaitCcObservedDisabled = 1;
	ssd_model_init();
	nvme_smp_boot_configured_worker();

	xil_printf("[ storage capacity %d MB ]\r\n", (unsigned int)(NVME_STORAGE / (1024ULL * 1024ULL)));

	xil_printf("Turn on the host PC \r\n");

	while(1)
	{
		if(g_nvmeTask.status == NVME_TASK_IDLE)
		{
			unsigned int ccEn;

			ccEn = check_nvme_cc_en();
			if(ccEn == 0)
				g_nvmeWaitCcObservedDisabled = 1;
			else if(g_nvmeWaitCcObservedDisabled != 0)
				g_nvmeTask.status = NVME_TASK_WAIT_CC_EN;
		}
		else if(g_nvmeTask.status == NVME_TASK_WAIT_CC_EN)
		{
			unsigned int ccEn;
			ccEn = check_nvme_cc_en();
			if(ccEn == 0)
			{
				g_nvmeWaitCcObservedDisabled = 1;
			}
			else
			{
				if(g_nvmeWaitCcObservedDisabled == 0)
					g_nvmeWaitCcObservedDisabled = 1;

				g_nvmeWaitCcObservedDisabled = 0;
				set_nvme_admin_queue(1, 1, 1);
				set_nvme_csts_rdy(1);
				nvme_smp_enable_io();
				g_nvmeTask.status = NVME_TASK_RUNNING;
				xil_printf("\r\nNVMe ready!!!\r\n");
			}
		}
		else if(g_nvmeTask.status == NVME_TASK_RUNNING)
		{
			NVME_COMMAND nvmeCmd;
			unsigned int cmdValid;

			ssd_model_poll();
			if(g_nvmeTask.status != NVME_TASK_RUNNING)
				continue;

			cmdValid = get_nvme_cmd(&nvmeCmd.qID, &nvmeCmd.cmdSlotTag, &nvmeCmd.cmdSeqNum, nvmeCmd.cmdDword);

			if(cmdValid == 1)
			{
				rstCnt = 0;
				if(nvmeCmd.qID == 0)
				{
					handle_nvme_admin_cmd(&nvmeCmd);
				}
				else
				{
					handle_nvme_io_cmd(&nvmeCmd);
				}
			}
		}
		else if(g_nvmeTask.status == NVME_TASK_SHUTDOWN)
		{
			unsigned int qID;

			set_nvme_csts_shst(1);

			for(qID = 0; qID < 8; qID++)
			{
				set_io_cq(qID, 0, 0, 0, 0, 0, 0);
				set_io_sq(qID, 0, 0, 0, 0, 0);
			}

			set_nvme_admin_queue(0, 0, 0);
			g_nvmeTask.cacheEn = 0;
			nvme_smp_disable_io();
			nvme_smp_reset_queues();
			reset_host_dma_credit();
			set_nvme_csts_shst(2);
			waitResetStartNs = nvme_main_now_ns();
			g_nvmeTask.status = NVME_TASK_WAIT_RESET;

			xil_printf("\r\nNVMe shutdown!!!\r\n");
		}
		else if(g_nvmeTask.status == NVME_TASK_WAIT_RESET)
		{
			unsigned int ccEn;
			unsigned int qID;

			ccEn = check_nvme_cc_en();
			if(waitResetStartNs == 0)
				waitResetStartNs = nvme_main_now_ns();

			if((ccEn == 0) ||
			   ((nvme_main_now_ns() - waitResetStartNs) >=
			    NVME_SHUTDOWN_REARM_DELAY_NS))
			{
				g_nvmeTask.cacheEn = 0;
				nvme_smp_disable_io();
				nvme_smp_reset_queues();
				ssd_model_reset();
				reset_host_dma_credit();
				clear_nvme_status_for_rearm();

				set_nvme_admin_queue(0, 0, 0);
				for(qID = 0; qID < 8; qID++)
				{
					set_io_cq(qID, 0, 0, 0, 0, 0, 0);
					set_io_sq(qID, 0, 0, 0, 0, 0);
				}

				waitResetStartNs = 0;
				g_nvmeWaitCcObservedDisabled = 0;
				dev_irq_init();
				g_nvmeTask.status = NVME_TASK_IDLE;
				xil_printf("\r\nNVMe disable!!!\r\n");
			}
		}
		else if(g_nvmeTask.status == NVME_TASK_RESET)
		{
			unsigned int qID;
			for(qID = 0; qID < 8; qID++)
			{
				set_io_cq(qID, 0, 0, 0, 0, 0, 0);
				set_io_sq(qID, 0, 0, 0, 0, 0);
			}

			if (rstCnt== 5){
				pcie_async_reset(rstCnt);
				rstCnt = 0;
				xil_printf("\r\nPcie iink disable!!!\r\n");
				xil_printf("Wait few minute or reconnect the PCIe cable\r\n");
			}
			else
				rstCnt++;

			g_nvmeTask.cacheEn = 0;
			nvme_smp_disable_io();
			nvme_smp_reset_queues();
			ssd_model_reset();
			reset_host_dma_credit();
			set_nvme_admin_queue(0, 0, 0);
			set_nvme_csts_shst(0);
			set_nvme_csts_rdy(0);
			g_nvmeTask.status = NVME_TASK_IDLE;

			xil_printf("\r\nNVMe reset!!!\r\n");
		}
	}
}


