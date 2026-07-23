# NVMe Hardware Capabilities and Protocol Gaps

This directory contains the canonical RTL for the NVMe controller datapath.
Generated Vivado IP copies are build artifacts and should be regenerated from
these sources rather than edited directly.

The current design targets one NVMe namespace with 4 KiB logical blocks. PF0 is
the host-visible NVMe function and PF1 is the management/firmware function.
PF1 is not a second NVMe host or a reservation registrant.

## Current Command Ownership

- MicroBlaze firmware handles controller lifecycle, admin commands, Identify
  data, queue setup, and automation configuration.
- `nvme_auto_io_engine.v` consumes enabled I/O queues and handles Read, Write,
  and no-data Flush commands.
- The DMA path transfers Read/Write data and requests automatic CQ completion
  after the final segment.
- `pcie_hcmd_cq` writes CQEs, releases command slots, and requests PF0 MSI.

## Admin Command Support

| Command | Opcode | Current behavior |
| --- | ---: | --- |
| Delete I/O Submission Queue | `0x00` | Implemented with basic QID validation. |
| Create I/O Submission Queue | `0x01` | Implemented with basic queue and address validation. |
| Get Log Page | `0x02` | Error, SMART/Health, and Firmware Slot pages return minimal mostly static data. |
| Delete I/O Completion Queue | `0x04` | Implemented with basic QID validation. |
| Create I/O Completion Queue | `0x05` | Implemented with queue, vector, and address validation. |
| Identify | `0x06` | Controller, namespace, active namespace list, and descriptor-list subsets are implemented. |
| Abort | `0x08` | Returns success but does not cancel a command. |
| Set Features | `0x09` | Only a limited feature subset has state or behavior. |
| Get Features | `0x0a` | Only a limited feature subset returns meaningful state. |
| Asynchronous Event Request | `0x0c` | Does not maintain a pending request or generate events. |
| Keep Alive | `0x18` | Returns success without a keep-alive timer. |
| Format NVM | `0x80` | Returns success without formatting; not advertised by OACS. |
| Other optional admin commands | various | Not implemented and not advertised. |

Queue creation still lacks complete NVMe validation for duplicate queue IDs,
queue-in-use relationships, queue flags, deletion ordering, and all invalid
field/status distinctions.

## NVM Command Support

| Command | Opcode | Current behavior |
| --- | ---: | --- |
| Flush | `0x00` | Accepted by hardware and completed without data DMA. Full write-drain and persistence ordering is not implemented. |
| Write | `0x01` | Hardware 4 KiB segmented DMA path. |
| Read | `0x02` | Hardware 4 KiB segmented DMA path. |
| Write Uncorrectable | `0x04` | Not implemented or advertised. |
| Compare | `0x05` | Not implemented or advertised. |
| Write Zeroes | `0x08` | Not implemented or advertised. |
| Dataset Management / Deallocate | `0x09` | Not implemented or advertised. |
| Verify | `0x0c` | Not implemented or advertised. |
| Reservation Register | `0x0d` | Not implemented or advertised. |
| Reservation Report | `0x0e` | Not implemented or advertised. |
| Reservation Acquire | `0x11` | Not implemented or advertised. |
| Reservation Release | `0x15` | Not implemented or advertised. |
| Copy | `0x19` | Not implemented or advertised. |

Read and Write currently assume the advertised 4 KiB LBA format and support at
most 256 blocks per command. The datapath does not fully validate NSID, PSDT,
FUA, limited retry, protection information, metadata, fused operation, or all
reserved command fields.

## Capability Advertisement

Unsupported optional commands must remain disabled in Identify data:

- Identify Controller `ONCS` is currently zero.
- Identify Namespace `RESCAP` is currently zero.
- SGL, metadata, protection information, multipath sharing, Dataset Management,
  Compare, Write Zeroes, Verify, Copy, and reservations are not advertised.
- Format NVM is not advertised through `OACS`.

Do not set an Identify capability bit before its command behavior, error
handling, reset behavior, and simulation tests are complete.

The legacy `fw/nvme/nvme.h` `ONCS` and `RESCAP` bitfield definitions are not
complete for modern NVMe revisions. They must be corrected or replaced with
explicit little-endian masks before optional capabilities are enabled.

## Required Correctness Work

The following gaps affect base behavior and have priority over optional command
support:

1. Flush must wait until all earlier Write DMA and modeled media-program work
   covered by the command has completed. Completing Flush immediately can allow
   it to pass an older in-flight Write.
