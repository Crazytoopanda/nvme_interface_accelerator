/*******************************************************************/
/* MicroBlaze linker script for the NVMe firmware target.           */
/*                                                                 */
/* Keep firmware code/data in MicroBlaze local memory. The shared   */
/* AXI BRAM window at 0x80000000 is used by firmware/RTL runtime    */
/* buffers and must not be consumed by normal program sections.      */
/*******************************************************************/

_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x4000;
_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x4000;

MEMORY
{
   microblaze_local_memory : ORIGIN = 0x00000000, LENGTH = 0x00100000
   shared_axi_bram         : ORIGIN = 0x80000000, LENGTH = 0x00020000
}

ENTRY(_start)

SECTIONS
{
.vectors.reset 0x00000000 : {
   KEEP (*(.vectors.reset))
} > microblaze_local_memory

.vectors.sw_exception 0x00000008 : {
   KEEP (*(.vectors.sw_exception))
} > microblaze_local_memory

.vectors.interrupt 0x00000010 : {
   KEEP (*(.vectors.interrupt))
} > microblaze_local_memory

.vectors.hw_exception 0x00000020 : {
   KEEP (*(.vectors.hw_exception))
} > microblaze_local_memory

.text : {
   *(.text)
   *(.text.*)
   *(.gnu.linkonce.t.*)
   *(.note.gnu.build-id)
} > microblaze_local_memory

.init : {
   KEEP (*(.init))
} > microblaze_local_memory

.fini : {
   KEEP (*(.fini))
} > microblaze_local_memory

.ctors : {
   __CTOR_LIST__ = .;
   ___CTORS_LIST___ = .;
   KEEP (*crtbegin.o(.ctors))
   KEEP (*(EXCLUDE_FILE(*crtend.o) .ctors))
   KEEP (*(SORT(.ctors.*)))
   KEEP (*(.ctors))
   __CTOR_END__ = .;
   ___CTORS_END___ = .;
} > microblaze_local_memory

.dtors : {
   __DTOR_LIST__ = .;
   ___DTORS_LIST___ = .;
   KEEP (*crtbegin.o(.dtors))
   KEEP (*(EXCLUDE_FILE(*crtend.o) .dtors))
   KEEP (*(SORT(.dtors.*)))
   KEEP (*(.dtors))
   PROVIDE(__DTOR_END__ = .);
   PROVIDE(___DTORS_END___ = .);
} > microblaze_local_memory

.drvcfg_sec : {
   . = ALIGN(8);
   __drvcfgsecdata_start = .;
   KEEP (*(.drvcfg_sec))
   __drvcfgsecdata_end = .;
   __drvcfgsecdata_size = __drvcfgsecdata_end - __drvcfgsecdata_start;
} > microblaze_local_memory

.rodata : {
   . = ALIGN(4);
   __rodata_start = .;
   *(.rodata)
   *(.rodata.*)
   *(.srodata)
   *(.srodata.*)
   *(.gnu.linkonce.r.*)
   __rodata_end = .;
} > microblaze_local_memory

.sdata2 : {
   . = ALIGN(4);
   __sdata2_start = .;
   *(.sdata2)
   *(.sdata2.*)
   *(.gnu.linkonce.s2.*)
   __sdata2_end = .;
} > microblaze_local_memory

.sbss2 (NOLOAD) : {
   . = ALIGN(4);
   __sbss2_start = .;
   *(.sbss2)
   *(.sbss2.*)
   *(.gnu.linkonce.sb2.*)
   __sbss2_end = .;
} > microblaze_local_memory

.data : {
   . = ALIGN(4);
   __data_start = .;
   *(.data)
   *(.data.*)
   *(.gnu.linkonce.d.*)
   __data_end = .;
} > microblaze_local_memory

.got : {
   *(.got)
} > microblaze_local_memory

.got1 : {
   *(.got1)
} > microblaze_local_memory

.got2 : {
   *(.got2)
} > microblaze_local_memory

.eh_frame : {
   *(.eh_frame)
} > microblaze_local_memory

.jcr : {
   *(.jcr)
} > microblaze_local_memory

.gcc_except_table : {
   *(.gcc_except_table)
} > microblaze_local_memory

.preinit_array : {
   . = ALIGN(8);
   __preinit_array_start = .;
   KEEP (*(SORT(.preinit_array.*)))
   KEEP (*(.preinit_array))
   __preinit_array_end = .;
} > microblaze_local_memory

.init_array : {
   . = ALIGN(8);
   __init_array_start = .;
   KEEP (*(SORT(.init_array.*)))
   KEEP (*(.init_array))
   __init_array_end = .;
} > microblaze_local_memory

.fini_array : {
   . = ALIGN(8);
   __fini_array_start = .;
   KEEP (*(SORT(.fini_array.*)))
   KEEP (*(.fini_array))
   __fini_array_end = .;
} > microblaze_local_memory

.sdata : {
   . = ALIGN(8);
   __sdata_start = .;
   *(.sdata)
   *(.sdata.*)
   *(.gnu.linkonce.s.*)
   __sdata_end = .;
} > microblaze_local_memory

.sbss (NOLOAD) : {
   . = ALIGN(4);
   __sbss_start = .;
   *(.sbss)
   *(.sbss.*)
   *(.gnu.linkonce.sb.*)
   . = ALIGN(8);
   __sbss_end = .;
} > microblaze_local_memory

.tdata : {
   __tdata_start = .;
   *(.tdata)
   *(.tdata.*)
   *(.gnu.linkonce.td.*)
   __tdata_end = .;
} > microblaze_local_memory

.tbss : {
   __tbss_start = .;
   *(.tbss)
   *(.tbss.*)
   *(.gnu.linkonce.tb.*)
   __tbss_end = .;
} > microblaze_local_memory

.bss (NOLOAD) : {
   . = ALIGN(4);
   __bss_start = .;
   __bss_start__ = .;
   *(.bss)
   *(.bss.*)
   *(.gnu.linkonce.b.*)
   *(COMMON)
   . = ALIGN(4);
   __bss_end = .;
   __bss_end__ = .;
} > microblaze_local_memory

.heap (NOLOAD) : {
   . = ALIGN(8);
   _heap = .;
   _heap_start = .;
   HeapBase = .;
   . += _HEAP_SIZE;
   HeapLimit = .;
   _heap_end = .;
} > microblaze_local_memory

.stack (NOLOAD) : {
   . = ALIGN(8);
   _stack_end = .;
   . += _STACK_SIZE;
   _stack = .;
   __stack = .;
} > microblaze_local_memory

_SDA_BASE_ = __sdata_start + ((__sbss_end - __sdata_start) / 2);
_SDA2_BASE_ = __sdata2_start + ((__sbss2_end - __sdata2_start) / 2);
_end = .;
end = .;
}
