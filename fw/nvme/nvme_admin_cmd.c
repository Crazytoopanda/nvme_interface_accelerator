//////////////////////////////////////////////////////////////////////////////////
// nvme_admin_cmd.c for Cosmos+ OpenSSD
// Copyright (c) 2016 Hanyang University ENC Lab.
// Contributed by Yong Ho Song <yhsong@enc.hanyang.ac.kr>
//				  Youngjin Jo <yjjo@enc.hanyang.ac.kr>
//				  Sangjin Lee <sjlee@enc.hanyang.ac.kr>
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
//
// Project Name: Cosmos+ OpenSSD
// Design Name: Cosmos+ Firmware
// Module Name: NVMe Admin Command Handler
// File Name: nvme_admin_cmd.c
//
// Version: v1.0.0
//
// Description:
//   - handles NVMe admin command
//////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////
// Revision History:
//
// * v1.0.0
//   - First draft
//////////////////////////////////////////////////////////////////////////////////


#include "xil_printf.h"
#include "xil_cache.h"
#include "debug.h"
#include "string.h"
#include "io_access.h"

#include "nvme.h"
#include "host_lld.h"
#include "nvme_identify.h"
#include "nvme_admin_cmd.h"
#include "ssd_model.h"
#include "../memory_map.h"

extern NVME_CONTEXT g_nvmeTask;

static void set_admin_cpl_status(NVME_COMPLETION *nvmeCPL, unsigned int sct, unsigned int sc, unsigned int dnr)
{
	nvmeCPL->dword[0] = 0;
	nvmeCPL->specific = 0x0;
	nvmeCPL->statusFieldWord = 0;
	nvmeCPL->statusField.SCT = sct;
	nvmeCPL->statusField.SC = sc;
	nvmeCPL->statusField.DNR = dnr;
}

static void set_admin_cpl_success(NVME_COMPLETION *nvmeCPL)
{
	set_admin_cpl_status(nvmeCPL, SCT_GENERIC_COMMAND_STATUS, SC_SUCCESSFUL_COMPLETION, 0);
}

static void set_admin_cpl_invalid_opcode(NVME_COMPLETION *nvmeCPL)
{
	set_admin_cpl_status(nvmeCPL, SCT_GENERIC_COMMAND_STATUS, SC_INVALID_COMMAND_OPCODE, 1);
}

unsigned int set_num_of_queue(unsigned int dword11)
{
	ADMIN_SET_FEATURES_NUMBER_OF_QUEUES_DW11 requested;
	ADMIN_SET_FEATURES_NUMBER_OF_QUEUES_COMPLETE allocated;

	requested.dword = dword11;
	xil_printf("Number of IO Submission Queues Requested (NSQR, zero-based): 0x%04X\r\n", requested.NSQR);
	xil_printf("Number of IO Completion Queues Requested (NCQR, zero-based): 0x%04X\r\n", requested.NCQR);

	//IO submission queue allocating
	if(requested.NSQR >= MAX_NUM_OF_IO_SQ)
		g_nvmeTask.numOfIOSubmissionQueuesAllocated = MAX_NUM_OF_IO_SQ;
	else
		g_nvmeTask.numOfIOSubmissionQueuesAllocated = requested.NSQR + 1;//zero-based -> non zero-based

	allocated.NSQA = g_nvmeTask.numOfIOSubmissionQueuesAllocated - 1;//non zero-based -> zero-based


	//IO completion queue allocating
	if(requested.NCQR >= MAX_NUM_OF_IO_CQ)
		g_nvmeTask.numOfIOCompletionQueuesAllocated = MAX_NUM_OF_IO_CQ;
	else
		g_nvmeTask.numOfIOCompletionQueuesAllocated = requested.NCQR + 1;//zero-based -> non zero-based

	allocated.NCQA = g_nvmeTask.numOfIOCompletionQueuesAllocated - 1;//non zero-based -> zero-based

	xil_printf("Number of IO Submission Queues Allocated (NSQA, zero-based): 0x%04X\r\n", allocated.NSQA);
	xil_printf("Number of IO Completion Queues Allocated (NCQA, zero-based): 0x%04X\r\n", allocated.NCQA);

	return allocated.dword;
}

