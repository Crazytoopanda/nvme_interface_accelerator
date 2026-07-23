MB_CC ?= microblaze-xilinx-elf-gcc
CFLAGS ?= -Wall -Wextra -O2 -I. -Invme
BUILD_DIR ?= build

SRCS := main.c nvme/auto_fw.c
OBJS := $(patsubst %.c,$(BUILD_DIR)/%.o,$(SRCS))

all: $(BUILD_DIR)/auto_fw.elf

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	mkdir -p $(dir $@)
	$(MB_CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/nvme/auto_fw.o: nvme/auto_fw.h nvme/auto_hw_regs.h \
	nvme/ssd_config.h kernel_config.h memory_map.h

$(BUILD_DIR)/auto_fw.elf: $(OBJS)
	$(MB_CC) $(CFLAGS) $(OBJS) -o $@

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean
