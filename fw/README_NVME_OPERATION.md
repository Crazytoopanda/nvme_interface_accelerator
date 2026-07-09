# NVMe Firmware Operation Notes

This note explains how this firmware handles NVMe queues and I/O commands in this project. It is intentionally written from the firmware point of view, not as a full NVMe specification.

## Big Picture

There are three sides involved:

1. Host PC memory
   - The host NVMe driver allocates Admin SQ/CQ and I/O SQ/CQ in host DRAM.
   - SQ means Submission Queue: host writes commands there.
   - CQ means Completion Queue: controller writes command results there.

2. FPGA NVMe controller hardware
   - It exposes NVMe BAR registers to the host.
   - It watches doorbells from the host.
   - It fetches SQ entries from host memory over PCIe.
   - It stores fetched commands in internal command slots/SRAM.
   - It writes CQ entries back to host memory.
   - It performs PCIe DMA for read/write data.

3. Firmware on ARM
   - It does not directly walk host SQ/CQ rings.
   - It configures queue base addresses into hardware.
   - It polls a hardware command FIFO.
   - It parses Admin and I/O commands.
   - It sends DMA and completion requests to hardware through MMIO registers.

A simplified path is:

```text
host SQ in host DRAM
        |
        | host writes SQE and rings doorbell
        v
FPGA hardware fetches SQE over PCIe
        |
        | stores command in internal command slot SRAM
        v
firmware polls hardware command FIFO
        |
        | parses command and writes hardware control registers
        v
FPGA hardware performs DMA and writes CQE
        |
        v
host CQ in host DRAM
```

## Important Memory Areas

### Firmware-visible DRAM

Defined in `fw/memory_map.h`:

```c
#define DRAM_START_ADDR             0x5000000000
#define NVME_MANAGEMENT_START_ADDR  (DRAM_START_ADDR | 0x00200000)
#define DATA_BUFFER_BASE_ADDR       0x5040000000ULL
#define DRAM_END_ADDR               0x5FFFFFFFFFULL
```

The main areas are:

| Region | Purpose |
|---|---|
| `NVME_MANAGEMENT_START_ADDR` | Temporary management/admin data buffer, for example Identify data before DMA to host. |
| `DATA_BUFFER_BASE_ADDR` | Fake NVMe storage data buffer. Read/write commands copy data between this DRAM area and host memory. |
| `DUMMY_RD_WR_ADDR` | Reserved dummy address for NVMe IP. |

This firmware treats `DATA_BUFFER_BASE_ADDR` as the backing storage. There is no real NAND/FTL layer here.

```text
DATA_BUFFER_BASE_ADDR
        |
        +-- LBA 0, 4 KiB
        +-- LBA 1, 4 KiB
        +-- LBA 2, 4 KiB
        ...
```

The block size is defined in `fw/nvme/nvme.h`:

```c
#define BYTES_PER_NVME_BLOCK 4096
```

So firmware maps an LBA to DRAM like this:

```c
devAddr = DATA_BUFFER_BASE_ADDR + startLba * BYTES_PER_NVME_BLOCK;
```

### Host memory

Host memory contains the real NVMe queues and PRP(Phyiscal Region Page) data buffers:

```text
Host DRAM
  +-- Admin SQ
  +-- Admin CQ
  +-- I/O SQ 1
  +-- I/O CQ 1
  +-- I/O SQ 2
  +-- I/O CQ 2
  +-- Read/write PRP data buffers
```

The firmware does not allocate these queues. The host driver allocates them and tells the 
controller their physical addresses through NVMe registers and Admin commands.

### FPGA internal command SRAM

Defined in `fw/nvme/host_lld.h`:

```c
#define NVME_CMD_FIFO_REG_ADDR  (HOST_IP_ADDR + 0x300)
#define NVME_CMD_SRAM_ADDR      (HOST_IP_ADDR + 0x10000)
```

When hardware fetches an SQE from host memory, it stores the 64-byte command into internal command SRAM. Firmware later reads it with:

```c
addr = NVME_CMD_SRAM_ADDR + (cmdSlotTag * 64);
```

Each command slot is 64 bytes, equal to one NVMe SQE.

```text
NVME_CMD_SRAM_ADDR
  +-- slot 0: 64B SQE
  +-- slot 1: 64B SQE
  +-- slot 2: 64B SQE
  ...
```