unsigned int get_num_of_queue(unsigned int dword10)
{
	ADMIN_GET_FEATURES_NUMBER_OF_QUEUES_COMPLETE allocated;

	allocated.NCQA = g_nvmeTask.numOfIOCompletionQueuesAllocated - 1;//non zero-based -> zero-based
	allocated.NSQA = g_nvmeTask.numOfIOSubmissionQueuesAllocated - 1;//non zero-based -> zero-based

	return allocated.dword;
}

void handle_set_features(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_SET_FEATURES_DW10 features;

	features.dword = nvmeAdminCmd->dword10;

	switch(features.FID)
	{
		case NUMBER_OF_QUEUES:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = set_num_of_queue(nvmeAdminCmd->dword11);
			break;
		}
		case INTERRUPT_COALESCING:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case ARBITRATION:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case ASYNCHRONOUS_EVENT_CONFIGURATION:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case VOLATILE_WRITE_CACHE:
		{
			xil_printf("Set VWC: 0x%X\r\n", nvmeAdminCmd->dword11);
			g_nvmeTask.cacheEn = (nvmeAdminCmd->dword11 & 0x1);
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case POWER_MANAGEMENT:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case TIMESTAMP:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case 0x80:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		default:
		{
			xil_printf("Not Support FID (Set): 0x%X\r\n", features.FID);
			ASSERT(0);
			break;
		}
	}
	if(__ADMIN_CMD_DONE_MESSAGE_PRINT)
    	xil_printf("Set Feature FID:0x%X\r\n", features.FID);
}

void handle_get_features(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_GET_FEATURES_DW10 features;
	NVME_COMPLETION cpl;

	features.dword = nvmeAdminCmd->dword10;

	switch(features.FID)
	{
		case NUMBER_OF_QUEUES:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = get_num_of_queue(nvmeAdminCmd->dword10);
			break;
		}
		case LBA_RANGE_TYPE:
		{
			//ASSERT(nvmeAdminCmd->NSID == 1);

			cpl.dword[0] = 0x0;
			cpl.statusField.SC = SC_INVALID_FIELD_IN_COMMAND;
			nvmeCPL->dword[0] = cpl.dword[0];
			nvmeCPL->specific = 0x0;
			break;
		}
		case TEMPERATURE_THRESHOLD:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = nvmeAdminCmd->dword11;
			break;
		}
		case VOLATILE_WRITE_CACHE:
		{
			
			xil_printf("Get VWC: 0x%X\r\n", g_nvmeTask.cacheEn);
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = g_nvmeTask.cacheEn;
			break;
		}
		case POWER_MANAGEMENT:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case POWER_STATE_TRANSITION:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case 0xD0:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		case 0x80:
		{
			nvmeCPL->dword[0] = 0x0;
			nvmeCPL->specific = 0x0;
			break;
		}
		default:
		{
			xil_printf("Not Support FID (Get): 0x%X\r\n", features.FID);
			ASSERT(0);
			break;
		}
	}
	if(__ADMIN_CMD_DONE_MESSAGE_PRINT)
    	xil_printf("Get Feature FID: 0x%X\r\n", features.FID);
}

void handle_create_io_sq(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_CREATE_IO_SQ_DW10 sqInfo10;
	ADMIN_CREATE_IO_SQ_DW11 sqInfo11;
	NVME_IO_SQ_STATUS *ioSqStatus;
	unsigned int ioSqIdx;

	sqInfo10.dword = nvmeAdminCmd->dword10;
	sqInfo11.dword = nvmeAdminCmd->dword11;

	xil_printf("Create IO SQ, DW11: 0x%08X, DW10: 0x%08X\r\n", sqInfo11.dword, sqInfo10.dword);

	ASSERT((nvmeAdminCmd->PRP1[0] & 0x3) == 0 && nvmeAdminCmd->PRP1[1] < 0x10000);
	ASSERT(0 < sqInfo10.QID && sqInfo10.QID <= 8 && sqInfo10.QSIZE < 0x100 && 0 < sqInfo11.CQID && sqInfo11.CQID <= 8);

	ioSqIdx = sqInfo10.QID - 1;
	ioSqStatus = g_nvmeTask.ioSqInfo + ioSqIdx;

	ioSqStatus->valid = 1;
	ioSqStatus->qSzie = sqInfo10.QSIZE;
	ioSqStatus->cqVector = sqInfo11.CQID;
	ioSqStatus->pcieBaseAddrL = nvmeAdminCmd->PRP1[0];
	ioSqStatus->pcieBaseAddrH = nvmeAdminCmd->PRP1[1];

	set_io_sq(ioSqIdx, ioSqStatus->valid, ioSqStatus->cqVector, ioSqStatus->qSzie, ioSqStatus->pcieBaseAddrL, ioSqStatus->pcieBaseAddrH);

	nvmeCPL->dword[0] = 0;
	nvmeCPL->specific = 0x0;

}

