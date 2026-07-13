#ifndef __SSD_MODEL_H_
#define __SSD_MODEL_H_

#include "nvme.h"

void ssd_model_init(void);
void ssd_model_reset(void);
void ssd_model_poll(void);
void ssd_model_set_worker_active(unsigned int active);
unsigned int ssd_model_core0_should_poll(void);

unsigned int ssd_model_submit_read(unsigned int cmdSlotTag,
				   unsigned long long devAddr,
				   unsigned int requestedNvmeBlock);
unsigned int ssd_model_submit_write(unsigned int cmdSlotTag,
				    unsigned long long devAddr,
				    unsigned int requestedNvmeBlock);
unsigned int ssd_model_submit_flush(unsigned int cmdSlotTag);

#endif
