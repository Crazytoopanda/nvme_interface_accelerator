KDIR ?= /lib/modules/$(shell uname -r)/build
BUILD_DIR ?= $(CURDIR)/build
XILINX_NVME_DIR ?= ../xilinx_nvme
NVME_ON_HOST_DEBUG ?= 0

all:
	mkdir -p $(BUILD_DIR)
	cp $(XILINX_NVME_DIR)/pci.c $(BUILD_DIR)/pci.c
	cp $(XILINX_NVME_DIR)/nvme.h $(BUILD_DIR)/nvme.h
	cp $(XILINX_NVME_DIR)/trace.h $(BUILD_DIR)/trace.h
	cp nvme_bar0_regs.h $(BUILD_DIR)/nvme_bar0_regs.h
	cp Kbuild.build $(BUILD_DIR)/Kbuild
	perl -0pi -e 's/#include "nvme\.h"/#include "nvme.h"\n#include "nvme_bar0_regs.h"/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/PCI_DEVICE\(0x10ee, 0x903f\)/PCI_DEVICE(NVME_ON_HOST_PCI_VENDOR_ID, NVME_ON_HOST_PCI_DEVICE_ID)/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/NVME_QUIRK_BOGUS_NID \| NVME_QUIRK_IDENTIFY_CNS/NVME_QUIRK_BOGUS_NID | NVME_QUIRK_IDENTIFY_CNS | NVME_QUIRK_SKIP_CID_GEN/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/static unsigned int io_queue_depth = 1024;/static unsigned int io_queue_depth = NVME_ON_HOST_IO_QUEUE_DEPTH;/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/return num_possible_cpus\(\) \+ dev->nr_write_queues \+ dev->nr_poll_queues;/return NVME_ON_HOST_MAX_IO_QUEUES;/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/pci_request_mem_regions\(pdev, "nvme"\)/pci_request_region(pdev, NVME_ON_HOST_BAR0_NR, NVME_ON_HOST_NAME)/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/pci_release_mem_regions\(pdev\)/pci_release_region(pdev, NVME_ON_HOST_BAR0_NR)/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/pci_release_mem_regions\(to_pci_dev\(dev->dev\)\)/pci_release_region(to_pci_dev(dev->dev), NVME_ON_HOST_BAR0_NR)/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/dev->ctrl\.max_hw_sectors = min_t\(u32,\n\t\tNVME_MAX_KB_SZ << 1, dma_opt_mapping_size\(&pdev->dev\) >> 9\);\n\tdev->ctrl\.max_segments = NVME_MAX_SEGS;/dev->ctrl.max_hw_sectors = NVME_ON_HOST_MAX_HW_SECTORS;\n\tdev->ctrl.max_segments = NVME_ON_HOST_MAX_SEGMENTS;/s' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/static int nvme_probe\(struct pci_dev \*pdev, const struct pci_device_id \*id\)\n\{\n\tstruct nvme_dev \*dev;\n\tint result = -ENOMEM;/static int nvme_probe(struct pci_dev *pdev, const struct pci_device_id *id)\n{\n\tstruct nvme_dev *dev;\n\tint result = -ENOMEM;\n\n\tif (PCI_FUNC(pdev->devfn) != NVME_ON_HOST_PCI_FUNCTION)\n\t\treturn -ENODEV;\n\tNVME_ON_HOST_DBG(\&pdev->dev, "probe PF%u BAR0 only\\n", PCI_FUNC(pdev->devfn));/' $(BUILD_DIR)/pci.c
	perl -0pi -e 's/\.name\s*=\s*"xilinx_nvme"/.name\t\t= NVME_ON_HOST_NAME/' $(BUILD_DIR)/pci.c
	$(MAKE) -C $(KDIR) M=$(BUILD_DIR) NVME_ON_HOST_DEBUG=$(NVME_ON_HOST_DEBUG) modules

clean:
	$(MAKE) -C $(KDIR) M=$(BUILD_DIR) clean
