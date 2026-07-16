//////////////////////////////////////////////////////////////////////////////////
// nvme_smp.c
// Lightweight SMP polling scheduler for NVMe IO commands.
//////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>

#include "xil_printf.h"

#include "nvme.h"
#include "nvme_io_cmd.h"
#include "nvme_smp.h"
#include "ssd_config.h"
#include "ssd_model.h"

extern volatile NVME_CONTEXT g_nvmeTask;

typedef struct _NVME_SMP_CMD_QUEUE
{
	volatile unsigned int head;
	volatile unsigned int tail;
	volatile unsigned int active;
	NVME_COMMAND cmd[NVME_SMP_CMD_QUEUE_DEPTH];
} NVME_SMP_CMD_QUEUE;

static volatile unsigned int g_nvmeSmpReady;
static volatile unsigned int g_nvmeSmpIoEnabled;
static volatile unsigned int g_nvmeUartLock;
static volatile unsigned int g_nvmeUartLockOwner = 0xFFFFFFFF;
static volatile unsigned int g_nvmeUartLockDepth;
static volatile unsigned int g_nvmeIoSubmitLock;
static NVME_SMP_CMD_QUEUE g_nvmeSmpQueue[NVME_SMP_NUM_CORES];
unsigned long g_nvmeSmpWorkerStack[NVME_SMP_NUM_CORES][2048] __attribute__((aligned(64), used));
volatile unsigned int g_nvmeSmpWorkerDebug[NVME_SMP_NUM_CORES];

static void nvme_smp_barrier(void)
{
	__sync_synchronize();
}

void nvme_smp_mask_worker_exceptions(void)
{
#if NVME_KERNEL_MICROBLAZE
	return;
#elif defined(__aarch64__)
	__asm__ volatile("msr daifset, #0xf" ::: "memory");
#else
	__asm__ volatile("cpsid if" ::: "memory");
#endif
}

void nvme_uart_lock(void)
{
	unsigned int coreId = nvme_smp_get_core_id();

	if(g_nvmeUartLockOwner == coreId)
	{
		g_nvmeUartLockDepth++;
		return;
	}

	while(__sync_lock_test_and_set(&g_nvmeUartLock, 1) != 0)
	{
	}

	__sync_synchronize();
	g_nvmeUartLockOwner = coreId;
	g_nvmeUartLockDepth = 1;
}

void nvme_uart_unlock(void)
{
	unsigned int coreId = nvme_smp_get_core_id();

	if(g_nvmeUartLockOwner != coreId)
		return;

	if(g_nvmeUartLockDepth > 1)
	{
		g_nvmeUartLockDepth--;
		return;
	}

	g_nvmeUartLockDepth = 0;
	g_nvmeUartLockOwner = 0xFFFFFFFF;
	__sync_synchronize();
	__sync_lock_release(&g_nvmeUartLock);
}

void nvme_io_submit_lock(void)
{
	while(__sync_lock_test_and_set(&g_nvmeIoSubmitLock, 1) != 0)
	{
	}
	__sync_synchronize();
}

void nvme_io_submit_unlock(void)
{
	__sync_synchronize();
	__sync_lock_release(&g_nvmeIoSubmitLock);
}

static void nvme_smp_worker_cpu_init(void)
{
	/* Core0 owns shared MMU/cache setup and all device interrupts. */
	nvme_smp_mask_worker_exceptions();
	nvme_smp_barrier();
}

void nvme_smp_worker_entry(unsigned int coreId) __attribute__((noreturn, used));

void nvme_smp_worker_entry(unsigned int coreId)
{
	nvme_smp_worker_cpu_init();
	nvme_smp_worker_loop(coreId);
}

