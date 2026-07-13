#include <stdint.h>

#include "host_lld.h"
#include "nvme.h"
#include "nvme_smp.h"
#include "ssd_config.h"
#include "ssd_model.h"

#define SSD_MODEL_CMD_SLOT_COUNT		(1U << P_SLOT_TAG_WIDTH)
#define SSD_MODEL_QUEUE_DEPTH			SSD_MODEL_CMD_SLOT_COUNT
#define SSD_MODEL_QUEUE_RING_SIZE		(SSD_MODEL_QUEUE_DEPTH + 1U)
#define SSD_MODEL_NUM_LANES			(NAND_CHANNELS * LUNS_PER_NAND_CH)

#define SSD_MODEL_FLUSH_BASE_NS			100000ULL
#define SSD_MODEL_WORKER_TIMEOUT_NS		100000000ULL

#define SSD_MODEL_OP_READ			1
#define SSD_MODEL_OP_WRITE			2
#define SSD_MODEL_OP_FLUSH			3
#define SSD_MODEL_SLOT_WAIT_LIMIT		1000000U

typedef unsigned long long SSD_MODEL_QUEUE_ENTRY;

typedef struct _SSD_MODEL_IO
{
	volatile unsigned char valid;
	volatile unsigned char modelPending;
	volatile unsigned char modelReady;
	volatile unsigned char completionPending;
	volatile unsigned char writeDmaSubmitted;
	unsigned char op;
	unsigned short cmdSlotTag;
	unsigned short qID;
	unsigned short commandId;
	unsigned int requestedNvmeBlock;
	unsigned long long devAddr;
	unsigned long long dueNs;
	unsigned int dmaTailIndex;
	unsigned int dmaTailAssistIndex;
} SSD_MODEL_IO;

typedef struct _SSD_MODEL_PTR_QUEUE
{
	volatile unsigned int head;
	volatile unsigned int tail;
	SSD_MODEL_QUEUE_ENTRY entry[SSD_MODEL_QUEUE_RING_SIZE];
} SSD_MODEL_PTR_QUEUE;

static volatile unsigned int g_ssdModelLock;
static volatile unsigned int g_ssdModelWorkerActive;
static volatile unsigned int g_ssdModelDmaWorkerActive;
static volatile unsigned long long g_ssdModelWorkerHeartbeatNs;

static SSD_MODEL_IO g_ssdModelIo[SSD_MODEL_CMD_SLOT_COUNT];
static SSD_MODEL_PTR_QUEUE g_ssdModelReqQueue;
static SSD_MODEL_PTR_QUEUE g_ssdModelReadyQueue;
static unsigned long long g_nandLaneAvailNs[SSD_MODEL_NUM_LANES];
static unsigned long long g_chAvailNs[NAND_CHANNELS];
volatile unsigned int g_ssdModelDebug[16];

static inline unsigned long long ssd_model_now_ns(void)
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

static void ssd_model_lock(void)
{
#if NVME_SMP_NUM_CORES > 1
	while(__sync_lock_test_and_set(&g_ssdModelLock, 1) != 0)
	{
	}
	__sync_synchronize();
#endif
}

static unsigned int ssd_model_try_lock(void)
{
#if NVME_SMP_NUM_CORES > 1
	if(__sync_lock_test_and_set(&g_ssdModelLock, 1) != 0)
		return 0;
	__sync_synchronize();
#endif
	return 1;
}

static void ssd_model_unlock(void)
{
#if NVME_SMP_NUM_CORES > 1
	__sync_synchronize();
	__sync_lock_release(&g_ssdModelLock);
#endif
}

static inline unsigned int ssd_model_queue_next(unsigned int idx)
{
	idx++;
	if(idx == SSD_MODEL_QUEUE_RING_SIZE)
		idx = 0;

	return idx;
}

static unsigned int ssd_model_queue_empty(SSD_MODEL_PTR_QUEUE *queue)
{
	return queue->head == queue->tail;
}

static unsigned int ssd_model_queue_full(SSD_MODEL_PTR_QUEUE *queue)
{
	return ssd_model_queue_next(queue->tail) == queue->head;
}

static unsigned int ssd_model_queue_push(SSD_MODEL_PTR_QUEUE *queue,
					 SSD_MODEL_IO *io)
{
	unsigned int nextTail;

	nextTail = ssd_model_queue_next(queue->tail);
	if(nextTail == queue->head)
		return 0;

	queue->entry[queue->tail] = (SSD_MODEL_QUEUE_ENTRY)(uintptr_t)io;
	__sync_synchronize();
	queue->tail = nextTail;

	return 1;
}

