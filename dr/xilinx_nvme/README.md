# Xilinx NVMe PCI Driver Clone

This is a local, out-of-tree copy of the Linux 6.8 NVMe PCI transport driver.
It is intentionally narrowed to the FPGA endpoint:

```text
vendor:device = 10ee:903f
driver name   = xilinx_nvme
```

The normal in-tree `nvme` driver is not modified and can keep owning real NVMe
devices.

## Version 

Linux-6.8.0-31-generic

## Build

```sh
make -C dr/xilinx_nvme
```

## Load

```sh
sudo modprobe nvme-core
sudo insmod build/xilinx_nvme_pci.ko
```

If the endpoint is already bound to another driver:

```sh
BDF=0000:b8:00.0
echo "$BDF" | sudo tee /sys/bus/pci/devices/$BDF/driver/unbind
echo xilinx_nvme | sudo tee /sys/bus/pci/devices/$BDF/driver_override
echo "$BDF" | sudo tee /sys/bus/pci/drivers_probe
```

Check probe output:

```sh
lspci -nnk -s "$BDF"
dmesg -T | grep -Ei 'b8:00.0|xilinx_nvme|nvme' | tail -100
```

This only changes PCI driver matching. The FPGA BAR0 must still expose valid
NVMe controller registers or the NVMe probe will fail.