void handle_delete_io_sq(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_DELETE_IO_SQ_DW10 sqInfo10;
	NVME_IO_SQ_STATUS *ioSqStatus;
	unsigned int ioSqIdx;

	sqInfo10.dword = nvmeAdminCmd->dword10;

	xil_printf("Delete IO SQ, DW10: 0x%08X\r\n", sqInfo10.dword);

	ioSqIdx = (unsigned int)sqInfo10.QID - 1;
	ioSqStatus = g_nvmeTask.ioSqInfo + ioSqIdx;

	ioSqStatus->valid = 0;
	ioSqStatus->cqVector = 0;
	ioSqStatus->qSzie = 0;
	ioSqStatus->pcieBaseAddrL = 0;
	ioSqStatus->pcieBaseAddrH = 0;

	set_io_sq(ioSqIdx, 0, 0, 0, 0, 0);

	nvmeCPL->dword[0] = 0;
	nvmeCPL->specific = 0x0;
}


void handle_create_io_cq(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_CREATE_IO_CQ_DW10 cqInfo10;
	ADMIN_CREATE_IO_CQ_DW11 cqInfo11;
	NVME_IO_CQ_STATUS *ioCqStatus;
	unsigned int ioCqIdx;

	cqInfo10.dword = nvmeAdminCmd->dword10;
	cqInfo11.dword = nvmeAdminCmd->dword11;

	xil_printf("Create IO CQ, DW11: 0x%08X, DW10: 0x%08X\r\n", cqInfo11.dword, cqInfo10.dword);

	ASSERT(((nvmeAdminCmd->PRP1[0] & 0x3) == 0) && (nvmeAdminCmd->PRP1[1] < 0x10000));
	ASSERT(cqInfo11.IV < 8 && cqInfo10.QSIZE < 0x100 && 0 < cqInfo10.QID && cqInfo10.QID <= 8);

	ioCqIdx = cqInfo10.QID - 1;
	ioCqStatus = g_nvmeTask.ioCqInfo + ioCqIdx;

	ioCqStatus->valid = 1;
	ioCqStatus->qSzie = cqInfo10.QSIZE;
	ioCqStatus->irqEn = cqInfo11.IEN;
	ioCqStatus->irqVector = cqInfo11.IV;
	ioCqStatus->pcieBaseAddrL = nvmeAdminCmd->PRP1[0];
	ioCqStatus->pcieBaseAddrH = nvmeAdminCmd->PRP1[1];

	set_io_cq(ioCqIdx, ioCqStatus->valid, ioCqStatus->irqEn, ioCqStatus->irqVector, ioCqStatus->qSzie, ioCqStatus->pcieBaseAddrL, ioCqStatus->pcieBaseAddrH);

	nvmeCPL->dword[0] = 0;
	nvmeCPL->specific = 0x0;
}

void handle_delete_io_cq(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_DELETE_IO_CQ_DW10 cqInfo10;
	NVME_IO_CQ_STATUS *ioCqStatus;
	unsigned int ioCqIdx;

	cqInfo10.dword = nvmeAdminCmd->dword10;

	xil_printf("Delete IO CQ, DW10: 0x%08X\r\n", cqInfo10.dword);

	ioCqIdx = (unsigned int)cqInfo10.QID - 1;
	ioCqStatus = g_nvmeTask.ioCqInfo + ioCqIdx;

	ioCqStatus->valid = 0;
	ioCqStatus->irqVector = 0;
	ioCqStatus->qSzie = 0;
	ioCqStatus->pcieBaseAddrL = 0;
	ioCqStatus->pcieBaseAddrH = 0;
	
	set_io_cq(ioCqIdx, 0, 0, 0, 0, 0, 0);

	nvmeCPL->dword[0] = 0;
	nvmeCPL->specific = 0x0;
}

