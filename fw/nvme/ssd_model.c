#include "xil_printf.h"

#include "host_lld.h"
#include "nvme.h"
#include "nvme_smp.h"
#include "ssd_config.h"
#include "ssd_model.h"

#define SSD_MODEL_MAX_PENDING_IO		256
#define SSD_MODEL_NUM_LANES			(NAND_CHANNELS * LUNS_PER_NAND_CH)

#define SSD_MODEL_FLUSH_BASE_NS			100000ULL

#define SSD_MODEL_OP_READ			1
#define SSD_MODEL_OP_WRITE			2
#define SSD_MODEL_OP_FLUSH			3

typedef struct _SSD_MODEL_PENDING_IO
{
	unsigned char valid;
	unsigned char op;
	unsigned short cmdSlotTag;
	unsigned int requestedNvmeBlock;
	unsigned long long devAddr;
	unsigned long long dueNs;
	unsigned int dmaTailIndex;
	unsigned int dmaTailAssistIndex;
} SSD_MODEL_PENDING_IO;

static volatile unsigned int g_ssdModelLock;
static volatile unsigned int g_ssdModelWorkerActive;
static SSD_MODEL_PENDING_IO g_pendingIo[SSD_MODEL_MAX_PENDING_IO];
static unsigned long long g_nandLaneAvailNs[SSD_MODEL_NUM_LANES];
static unsigned long long g_chAvailNs[NAND_CHANNELS];

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

void ssd_model_set_worker_active(unsigned int active)
{
	g_ssdModelWorkerActive = active ? 1 : 0;
	__sync_synchronize();
}

unsigned int ssd_model_core0_should_poll(void)
{
#if SSD_MODEL_POLL_CORE == 0
	return 1;
#else
	return g_ssdModelWorkerActive == 0;
#endif
}

static inline unsigned long long ssd_model_now_ns(void)
{
	unsigned long long cnt;
	unsigned long long freq;

	__asm__ volatile("mrs %0, cntvct_el0" : "=r"(cnt));
	__asm__ volatile("mrs %0, cntfrq_el0" : "=r"(freq));

	if(freq == 0)
		return 0;

	return (cnt * 1000000000ULL) / freq;
}

static inline unsigned long long ssd_model_max_ull(unsigned long long a,
						   unsigned long long b)
{
	return (a > b) ? a : b;
}

static unsigned int ssd_model_alloc_slot(void)
{
	unsigned int idx;

	for(idx = 0; idx < SSD_MODEL_MAX_PENDING_IO; idx++)
	{
		if(g_pendingIo[idx].valid == 0)
			return idx;
	}

	return SSD_MODEL_MAX_PENDING_IO;
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

static unsigned int ssd_model_submit_write_rx_dma(SSD_MODEL_PENDING_IO *io)
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

	return 1;
}

