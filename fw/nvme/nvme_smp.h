//////////////////////////////////////////////////////////////////////////////////
// nvme_smp.h
// Lightweight SMP polling scheduler for NVMe IO commands.
//////////////////////////////////////////////////////////////////////////////////

#ifndef __NVME_SMP_H_
#define __NVME_SMP_H_

#include "nvme.h"

#define NVME_SMP_NUM_CORES			1
#define NVME_SMP_CMD_QUEUE_DEPTH	32

unsigned int nvme_smp_get_core_id(void);
void nvme_smp_init(void);
void nvme_smp_enable_io(void);
void nvme_smp_disable_io(void);
void nvme_smp_reset_queues(void);
void nvme_smp_dispatch_io_cmd(NVME_COMMAND *nvmeCmd);
unsigned int nvme_smp_poll_core(unsigned int coreId);
void nvme_smp_worker_loop(unsigned int coreId) __attribute__((noreturn));
void nvme_smp_start_worker(unsigned int coreId) __attribute__((noreturn));
void nvme_smp_mask_worker_exceptions(void);
void nvme_uart_lock(void);
void nvme_uart_unlock(void);
void nvme_io_submit_lock(void);
void nvme_io_submit_unlock(void);
void nvme_smp_worker_entry(unsigned int coreId) __attribute__((noreturn));
extern unsigned long g_nvmeSmpWorkerStack[NVME_SMP_NUM_CORES][2048];

#endif	//__NVME_SMP_H_