void handle_identify(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_IDENTIFY_COMMAND_DW10 identifyInfo;
	unsigned long long pIdentifyData = NVME_MANAGEMENT_START_ADDR;
	unsigned long long pIdentifyBase = pIdentifyData;
	unsigned int prp[2];
	unsigned int prpLen;
	identifyInfo.dword = nvmeAdminCmd->dword10;

	if(identifyInfo.CNS == 1 || identifyInfo.CNS == 6)//CI: Controller Identify
	{
		if((nvmeAdminCmd->PRP1[0] & 0x3) != 0 || (nvmeAdminCmd->PRP2[0] & 0x3) != 0)
			xil_printf("CI: PRP1 = 0x%08X_%08X, PRP2 = %08X_%08X\r\n", nvmeAdminCmd->PRP1[1], nvmeAdminCmd->PRP1[0], nvmeAdminCmd->PRP2[1], nvmeAdminCmd->PRP2[0]);

		ASSERT((nvmeAdminCmd->PRP1[0] & 0x3) == 0 && (nvmeAdminCmd->PRP2[0] & 0x3) == 0);
		controller_identification(pIdentifyData);
	}
	else if(identifyInfo.CNS == 2 || identifyInfo.CNS == 7)//Active Namespace ID list
	{
		unsigned int *namespaceList = (unsigned int *)pIdentifyData;

		memset(namespaceList, 0, 0x1000);
		namespaceList[0] = 1;
	}
	else if(identifyInfo.CNS == 3)//Namespace Identification Descriptor list
	{
		memset((void *)pIdentifyData, 0, 0x1000);
	}
	else if(identifyInfo.CNS == 0 || identifyInfo.CNS == 5)//NI: Namespace Identify
	{
		if((nvmeAdminCmd->PRP1[0] & 0x3) != 0 || (nvmeAdminCmd->PRP2[0] & 0x3) != 0)
			xil_printf("NI: 0xPRP1 = %08X_%08X, PRP2 = %08X_%08X\r\n", nvmeAdminCmd->PRP1[1], nvmeAdminCmd->PRP1[0], nvmeAdminCmd->PRP2[1], nvmeAdminCmd->PRP2[0]);

		//ASSERT(nvmeAdminCmd->NSID == 1);
		ASSERT((nvmeAdminCmd->PRP1[0] & 0x3) == 0 && (nvmeAdminCmd->PRP2[0] & 0x3) == 0);
		namespace_identification(pIdentifyData);
	}
	else
	{
		xil_printf("Unsupported Identify CNS: 0x%X\r\n", identifyInfo.CNS);
		nvmeCPL->dword[0] = 0;
		nvmeCPL->specific = 0x0;
		nvmeCPL->statusField.SC = SC_INVALID_FIELD_IN_COMMAND;
		nvmeCPL->statusField.SCT = SCT_GENERIC_COMMAND_STATUS;
		return;
	}

	Xil_DCacheFlushRange((UINTPTR)pIdentifyBase, 0x1000);
	// identifyWords = (volatile unsigned int *)pIdentifyBase;
	// xil_printf("[Identify] CNS=%X buf=%08X_%08X PRP1=%08X_%08X PRP2=%08X_%08X\r\n",
	// 		identifyInfo.CNS,
	// 		(unsigned int)(pIdentifyBase >> 32), (unsigned int)pIdentifyBase,
	// 		nvmeAdminCmd->PRP1[1], nvmeAdminCmd->PRP1[0],
	// 		nvmeAdminCmd->PRP2[1], nvmeAdminCmd->PRP2[0]);
	// xil_printf("[Identify] first dwords:");
	// for(idx = 0; idx < 8; idx++)
	// 	xil_printf(" %08X", identifyWords[idx]);
	// xil_printf("\r\n");
	
	prp[0] = nvmeAdminCmd->PRP1[0];
	prp[1] = nvmeAdminCmd->PRP1[1];

	prpLen = 0x1000 - (prp[0] & 0xFFF);
//	xil_printf("prpLen = %X, prp[1] = %X, prp[0] = %X\r\n",prpLen, prp[1], prp[0]);
	set_direct_tx_dma(pIdentifyData, prp[1], prp[0], prpLen);
	if(prpLen != 0x1000)
	{
		pIdentifyData = pIdentifyData + prpLen;
		prpLen = 0x1000 - prpLen;
		prp[0] = nvmeAdminCmd->PRP2[0];
		prp[1] = nvmeAdminCmd->PRP2[1];

//		ASSERT((prp[1] & 0xFFF) == 0);
//		xil_printf("prpLen = %X, prp[1] = %X, prp[0] = %X\r\n",prpLen, prp[1], prp[0]);
		set_direct_tx_dma(pIdentifyData, prp[1], prp[0], prpLen);
	}

	check_direct_tx_dma_done();
	nvmeCPL->dword[0] = 0;
	nvmeCPL->specific = 0x0;
}

