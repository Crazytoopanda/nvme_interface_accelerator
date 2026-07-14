#include <stdint.h>

#include "host_lld.h"
#include "nvme.h"
#include "nvme_smp.h"
#include "ssd_config.h"
#include "ssd_model.h"
#include "../memory_map.h"

#define SSD_MODEL_CMD_SLOT_COUNT		(1U << P_SLOT_TAG_WIDTH)
#define SSD_MODEL_QUEUE_DEPTH			SSD_MODEL_CMD_SLOT_COUNT
#define SSD_MODEL_QUEUE_RING_SIZE		(SSD_MODEL_QUEUE_DEPTH + 1U)
#define SSD_MODEL_BUFFER_RELEASE_SLOTS		(SSD_MODEL_CMD_SLOT_COUNT * 64U)
#define SSD_MODEL_PARTITIONS			SSD_PARTITIONS
#define SSD_MODEL_PART_NAND_CHANNELS		(NAND_CHANNELS / SSD_MODEL_PARTITIONS)
#define SSD_MODEL_NUM_LANES			(NAND_CHANNELS * LUNS_PER_NAND_CH)
#define SSD_MODEL_PART_LANES			(SSD_MODEL_PART_NAND_CHANNELS * LUNS_PER_NAND_CH)
#define SSD_MODEL_INVALID_PAGE			0xFFFFFFFFU
#define SSD_MODEL_DIV_ROUND_UP(x, y)		(((x) + (y) - 1ULL) / (y))
#define SSD_MODEL_PAGES_PER_ONESHOT		(ONESHOT_PAGE_SIZE / BYTES_PER_NVME_BLOCK)
#define SSD_MODEL_BLOCK_BYTES			SSD_MODEL_DIV_ROUND_UP(NVME_STORAGE, \
						 ((BLKS_PER_PLN * 1ULL) * PLNS_PER_LUN * \
						  LUNS_PER_NAND_CH * NAND_CHANNELS))
#define SSD_MODEL_ONESHOTS_PER_BLOCK		SSD_MODEL_DIV_ROUND_UP(SSD_MODEL_BLOCK_BYTES, \
						 ONESHOT_PAGE_SIZE)
#define SSD_MODEL_PAGES_PER_BLOCK		(SSD_MODEL_PAGES_PER_ONESHOT * \
						 SSD_MODEL_ONESHOTS_PER_BLOCK)
#define SSD_MODEL_PAGES_PER_LINE		(SSD_MODEL_PAGES_PER_BLOCK * SSD_MODEL_PART_LANES)
#define SSD_MODEL_LINE_COUNT			BLKS_PER_PLN
#define SSD_MODEL_TOTAL_LINE_COUNT		(SSD_MODEL_LINE_COUNT * SSD_MODEL_PARTITIONS)
#define SSD_MODEL_LOGICAL_PAGES			(NVME_STORAGE / BYTES_PER_NVME_BLOCK)
#define SSD_MODEL_PART_PHYSICAL_PAGES		((SSD_MODEL_LINE_COUNT * 1ULL) * \
						 SSD_MODEL_PAGES_PER_LINE)
#define SSD_MODEL_PHYSICAL_PAGES		(SSD_MODEL_PART_PHYSICAL_PAGES * \
						 SSD_MODEL_PARTITIONS)
#define SSD_MODEL_L2P_ADDR			NVME_MANAGEMENT_START_ADDR
#define SSD_MODEL_P2L_ADDR			(SSD_MODEL_L2P_ADDR + \
						 (SSD_MODEL_LOGICAL_PAGES * 4ULL))
#define SSD_MODEL_CH_CREDIT_ENTRIES		(1024U * 96U)
#define SSD_MODEL_CH_UNIT_TIME_NS		4000ULL
#define SSD_MODEL_CH_UNIT_XFER_BYTES		128ULL
#define SSD_MODEL_CH_UNIT_CREDITS		1U
#define SSD_MODEL_CH_CREDIT_ADDR		(SSD_MODEL_P2L_ADDR + \
						 (SSD_MODEL_PHYSICAL_PAGES * 4ULL))
#define SSD_MODEL_META_END_ADDR			(SSD_MODEL_CH_CREDIT_ADDR + \
						 ((NAND_CHANNELS * 1ULL) * \
						  SSD_MODEL_CH_CREDIT_ENTRIES * 2ULL))

#if (NAND_CHANNELS % SSD_MODEL_PARTITIONS) != 0
#error "NAND_CHANNELS must be divisible by SSD_PARTITIONS"
#endif

#if SSD_MODEL_PHYSICAL_PAGES < SSD_MODEL_LOGICAL_PAGES
#error "SSD model physical pages must cover advertised logical pages"
#endif

#if SSD_MODEL_META_END_ADDR > NVME_MANAGEMENT_END_ADDR
#error "NVMe management DRAM is too small for SSD model metadata"
#endif

#define SSD_MODEL_FLUSH_BASE_NS			100000ULL
#define SSD_MODEL_WORKER_TIMEOUT_NS		100000000ULL
#define SSD_MODEL_READ_SMALL_LIMIT_BYTES		(64ULL * 1024ULL)
#define SSD_MODEL_READ_SMALL_MIB_PER_SEC	4700ULL
#define SSD_MODEL_READ_LARGE_MIB_PER_SEC	4000ULL
#define SSD_MODEL_WRITE_SMALL_LIMIT_BYTES	(64ULL * 1024ULL)
#define SSD_MODEL_WRITE_SMALL_MIB_PER_SEC	1000ULL
#define SSD_MODEL_WRITE_LARGE_MIB_PER_SEC	2000ULL
#define SSD_MODEL_GC_THRES_LINES		2U
#define SSD_MODEL_GC_THRES_LINES_HIGH		2U

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

typedef struct _SSD_MODEL_WRITE_POINTER
{
	unsigned int line;
	unsigned int page;
	unsigned int lun;
	unsigned int ch;
} SSD_MODEL_WRITE_POINTER;

typedef struct _SSD_MODEL_CHANNEL_MODEL
{
	unsigned long long curTimeNs;
	unsigned int head;
	unsigned int validLen;
	unsigned int maxCredits;
	unsigned int commandCredits;
	unsigned int xferLatNs;
} SSD_MODEL_CHANNEL_MODEL;

#define SSD_MODEL_LINE_FREE			0
#define SSD_MODEL_LINE_OPEN			1
#define SSD_MODEL_LINE_FULL			2
#define SSD_MODEL_LINE_VICTIM			3

static volatile unsigned int g_ssdModelLock;
static volatile unsigned int g_ssdModelWorkerActive;
static volatile unsigned int g_ssdModelDmaWorkerActive;
static volatile unsigned long long g_ssdModelWorkerHeartbeatNs;

static SSD_MODEL_IO g_ssdModelIo[SSD_MODEL_CMD_SLOT_COUNT];
static SSD_MODEL_PTR_QUEUE g_ssdModelReqQueue;
static SSD_MODEL_PTR_QUEUE g_ssdModelReadyQueue;
static unsigned long long g_nandLaneAvailNs[SSD_MODEL_NUM_LANES];
static unsigned long long g_chAvailNs[NAND_CHANNELS];
static SSD_MODEL_CHANNEL_MODEL g_chModel[NAND_CHANNELS];
static unsigned long long g_writeBufferReleaseNs[SSD_MODEL_BUFFER_RELEASE_SLOTS];
static unsigned long long g_writeBufferReleaseBytes[SSD_MODEL_BUFFER_RELEASE_SLOTS];
static unsigned int g_writeBufferReleaseHead;
static unsigned int g_writeBufferReleaseTail;
static unsigned long long g_writeBufferUsedBytes;
static unsigned long long g_readPipeAvailNs;
static unsigned long long g_writeFrontendAvailNs;
static unsigned short g_lineValidPages[SSD_MODEL_TOTAL_LINE_COUNT];
static unsigned short g_lineInvalidPages[SSD_MODEL_TOTAL_LINE_COUNT];
static unsigned char g_lineState[SSD_MODEL_TOTAL_LINE_COUNT];
static unsigned int g_freeLineCount[SSD_MODEL_PARTITIONS];
static SSD_MODEL_WRITE_POINTER g_userWritePointer[SSD_MODEL_PARTITIONS];
static SSD_MODEL_WRITE_POINTER g_gcWritePointer[SSD_MODEL_PARTITIONS];
static unsigned int g_writeCredits[SSD_MODEL_PARTITIONS];
static unsigned int g_creditsToRefill[SSD_MODEL_PARTITIONS];
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

static unsigned long long ssd_model_pipe_xfer(unsigned long long *availNs,
					      unsigned long long startNs,
					      unsigned long long bytes,
					      unsigned long long mibPerSec)
{
	unsigned long long pipeStartNs;
	unsigned long long doneNs;

	pipeStartNs = ssd_model_max_ull(startNs, *availNs);
	doneNs = pipeStartNs + ssd_model_xfer_ns(bytes, mibPerSec);
	*availNs = doneNs;

	return doneNs;
}

static unsigned long long ssd_model_read_pipe_mib_per_sec(unsigned long long bytes)
{
	return (bytes <= SSD_MODEL_READ_SMALL_LIMIT_BYTES) ?
	       SSD_MODEL_READ_SMALL_MIB_PER_SEC : SSD_MODEL_READ_LARGE_MIB_PER_SEC;
}

static unsigned long long ssd_model_write_pipe_mib_per_sec(unsigned long long bytes)
{
	return (bytes <= SSD_MODEL_WRITE_SMALL_LIMIT_BYTES) ?
	       SSD_MODEL_WRITE_SMALL_MIB_PER_SEC : SSD_MODEL_WRITE_LARGE_MIB_PER_SEC;
}


static inline unsigned int ssd_model_part_from_lpn(unsigned int lpn)
{
	return lpn % SSD_MODEL_PARTITIONS;
}

static inline unsigned int ssd_model_local_lpn(unsigned int lpn)
{
	return lpn / SSD_MODEL_PARTITIONS;
}

static inline unsigned int ssd_model_line_slot(unsigned int part,
					       unsigned int line)
{
	return (part * SSD_MODEL_LINE_COUNT) + line;
}

static inline unsigned int ssd_model_ppa_part(unsigned int ppa)
{
	return ppa / SSD_MODEL_PART_PHYSICAL_PAGES;
}

static inline unsigned int ssd_model_ppa_local(unsigned int ppa)
{
	return ppa % SSD_MODEL_PART_PHYSICAL_PAGES;
}

