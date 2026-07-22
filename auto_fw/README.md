# auto_fw

Minimal MicroBlaze firmware for the autonomous NVMe datapath.

This tree is intentionally separate from `fw/`.  The target split is:

- MicroBlaze handles NVMe controller bring-up, admin commands, queue setup,
  shutdown, and hardware automation configuration.
- Hardware handles IO SQ consumption, SQE decode, auto DMA submission, DMA-done
  tracking, CQ write, slot release, and PF0 MSI for normal IO.
- MicroBlaze only sees automation errors, unsupported commands, and status
  counters after IO automation is enabled.

The hardware register contract is defined in `nvme/auto_hw_regs.h`.


Source layout:

- `main.c`: MicroBlaze entry point, matching the top-level `fw/main.c` convention.
- `nvme/`: auto firmware helpers and hardware register definitions.
- `kernel_config.h` and `memory_map.h`: minimal top-level configuration headers.
- `boot/microblaze/lscript.ld`: MicroBlaze linker script copied from the normal firmware tree.

This keeps `auto_fw` usable as a replacement firmware source tree, for example
by linking or selecting `auto_fw` where a Vitis project previously used `fw`.

Bring-up sequence:

1. Initialize platform/cache/interrupts.
2. Clear stale NVMe status and automation state.
3. Wait for `CC.EN`, run the normal NVMe admin handshake.
4. Program IO SQ/CQ registers as before.
5. Write automation registers and set `AUTO_CTRL.EN`.
6. Poll/handle `AUTO_STATUS.ERROR` and interrupt status.

Current `auto_fw` behavior:

- Polls `AUTO_NVME_STATUS` and, when PF0 sets `CC.EN`, enables the admin SQ/CQ
  registers and sets `CSTS.RDY`.
- Handles admin commands needed by the Linux NVMe probe: Set/Get Features,
  Identify, Get Log Page, Create/Delete IO CQ/SQ, Keep Alive, Abort, Format,
  and Async Event Request slot release.
- Fetches SQEs from the S1 AXI command window `0xB0000000` by default, matching
  `fw/nvme/host_lld.h`. Set `AUTO_FW_USE_S1_AXI_CMD_WINDOW=0` only if the
  s0 command SRAM window at `0xA0010000` is the intended path.
- Uses card DDR at `NVME_MANAGEMENT_START_ADDR` as a 4 KiB staging buffer for
  Identify/Get Log data, then submits direct TX DMA to the host PRP.
- Uses `AUTO_FW_MGMT_BASE` default `0x5000200000` for admin DMA staging and
  `AUTO_FW_DDR_BASE` default `0x5040000000` for namespace data.
- Uses the non-destructive SQ-head peek register at `0xA0000344` before
  popping commands. When `AUTO_REG_CTRL.EN` is set, enabled IO QIDs stay in
  the FIFO for hardware automation; QID0 admin and masked/fallback entries are
  still popped by MicroBlaze.
- Enables `AUTO_REG_CTRL.EN` automatically when `CSTS.RDY` is asserted. The RTL
  auto engine now only pops enabled IO QIDs, so later admin commands remain
  routed to MicroBlaze.

Register layout:

Legacy NVMe FIFO helper registers in the same `0xA0000000` window:

| Offset | Address | Name | Access | Description |
| --- | --- | --- | --- | --- |
| `0x300` | `0xA0000300` | `AUTO_CMD_FIFO` | RO pop | Pops one fetched SQE descriptor. Bit 31 valid, bits 23:16 sequence, bits 14:5 slot, bits 3:0 qid. |
| `0x344` | `0xA0000344` | `AUTO_CMD_FIFO_PEEK` | RO peek | Same descriptor format as `AUTO_CMD_FIFO`, but does not advance the FIFO. Firmware uses this to avoid stealing IO commands from hardware. |

Automation registers live in the existing `s0_axi` window at
`0xA0000000 + 0x400`.  From PF1 BAR2 direct access, use the same low offset
inside BAR2, for example BAR2 `+ 0x400` for `AUTO_REG_MAGIC`.