void handle_get_log_page(NVME_ADMIN_COMMAND *nvmeAdminCmd, NVME_COMPLETION *nvmeCPL)
{
	ADMIN_GET_LOG_PAGE_DW10 getLogPageInfo;
	unsigned long long logBase = NVME_MANAGEMENT_START_ADDR;
	volatile unsigned char *logData = (volatile unsigned char *)logBase;
	unsigned int transferLen;
	unsigned int firstPrpLen;
	unsigned int idx;

	getLogPageInfo.dword = nvmeAdminCmd->dword10;
	transferLen = ((unsigned int)getLogPageInfo.NUMD + 1) * 4;

	nvmeCPL->dword[0] = 0;
	nvmeCPL->specific = 0;

	if(transferLen == 0 || transferLen > 0x1000)
	{
		nvmeCPL->statusField.SCT = 0;
		nvmeCPL->statusField.SC = SC_INVALID_FIELD_IN_COMMAND;
		nvmeCPL->statusField.DNR = 1;
		return;
	}

	ASSERT((nvmeAdminCmd->PRP1[0] & 0x3) == 0 && (nvmeAdminCmd->PRP2[0] & 0x3) == 0);
	ASSERT(nvmeAdminCmd->PRP1[1] < 0x10000 && nvmeAdminCmd->PRP2[1] < 0x10000);

	for(idx = 0; idx < 0x1000; idx++)
		logData[idx] = 0;

	switch(getLogPageInfo.LID)
	{
		case 0x01:
		{
			break;
		}
		case 0x02:
		{
			logData[0] = 0x00;
			logData[1] = 0x2C;
			logData[2] = 0x01;
			logData[3] = 100;
			logData[4] = 10;
			logData[5] = 0;
			break;
		}
		case 0x03:
		{
			logData[0] = 0x01;
			break;
		}
		default:
		{
			nvmeCPL->statusField.SCT = 1;
			nvmeCPL->statusField.SC = SC_INVALID_LOG_PAGE;
			nvmeCPL->statusField.DNR = 1;
			return;
		}
	}

	Xil_DCacheFlushRange((UINTPTR)logBase, 0x1000);

	firstPrpLen = 0x1000 - (nvmeAdminCmd->PRP1[0] & 0xFFF);
	if(firstPrpLen > transferLen)
		firstPrpLen = transferLen;

	set_direct_tx_dma(logBase, nvmeAdminCmd->PRP1[1], nvmeAdminCmd->PRP1[0], firstPrpLen);
	if(firstPrpLen < transferLen)
	{
		set_direct_tx_dma(logBase + firstPrpLen,
				nvmeAdminCmd->PRP2[1],
				nvmeAdminCmd->PRP2[0],
				transferLen - firstPrpLen);
	}

	check_direct_tx_dma_done();
	nvmeCPL->statusFieldWord = 0;
	nvmeCPL->specific = 0;
}