static inline unsigned int ssd_model_ppa_line(unsigned int ppa)
{
	return ssd_model_ppa_local(ppa) / SSD_MODEL_PAGES_PER_LINE;
}

static inline unsigned int ssd_model_ppa_line_slot(unsigned int ppa)
{
	return ssd_model_line_slot(ssd_model_ppa_part(ppa), ssd_model_ppa_line(ppa));
}

static inline unsigned int ssd_model_ppa_page(unsigned int ppa)
{
	return (ssd_model_ppa_local(ppa) % SSD_MODEL_PAGES_PER_LINE) /
	       SSD_MODEL_PART_LANES;
}

static inline unsigned int ssd_model_ppa_local_lane(unsigned int ppa)
{
	return ssd_model_ppa_local(ppa) % SSD_MODEL_PART_LANES;
}

static inline volatile unsigned short *ssd_model_ch_credits(unsigned int ch)
{
	return (volatile unsigned short *)(unsigned long)
	       (SSD_MODEL_CH_CREDIT_ADDR +
		((unsigned long long)ch * SSD_MODEL_CH_CREDIT_ENTRIES * 2ULL));
}

static unsigned int ssd_model_ch_max_credits(void)
{
	unsigned long long credits;

	credits = (NAND_CHANNEL_BANDWIDTH * 1024ULL * 1024ULL *
		   SSD_MODEL_CH_UNIT_TIME_NS);
	credits /= 1000000000ULL;
	credits /= SSD_MODEL_CH_UNIT_XFER_BYTES;
	credits *= SSD_MODEL_CH_UNIT_CREDITS;

	if(credits == 0)
		credits = 1;
	if(credits > 0xFFFFU)
		credits = 0xFFFFU;

	return (unsigned int)credits;
}

static unsigned int ssd_model_ch_xfer_lat_ns(void)
{
	unsigned long long bytesPerSec;
	unsigned long long lat;

	bytesPerSec = NAND_CHANNEL_BANDWIDTH * 1024ULL * 1024ULL;
	if(bytesPerSec == 0)
		return 0;

	lat = (SSD_MODEL_CH_UNIT_XFER_BYTES * 1000000000ULL) / bytesPerSec;
	lat += (FW_CH_XFER_LATENCY * SSD_MODEL_CH_UNIT_XFER_BYTES) /
	       BYTES_PER_NVME_BLOCK;

	return (unsigned int)lat;
}

static void ssd_model_ch_reset_range(unsigned int ch,
					     unsigned int start,
					     unsigned int count)
{
	volatile unsigned short *credits = ssd_model_ch_credits(ch);
	unsigned int idx;
	unsigned int pos = start;
	unsigned short value = (unsigned short)g_chModel[ch].maxCredits;

	for(idx = 0; idx < count; idx++)
	{
		credits[pos] = value;
		pos++;
		if(pos == SSD_MODEL_CH_CREDIT_ENTRIES)
			pos = 0;
	}
}

static void ssd_model_ch_init(unsigned int ch)
{
	g_chModel[ch].curTimeNs = 0;
	g_chModel[ch].head = 0;
	g_chModel[ch].validLen = 0;
	g_chModel[ch].maxCredits = ssd_model_ch_max_credits();
	g_chModel[ch].commandCredits = 0;
	g_chModel[ch].xferLatNs = ssd_model_ch_xfer_lat_ns();
	ssd_model_ch_reset_range(ch, 0, SSD_MODEL_CH_CREDIT_ENTRIES);
}

static unsigned long long ssd_model_ch_request(unsigned int ch,
					       unsigned long long requestTimeNs,
					       unsigned long long bytes)
{
	SSD_MODEL_CHANNEL_MODEL *model = &g_chModel[ch];
	volatile unsigned short *credits = ssd_model_ch_credits(ch);
	unsigned long long curTimeNs = ssd_model_now_ns();
	unsigned long long totalLatencyNs;
	unsigned int curOffs;
	unsigned int reqOffs;
	unsigned int pos;
	unsigned int nextPos;
	unsigned int remainingCredits;
	unsigned int consumedCredits;
	unsigned int defaultDelay;
	unsigned int delay = 0;
	unsigned int validLen;
	unsigned int unitsToXfer;

	if(bytes == 0)
		return requestTimeNs;

	curOffs = (unsigned int)((curTimeNs / SSD_MODEL_CH_UNIT_TIME_NS) -
				       (model->curTimeNs / SSD_MODEL_CH_UNIT_TIME_NS));
	if(curOffs > model->validLen)
		curOffs = model->validLen;

	if(curOffs != 0)
	{
		ssd_model_ch_reset_range(ch, model->head, curOffs);
		model->head = (model->head + curOffs) % SSD_MODEL_CH_CREDIT_ENTRIES;
		model->curTimeNs = curTimeNs;
		model->validLen -= curOffs;
	}
	else if(model->curTimeNs == 0)
	{
		model->curTimeNs = curTimeNs;
	}

	if(requestTimeNs < curTimeNs)
		return requestTimeNs;

	reqOffs = (unsigned int)((requestTimeNs / SSD_MODEL_CH_UNIT_TIME_NS) -
				       (curTimeNs / SSD_MODEL_CH_UNIT_TIME_NS));
	if(reqOffs >= SSD_MODEL_CH_CREDIT_ENTRIES)
	{
		g_ssdModelDebug[15]++;
		return requestTimeNs;
	}

	pos = (model->head + reqOffs) % SSD_MODEL_CH_CREDIT_ENTRIES;
	unitsToXfer = (unsigned int)SSD_MODEL_DIV_ROUND_UP(bytes,
							 SSD_MODEL_CH_UNIT_XFER_BYTES);
	remainingCredits = (unitsToXfer * SSD_MODEL_CH_UNIT_CREDITS) +
			   model->commandCredits;
	defaultDelay = remainingCredits / model->maxCredits;

	while(remainingCredits != 0)
	{
		consumedCredits = (remainingCredits <= credits[pos]) ?
				  remainingCredits : credits[pos];
		credits[pos] = (unsigned short)(credits[pos] - consumedCredits);
		remainingCredits -= consumedCredits;

		if(remainingCredits == 0)
			break;

		nextPos = pos + 1;
		if(nextPos == SSD_MODEL_CH_CREDIT_ENTRIES)
			nextPos = 0;
		if(nextPos == model->head)
		{
			g_ssdModelDebug[15]++;
			break;
		}

		delay++;
		pos = nextPos;
	}

	validLen = (pos >= model->head) ?
		   (pos - model->head + 1U) :
		   (SSD_MODEL_CH_CREDIT_ENTRIES - (model->head - pos - 1U));
	if(validLen > model->validLen)
		model->validLen = validLen;

	delay = (delay > defaultDelay) ? (delay - defaultDelay) : 0;
	totalLatencyNs = ((unsigned long long)model->xferLatNs * unitsToXfer) +
			 ((unsigned long long)delay * SSD_MODEL_CH_UNIT_TIME_NS);

	return requestTimeNs + totalLatencyNs;
}

