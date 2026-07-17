KDIR ?= /lib/modules/$(shell uname -r)/build
BUILD_DIR ?= $(CURDIR)/build

BUILD_INPUTS := pci.c nvme.h trace.h

all:
	mkdir -p $(BUILD_DIR)
	cp $(BUILD_INPUTS) $(BUILD_DIR)/
	cp Kbuild.build $(BUILD_DIR)/Kbuild
	$(MAKE) -C $(KDIR) M=$(BUILD_DIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(BUILD_DIR) clean