void handle_nvme_admin_cmd(NVME_COMMAND *nvmeCmd)
{
	NVME_ADMIN_COMMAND *nvmeAdminCmd;
	NVME_COMPLETION nvmeCPL;
	unsigned int opc;
	unsigned int needCpl;
	unsigned int needSlotRelease;

	nvmeAdminCmd = (NVME_ADMIN_COMMAND*)nvmeCmd->cmdDword;
	opc = (unsigned int)nvmeAdminCmd->OPC;

	needCpl = 1;
	needSlotRelease = 0;
	switch(opc)
	{
		case ADMIN_SET_FEATURES:
		{
			handle_set_features(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_CREATE_IO_CQ:
		{
			handle_create_io_cq(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_CREATE_IO_SQ:
		{
			handle_create_io_sq(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_IDENTIFY:
		{
			PRINT("ADMIN_IDENTIFY\r\n");
			handle_identify(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_GET_FEATURES:
		{
			handle_get_features(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_DELETE_IO_CQ:
		{
			handle_delete_io_cq(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_DELETE_IO_SQ:
		{
			handle_delete_io_sq(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_ASYNCHRONOUS_EVENT_REQUEST:
		{
			needCpl = 0;
			needSlotRelease = 1;
			nvmeCPL.dword[0] = 0;
			nvmeCPL.specific = 0x0;
			break;
		}
		case ADMIN_GET_LOG_PAGE:
		{
			handle_get_log_page(nvmeAdminCmd, &nvmeCPL);
			break;
		}
		case ADMIN_KEEP_ALIVE:
		{
			set_admin_cpl_success(&nvmeCPL);
			break;
		}
		case ADMIN_FORMAT_NVM:
		{
			ssd_model_reset();
			set_admin_cpl_success(&nvmeCPL);
			break;
		}
		case ADMIN_SECURITY_SEND:
		case ADMIN_SECURITY_RECEIVE:
		case ADMIN_DOORBELL_BUFFER_CONFIG:
		case ADMIN_FIRMWARE_ACTIVATE:
		case ADMIN_FIRMWARE_IMAGE_DOWNLOAD:
		case ADMIN_DEVICE_SELF_TEST:
		case ADMIN_NAMESPACE_MANAGEMENT:
		case ADMIN_NAMESPACE_ATTACHMENT:
		case ADMIN_DIRECTIVE_SEND:
		case ADMIN_DIRECTIVE_RECEIVE:
		case ADMIN_VIRTUALIZATION_MANAGEMENT:
		case ADMIN_NVME_MI_SEND:
		case ADMIN_NVME_MI_RECEIVE:
		case ADMIN_CAPACITY_MANAGEMENT:
		case ADMIN_LOCKDOWN:
		case ADMIN_SANITIZE:
		case ADMIN_GET_LBA_STATUS:
		{
			set_admin_cpl_invalid_opcode(&nvmeCPL);
			break;
		}
		case ADMIN_VENDOR_LIBNVM:
		{
			set_admin_cpl_success(&nvmeCPL);
			break;
		}
		case ADMIN_ABORT:
		{
			unsigned int abortSqId;
			unsigned int abortCmdId;

			abortSqId = nvmeAdminCmd->dword10 & 0xFFFFU;
			abortCmdId = (nvmeAdminCmd->dword10 >> 16) & 0xFFFFU;
			nvmeCPL.dword[0] = ssd_model_abort(abortSqId, abortCmdId);
			nvmeCPL.specific = 0x0;
			break;
		}
		default:
		{
			xil_printf("Not Support Admin Command OPC: 0x%X\r\n", opc);
			set_admin_cpl_invalid_opcode(&nvmeCPL);
			break;
		}
	}

	/* if CQE error, we try it as below */
	// if(needCpl == 1) {
	// 	set_nvme_cpl(nvmeCmd->qID, nvmeAdminCmd->CID,
	// 			nvmeCPL.specific, nvmeCPL.statusFieldWord);
	// 	set_nvme_slot_release(nvmeCmd->cmdSlotTag);
	// }
	// else if(needSlotRelease == 1) {
	// 	set_nvme_slot_release(nvmeCmd->cmdSlotTag);
	// }

	if(needCpl == 1)
		set_auto_nvme_cpl(nvmeCmd->cmdSlotTag, nvmeCPL.specific, nvmeCPL.statusFieldWord);
	else if(needSlotRelease == 1)
		set_nvme_slot_release(nvmeCmd->cmdSlotTag);
	else

	set_nvme_cpl(nvmeCmd->qID, nvmeAdminCmd->CID, nvmeCPL.specific, nvmeCPL.statusFieldWord);

	if(__ADMIN_CMD_DONE_MESSAGE_PRINT)
		xil_printf("Admin Command Done, OPC: 0x%02X\r\n", opc);
}