static unsigned int ssd_model_release_next(unsigned int idx)
{
	idx++;
	if(idx == SSD_MODEL_BUFFER_RELEASE_SLOTS)
		idx = 0;

	return idx;
}

static void ssd_model_release_write_buffer(unsigned long long nowNs)
{
	while(g_writeBufferReleaseHead != g_writeBufferReleaseTail)
	{
		unsigned int idx = g_writeBufferReleaseHead;

		if(g_writeBufferReleaseBytes[idx] == 0 ||
		   g_writeBufferReleaseNs[idx] > nowNs)
			break;

		if(g_writeBufferReleaseBytes[idx] <= g_writeBufferUsedBytes)
			g_writeBufferUsedBytes -= g_writeBufferReleaseBytes[idx];
		else
			g_writeBufferUsedBytes = 0;

		g_writeBufferReleaseBytes[idx] = 0;
		g_writeBufferReleaseNs[idx] = 0;
		g_writeBufferReleaseHead = ssd_model_release_next(idx);
	}
}

static unsigned long long ssd_model_earliest_write_buffer_release(void)
{
	if(g_writeBufferReleaseHead == g_writeBufferReleaseTail)
		return ~0ULL;

	return g_writeBufferReleaseNs[g_writeBufferReleaseHead];
}

static void ssd_model_queue_write_buffer_release(unsigned long long doneNs,
						 unsigned long long bytes)
{
	unsigned int nextTail;
	unsigned int tail = g_writeBufferReleaseTail;

	if(bytes == 0)
		return;

	nextTail = ssd_model_release_next(tail);
	if(nextTail == g_writeBufferReleaseHead)
	{
		g_ssdModelDebug[15]++;
		return;
	}

	g_writeBufferReleaseBytes[tail] = bytes;
	g_writeBufferReleaseNs[tail] = doneNs;
	g_writeBufferReleaseTail = nextTail;
}

static unsigned long long ssd_model_advance_write_buffer(unsigned long long startNs,
						 unsigned long long bytes)
{
	unsigned long long units;
	unsigned long long releaseNs;

	if(bytes == 0 || GLOBAL_WB_SIZE == 0)
		return startNs;

	ssd_model_release_write_buffer(startNs);
	while(g_writeBufferUsedBytes + bytes > GLOBAL_WB_SIZE)
	{
		releaseNs = ssd_model_earliest_write_buffer_release();
		if(releaseNs == ~0ULL)
			break;

		startNs = ssd_model_max_ull(startNs, releaseNs);
		ssd_model_release_write_buffer(startNs);
	}

	g_writeBufferUsedBytes += bytes;
	units = (bytes + BYTES_PER_NVME_BLOCK - 1ULL) / BYTES_PER_NVME_BLOCK;

	return startNs + FW_WBUF_LATENCY0 + (FW_WBUF_LATENCY1 * units) +
	       ssd_model_xfer_ns(bytes, PCIE_BANDWIDTH);
}

static inline unsigned int *ssd_model_l2p(void)
{
	return (unsigned int *)(unsigned long)SSD_MODEL_L2P_ADDR;
}

static inline unsigned int *ssd_model_p2l(void)
{
	return (unsigned int *)(unsigned long)SSD_MODEL_P2L_ADDR;
}

static unsigned int ssd_model_lpn_from_addr(unsigned long long devAddr)
{
	return (unsigned int)((devAddr - DATA_BUFFER_BASE_ADDR) / BYTES_PER_NVME_BLOCK);
}

