# Boot Directory Layout

Target-specific boot files live under one subdirectory per kernel:

- `cortex_a53/`: Cortex-A53 linker script and MMU translation table.
- `microblaze/`: MicroBlaze linker script. Firmware code/data stay in local LMB; shared AXI BRAM is left for runtime buffers.

Use one Vitis application per processor target.

For the Cortex-A53 app:

- Compiler symbol: `CORTEX_A53_KERNEL`
- Linker script: `fw/boot/cortex_a53/lscript.ld`
- Compile/link `fw/boot/cortex_a53/translation_table.S`
- Exclude `fw/boot/microblaze`

For the MicroBlaze app:

- Compiler symbols: `MICROBLAZE_KERNEL` and normally `DISABLE_NVMEVIRT`
- Linker script: `fw/boot/microblaze/lscript.ld`
- Exclude `fw/boot/cortex_a53`

In Vitis managed build, do not edit generated Makefiles directly. Right-click the unused folder or file, then use `Resource Configurations -> Exclude from Build...` for the active `Debug`/`Release` configuration. Alternatively, link only the matching boot subdirectory into each Vitis app instead of linking the whole `fw/boot` tree.
