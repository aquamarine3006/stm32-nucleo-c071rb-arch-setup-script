ENTRY(Reset_Handler)

_Min_Heap_Size  = 0x200;
_Min_Stack_Size = 0x400;

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 128K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 24K
}

PROVIDE(_estack = ORIGIN(RAM) + LENGTH(RAM));

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        KEEP(*(.isr_vector))
        . = ALIGN(4);
        *(.text*)
        KEEP(*(.init))
        KEEP(*(.fini))
        *(.rodata*)

        . = ALIGN(4);
        _preinit_array_start = .;
        KEEP(*(.preinit_array))
        _preinit_array_end = .;

        . = ALIGN(4);
        _init_array_start = .;
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
        _init_array_end = .;

        . = ALIGN(4);
        _fini_array_start = .;
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array))
        _fini_array_end = .;

        . = ALIGN(4);
        _etext = .;
    } > FLASH

    /* LMA of .data initialiser image in FLASH */
    _sidata = LOADADDR(.data);

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > FLASH

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Heap then stack — assert catches overflow at link time */
    ._user_heap_stack (NOLOAD) :
    {
        . = ALIGN(4);
        PROVIDE(end  = .);
        PROVIDE(_end = .);
        . = . + _Min_Heap_Size;
        . = . + _Min_Stack_Size;
        . = ALIGN(4);
    } > RAM

    ASSERT(. <= ORIGIN(RAM) + LENGTH(RAM), "RAM overflow: reduce heap/stack or code size")

    /DISCARD/ :
    {
        *(.ARM.exidx*)
        *(.ARM.extab*)
        *(.note*)
        *(.comment*)
    }
}