static unsigned int ssd_model_ppa_lane(unsigned int ppa)
{
	unsigned int part = ssd_model_ppa_part(ppa);
	unsigned int localLane = ssd_model_ppa_local_lane(ppa);
	unsigned int lun = localLane / SSD_MODEL_PART_NAND_CHANNELS;
	unsigned int ch = localLane % SSD_MODEL_PART_NAND_CHANNELS;

	return (lun * NAND_CHANNELS) + (part * SSD_MODEL_PART_NAND_CHANNELS) + ch;
}

static unsigned int ssd_model_same_flash_page(unsigned int a, unsigned int b)
{
	if(ssd_model_ppa_part(a) != ssd_model_ppa_part(b))
		return 0;
	if(ssd_model_ppa_lane(a) != ssd_model_ppa_lane(b))
		return 0;

	return (ssd_model_ppa_local(a) /
		(SSD_MODEL_PART_LANES * SSD_MODEL_PAGES_PER_ONESHOT)) ==
	       (ssd_model_ppa_local(b) /
		(SSD_MODEL_PART_LANES * SSD_MODEL_PAGES_PER_ONESHOT));
}

static unsigned long long ssd_model_read_latency_ppa_ns(unsigned int ppa,
						 unsigned long long xferBytes)
{
	if((ssd_model_ppa_page(ppa) & 1U) != 0)
		return (xferBytes == BYTES_PER_NVME_BLOCK) ?
		       NAND_4KB_READ_LATENCY_MSB : NAND_READ_LATENCY_MSB;

	return (xferBytes == BYTES_PER_NVME_BLOCK) ?
	       NAND_4KB_READ_LATENCY_LSB : NAND_READ_LATENCY_LSB;
}

static unsigned long long ssd_model_schedule_nand_read_ppa(unsigned int ppa,
						   unsigned long long startNs,
						   unsigned long long xferBytes)
{
	unsigned int lane = ssd_model_ppa_lane(ppa);
	unsigned int ch = lane % NAND_CHANNELS;
	unsigned long long nandStartNs;
	unsigned long long nandDoneNs;
	unsigned long long chStartNs;
	unsigned long long chDoneNs;

	nandStartNs = ssd_model_max_ull(startNs, g_nandLaneAvailNs[lane]);
	nandDoneNs = nandStartNs + ssd_model_read_latency_ppa_ns(ppa, xferBytes);
	chStartNs = nandDoneNs;
	chDoneNs = ssd_model_ch_request(ch, chStartNs, xferBytes);

	g_nandLaneAvailNs[lane] = chDoneNs;
	g_chAvailNs[ch] = ssd_model_max_ull(g_chAvailNs[ch], chDoneNs);
	return chDoneNs;
}

static unsigned long long ssd_model_schedule_nand_write_ppa(unsigned int ppa,
						    unsigned long long startNs,
						    unsigned long long bytes)
{
	unsigned int lane = ssd_model_ppa_lane(ppa);
	unsigned int ch = lane % NAND_CHANNELS;
	unsigned long long chStartNs;
	unsigned long long chDoneNs;
	unsigned long long nandStartNs;
	unsigned long long nandDoneNs;

	chStartNs = ssd_model_max_ull(startNs, g_nandLaneAvailNs[lane]);
	chDoneNs = ssd_model_ch_request(ch, chStartNs, bytes);
	nandStartNs = chDoneNs;
	nandDoneNs = nandStartNs + NAND_PROG_LATENCY;

	g_chAvailNs[ch] = ssd_model_max_ull(g_chAvailNs[ch], chDoneNs);
	g_nandLaneAvailNs[lane] = nandDoneNs;
	return nandDoneNs;
}

static void ssd_model_write_pointer_clear(SSD_MODEL_WRITE_POINTER *wp)
{
	wp->line = SSD_MODEL_INVALID_PAGE;
	wp->page = 0;
	wp->lun = 0;
	wp->ch = 0;
}

static unsigned int ssd_model_open_free_line(unsigned int part,
					     SSD_MODEL_WRITE_POINTER *wp)
{
	unsigned int line;

	for(line = 0; line < SSD_MODEL_LINE_COUNT; line++)
	{
		unsigned int slot = ssd_model_line_slot(part, line);

		if(g_lineState[slot] == SSD_MODEL_LINE_FREE)
		{
			g_lineState[slot] = SSD_MODEL_LINE_OPEN;
			if(g_freeLineCount[part] != 0)
				g_freeLineCount[part]--;
			wp->line = line;
			wp->page = 0;
			wp->lun = 0;
			wp->ch = 0;
			return 1;
		}
	}

	return 0;
}

static void ssd_model_advance_write_pointer(unsigned int part,
					    SSD_MODEL_WRITE_POINTER *wp)
{
	unsigned int slot = ssd_model_line_slot(part, wp->line);

	wp->page++;
	if((wp->page % SSD_MODEL_PAGES_PER_ONESHOT) != 0)
		return;

	wp->page -= SSD_MODEL_PAGES_PER_ONESHOT;
	wp->ch++;
	if(wp->ch != SSD_MODEL_PART_NAND_CHANNELS)
		return;

	wp->ch = 0;
	wp->lun++;
	if(wp->lun != LUNS_PER_NAND_CH)
		return;

	wp->lun = 0;
	wp->page += SSD_MODEL_PAGES_PER_ONESHOT;
	if(wp->page != SSD_MODEL_PAGES_PER_BLOCK)
		return;

	g_lineState[slot] = g_lineInvalidPages[slot] ?
			     SSD_MODEL_LINE_VICTIM : SSD_MODEL_LINE_FULL;
	ssd_model_write_pointer_clear(wp);
}

