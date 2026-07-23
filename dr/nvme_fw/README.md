# nvme_fw

PF1 firmware/control driver for BAR2. It binds function 1 by default and creates
`/dev/nvme_fw<N>`.

BAR2 register offsets and ioctl ABI live in `nvme_fw_regs.h`.

Build:

```sh
make -C dr/nvme_fw
```

Build output: `dr/nvme_fw/build/nvme_fw.ko`.
Helper tools are also placed in `dr/nvme_fw/build/`.

Verbose logs:

```sh
make -C dr/nvme_fw NVME_FW_DEBUG=1
# or at runtime
sudo insmod dr/nvme_fw/build/nvme_fw.ko debug=1
```

Default host-firmware mode:

```sh
sudo insmod dr/nvme_fw/build/nvme_fw.ko
```

The default `run_firmware=1 fw_use_auto_hw=1` mode replaces MicroBlaze
`auto_fw`. The PF1 kernel worker owns CC/CSTS lifecycle, admin commands, admin
DMA, and IO queue setup. It configures the hardware automation and SSD latency
registers, then leaves enabled IO QIDs in the command FIFO for hardware
Read/Write/Flush, DMA, CQ write, and PF0 MSI processing.

The expected load log includes `firmware=1 auto_hw=1`. If `auto_hw=0`, the
automation magic did not match and the worker falls back to the older software
IO path.

To use MicroBlaze `auto_fw` instead, select management-only mode explicitly:

```sh
sudo insmod dr/nvme_fw/build/nvme_fw.ko run_firmware=0
```

Never run both firmware owners. `run_firmware=1`, MicroBlaze `auto_fw`, and
`nvme_fw_daemon --run` are mutually exclusive. Optional PCI settings remain
available for targeted testing:

```sh
sudo insmod dr/nvme_fw/build/nvme_fw.ko \
  use_msi=1 enable_busmaster=1 probe_check_magic=1 \
  auto_enable_pf1_msi=1 auto_enable_pf0_msi=1
```

PF0 MSI trigger can be done through ioctl `NVME_FW_IOC_TRIGGER_PF0_MSI` or a raw
write of `1` to `BAR2 + 0x22044`, after PF0 manual MSI has been enabled with
`BAR2 + 0x22040 = 0x101`.


## BAR2 Probe Test

`nvme_fw.ko` can optionally read probe-test registers during `insmod`. Keep this
disabled for normal safe loading. Use levels in order after a reboot or FPGA
reload:

```sh
sudo insmod dr/nvme_fw/build/nvme_fw.ko probe_test_level=1
```

Level 1 reads only the BAR2 stream-local debug window:

- `0x3ffe0` local debug magic
- `0x3ffe4` local counts
- `0x3ffe8` last BAR2 address
- `0x3fff0` BAR2 request count

If level 1 survives, test the BAR2 direct s0-compatible register path:

```sh
sudo rmmod nvme_fw
sudo insmod dr/nvme_fw/build/nvme_fw.ko probe_test_level=2
```

Level 2 additionally reads:

- `0x200` NVMe status
- `0x21c` admin queue control
- `0x300` command FIFO
- `0x400` automation magic
- `0x408` automation status
- `0x40c` automation error

If level 2 survives, test the BAR2 DMA-ring control path:

```sh
sudo rmmod nvme_fw
sudo insmod dr/nvme_fw/build/nvme_fw.ko probe_test_level=3
```

Level 3 additionally reads the ring magic/status/info/PID counters under
`0x22000`. The dmesg line printed immediately before a hang identifies the next
BAR2 register that was about to be read.

## PF0 bring-up debug

With the default parameters, `nvme_fw` implements the host-resident firmware
worker. If PF0 reports `Device not ready; CSTS=0x0`, verify that the loaded
module reports `firmware=1 auto_hw=1`, then inspect CC/CSTS and automation state.

```sh
make -C dr/nvme_fw
sudo dr/nvme_fw/build/nvme_fw_ctl info
sudo dr/nvme_fw/build/nvme_fw_ctl status
sudo dr/nvme_fw/build/nvme_fw_ctl auto-status
sudo dr/nvme_fw/build/nvme_fw_ctl read 0x200
```

For a bitstream containing the current automation block, `auto-status` must
report:

