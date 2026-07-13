//////////////////////////////////////////////////////////////////////////////////
// nvme_io_cmd.c for Cosmos+ OpenSSD
// Copyright (c) 2016 Hanyang University ENC Lab.
// Contributed by Yong Ho Song <yhsong@enc.hanyang.ac.kr>
//				  Youngjin Jo <yjjo@enc.hanyang.ac.kr>
//				  Sangjin Lee <sjlee@enc.hanyang.ac.kr>
//				  Jaewook Kwak <jwkwak@enc.hanyang.ac.kr>
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
//
// Project Name: Cosmos+ OpenSSD
// Design Name: Cosmos+ Firmware
// Module Name: NVMe IO Command Handler
// File Name: nvme_io_cmd.c
//
// Version: v1.0.1
//
// Description:
//   - handles NVMe IO command
//////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////
// Revision History:
//
// * v1.0.1
//   - header file for buffer is changed from "ia_lru_buffer.h" to "lru_buffer.h"
//
// * v1.0.0
//   - First draft
//////////////////////////////////////////////////////////////////////////////////


#include "xil_printf.h"
#include "debug.h"
#include "io_access.h"

#include "nvme.h"
#include "host_lld.h"
#include "nvme_io_cmd.h"
#include "ssd_model.h"
#include "../memory_map.h"

static inline unsigned long long get_io_cmd_dev_addr(const unsigned int *cmdDword)
{
	unsigned long long startLba;

	startLba = ((unsigned long long)cmdDword[11] << 32) | cmdDword[10];
	return DATA_BUFFER_BASE_ADDR + (startLba * BYTES_PER_NVME_BLOCK);
}

static inline unsigned int get_io_cmd_nlb(const unsigned int *cmdDword)
{
	return cmdDword[12] & 0xFFFFU;
}

static void complete_io_internal_error(unsigned int cmdSlotTag)
{
	NVME_COMPLETION nvmeCPL;

	nvmeCPL.dword[0] = 0;
	nvmeCPL.specific = 0x0;
	nvmeCPL.statusField.SC = SC_INTERNAL_DEVICE_ERROR;
	nvmeCPL.statusField.SCT = SCT_GENERIC_COMMAND_STATUS;
	nvmeCPL.statusField.DNR = 1;

	set_auto_nvme_cpl(cmdSlotTag, nvmeCPL.specific, nvmeCPL.statusFieldWord);
}

static void handle_nvme_io_read_model(unsigned int cmdSlotTag, const unsigned int *cmdDword)
{
	unsigned int requestedNvmeBlock;
	unsigned long long devAddr;

	requestedNvmeBlock = get_io_cmd_nlb(cmdDword) + 1;
	devAddr = get_io_cmd_dev_addr(cmdDword);

	if(ssd_model_submit_read(cmdSlotTag, devAddr, requestedNvmeBlock) == 0)
		complete_io_internal_error(cmdSlotTag);
}

static void handle_nvme_io_write_model(unsigned int cmdSlotTag, const unsigned int *cmdDword)
{
	unsigned int requestedNvmeBlock;
	unsigned long long devAddr;

	requestedNvmeBlock = get_io_cmd_nlb(cmdDword) + 1;
	devAddr = get_io_cmd_dev_addr(cmdDword);

	if(ssd_model_submit_write(cmdSlotTag, devAddr, requestedNvmeBlock) == 0)
		complete_io_internal_error(cmdSlotTag);
}

void handle_nvme_io_cmd(NVME_COMMAND *nvmeCmd)
{
	unsigned int *cmdDword;
	unsigned int opc;

	cmdDword = nvmeCmd->cmdDword;
	opc = cmdDword[0] & 0xFFU;

	switch(opc)
	{
		case IO_NVM_FLUSH:
		{
			PRINT("IO Flush Command\r\n");
			if(ssd_model_submit_flush(nvmeCmd->cmdSlotTag) == 0)
				complete_io_internal_error(nvmeCmd->cmdSlotTag);
			break;
		}
		case IO_NVM_WRITE:
		{
			PRINT("IO Write Command\r\n");
			handle_nvme_io_write_model(nvmeCmd->cmdSlotTag, cmdDword);
			break;
		}
		case IO_NVM_READ:
		{
			PRINT("IO Read Command\r\n");
			handle_nvme_io_read_model(nvmeCmd->cmdSlotTag, cmdDword);
			break;
		}
		default:
		{
			xil_printf("Not Support IO Command OPC: 0x%X\r\n", opc);
			ASSERT(0);
			break;
		}
	}

#if (__IO_CMD_DONE_MESSAGE_PRINT)
	{
		NVME_IO_COMMAND *nvmeIOCmd;

		nvmeIOCmd = (NVME_IO_COMMAND*)cmdDword;
		xil_printf("OPC = 0x%X\r\n", nvmeIOCmd->OPC);
		xil_printf("PRP1[63:32] = 0x%X, PRP1[31:0] = 0x%X\r\n", nvmeIOCmd->PRP1[1], nvmeIOCmd->PRP1[0]);
		xil_printf("PRP2[63:32] = 0x%X, PRP2[31:0] = 0x%X\r\n", nvmeIOCmd->PRP2[1], nvmeIOCmd->PRP2[0]);
		xil_printf("dword10 = 0x%X\r\n", nvmeIOCmd->dword10);
		xil_printf("dword11 = 0x%X\r\n", nvmeIOCmd->dword11);
		xil_printf("dword12 = 0x%X\r\n", nvmeIOCmd->dword12);
	}
#endif
}
