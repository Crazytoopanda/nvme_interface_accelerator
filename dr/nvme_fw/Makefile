KDIR ?= /lib/modules/$(shell uname -r)/build
BUILD_DIR ?= $(CURDIR)/build
NVME_FW_DEBUG ?= 0
HOSTCC ?= cc
HOSTCFLAGS ?= -Wall -Wextra -O2

BUILD_INPUTS := nvme_fw_regs.h ssd_config.c ssd_config.h

all: modules tools

modules:
	mkdir -p $(BUILD_DIR)
	cp $(BUILD_INPUTS) $(BUILD_DIR)/
	cp nvme_fw.c $(BUILD_DIR)/nvme_fw_core.c
	cp Kbuild.build $(BUILD_DIR)/Kbuild
	$(MAKE) -C $(KDIR) M=$(BUILD_DIR) NVME_FW_DEBUG=$(NVME_FW_DEBUG) modules

tools:
	mkdir -p $(BUILD_DIR)
	$(HOSTCC) $(HOSTCFLAGS) -I. -o $(BUILD_DIR)/nvme_fw_ctl nvme_fw_ctl.c
	$(HOSTCC) $(HOSTCFLAGS) -I. -o $(BUILD_DIR)/nvme_fw_daemon nvme_fw_daemon.c

clean:
	$(MAKE) -C $(KDIR) M=$(BUILD_DIR) clean
	rm -f $(BUILD_DIR)/nvme_fw_ctl $(BUILD_DIR)/nvme_fw_daemon

.PHONY: all modules tools clean