The `cmdSlotTag` is important. Firmware uses it later when asking hardware to do auto DMA or auto completion, because hardware remembers the original command metadata and PRP fields in that slot.

## Controller Startup Flow

The entry point is `main()` in `fw/main.c`:

1. Disable caches.
2. Configure MMU memory attributes.
3. Enable caches.
4. Initialize exception and GIC interrupt handling.
5. Register FPGA interrupt handler `dev_irq_handler()`.
6. Call `nvme_main()`.

The firmware then waits in `nvme_main()`.

The state machine is in `fw/nvme/nvme_main.c`:

```c
NVME_TASK_IDLE
NVME_TASK_WAIT_CC_EN
NVME_TASK_RUNNING
NVME_TASK_SHUTDOWN
NVME_TASK_WAIT_RESET
NVME_TASK_RESET
```

When the host enables the NVMe controller by setting `CC.EN`, hardware raises an interrupt. `dev_irq_handler()` sees the `nvmeCcEn` bit and moves firmware into `NVME_TASK_WAIT_CC_EN`.

Then `nvme_main()` does:

```c
set_nvme_admin_queue(1, 1, 1);
set_nvme_csts_rdy(1);
g_nvmeTask.status = NVME_TASK_RUNNING;
```

Meaning:

| Function | Meaning |
|---|---|
| `set_nvme_admin_queue(1, 1, 1)` | Tell hardware Admin SQ and Admin CQ are valid, and Admin CQ interrupt is enabled. |
| `set_nvme_csts_rdy(1)` | Set NVMe `CSTS.RDY`, so the host sees the controller is ready. |

## Admin Queue Formation

Admin SQ/CQ are special because the host sets them before normal I/O queues exist.

Typical host-side sequence:

1. Host allocates Admin SQ and Admin CQ in host memory.
2. Host writes NVMe Admin Queue registers such as ASQ, ACQ, and AQA.
3. Host writes `CC.EN = 1`.
4. Controller firmware marks Admin Queue valid and sets `CSTS.RDY = 1`.

Firmware does not manually parse ASQ/ACQ. Hardware handles those BAR registers. Firmware only enables the hardware Admin Queue path through:

```c
set_nvme_admin_queue(sqValid, cqValid, cqIrqEn);
```

This writes the FPGA control register:

```c
NVME_ADMIN_QUEUE_SET_REG_ADDR
```

After this, host can submit Admin commands.

## How Firmware Receives Commands

When host submits a command:

1. Host writes a 64-byte SQE into a host SQ.
2. Host rings the SQ doorbell.
3. FPGA hardware notices the doorbell.
4. FPGA hardware reads the SQE from host memory over PCIe.
5. FPGA hardware stores the SQE into internal command SRAM.
6. FPGA hardware pushes a small descriptor into the command FIFO.
7. Firmware polls the command FIFO.

Firmware polling happens in `nvme_main()`:

```c
cmdValid = get_nvme_cmd(&nvmeCmd.qID,
                        &nvmeCmd.cmdSlotTag,
                        &nvmeCmd.cmdSeqNum,
                        nvmeCmd.cmdDword);

if (cmdValid == 1) {
    if (nvmeCmd.qID == 0)
        handle_nvme_admin_cmd(&nvmeCmd);
    else
        handle_nvme_io_cmd(&nvmeCmd);
}
```

`get_nvme_cmd()` reads:

```c
NVME_CMD_FIFO_REG_ADDR
```

That register tells firmware:

| Field | Meaning |
|---|---|
| `cmdValid` | Hardware has a command ready. |
| `qID` | Queue ID. `0` is Admin Queue, nonzero is I/O SQ. |
| `cmdSlotTag` | Hardware internal slot index where the 64B SQE is stored. |
| `cmdSeqNum` | Command sequence number from hardware. |

If `cmdValid` is set, firmware reads the full SQE from:

```c
NVME_CMD_SRAM_ADDR + cmdSlotTag * 64
```

## I/O Queue Creation

I/O SQ/CQ are created by Admin commands.

### Create I/O Completion Queue

Handled by:

```c
handle_create_io_cq()
```

This parses the Admin command fields:

| Field | Meaning |
|---|---|
| `DW10.QID` | Completion Queue ID. |
| `DW10.QSIZE` | Queue size, zero-based per NVMe. |
| `DW11.IEN` | Interrupt enable. |
| `DW11.IV` | Interrupt vector. |
| `PRP1` | Host physical base address of the CQ. |