static SSD_MODEL_IO *ssd_model_queue_pop(SSD_MODEL_PTR_QUEUE *queue)
{
	SSD_MODEL_IO *io;
	unsigned int nextHead;

	if(ssd_model_queue_empty(queue))
		return 0;

	__sync_synchronize();
	io = (SSD_MODEL_IO *)(uintptr_t)queue->entry[queue->head];
	nextHead = ssd_model_queue_next(queue->head);
	__sync_synchronize();
	queue->head = nextHead;

	return io;
}

void ssd_model_set_worker_active(unsigned int active)
{
	g_ssdModelWorkerActive = active ? 1 : 0;
	if(active)
		g_ssdModelWorkerHeartbeatNs = ssd_model_now_ns();
	else
		g_ssdModelWorkerHeartbeatNs = 0;
	__sync_synchronize();
}

void ssd_model_set_dma_active(unsigned int active)
{
	g_ssdModelDmaWorkerActive = active ? 1 : 0;
	__sync_synchronize();
}

unsigned int ssd_model_core0_should_poll(void)
{
#if SSD_MODEL_CORE == NVME_HOST_CORE
	return 1;
#else
	return g_ssdModelWorkerActive == 0;
#endif
}

static unsigned int ssd_model_host_should_poll_dma(void)
{
#if NVME_DMA_CORE == NVME_HOST_CORE
	return 1;
#else
	return g_ssdModelDmaWorkerActive == 0;
#endif
}

void ssd_model_worker_heartbeat(void)
{
#if SSD_MODEL_CORE != NVME_HOST_CORE
	g_ssdModelWorkerHeartbeatNs = ssd_model_now_ns();
	__sync_synchronize();
#endif
}

static unsigned int ssd_model_use_worker(void)
{
#if SSD_MODEL_CORE == NVME_HOST_CORE
	return 0;
#else
	return g_ssdModelWorkerActive != 0;
#endif
}

static inline unsigned long long ssd_model_max_ull(unsigned long long a,
						   unsigned long long b)
{
	return (a > b) ? a : b;
}

static unsigned long long ssd_model_xfer_ns(unsigned long long bytes,
					    unsigned long long mibPerSec)
{
	unsigned long long bytesPerSec = mibPerSec * 1024ULL * 1024ULL;

	if(bytesPerSec == 0)
		return 0;

	return ((bytes * 1000000000ULL) + bytesPerSec - 1) / bytesPerSec;
}

static unsigned int ssd_model_lane(unsigned long long devAddr)
{
	return (unsigned int)((devAddr / BYTES_PER_NVME_BLOCK) % SSD_MODEL_NUM_LANES);
}

static void ssd_model_submit_write_rx_dma(SSD_MODEL_IO *io)
{
	unsigned int dmaIndex;
	unsigned long long devAddr = io->devAddr;

	for(dmaIndex = 0; dmaIndex < io->requestedNvmeBlock; dmaIndex++)
	{
		set_auto_rx_dma(io->cmdSlotTag, dmaIndex, devAddr,
				NVME_COMMAND_AUTO_COMPLETION_OFF);
		devAddr += BYTES_PER_NVME_BLOCK;
	}

	io->dmaTailIndex = g_hostDmaStatus.fifoTail.autoDmaRx;
	io->dmaTailAssistIndex = g_hostDmaAssistStatus.autoDmaRxOverFlowCnt;
}