```text
magic                [0x400] = 0xa710f001
compatible=yes
```

It also reports automation control/status/error, DDR range, command/DMA/CQ
counters, the last QID/slot/opcode, CQ retry cycles, and SSD model counters.
An all-ones value means the PF1 BAR2 request was not completed. A zero or
unexpected magic means BAR2 is alive but the current automation register block
is not present at offset `0x400`.

`BAR2 + 0x200` readback bits include `CC.EN` at bit 0 and `CSTS.RDY` at bit 4.
While loading PF0, if bit 0 becomes 1 and bit 4 stays 0, the firmware side has
not marked the controller ready. For a manual smoke test:

The `ready` command is only a low-level BAR smoke test. Do not use it while the
kernel firmware worker or MicroBlaze `auto_fw` is active.

```sh
sudo dr/nvme_fw/build/nvme_fw_ctl ready 0
# in another shell: sudo insmod dr/nvme_on_host/build/nvme_on_host.ko
sudo dr/nvme_fw/build/nvme_fw_ctl ready 1
```

After RDY is set, PF0 can move past controller-enable. Real NVMe initialization
still needs firmware behavior: fetch admin SQEs, perform needed DMA/data setup,
write completions, and trigger PF0 MSI.

## Legacy host firmware daemon

`nvme_fw_daemon` is the host-side replacement for the card firmware loop. It is
structured after `fw/nvme/nvme_main.c`, but every register access goes through
the PF1 BAR2 ABI in `nvme_fw_regs.h` instead of MicroBlaze `HOST_IP_ADDR`
pointers. It is retained for host-only bring-up and must not run concurrently
with MicroBlaze `auto_fw`.

The daemon defaults to open-only mode and performs no MSI or controller writes.
For legacy host-owned firmware testing, first stop MicroBlaze firmware, then
explicitly pass `--run`:

```sh
sudo insmod dr/nvme_fw/build/nvme_fw.ko run_firmware=0
sudo dr/nvme_fw/build/nvme_fw_daemon --run
# another shell
sudo insmod dr/nvme_on_host/build/nvme_on_host.ko
```

Implemented daemon flow:

- `IDLE -> WAIT_CC_EN -> RUNNING -> SHUTDOWN -> WAIT_RESET`, matching `fw/`.
- On `CC.EN`, writes admin queue enable at BAR2 `0x21c` and sets `CSTS.RDY`.
- On shutdown/reset, clears admin and IO queues and clears `CSTS`.
- Enables PF0 manual MSI from daemon startup, not from module probe.
- Fetches commands through `NVME_FW_IOC_FETCH_CMD`.
- Posts normal admin completions as `NVME_FW_CPL_AUTO`, matching
  `set_auto_nvme_cpl()` in `fw/nvme/host_lld.c`.
- Programs IO SQ/CQ registers using the hardware BAR2 layout at `0x220/0x260`.
- Generates minimal Identify Controller, Identify Namespace, namespace-list, and
  Log Page payloads.
- Stages those payloads through a PF1 coherent host buffer, RX-DMAs them into
  card-local `NVME_MANAGEMENT_START_ADDR`, then TX-DMAs to the host PRP.
- Triggers PF0 MSI after completions.

The daemon is retained only as a diagnostic alternative. It does not run with
the default kernel firmware worker.

## Current hardware load sequence

With the FPGA bitstream loaded and MicroBlaze stopped:

```sh
sudo insmod dr/nvme_fw/build/nvme_fw.ko
sudo dr/nvme_fw/build/nvme_fw_ctl info
sudo dr/nvme_fw/build/nvme_fw_ctl auto-status
sudo insmod dr/nvme_on_host/build/nvme_on_host.ko
```

Expected ownership:

- PF1 `nvme_fw.ko`: CC/CSTS lifecycle, admin commands and DMA, IO queue setup,
  automation configuration, BAR2 diagnostics.
- Hardware automation: normal Read/Write/Flush execution, data DMA, CQ writes,
  SSD latency gating, and PF0 MSI.
- PF0 `nvme_on_host.ko`: Linux NVMe host driver.
- MicroBlaze `auto_fw`: stopped.

For MicroBlaze-owned firmware, load PF1 with `run_firmware=0` instead.