Firmware saves this into:

```c
g_nvmeTask.ioCqInfo[ioCqIdx]
```

Then it tells hardware:

```c
set_io_cq(ioCqIdx,
          valid,
          irqEn,
          irqVector,
          qSize,
          pcieBaseAddrL,
          pcieBaseAddrH);
```

This writes FPGA registers starting at:

```c
NVME_IO_CQ_SET_REG_ADDR + ioCqIdx * 8
```

### Create I/O Submission Queue

Handled by:

```c
handle_create_io_sq()
```

This parses:

| Field | Meaning |
|---|---|
| `DW10.QID` | Submission Queue ID. |
| `DW10.QSIZE` | Queue size. |
| `DW11.CQID` | Completion Queue associated with this SQ. |
| `PRP1` | Host physical base address of the SQ. |

Firmware saves this into:

```c
g_nvmeTask.ioSqInfo[ioSqIdx]
```

Then it tells hardware:

```c
set_io_sq(ioSqIdx,
          valid,
          cqVector,
          qSize,
          pcieBaseAddrL,
          pcieBaseAddrH);
```

This writes FPGA registers starting at:

```c
NVME_IO_SQ_SET_REG_ADDR + ioSqIdx * 8
```

After this, hardware knows where each host I/O SQ is and which CQ it completes into.

## Completion Generation

Firmware completes commands by writing completion requests into a hardware FIFO.

Important functions:

```c
set_nvme_cpl(sqId, cid, specific, statusFieldWord);
set_auto_nvme_cpl(cmdSlotTag, specific, statusFieldWord);
set_nvme_slot_release(cmdSlotTag);
```

These write registers around:

```c
NVME_CPL_FIFO_REG_ADDR
HOST_CPL_FIFO_TRIG_ADDR
```

There are three completion modes:

| Type | Meaning |
|---|---|
| `ONLY_CPL_TYPE` | Firmware provides SQID/CID/status; hardware writes CQE. |
| `AUTO_CPL_TYPE` | Firmware provides `cmdSlotTag`; hardware uses saved command metadata to form CQE. |
| `CMD_SLOT_RELEASE_TYPE` | Release hardware command slot without writing a normal completion. |

Most Admin commands use:

```c
set_auto_nvme_cpl(cmdSlotTag, specific, statusFieldWord);
```

For I/O read/write, completion is usually tied to auto DMA completion.

## Read Command Flow

Read is handled by:

```c
handle_nvme_io_read()
```

This is NVMe Read from host point of view: host wants to read data from the device. Therefore data moves:

```text
device DRAM -> host PRP buffer
```

Firmware steps:

1. Parse starting LBA:

```c
startLba[0] = nvmeIOCmd->dword[10];
startLba[1] = nvmeIOCmd->dword[11];
```

2. Parse number of logical blocks:

```c
readInfo12.dword = nvmeIOCmd->dword[12];
nlb = readInfo12.NLB;
requestedNvmeBlock = nlb + 1;
```

NVMe `NLB` is zero-based, so `0` means one block.

3. Convert LBA to local DRAM address:

```c
devAddr = DATA_BUFFER_BASE_ADDR + startLba[0] * BYTES_PER_NVME_BLOCK;
```

4. For each 4 KiB block, submit auto TX DMA:

```c
set_auto_tx_dma(cmdSlotTag,
                dmaIndex,
                devAddr,
                NVME_COMMAND_AUTO_COMPLETION_ON);
```

`TX` here means controller/device transmits data to host.

The firmware does not directly pass PRP1/PRP2 here. It only passes `cmdSlotTag` and `dmaIndex`. Hardware uses the original SQE stored in that command slot to find PRP addresses.

## Write Command Flow

Write is handled by:

```c
handle_nvme_io_write()
```

This is NVMe Write from host point of view: host writes data to the device. Therefore data moves:

```text
host PRP buffer -> device DRAM
```

Firmware steps are almost the same:

1. Parse LBA and NLB.
2. Compute local DRAM destination:

```c
devAddr = DATA_BUFFER_BASE_ADDR + startLba[0] * BYTES_PER_NVME_BLOCK;
```

3. For each 4 KiB block, submit auto RX DMA:

```c
set_auto_rx_dma(cmdSlotTag,
                dmaIndex,
                devAddr,
                NVME_COMMAND_AUTO_COMPLETION_ON);
```