static void ssd_model_schedule_io(SSD_MODEL_IO *io)
{
	unsigned int pageIdx;
	unsigned long long nowNs;
	unsigned long long latestNs;

	nowNs = ssd_model_now_ns();
	latestNs = nowNs;

	if(io->op == SSD_MODEL_OP_FLUSH)
	{
		unsigned int lane;

		latestNs = nowNs + SSD_MODEL_FLUSH_BASE_NS;
		for(lane = 0; lane < SSD_MODEL_NUM_LANES; lane++)
			latestNs = ssd_model_max_ull(latestNs, g_nandLaneAvailNs[lane]);

		for(lane = 0; lane < NAND_CHANNELS; lane++)
			latestNs = ssd_model_max_ull(latestNs, g_chAvailNs[lane]);

		io->dueNs = latestNs;
		io->modelPending = 1;
		return;
	}

	for(pageIdx = 0; pageIdx < io->requestedNvmeBlock; pageIdx++)
	{
		unsigned long long pageAddr;
		unsigned int lane;
		unsigned int ch;
		unsigned long long nandStartNs;
		unsigned long long nandDoneNs;
		unsigned long long chStartNs;
		unsigned long long chDoneNs;

		pageAddr = io->devAddr + ((unsigned long long)pageIdx * BYTES_PER_NVME_BLOCK);
		lane = ssd_model_lane(pageAddr);
		ch = lane % NAND_CHANNELS;

		if(io->op == SSD_MODEL_OP_READ)
		{
			nandStartNs = ssd_model_max_ull(nowNs, g_nandLaneAvailNs[lane]);
			nandDoneNs = nandStartNs + FW_4KB_READ_LATENCY +
				     NAND_4KB_READ_LATENCY_LSB;

			chStartNs = ssd_model_max_ull(nandDoneNs, g_chAvailNs[ch]);
			chDoneNs = chStartNs + FW_CH_XFER_LATENCY +
				   ssd_model_xfer_ns(BYTES_PER_NVME_BLOCK,
						    NAND_CHANNEL_BANDWIDTH);

			g_nandLaneAvailNs[lane] = nandDoneNs;
			g_chAvailNs[ch] = chDoneNs;
			latestNs = ssd_model_max_ull(latestNs, chDoneNs);
		}
		else
		{
			chStartNs = ssd_model_max_ull(nowNs, g_chAvailNs[ch]);
			chDoneNs = chStartNs + FW_WBUF_LATENCY0 + FW_WBUF_LATENCY1 +
				   FW_CH_XFER_LATENCY +
				   ssd_model_xfer_ns(BYTES_PER_NVME_BLOCK,
						    NAND_CHANNEL_BANDWIDTH);

			nandStartNs = ssd_model_max_ull(chDoneNs, g_nandLaneAvailNs[lane]);
			nandDoneNs = nandStartNs + NAND_PROG_LATENCY;

			g_chAvailNs[ch] = chDoneNs;
			g_nandLaneAvailNs[lane] = nandDoneNs;

			if(WRITE_EARLY_COMPLETION)
				latestNs = ssd_model_max_ull(latestNs, chDoneNs);
			else
				latestNs = ssd_model_max_ull(latestNs, nandDoneNs);
		}
	}

	io->dueNs = latestNs;
	io->modelPending = 1;
}

static void ssd_model_submit_read_dma(SSD_MODEL_IO *io)
{
	unsigned int dmaIndex;
	unsigned long long devAddr = io->devAddr;

	for(dmaIndex = 0; dmaIndex < io->requestedNvmeBlock; dmaIndex++)
	{
		set_auto_tx_dma(io->cmdSlotTag, dmaIndex, devAddr,
				NVME_COMMAND_AUTO_COMPLETION_ON);
		devAddr += BYTES_PER_NVME_BLOCK;
	}
}

static unsigned int ssd_model_try_complete(SSD_MODEL_IO *io)
{
	if(io->valid == 0 || io->modelReady == 0)
		return 1;

	if(io->op == SSD_MODEL_OP_FLUSH)
	{
		set_auto_nvme_cpl(io->cmdSlotTag, 0, 0);
		io->valid = 0;
		return 1;
	}

	if(io->op == SSD_MODEL_OP_READ)
	{
		ssd_model_submit_read_dma(io);
		g_ssdModelDebug[6]++;
		io->valid = 0;
		return 1;
	}

	if(io->writeDmaSubmitted == 0)
	{
		ssd_model_submit_write_rx_dma(io);
		io->writeDmaSubmitted = 1;
	}

	if(check_auto_rx_dma_partial_done(io->dmaTailIndex,
					  io->dmaTailAssistIndex) == 0)
	{
		io->completionPending = 1;
		return 0;
	}

	set_auto_nvme_cpl(io->cmdSlotTag, 0, 0);
	g_ssdModelDebug[7]++;
	io->valid = 0;
	return 1;
}

static void ssd_model_dma_poll_ready(void)
{
	SSD_MODEL_IO *io;
	unsigned int idx;

	while((io = ssd_model_queue_pop(&g_ssdModelReadyQueue)) != 0)
	{
		g_ssdModelDebug[5]++;
		if(io->valid == 0)
			continue;

		io->modelReady = 1;
		ssd_model_try_complete(io);
	}

	for(idx = 0; idx < SSD_MODEL_CMD_SLOT_COUNT; idx++)
	{
		if(g_ssdModelIo[idx].valid == 0 ||
		   g_ssdModelIo[idx].completionPending == 0)
			continue;

		if(ssd_model_try_complete(&g_ssdModelIo[idx]))
		{
			g_ssdModelIo[idx].completionPending = 0;
			g_ssdModelIo[idx].writeDmaSubmitted = 0;
		}
	}
}