static unsigned int ssd_model_write_pointer_ppa(unsigned int part,
					       const SSD_MODEL_WRITE_POINTER *wp)
{
	return (part * SSD_MODEL_PART_PHYSICAL_PAGES) +
	       (wp->line * SSD_MODEL_PAGES_PER_LINE) +
	       (wp->page * SSD_MODEL_PART_LANES) +
	       (wp->lun * SSD_MODEL_PART_NAND_CHANNELS) + wp->ch;
}

static unsigned int ssd_model_program_ready_ppa(unsigned int ppa)
{
	return (ssd_model_ppa_page(ppa) % SSD_MODEL_PAGES_PER_ONESHOT) ==
	       (SSD_MODEL_PAGES_PER_ONESHOT - 1U);
}

static void ssd_model_invalidate_lpn(unsigned int lpn)
{
	unsigned int *l2p = ssd_model_l2p();
	unsigned int *p2l = ssd_model_p2l();
	unsigned int oldPpa;
	unsigned int slot;

	if(lpn >= SSD_MODEL_LOGICAL_PAGES)
		return;

	oldPpa = l2p[lpn];
	if(oldPpa == SSD_MODEL_INVALID_PAGE || oldPpa >= SSD_MODEL_PHYSICAL_PAGES)
		return;

	slot = ssd_model_ppa_line_slot(oldPpa);
	if(g_lineValidPages[slot] != 0)
		g_lineValidPages[slot]--;
	g_lineInvalidPages[slot]++;
	if(g_lineState[slot] == SSD_MODEL_LINE_FULL)
		g_lineState[slot] = SSD_MODEL_LINE_VICTIM;

	p2l[oldPpa] = SSD_MODEL_INVALID_PAGE;
	l2p[lpn] = SSD_MODEL_INVALID_PAGE;
}

static unsigned int ssd_model_allocate_ppa(unsigned int part,
					  unsigned int lpn,
					  unsigned int gcIo)
{
	unsigned int *l2p = ssd_model_l2p();
	unsigned int *p2l = ssd_model_p2l();
	SSD_MODEL_WRITE_POINTER *wp = gcIo ? &g_gcWritePointer[part] :
						 &g_userWritePointer[part];
	unsigned int ppa;
	unsigned int slot;

	if(part >= SSD_MODEL_PARTITIONS || lpn >= SSD_MODEL_LOGICAL_PAGES)
		return SSD_MODEL_INVALID_PAGE;

	if(wp->line == SSD_MODEL_INVALID_PAGE &&
	   ssd_model_open_free_line(part, wp) == 0)
		return SSD_MODEL_INVALID_PAGE;

	ppa = ssd_model_write_pointer_ppa(part, wp);
	if(ppa >= SSD_MODEL_PHYSICAL_PAGES)
		return SSD_MODEL_INVALID_PAGE;

	p2l[ppa] = lpn;
	l2p[lpn] = ppa;
	slot = ssd_model_line_slot(part, wp->line);
	g_lineValidPages[slot]++;
	ssd_model_advance_write_pointer(part, wp);
	return ppa;
}

static unsigned int ssd_model_select_gc_victim(unsigned int part,
					       unsigned int force)
{
	unsigned int line;
	unsigned int victim = SSD_MODEL_INVALID_PAGE;
	unsigned int bestValid = 0xFFFFFFFFU;

	for(line = 0; line < SSD_MODEL_LINE_COUNT; line++)
	{
		unsigned int slot = ssd_model_line_slot(part, line);

		if(g_lineState[slot] != SSD_MODEL_LINE_VICTIM)
			continue;
		if(!force && g_lineValidPages[slot] > (SSD_MODEL_PAGES_PER_LINE / 8U))
			continue;
		if(g_lineValidPages[slot] < bestValid)
		{
			bestValid = g_lineValidPages[slot];
			victim = line;
		}
	}

	return victim;
}

static unsigned long long ssd_model_refill_write_credit(unsigned int part,
						       unsigned long long startNs);