unsigned int nvme_smp_get_core_id(void)
{
#if NVME_KERNEL_MICROBLAZE
	return 0;
#else
	unsigned long mpidr;

#if defined(__aarch64__)
	__asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
#else
	__asm__ volatile("mrc p15, 0, %0, c0, c0, 5" : "=r"(mpidr));
#endif

	if((mpidr & 0xFF) != 0)
		return (unsigned int)(mpidr & 0x3);

	return (unsigned int)((mpidr >> 8) & 0x3);
#endif
}

static unsigned int nvme_smp_queue_is_full(NVME_SMP_CMD_QUEUE *queue)
{
	unsigned int nextTail = (queue->tail + 1) % NVME_SMP_CMD_QUEUE_DEPTH;
	return nextTail == queue->head;
}

static unsigned int nvme_smp_queue_is_empty(NVME_SMP_CMD_QUEUE *queue)
{
	return queue->head == queue->tail;
}

static unsigned int nvme_smp_enqueue(unsigned int coreId, NVME_COMMAND *nvmeCmd)
{
	NVME_SMP_CMD_QUEUE *queue = &g_nvmeSmpQueue[coreId];
	unsigned int nextTail;

	if(nvme_smp_queue_is_full(queue))
		return 0;

	queue->cmd[queue->tail] = *nvmeCmd;
	nvme_smp_barrier();

	nextTail = (queue->tail + 1) % NVME_SMP_CMD_QUEUE_DEPTH;
	queue->tail = nextTail;

	return 1;
}

static unsigned int nvme_smp_dequeue(unsigned int coreId, NVME_COMMAND *nvmeCmd)
{
	NVME_SMP_CMD_QUEUE *queue = &g_nvmeSmpQueue[coreId];
	unsigned int nextHead;

	if(nvme_smp_queue_is_empty(queue))
		return 0;

	*nvmeCmd = queue->cmd[queue->head];
	nvme_smp_barrier();

	nextHead = (queue->head + 1) % NVME_SMP_CMD_QUEUE_DEPTH;
	queue->head = nextHead;

	return 1;
}

static unsigned int nvme_smp_map_qid_to_core(unsigned int qID)
{
#if SSD_MODEL_POLL_CORE != 0
	(void)qID;
	return SSD_MODEL_POLL_CORE;
#else
	return (qID - 1) % NVME_SMP_NUM_CORES;
#endif
}

void nvme_smp_init(void)
{
	unsigned int coreId;

	g_nvmeSmpIoEnabled = 0;
	for(coreId = 0; coreId < NVME_SMP_NUM_CORES; coreId++)
	{
		g_nvmeSmpQueue[coreId].head = 0;
		g_nvmeSmpQueue[coreId].tail = 0;
		g_nvmeSmpQueue[coreId].active = 0;
	}

	nvme_smp_barrier();
	g_nvmeSmpReady = 1;
}

void nvme_smp_enable_io(void)
{
	nvme_smp_barrier();
	g_nvmeSmpIoEnabled = 1;
}

void nvme_smp_disable_io(void)
{
	g_nvmeSmpIoEnabled = 0;
	nvme_smp_barrier();
}

void nvme_smp_reset_queues(void)
{
	unsigned int coreId;

	for(coreId = 0; coreId < NVME_SMP_NUM_CORES; coreId++)
	{
		g_nvmeSmpQueue[coreId].head = 0;
		g_nvmeSmpQueue[coreId].tail = 0;
	}
	nvme_smp_barrier();
}

void nvme_smp_dispatch_io_cmd(NVME_COMMAND *nvmeCmd)
{
	unsigned int coreId;

	if(nvmeCmd->qID == 0)
		return;

	if(g_nvmeTask.status != NVME_TASK_RUNNING)
		return;

	if(g_nvmeSmpIoEnabled == 0)
	{
		handle_nvme_io_cmd(nvmeCmd);
		return;
	}

	coreId = nvme_smp_map_qid_to_core(nvmeCmd->qID);

	if(coreId >= NVME_SMP_NUM_CORES)
		coreId = 0;

	if(coreId != 0 && g_nvmeSmpQueue[coreId].active == 0)
	{
		handle_nvme_io_cmd(nvmeCmd);
		return;
	}

	while(nvme_smp_enqueue(coreId, nvmeCmd) == 0)
	{
		if(g_nvmeTask.status != NVME_TASK_RUNNING)
			return;
		if(g_nvmeSmpIoEnabled == 0)
		{
			handle_nvme_io_cmd(nvmeCmd);
			return;
		}

		if(coreId == 0)
			nvme_smp_poll_core(0);
		else if(g_nvmeSmpQueue[coreId].active == 0)
		{
			handle_nvme_io_cmd(nvmeCmd);
			return;
		}
	}
}