static void ssd_model_worker_poll(void)
{
	SSD_MODEL_IO *io;
	unsigned int idx;
	unsigned long long nowNs;

	if(ssd_model_try_lock() == 0)
		return;

	while((io = ssd_model_queue_pop(&g_ssdModelReqQueue)) != 0)
	{
		g_ssdModelDebug[3]++;
		if(io->valid == 0)
			continue;

		ssd_model_schedule_io(io);
	}

	nowNs = ssd_model_now_ns();
	for(idx = 0; idx < SSD_MODEL_CMD_SLOT_COUNT; idx++)
	{
		io = &g_ssdModelIo[idx];
		if(io->valid == 0 || io->modelPending == 0)
			continue;

		if(io->dueNs > nowNs)
			continue;

		io->modelPending = 0;
		__sync_synchronize();
		if(ssd_model_queue_push(&g_ssdModelReadyQueue, io) == 0)
		{
			io->modelPending = 1;
			g_ssdModelDebug[9]++;
			break;
		}
		g_ssdModelDebug[4]++;
	}

	ssd_model_unlock();
}

void ssd_model_reset(void)
{
	unsigned int idx;

	ssd_model_lock();

	g_ssdModelReqQueue.head = 0;
	g_ssdModelReqQueue.tail = 0;
	g_ssdModelReadyQueue.head = 0;
	g_ssdModelReadyQueue.tail = 0;

	g_ssdModelDebug[14]++;

	for(idx = 0; idx < SSD_MODEL_CMD_SLOT_COUNT; idx++)
	{
		g_ssdModelIo[idx].valid = 0;
		g_ssdModelIo[idx].modelPending = 0;
		g_ssdModelIo[idx].modelReady = 0;
		g_ssdModelIo[idx].completionPending = 0;
		g_ssdModelIo[idx].writeDmaSubmitted = 0;
	}

	for(idx = 0; idx < SSD_MODEL_NUM_LANES; idx++)
		g_nandLaneAvailNs[idx] = 0;

	for(idx = 0; idx < NAND_CHANNELS; idx++)
		g_chAvailNs[idx] = 0;

	ssd_model_unlock();
}

void ssd_model_init(void)
{
	unsigned int idx;

	g_ssdModelLock = 0;
	g_ssdModelWorkerActive = 0;
	g_ssdModelDmaWorkerActive = 0;
	g_ssdModelWorkerHeartbeatNs = 0;
	g_ssdModelReqQueue.head = 0;
	g_ssdModelReqQueue.tail = 0;
	g_ssdModelReadyQueue.head = 0;
	g_ssdModelReadyQueue.tail = 0;

	for(idx = 0; idx < 16; idx++)
		g_ssdModelDebug[idx] = 0;

	for(idx = 0; idx < SSD_MODEL_CMD_SLOT_COUNT; idx++)
	{
		g_ssdModelIo[idx].valid = 0;
		g_ssdModelIo[idx].modelPending = 0;
		g_ssdModelIo[idx].modelReady = 0;
		g_ssdModelIo[idx].completionPending = 0;
		g_ssdModelIo[idx].writeDmaSubmitted = 0;
	}

	for(idx = 0; idx < SSD_MODEL_NUM_LANES; idx++)
		g_nandLaneAvailNs[idx] = 0;

	for(idx = 0; idx < NAND_CHANNELS; idx++)
		g_chAvailNs[idx] = 0;

	__sync_synchronize();
}

void ssd_model_poll(void)
{
	unsigned int coreId;

	coreId = nvme_smp_get_core_id();

#if SSD_MODEL_CORE != NVME_HOST_CORE
	if(coreId == SSD_MODEL_CORE)
	{
		ssd_model_worker_poll();
#if NVME_DMA_CORE == SSD_MODEL_CORE
		ssd_model_dma_poll_ready();
#endif
		return;
	}
#endif

#if NVME_DMA_CORE != NVME_HOST_CORE && NVME_DMA_CORE != SSD_MODEL_CORE
	if(coreId == NVME_DMA_CORE)
	{
		ssd_model_dma_poll_ready();
		return;
	}
#endif

	if(coreId != NVME_HOST_CORE)
		return;

	if(ssd_model_host_should_poll_dma())
		ssd_model_dma_poll_ready();

	if(ssd_model_core0_should_poll())
		ssd_model_worker_poll();

	if(ssd_model_host_should_poll_dma())
		ssd_model_dma_poll_ready();
}