static unsigned long long ssd_model_reclaim_one_line(unsigned int part,
						     unsigned long long startNs,
						     unsigned int force)
{
	unsigned int *l2p = ssd_model_l2p();
	unsigned int *p2l = ssd_model_p2l();
	unsigned int victim = ssd_model_select_gc_victim(part, force);
	unsigned int victimSlot;
	unsigned int idx;
	unsigned long long latestNs = startNs;

	if(victim == SSD_MODEL_INVALID_PAGE)
		return latestNs;

	victimSlot = ssd_model_line_slot(part, victim);
	g_creditsToRefill[part] = g_lineInvalidPages[victimSlot];

	for(idx = 0; idx < SSD_MODEL_PAGES_PER_LINE; idx++)
	{
		unsigned int oldPpa = (part * SSD_MODEL_PART_PHYSICAL_PAGES) +
				      (victim * SSD_MODEL_PAGES_PER_LINE) + idx;
		unsigned int lpn = p2l[oldPpa];
		unsigned int newPpa;
		unsigned long long readDoneNs;

		if(lpn == SSD_MODEL_INVALID_PAGE || lpn >= SSD_MODEL_LOGICAL_PAGES ||
		   l2p[lpn] != oldPpa)
		{
			p2l[oldPpa] = SSD_MODEL_INVALID_PAGE;
			continue;
		}

		readDoneNs = ssd_model_schedule_nand_read_ppa(oldPpa, startNs,
							   BYTES_PER_NVME_BLOCK);
		latestNs = ssd_model_max_ull(latestNs, readDoneNs);
		newPpa = ssd_model_allocate_ppa(part, lpn, 1);
		if(newPpa == SSD_MODEL_INVALID_PAGE)
		{
			g_ssdModelDebug[15]++;
			break;
		}

		p2l[oldPpa] = SSD_MODEL_INVALID_PAGE;
		if(ssd_model_program_ready_ppa(newPpa))
		{
			unsigned long long writeDoneNs;

			writeDoneNs = ssd_model_schedule_nand_write_ppa(newPpa,
								       readDoneNs,
								       ONESHOT_PAGE_SIZE);
			latestNs = ssd_model_max_ull(latestNs, writeDoneNs);
		}
	}

	g_lineValidPages[victimSlot] = 0;
	g_lineInvalidPages[victimSlot] = 0;
	g_lineState[victimSlot] = SSD_MODEL_LINE_FREE;
	g_freeLineCount[part]++;
	g_ssdModelDebug[15]++;
	return latestNs + NAND_ERASE_LATENCY;
}

static unsigned long long ssd_model_foreground_gc(unsigned int part,
						      unsigned long long startNs)
{
	if(g_freeLineCount[part] <= SSD_MODEL_GC_THRES_LINES_HIGH)
		return ssd_model_reclaim_one_line(part, startNs, 1);

	return startNs;
}

static unsigned long long ssd_model_refill_write_credit(unsigned int part,
						       unsigned long long startNs)
{
	unsigned long long latestNs = startNs;

	if(g_writeCredits[part] != 0)
		return latestNs;

	latestNs = ssd_model_foreground_gc(part, startNs);
	g_writeCredits[part] += g_creditsToRefill[part];
	return latestNs;
}