`RX` here means controller/device receives data from host.

## Direct DMA vs Auto DMA

There are two styles of DMA command in `host_lld.c`.

### Direct DMA

Used when firmware explicitly knows the host PCIe address.

Example: Identify command.

Firmware builds Identify data in local DRAM at `NVME_MANAGEMENT_START_ADDR`, then calls:

```c
set_direct_tx_dma(localIdentifyBuffer,
                  hostPrpHigh,
                  hostPrpLow,
                  length);
```

This explicitly says:

```text
copy local DRAM buffer -> host PRP address
```

### Auto DMA

Used for normal I/O read/write.

Firmware does not give host PRP address directly. It gives:

```c
cmdSlotTag
cmd4KBOffset
devAddr
direction
autoCompletion
```

Hardware already has the original SQE in the command slot, so it can resolve PRP1/PRP2 and do the right PCIe DMA.

This is why `cmdSlotTag` is central to the whole design.

## Simplified Read Example

Assume host submits NVMe Read:

```text
SQID = 1
CID = 0x20
SLBA = 100
NLB = 3
PRP1 = host buffer address
```

`NLB = 3` means 4 blocks, so 16 KiB total.

Flow:

```text
1. Host writes Read SQE into I/O SQ 1.
2. Host rings SQ 1 doorbell.
3. FPGA fetches SQE into command slot, e.g. slot 7.
4. Firmware sees command FIFO valid:
      qID = 1
      cmdSlotTag = 7
5. Firmware parses command:
      startLba = 100
      requestedNvmeBlock = 4
6. Firmware computes local addresses:
      DATA_BUFFER_BASE_ADDR + 100 * 4096
      DATA_BUFFER_BASE_ADDR + 101 * 4096
      DATA_BUFFER_BASE_ADDR + 102 * 4096
      DATA_BUFFER_BASE_ADDR + 103 * 4096
7. Firmware submits four auto TX DMA commands:
      slot 7, offset 0, local block 100
      slot 7, offset 1, local block 101
      slot 7, offset 2, local block 102
      slot 7, offset 3, local block 103
8. Hardware uses slot 7 PRP info to DMA data to host.
9. Hardware writes CQE after DMA, because autoCompletion is ON.
10. Host sees completion in CQ.
```

## Simplified Write Example

Assume host submits NVMe Write:

```text
SQID = 2
CID = 0x35
SLBA = 200
NLB = 0
PRP1 = host buffer address
```

`NLB = 0` means 1 block, so 4 KiB total.

Flow:

```text
1. Host writes Write SQE into I/O SQ 2.
2. Host rings SQ 2 doorbell.
3. FPGA fetches SQE into command slot, e.g. slot 9.
4. Firmware sees command FIFO valid:
      qID = 2
      cmdSlotTag = 9
5. Firmware parses command:
      startLba = 200
      requestedNvmeBlock = 1
6. Firmware computes local destination:
      DATA_BUFFER_BASE_ADDR + 200 * 4096
7. Firmware submits one auto RX DMA command:
      slot 9, offset 0, local block 200
8. Hardware uses slot 9 PRP info to DMA host data into local DRAM.
9. Hardware writes CQE after DMA, because autoCompletion is ON.
10. Host sees completion in CQ.
```

## Key Firmware Files

| File | Role |
|---|---|
| `fw/main.c` | Platform init: MMU, cache, interrupt controller, then enters `nvme_main()`. |
| `fw/nvme/nvme_main.c` | Main NVMe state machine and command polling loop. |
| `fw/nvme/host_lld.h` | Hardware MMIO register addresses and register bitfield structs. |
| `fw/nvme/host_lld.c` | Low-level hardware control: queue setup, command fetch, completion FIFO, DMA FIFO. |
| `fw/nvme/nvme_admin_cmd.c` | Admin command handling, including queue creation and Identify. |
| `fw/nvme/nvme_io_cmd.c` | I/O command handling: Read, Write, Flush. |
| `fw/nvme/nvme.h` | NVMe command structures, opcodes, status codes, queue context structures. |
| `fw/memory_map.h` | Local DRAM layout used by firmware. |

## One-Line Mental Model

The host owns SQ/CQ memory. Hardware owns queue walking and PCIe movement. Firmware owns command interpretation and tells hardware what operation to perform next.