| Offset | Address | Name | Access | Description |
| --- | --- | --- | --- | --- |
| `0x000` | `0xA0000400` | `AUTO_REG_MAGIC` | RO | Must read `0xA710F001`. |
| `0x004` | `0xA0000404` | `AUTO_REG_CTRL` | RW | Bit 0 enable, bit 1 reset pulse, bit 8 read enable, bit 9 write enable, bit 10 auto CQ enable, bit 11 auto MSI enable. |
| `0x008` | `0xA0000408` | `AUTO_REG_STATUS` | RO | Bit 0 enabled, bit 1 idle, bit 8 error, bit 9 unsupported pending, bit 10 DMA stalled, bit 16 busy, bit 17 MSI enabled, bits 24:20 engine state. |
| `0x00c` | `0xA000040c` | `AUTO_REG_ERROR` | RW1C | Error latch. Write `1` bits to clear. |
| `0x010` | `0xA0000410` | `AUTO_REG_DDR_BASE_LO` | RW | Device DDR namespace base address bits 31:0. |
| `0x014` | `0xA0000414` | `AUTO_REG_DDR_BASE_HI` | RW | Device DDR namespace base address high bits. |
| `0x018` | `0xA0000418` | `AUTO_REG_DDR_LIMIT_LO` | RW | Inclusive device DDR namespace limit bits 31:0. |
| `0x01c` | `0xA000041c` | `AUTO_REG_DDR_LIMIT_HI` | RW | Inclusive device DDR namespace limit high bits. |
| `0x020` | `0xA0000420` | `AUTO_REG_IO_ENABLE_MASK` | RW | Queue mask for IO QID 1-8. Default firmware value is `0x1fe`. |
| `0x024` | `0xA0000424` | `AUTO_REG_PF0_MSI_CTRL` | RW | Stored PF0 MSI control value for firmware policy/debug. |
| `0x028` | `0xA0000428` | `AUTO_REG_CQ_MODE` | RW | `0` means hardware auto CQ. `1` is reserved for MicroBlaze ACK mode and is currently rejected by RTL. |
| `0x030` | `0xA0000430` | `AUTO_REG_CMD_COUNT` | RO | Number of SQ entries consumed by the auto engine. |
| `0x034` | `0xA0000434` | `AUTO_REG_DMA_SUBMIT_COUNT` | RO | Number of 4 KiB DMA segments submitted by the auto engine. |
| `0x038` | `0xA0000438` | `AUTO_REG_DMA_DONE_COUNT` | RO | Current `{dma_tx_done_cnt, dma_rx_done_cnt}` mirror. |
| `0x03c` | `0xA000043c` | `AUTO_REG_CQ_WRITE_COUNT` | RO | Number of CQ memory writes issued by the CQ writer. |
| `0x040` | `0xA0000440` | `AUTO_REG_LAST_CQE_DW3` | RO | Last CQE DW3 `{status, phase, cid}` captured when the CQ writer issues a memory write. |
| `0x044` | `0xA0000444` | `AUTO_REG_UNSUPPORTED_COUNT` | RO | Number of commands rejected by the auto engine. |
| `0x048` | `0xA0000448` | `AUTO_REG_LAST_QID_SLOT` | RO | Last consumed SQ entry metadata `{seq, slot, qid}`. |
| `0x04c` | `0xA000044c` | `AUTO_REG_LAST_OPCODE` | RO | Last decoded SQE opcode. |
| `0x050` | `0xA0000450` | `AUTO_REG_LAST_ERROR_INFO` | RO | Last error context `{opcode, qid, slot}`. |
| `0x054` | `0xA0000454` | `AUTO_REG_LAST_CQE_DW2` | RO | Last CQE DW2 `{sqid, sqhd}` captured when the CQ writer issues a memory write. |
| `0x058` | `0xA0000458` | `AUTO_REG_CQ_IRQ_RETRY` | W1P/RO | Write bit 0 as `1` with bits `[7:4]` holding CQID `0`-`8` to retry PF0 MSI for an already-written CQE. Read returns `{retry_count[15:0], 12'b0, last_cqid}`. |
| `0x05c` | `0xA000045c` | `AUTO_REG_SW_DOORBELL` | Reserved | Declared for future firmware handoff, not decoded by current RTL. |

CQ IRQ retry watchdog:

- `auto_fw_service()` tracks the last CQE write count and last CQE DW2/DW3.
- If the last CQE stays unchanged for `AUTO_FW_CQ_IRQ_RETRY_DELAY_SERVICE` service passes, firmware writes `AUTO_REG_CQ_IRQ_RETRY` for the decoded CQID.
- This is a lost-MSI fallback. The card cannot know the Linux timeout directly; exact detection requires exposing host CQ head doorbell updates/counters to the automation register window.


`AUTO_REG_ERROR` bits:

| Bit | Name | Meaning |
| --- | --- | --- |
| 0 | `AUTO_ERR_ADMIN_OR_MASKED_QID` | Admin queue or disabled IO queue was consumed. |
| 1 | `AUTO_ERR_UNSUPPORTED_OPCODE` | Opcode was not IO read/write. |
| 2 | `AUTO_ERR_DISABLED_OPCODE` | Read/write opcode is disabled in `AUTO_REG_CTRL`. |
| 3 | `AUTO_ERR_DDR_RANGE` | `auto_ddr_base + (SLBA + NLB) * 4096` exceeds `AUTO_REG_DDR_LIMIT`. |
| 4 | `AUTO_ERR_AUTO_CQ_DISABLED` | Auto CQ bit is not enabled. |
| 5 | `AUTO_ERR_CQ_MODE_UNSUPPORTED` | `AUTO_REG_CQ_MODE` is not hardware mode. |
| 6 | `AUTO_ERR_NLB_TOO_LARGE` | NLB uses bits above 7. Current RTL supports up to 256 4 KiB blocks per command. |

The RTL integration includes `nvme_auto_io_engine`. `auto_fw_init()` clears the
engine and programs its DDR range; `auto_fw_enter_running()` enables it after
asserting `CSTS.RDY`. Firmware continues to service QID0 admin commands using
the SQ-head peek register while hardware consumes enabled IO QIDs.