static void ssd_model_ftl_reset(void)
{
	unsigned int *l2p = ssd_model_l2p();
	unsigned int *p2l = ssd_model_p2l();
	unsigned int idx;
	unsigned int part;

	for(idx = 0; idx < SSD_MODEL_LOGICAL_PAGES; idx++)
		l2p[idx] = SSD_MODEL_INVALID_PAGE;

	for(idx = 0; idx < SSD_MODEL_PHYSICAL_PAGES; idx++)
		p2l[idx] = SSD_MODEL_INVALID_PAGE;

	for(idx = 0; idx < SSD_MODEL_TOTAL_LINE_COUNT; idx++)
	{
		g_lineValidPages[idx] = 0;
		g_lineInvalidPages[idx] = 0;
		g_lineState[idx] = SSD_MODEL_LINE_FREE;
	}

	for(part = 0; part < SSD_MODEL_PARTITIONS; part++)
	{
		g_freeLineCount[part] = SSD_MODEL_LINE_COUNT;
		ssd_model_write_pointer_clear(&g_userWritePointer[part]);
		ssd_model_write_pointer_clear(&g_gcWritePointer[part]);
		g_writeCredits[part] = SSD_MODEL_PAGES_PER_LINE;
		g_creditsToRefill[part] = SSD_MODEL_PAGES_PER_LINE;
	}
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
	unsigned long long writeBufferDoneNs = 0;
	unsigned long long writeNandLatestNs = 0;
	unsigned long long writeBytes = 0;

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

		ssd_model_release_write_buffer(latestNs);
		io->dueNs = latestNs;
		io->modelPending = 1;
		return;
	}

	if(io->op == SSD_MODEL_OP_WRITE)
	{
		writeBytes = (unsigned long long)io->requestedNvmeBlock *
			     BYTES_PER_NVME_BLOCK;
		writeBufferDoneNs = ssd_model_advance_write_buffer(nowNs, writeBytes);
		writeBufferDoneNs = ssd_model_max_ull(writeBufferDoneNs,
						ssd_model_pipe_xfer(&g_writeFrontendAvailNs,
								    nowNs,
								    writeBytes,
								    ssd_model_write_pipe_mib_per_sec(writeBytes)));
		writeNandLatestNs = writeBufferDoneNs;
		if(WRITE_EARLY_COMPLETION)
			latestNs = ssd_model_max_ull(latestNs, writeBufferDoneNs);
	}

	if(io->op == SSD_MODEL_OP_READ)
	{
		unsigned int *l2p = ssd_model_l2p();
		unsigned int startLpn = ssd_model_lpn_from_addr(io->devAddr);
		unsigned int endLpn = startLpn + io->requestedNvmeBlock - 1U;
		unsigned long long readStartNs;
		unsigned int partOffset;

		readStartNs = nowNs + ((io->requestedNvmeBlock <= SSD_MODEL_PARTITIONS) ?
					     FW_4KB_READ_LATENCY : FW_READ_LATENCY);
		latestNs = readStartNs;

		for(partOffset = 0;
		    partOffset < SSD_MODEL_PARTITIONS && startLpn + partOffset <= endLpn;
		    partOffset++)
		{
			unsigned int lpn = startLpn + partOffset;

			while(lpn <= endLpn)
			{
				unsigned long long xferBytes;
				unsigned int ppa;
				unsigned int nextLpn;

				if(lpn >= SSD_MODEL_LOGICAL_PAGES)
					break;

				ppa = l2p[lpn];
				if(ppa == SSD_MODEL_INVALID_PAGE || ppa >= SSD_MODEL_PHYSICAL_PAGES)
				{
					latestNs = ssd_model_max_ull(latestNs, readStartNs);
					lpn += SSD_MODEL_PARTITIONS;
					continue;
				}

				xferBytes = BYTES_PER_NVME_BLOCK;
				nextLpn = lpn + SSD_MODEL_PARTITIONS;
				while(nextLpn <= endLpn && nextLpn < SSD_MODEL_LOGICAL_PAGES)
				{
					unsigned int nextPpa = l2p[nextLpn];

					if(nextPpa == SSD_MODEL_INVALID_PAGE ||
					   nextPpa >= SSD_MODEL_PHYSICAL_PAGES ||
					   ssd_model_same_flash_page(ppa, nextPpa) == 0)
						break;

					xferBytes += BYTES_PER_NVME_BLOCK;
					nextLpn += SSD_MODEL_PARTITIONS;
				}

				latestNs = ssd_model_max_ull(latestNs,
						     ssd_model_schedule_nand_read_ppa(ppa,
										 readStartNs,
										 xferBytes));
				lpn = nextLpn;
			}
		}

		{
			unsigned long long readBytes;
			unsigned long long readPipeDoneNs;

			readBytes = (unsigned long long)io->requestedNvmeBlock *
				    BYTES_PER_NVME_BLOCK;
			readPipeDoneNs = ssd_model_pipe_xfer(&g_readPipeAvailNs,
							    nowNs,
							    readBytes,
							    ssd_model_read_pipe_mib_per_sec(readBytes));
			latestNs = ssd_model_max_ull(latestNs, readPipeDoneNs);
		}

		io->dueNs = latestNs;
		io->modelPending = 1;
		return;
	}

	for(pageIdx = 0; pageIdx < io->requestedNvmeBlock; pageIdx++)
	{
		unsigned long long pageAddr;
		unsigned int lpn;
		unsigned int ppa;

		pageAddr = io->devAddr + ((unsigned long long)pageIdx * BYTES_PER_NVME_BLOCK);
		lpn = ssd_model_lpn_from_addr(pageAddr);
		if(lpn >= SSD_MODEL_LOGICAL_PAGES)
			continue;

		{
			unsigned int part = ssd_model_part_from_lpn(lpn);

			ssd_model_invalidate_lpn(lpn);
			ppa = ssd_model_allocate_ppa(part, lpn, 0);
			if(ppa == SSD_MODEL_INVALID_PAGE)
			{
				writeNandLatestNs = ssd_model_max_ull(writeNandLatestNs,
								 ssd_model_reclaim_one_line(part,
											    writeBufferDoneNs,
											    1));
				ppa = ssd_model_allocate_ppa(part, lpn, 0);
			}
		if(ppa == SSD_MODEL_INVALID_PAGE)
		{
			g_ssdModelDebug[10]++;
			continue;
		}

		if(g_writeCredits[part] != 0)
			g_writeCredits[part]--;

		if(ssd_model_program_ready_ppa(ppa))
		{
			unsigned long long programDoneNs;

			programDoneNs = ssd_model_schedule_nand_write_ppa(ppa,
									 writeBufferDoneNs,
									 ONESHOT_PAGE_SIZE);
			writeNandLatestNs = ssd_model_max_ull(writeNandLatestNs, programDoneNs);
			ssd_model_queue_write_buffer_release(programDoneNs, ONESHOT_PAGE_SIZE);
		}
		}
	}

	if(io->op == SSD_MODEL_OP_WRITE)
	{
		unsigned int part;

		for(part = 0; part < SSD_MODEL_PARTITIONS; part++)
			writeNandLatestNs = ssd_model_max_ull(writeNandLatestNs,
						 ssd_model_refill_write_credit(part,
									       writeBufferDoneNs));

		if(WRITE_EARLY_COMPLETION == 0)
			latestNs = ssd_model_max_ull(latestNs, writeNandLatestNs);
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
	{
		g_chAvailNs[idx] = 0;
		ssd_model_ch_init(idx);
	}

	for(idx = 0; idx < SSD_MODEL_BUFFER_RELEASE_SLOTS; idx++)
	{
		g_writeBufferReleaseNs[idx] = 0;
		g_writeBufferReleaseBytes[idx] = 0;
	}
	g_writeBufferReleaseHead = 0;
	g_writeBufferReleaseTail = 0;
	g_writeBufferUsedBytes = 0;
	g_readPipeAvailNs = 0;
	g_writeFrontendAvailNs = 0;
	ssd_model_ftl_reset();

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
	{
		g_chAvailNs[idx] = 0;
		ssd_model_ch_init(idx);
	}

	for(idx = 0; idx < SSD_MODEL_BUFFER_RELEASE_SLOTS; idx++)
	{
		g_writeBufferReleaseNs[idx] = 0;
		g_writeBufferReleaseBytes[idx] = 0;
	}
	g_writeBufferReleaseHead = 0;
	g_writeBufferReleaseTail = 0;
	g_writeBufferUsedBytes = 0;
	g_readPipeAvailNs = 0;
	g_writeFrontendAvailNs = 0;
	ssd_model_ftl_reset();

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