static unsigned int ssd_model_submit(unsigned char op,
				     unsigned int cmdSlotTag,
				     unsigned long long devAddr,
				     unsigned int requestedNvmeBlock)
{
	unsigned int idx;
	unsigned int pageIdx;
	unsigned long long nowNs;
	unsigned long long latestNs;

	ssd_model_lock();

	idx = ssd_model_alloc_slot();
	if(idx == SSD_MODEL_MAX_PENDING_IO)
	{
		ssd_model_unlock();
		return 0;
	}

	nowNs = ssd_model_now_ns();
	latestNs = nowNs;

	g_pendingIo[idx].valid = 1;
	g_pendingIo[idx].op = op;
	g_pendingIo[idx].cmdSlotTag = (unsigned short)cmdSlotTag;
	g_pendingIo[idx].requestedNvmeBlock = requestedNvmeBlock;
	g_pendingIo[idx].devAddr = devAddr;
	g_pendingIo[idx].dmaTailIndex = 0;
	g_pendingIo[idx].dmaTailAssistIndex = 0;

	if(op == SSD_MODEL_OP_WRITE)
		ssd_model_submit_write_rx_dma(&g_pendingIo[idx]);

	for(pageIdx = 0; pageIdx < requestedNvmeBlock; pageIdx++)
	{
		unsigned int lane = ssd_model_lane(devAddr +
						   ((unsigned long long)pageIdx * BYTES_PER_NVME_BLOCK));
		unsigned int ch = lane % NAND_CHANNELS;
		unsigned long long nandStartNs;
		unsigned long long nandDoneNs;
		unsigned long long chStartNs;
		unsigned long long chDoneNs;

		if(op == SSD_MODEL_OP_READ)
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

	g_pendingIo[idx].dueNs = latestNs;

	ssd_model_unlock();
	return 1;
}

static void ssd_model_submit_auto_dma(const SSD_MODEL_PENDING_IO *io)
{
	unsigned int dmaIndex;
	unsigned long long devAddr = io->devAddr;

	for(dmaIndex = 0; dmaIndex < io->requestedNvmeBlock; dmaIndex++)
	{
		if(io->op == SSD_MODEL_OP_READ)
			set_auto_tx_dma(io->cmdSlotTag, dmaIndex, devAddr,
					NVME_COMMAND_AUTO_COMPLETION_ON);
		else
			set_auto_rx_dma(io->cmdSlotTag, dmaIndex, devAddr,
					NVME_COMMAND_AUTO_COMPLETION_ON);

		devAddr += BYTES_PER_NVME_BLOCK;
	}

}

void ssd_model_reset(void)
{
	unsigned int idx;

	ssd_model_lock();

	for(idx = 0; idx < SSD_MODEL_MAX_PENDING_IO; idx++)
		g_pendingIo[idx].valid = 0;

	for(idx = 0; idx < SSD_MODEL_NUM_LANES; idx++)
		g_nandLaneAvailNs[idx] = 0;

	for(idx = 0; idx < NAND_CHANNELS; idx++)
		g_chAvailNs[idx] = 0;

	ssd_model_unlock();
}

void ssd_model_init(void)
{
	ssd_model_reset();
	xil_printf("[SSD model] Samsung 970 PRO profile: %u ch, %u luns/ch, nand ch %u MiB/s\r\n",
		   (unsigned int)NAND_CHANNELS,
		   (unsigned int)LUNS_PER_NAND_CH,
		   (unsigned int)NAND_CHANNEL_BANDWIDTH);
}

void ssd_model_poll(void)
{
	unsigned int idx;
	unsigned long long nowNs;

	if(ssd_model_try_lock() == 0)
		return;

	nowNs = ssd_model_now_ns();

	for(idx = 0; idx < SSD_MODEL_MAX_PENDING_IO; idx++)
	{
		if(g_pendingIo[idx].valid == 0)
			continue;

		if(g_pendingIo[idx].dueNs > nowNs)
			continue;

		if(g_pendingIo[idx].op == SSD_MODEL_OP_FLUSH)
		{
			set_auto_nvme_cpl(g_pendingIo[idx].cmdSlotTag, 0, 0);
			g_pendingIo[idx].valid = 0;
		}
		else if(g_pendingIo[idx].op == SSD_MODEL_OP_READ)
		{
			ssd_model_submit_auto_dma(&g_pendingIo[idx]);
			g_pendingIo[idx].valid = 0;
		}
		else
		{
			if(check_auto_rx_dma_partial_done(g_pendingIo[idx].dmaTailIndex,
					g_pendingIo[idx].dmaTailAssistIndex) == 0)
				continue;

			set_auto_nvme_cpl(g_pendingIo[idx].cmdSlotTag, 0, 0);
			g_pendingIo[idx].valid = 0;
		}
	}
	ssd_model_unlock();
}

unsigned int ssd_model_submit_read(unsigned int cmdSlotTag,
				   unsigned long long devAddr,
				   unsigned int requestedNvmeBlock)
{
	return ssd_model_submit(SSD_MODEL_OP_READ, cmdSlotTag, devAddr,
				requestedNvmeBlock);
}

unsigned int ssd_model_submit_write(unsigned int cmdSlotTag,
				    unsigned long long devAddr,
				    unsigned int requestedNvmeBlock)
{
	return ssd_model_submit(SSD_MODEL_OP_WRITE, cmdSlotTag, devAddr,
				requestedNvmeBlock);
}

unsigned int ssd_model_submit_flush(unsigned int cmdSlotTag)
{
	unsigned int idx;
	unsigned int lane;
	unsigned long long dueNs;
	unsigned long long nowNs;

	ssd_model_lock();

	idx = ssd_model_alloc_slot();
	if(idx == SSD_MODEL_MAX_PENDING_IO)
	{
		ssd_model_unlock();
		return 0;
	}

	nowNs = ssd_model_now_ns();
	dueNs = nowNs + SSD_MODEL_FLUSH_BASE_NS;

	for(lane = 0; lane < SSD_MODEL_NUM_LANES; lane++)
	{
		dueNs = ssd_model_max_ull(dueNs, g_nandLaneAvailNs[lane]);
	}

	for(lane = 0; lane < NAND_CHANNELS; lane++)
		dueNs = ssd_model_max_ull(dueNs, g_chAvailNs[lane]);


	g_pendingIo[idx].valid = 1;
	g_pendingIo[idx].op = SSD_MODEL_OP_FLUSH;
	g_pendingIo[idx].cmdSlotTag = (unsigned short)cmdSlotTag;
	g_pendingIo[idx].requestedNvmeBlock = 0;
	g_pendingIo[idx].devAddr = 0;
	g_pendingIo[idx].dueNs = dueNs;

	ssd_model_unlock();
	return 1;
}
