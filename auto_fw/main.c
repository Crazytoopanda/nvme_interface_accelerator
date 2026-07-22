#include "nvme/auto_fw.h"
#include "nvme/auto_hw_regs.h"

#ifdef __MICROBLAZE__
#include "xil_cache.h"
#include "xil_printf.h"
#else
#define xil_printf(...) ((void)0)
#endif

#ifndef AUTO_FW_DEBUG
#define AUTO_FW_DEBUG 0U
#endif

#define AUTO_FW_DEBUG_PRINT(...) do { \
	if(AUTO_FW_DEBUG != 0U) \
		xil_printf(__VA_ARGS__); \
} while(0)

static void platform_init(void)
{
#ifdef __MICROBLAZE__
	Xil_ICacheDisable();
	Xil_DCacheDisable();
	Xil_ICacheEnable();
	Xil_DCacheEnable();
#endif
}

int main(void)
{
	unsigned int magic;

	platform_init();
	AUTO_FW_DEBUG_PRINT("auto_fw: start\r\n");

	magic = auto_reg_read(AUTO_REG_MAGIC);
	if(magic != AUTO_MAGIC_VALUE)
		xil_printf("auto_fw: warning automation magic 0x%08x\r\n", magic);

	auto_fw_init();

#ifdef AUTO_FW_STANDALONE_SMOKE
	/* For BAR/register smoke tests only.  Production firmware must call this
	 * after NVMe admin handshake and IO SQ/CQ setup are complete.
	 */
	auto_fw_enable_io();
#endif

	while(1)
		auto_fw_service();

	return 0;
}