static unsigned int ssd_model_wait_slot_free(SSD_MODEL_IO *io)
{
	unsigned int spin;

	if(io->valid == 0)
		return 1;

	g_ssdModelDebug[13]++;
	for(spin = 0; spin < SSD_MODEL_SLOT_WAIT_LIMIT; spin++)
	{
		__sync_synchronize();
		if(io->valid == 0)
			return 1;

		if((spin & 0x3FFU) == 0)
			ssd_model_poll();
	}

	return io->valid == 0;
}

static unsigned int ssd_model_submit(unsigned char op,
				     unsigned int cmdSlotTag,
				     unsigned int qID,
				     unsigned int commandId,
				     unsigned long long devAddr,
				     unsigned int requestedNvmeBlock)
{
	SSD_MODEL_IO *io;
	unsigned int useWorker;

	if(cmdSlotTag >= SSD_MODEL_CMD_SLOT_COUNT)
		return 0;

	useWorker = ssd_model_use_worker();
	if(useWorker && ssd_model_queue_full(&g_ssdModelReqQueue))
	{
		g_ssdModelDebug[8]++;
		return 0;
	}

	io = &g_ssdModelIo[cmdSlotTag];
	if(ssd_model_wait_slot_free(io) == 0)
	{
		g_ssdModelDebug[10]++;
		return 0;
	}

	io->valid = 0;
	io->modelPending = 0;
	io->modelReady = 0;
	io->completionPending = 0;
	io->writeDmaSubmitted = 0;
	io->op = op;
	io->cmdSlotTag = (unsigned short)cmdSlotTag;
	io->qID = (unsigned short)qID;
	io->commandId = (unsigned short)commandId;
	io->requestedNvmeBlock = requestedNvmeBlock;
	io->devAddr = devAddr;
	io->dueNs = 0;
	io->dmaTailIndex = 0;
	io->dmaTailAssistIndex = 0;

#if NVME_DMA_CORE == NVME_HOST_CORE
	if(op == SSD_MODEL_OP_WRITE)
	{
		ssd_model_submit_write_rx_dma(io);
		io->writeDmaSubmitted = 1;
	}
#endif

	__sync_synchronize();
	io->valid = 1;

	if(useWorker)
	{
		if(ssd_model_queue_push(&g_ssdModelReqQueue, io))
		{
			g_ssdModelDebug[2]++;
			return 1;
		}

		g_ssdModelDebug[8]++;
		io->valid = 0;
		return 0;
	}

	g_ssdModelDebug[11]++;

	ssd_model_lock();
	ssd_model_schedule_io(io);
	ssd_model_unlock();

	return 1;
}

unsigned int ssd_model_submit_read(unsigned int cmdSlotTag,
				   unsigned int qID,
				   unsigned int commandId,
				   unsigned long long devAddr,
				   unsigned int requestedNvmeBlock)
{
	g_ssdModelDebug[0]++;
	return ssd_model_submit(SSD_MODEL_OP_READ, cmdSlotTag, qID, commandId,
				devAddr, requestedNvmeBlock);
}

unsigned int ssd_model_submit_write(unsigned int cmdSlotTag,
				    unsigned int qID,
				    unsigned int commandId,
				    unsigned long long devAddr,
				    unsigned int requestedNvmeBlock)
{
	g_ssdModelDebug[1]++;
	return ssd_model_submit(SSD_MODEL_OP_WRITE, cmdSlotTag, qID, commandId,
				devAddr, requestedNvmeBlock);
}

unsigned int ssd_model_submit_flush(unsigned int cmdSlotTag,
				    unsigned int qID,
				    unsigned int commandId)
{
	return ssd_model_submit(SSD_MODEL_OP_FLUSH, cmdSlotTag, qID, commandId, 0, 0);
}

unsigned int ssd_model_abort(unsigned int qID, unsigned int commandId)
{
	unsigned int idx;
	unsigned int aborted = 0;

	ssd_model_lock();
	for(idx = 0; idx < SSD_MODEL_CMD_SLOT_COUNT; idx++)
	{
		if(g_ssdModelIo[idx].valid == 0)
			continue;

		if(g_ssdModelIo[idx].qID != (unsigned short)qID ||
		   g_ssdModelIo[idx].commandId != (unsigned short)commandId)
			continue;

		g_ssdModelIo[idx].valid = 0;
		g_ssdModelIo[idx].modelPending = 0;
		g_ssdModelIo[idx].modelReady = 0;
		g_ssdModelIo[idx].completionPending = 0;
		g_ssdModelIo[idx].writeDmaSubmitted = 0;
		aborted++;
	}
	ssd_model_unlock();

	g_ssdModelDebug[12] += aborted;
	return aborted;
}