unsigned int nvme_smp_poll_core(unsigned int coreId)
{
	NVME_COMMAND nvmeCmd;

	if(coreId >= NVME_SMP_NUM_CORES || g_nvmeSmpIoEnabled == 0)
		return 0;

	if(nvme_smp_dequeue(coreId, &nvmeCmd) == 0)
		return 0;

	handle_nvme_io_cmd(&nvmeCmd);
	return 1;
}

void nvme_smp_start_worker(unsigned int coreId)
{
#if NVME_KERNEL_HAS_SMP_BOOT
#if defined(__aarch64__)
	register unsigned long coreReg __asm__("x0") = coreId;

	__asm__ volatile(
		"cmp x0, #3\n"
		"b.ls 1f\n"
		"mov x0, #0\n"
		"1:\n"
		"adrp x1, g_nvmeSmpWorkerStack\n"
		"add x1, x1, :lo12:g_nvmeSmpWorkerStack\n"
		"add x2, x0, #1\n"
		"lsl x2, x2, #14\n"
		"add x1, x1, x2\n"
		"and x1, x1, #0xfffffffffffffff0\n"
		"msr daifset, #0xf\n"
		"mov sp, x1\n"
		"b nvme_smp_worker_entry\n"
		: "+r"(coreReg)
		:
		: "x1", "x2", "memory");
#else
#error "NVME SMP worker startup is only implemented for Cortex-A53 AArch64"
#endif
#else
	(void)coreId;
	while(1)
	{
	}
#endif

	__builtin_unreachable();
}

void nvme_smp_worker_loop(unsigned int coreId)
{
	if(coreId >= NVME_SMP_NUM_CORES)
		coreId = 0;

	g_nvmeSmpWorkerDebug[coreId] = 0x10;

	while(g_nvmeSmpReady == 0)
	{
	}

	g_nvmeSmpWorkerDebug[coreId] = 0x20;
	g_nvmeSmpQueue[coreId].active = 1;
	g_nvmeSmpWorkerDebug[coreId] = 0x30;

#if SSD_MODEL_CORE != NVME_HOST_CORE
	if(coreId == SSD_MODEL_CORE)
	{
		g_nvmeSmpWorkerDebug[coreId] = 0x40;
		ssd_model_set_worker_active(1);
		g_nvmeSmpWorkerDebug[coreId] = 0x50;
	}
#endif

#if NVME_DMA_CORE != NVME_HOST_CORE
	if(coreId == NVME_DMA_CORE)
	{
		g_nvmeSmpWorkerDebug[coreId] = 0x44;
		ssd_model_set_dma_active(1);
		g_nvmeSmpWorkerDebug[coreId] = 0x54;
	}
#endif

	while(1)
	{
#if SSD_MODEL_CORE != NVME_HOST_CORE
		if(coreId == SSD_MODEL_CORE)
		{
			g_nvmeSmpWorkerDebug[coreId] = 0x60;
			ssd_model_worker_heartbeat();
		}
#endif

		if(g_nvmeTask.status == NVME_TASK_RUNNING)
		{
			if(coreId == SSD_MODEL_CORE || coreId == NVME_DMA_CORE)
			{
				g_nvmeSmpWorkerDebug[coreId] = 0x70;
				ssd_model_poll();
			}

			nvme_smp_poll_core(coreId);
		}
	}
}
