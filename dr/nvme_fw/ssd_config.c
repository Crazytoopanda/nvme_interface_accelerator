// SPDX-License-Identifier: GPL-2.0
#include <linux/compiler.h>
#include <linux/build_bug.h>
#include <linux/device.h>
#include <linux/io.h>
#include <linux/module.h>

#include "nvme_fw_regs.h"
#include "ssd_config.h"

static_assert(NVME_FW_SSD_PCIE_USER_CLOCK_HZ > 0);
static_assert(NVME_FW_SSD_CHANNEL_BANDWIDTH_MBPS > 0);
static_assert(NVME_FW_SSD_NAND_CHANNELS >= 1 &&
	      NVME_FW_SSD_NAND_CHANNELS <= 16 &&
	      (NVME_FW_SSD_NAND_CHANNELS &
	       (NVME_FW_SSD_NAND_CHANNELS - 1)) == 0);

static bool fw_ssd_model_enable = true;
module_param(fw_ssd_model_enable, bool, 0644);
MODULE_PARM_DESC(fw_ssd_model_enable,
		 "enable hardware SSD latency gating; applied on controller rearm");

static uint fw_ssd_read_lsb_cycles = NVME_FW_SSD_READ_LSB_CYCLES_DEFAULT;
module_param(fw_ssd_read_lsb_cycles, uint, 0644);
MODULE_PARM_DESC(fw_ssd_read_lsb_cycles,
		 "SSD model 4 KiB LSB read latency in PCIe-user-clock cycles");

static uint fw_ssd_read_msb_cycles = NVME_FW_SSD_READ_MSB_CYCLES_DEFAULT;
module_param(fw_ssd_read_msb_cycles, uint, 0644);
MODULE_PARM_DESC(fw_ssd_read_msb_cycles,
		 "SSD model 4 KiB MSB read latency in PCIe-user-clock cycles");

static uint fw_ssd_program_cycles = NVME_FW_SSD_PROGRAM_CYCLES_DEFAULT;
module_param(fw_ssd_program_cycles, uint, 0644);
MODULE_PARM_DESC(fw_ssd_program_cycles,
		 "SSD model NAND program latency in PCIe-user-clock cycles");

static uint fw_ssd_fw_read_cycles = NVME_FW_SSD_FW_READ_CYCLES_DEFAULT;
module_param(fw_ssd_fw_read_cycles, uint, 0644);
MODULE_PARM_DESC(fw_ssd_fw_read_cycles,
		 "SSD model firmware read overhead in PCIe-user-clock cycles");

static uint fw_ssd_fw_write_cycles = NVME_FW_SSD_FW_WRITE_CYCLES_DEFAULT;
module_param(fw_ssd_fw_write_cycles, uint, 0644);
MODULE_PARM_DESC(fw_ssd_fw_write_cycles,
		 "SSD model firmware write overhead in PCIe-user-clock cycles");

static uint fw_ssd_ch_xfer_4k_cycles =
	NVME_FW_SSD_CH_XFER_4K_CYCLES_DEFAULT;
module_param(fw_ssd_ch_xfer_4k_cycles, uint, 0644);
MODULE_PARM_DESC(fw_ssd_ch_xfer_4k_cycles,
		 "SSD model NAND-channel transfer time per 4 KiB in PCIe-user-clock cycles");

static uint fw_ssd_channel_count = NVME_FW_SSD_NAND_CHANNELS;
module_param(fw_ssd_channel_count, uint, 0644);
MODULE_PARM_DESC(fw_ssd_channel_count,
		 "SSD model NAND channels; supported values are 1, 2, 4, 8, and 16");

static bool nvme_fw_ssd_valid_channel_count(u32 channels)
{
	return channels >= 1 && channels <= 16 &&
	       (channels & (channels - 1)) == 0;
}

static void nvme_fw_ssd_writel(void __iomem *bar2, u32 reg, u32 value)
{
	iowrite32(value, bar2 + NVME_FW_CTRL_BASE + reg);
}

void nvme_fw_ssd_reset(void __iomem *bar2)
{
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_MODEL_CTRL,
			   NVME_FW_SSD_MODEL_RESET);
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_MODEL_CTRL, 0);
	/* Flush posted writes before automation state is reset or reconfigured. */
	ioread32(bar2 + NVME_FW_CTRL_BASE + NVME_FW_REG_SSD_MODEL_CTRL);
}

void nvme_fw_ssd_apply(void __iomem *bar2, struct device *dev)
{
	u32 channels = READ_ONCE(fw_ssd_channel_count);

	if (!nvme_fw_ssd_valid_channel_count(channels)) {
		dev_warn(dev, "invalid SSD channel count %u; using %u\n",
			 channels, NVME_FW_SSD_NAND_CHANNELS);
		channels = NVME_FW_SSD_NAND_CHANNELS;
	}

	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_READ_LSB_CYCLES,
			   READ_ONCE(fw_ssd_read_lsb_cycles));
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_READ_MSB_CYCLES,
			   READ_ONCE(fw_ssd_read_msb_cycles));
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_PROGRAM_CYCLES,
			   READ_ONCE(fw_ssd_program_cycles));
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_FW_READ_CYCLES,
			   READ_ONCE(fw_ssd_fw_read_cycles));
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_FW_WRITE_CYCLES,
			   READ_ONCE(fw_ssd_fw_write_cycles));
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_CH_XFER_4K_CYCLES,
			   READ_ONCE(fw_ssd_ch_xfer_4k_cycles));
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_CHANNEL_COUNT, channels);
	nvme_fw_ssd_writel(bar2, NVME_FW_REG_SSD_MODEL_CTRL,
			   READ_ONCE(fw_ssd_model_enable) ?
			   NVME_FW_SSD_MODEL_ENABLE : 0);
	ioread32(bar2 + NVME_FW_CTRL_BASE + NVME_FW_REG_SSD_MODEL_CTRL);
}

void nvme_fw_ssd_log(struct device *dev)
{
	dev_info(dev,
		 "firmware worker: SSD model enable=%d channels=%u read_lsb=%u read_msb=%u program=%u fw_read=%u fw_write=%u ch_xfer_4k=%u cycles\n",
		 READ_ONCE(fw_ssd_model_enable),
		 READ_ONCE(fw_ssd_channel_count),
		 READ_ONCE(fw_ssd_read_lsb_cycles),
		 READ_ONCE(fw_ssd_read_msb_cycles),
		 READ_ONCE(fw_ssd_program_cycles),
		 READ_ONCE(fw_ssd_fw_read_cycles),
		 READ_ONCE(fw_ssd_fw_write_cycles),
		 READ_ONCE(fw_ssd_ch_xfer_4k_cycles));
}
