#ifndef AUTO_FW_H
#define AUTO_FW_H

void auto_fw_init(void);
int auto_fw_hw_present(void);
void auto_fw_enable_io(void);
void auto_fw_shutdown(void);
unsigned int auto_fw_status(void);
unsigned int auto_fw_error(void);
void auto_fw_clear_errors(unsigned int mask);
void auto_fw_retry_cq_irq(unsigned int cqid);
void auto_fw_set_cq_irq_retry_cycles(unsigned int cycles);
int auto_fw_service(void);
void auto_fw_run(void);

#endif
