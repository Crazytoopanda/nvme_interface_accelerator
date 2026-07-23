# nvme_on_host

PF0 NVMe host driver wrapper. It builds from `../xilinx_nvme/pci.c` by default, but patches
the temporary build copy so the module:

- binds only PCI function 0 by default;
- requests/releases only BAR0;
- uses driver name `nvme_on_host`;
- keeps BAR0 register definitions in `nvme_bar0_regs.h`;
- requests up to eight IO queues with 256 entries per queue.

PF0 currently exposes eight usable interrupt vectors. Linux therefore normally
creates seven IO queues plus the admin queue and reports `7/0/0`.

Build:

```sh
make -C dr/nvme_on_host
```

Build output: `dr/nvme_on_host/build/nvme_on_host.ko`.

Verbose build-time logs:

```sh
make -C dr/nvme_on_host NVME_ON_HOST_DEBUG=1
```