2. An unsupported or firmware-owned I/O opcode must produce a command-specific
   error or be handed to firmware. It must not leave the automation engine in a
   global fault after consuming the SQ entry.
3. Invalid NSID, LBA range, transfer length, PRP/SGL format, and command fields
   need precise NVMe completion status values rather than a controller-wide
   automation error.
4. Abort must locate and cancel, or report the state of, the requested command.
5. Asynchronous Event Requests must remain pending until an event or controller
   reset and must not release their command slots early.
6. Controller reset and shutdown must drain or cancel outstanding DMA, CQ, MSI,
   latency-model, and firmware-owned work without emitting stale completions.
7. Get Log Page and health/error counters need live controller state rather than
   static placeholder data.

## Firmware-Owned I/O Handoff

The automation engine currently examines an opcode only after it has consumed
the common hardware command FIFO entry. Therefore, implementing an optional I/O
command only in MicroBlaze firmware is insufficient.

Add a backpressured special-command FIFO with at least:

```text
{sequence, qid, slot, opcode}
```

For an opcode not owned by the Read/Write/Flush fast path, hardware should:

1. Keep the command slot allocated.
2. Enqueue its metadata for MicroBlaze.
3. Allow firmware to read the complete SQE through the existing SQE window.
4. Let firmware issue a completion-and-release request through the CQ FIFO.
5. Stall only that handoff when the special-command FIFO is full.

An unsupported command should be completed with Invalid Command Opcode. It
should not require resetting the automation engine.

## Reservation Support Plan

Reservations are low-frequency control operations and should be implemented in
firmware through the special-command handoff. The high-throughput data path only
needs a cached permission check.

Firmware needs one reservation state object per namespace:

```text
generation
reservation_type
holder
registrants[] = {host_id, controller_id, reservation_key}
ptpl_state
```

Required command behavior:

- Reservation Register (`0x0d`) receives current and new 64-bit keys and
  implements register, unregister, and replace actions.
- Reservation Report (`0x0e`) returns the generation, reservation type,
  registrant count, PTPL state, and registrant descriptors.
- Reservation Acquire (`0x11`) implements acquire, preempt, and
  preempt-and-abort actions.
- Reservation Release (`0x15`) implements release and clear actions.

Supporting work:

- Add direct host-to-device DMA support in `auto_fw` for Register, Acquire, and
  Release parameter data.
- Use direct device-to-host DMA for Reservation Report data.
- Implement the Host Identifier feature and associate controllers belonging to
  the same host.
- Implement the reservation conflict permission matrix for Read, Write, Flush,
  and other media-access commands.
- Return Reservation Conflict and reservation-specific status codes per
  command, without raising a global automation fault.
- Define controller reset, subsystem reset, and power-loss handling. Advertise
  Persist Through Power Loss only if state is actually preserved.
- Add reservation notification events and log data only if those features are
  advertised.

For the current single-host PF0 design, hardware may cache one
`read_allowed`/`write_allowed` decision per namespace. A future multi-host or
SR-IOV design must carry a controller/host identity with each command before
the permission check.

Only after the implementation passes command and reset tests should firmware
set Identify Controller `ONCS` reservation support and the applicable Identify
Namespace `RESCAP` reservation-type bits.

## Recommended Implementation Order

1. Correct Flush ordering and outstanding-write tracking.
2. Add the special-command handoff FIFO and per-command error completion.
3. Complete Abort, AER, reset, and shutdown semantics.
4. Add Reservation Register, Report, Acquire, and Release in firmware.
5. Add fast-path reservation conflict checks.
6. Enable `ONCS` and `RESCAP`.
7. Add optional Dataset Management, Write Zeroes, Compare, Verify, and Copy as
   required by the target SSD model.

## Verification Requirements

Protocol additions should include:

- RTL simulation with CQ and firmware FIFO backpressure.
- One completion and one slot release for every consumed command.
- No DMA on commands rejected before data transfer.
- Flush ordering tests with multiple outstanding Writes.
- Reservation key/action and conflict-matrix tests.
- Reset tests with commands in DMA, latency, CQ, MSI, and firmware queues.
- Linux `nvme-cli` tests for Identify, logs, features, reset, and reservations.
- Sustained multi-queue I/O tests checking for stale CID, SQID, phase, and
  duplicate completion errors.

## Contributors

* Chatgpt-5.5 

