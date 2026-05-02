#!/bin/bash

set -euo pipefail

die() {
    echo "ERROR: $*" >&2
    exit 1
}

read -rp "Install necessary packages? [y/N] " ans
if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    echo ">> syncing package database..."
    sudo pacman -Syy || die "Failed to sync package database"

    echo ">> installing packages..."
    sudo pacman -S --needed \
        arm-none-eabi-gcc \
        arm-none-eabi-newlib \
        arm-none-eabi-gdb || die "Failed to install packages"

    # yay may not be installed; check first
    if command -v yay &>/dev/null; then
        yay -S --needed openocd-git || die "Failed to install openocd-git"
    else
        echo ">> WARNING: 'yay' not found. Install openocd-git manually or install yay first."
    fi
fi

# Verify required tools are available
for tool in arm-none-eabi-gcc arm-none-eabi-objcopy openocd; do
    command -v "$tool" &>/dev/null || die "'$tool' not found. Re-run and choose to install packages."
done

echo ">> generating project files..."

# --------------------------------------------------------------------------
# startup_stm32c071xx.s
# - Correct vector table for STM32C071 (32 external IRQs) per RM0490
# - Cortex-M0+ safe post-increment via adds (no post-index LDR/STR)
# - __libc_init_array called after SystemInit, before main
# - Weak SystemInit stub so link succeeds if user omits it
# --------------------------------------------------------------------------
cat > startup_stm32c071xx.s << 'EOF'
.syntax unified
.cpu cortex-m0plus
.thumb

.global Reset_Handler
.global Default_Handler
.global g_pfnVectors

/* ========== VECTOR TABLE ========== */
.section .isr_vector,"a",%progbits
.type g_pfnVectors, %object

g_pfnVectors:
    .word _estack                           /* initial stack pointer */
    .word Reset_Handler                     /* Reset */
    .word NMI_Handler
    .word HardFault_Handler
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word SVC_Handler
    .word 0
    .word 0
    .word PendSV_Handler
    .word SysTick_Handler

    /* External interrupts — 32 entries per STM32C071 RM0490 Table 46 */
    .word WWDG_IRQHandler
    .word PVD_IRQHandler
    .word RTC_TAMP_IRQHandler
    .word FLASH_IRQHandler
    .word RCC_IRQHandler
    .word EXTI0_1_IRQHandler
    .word EXTI2_3_IRQHandler
    .word EXTI4_15_IRQHandler
    .word 0
    .word DMA1_Channel1_IRQHandler
    .word DMA1_Channel2_3_IRQHandler
    .word DMA1_Ch4_7_IRQHandler
    .word ADC1_IRQHandler
    .word TIM1_BRK_UP_TRG_COM_IRQHandler
    .word TIM1_CC_IRQHandler
    .word 0
    .word TIM3_IRQHandler
    .word TIM6_IRQHandler
    .word TIM7_IRQHandler
    .word TIM14_IRQHandler
    .word TIM15_IRQHandler
    .word TIM16_IRQHandler
    .word TIM17_IRQHandler
    .word I2C1_IRQHandler
    .word I2C2_IRQHandler
    .word SPI1_IRQHandler
    .word SPI2_IRQHandler
    .word USART1_IRQHandler
    .word USART2_IRQHandler
    .word USART3_4_IRQHandler
    .word 0
    .word USB_IRQHandler

.size g_pfnVectors, .-g_pfnVectors


/* ========== RESET HANDLER ========== */
.section .text.Reset_Handler
.weak Reset_Handler
.thumb_func
.type Reset_Handler, %function

Reset_Handler:
    /* Set stack pointer explicitly (safety for debuggers that skip vector load) */
    ldr   r0, =_estack
    mov   sp, r0

    /* Copy .data from FLASH to RAM
       r0 = dest (_sdata), r1 = limit (_edata), r2 = src (_sidata) */
    ldr   r0, =_sdata
    ldr   r1, =_edata
    ldr   r2, =_sidata
    b     CopyDataCheck

CopyDataLoop:
    ldr   r3, [r2]
    str   r3, [r0]
    adds  r0, r0, #4
    adds  r2, r2, #4

CopyDataCheck:
    cmp   r0, r1
    blo   CopyDataLoop

    /* Zero .bss
       r0 = start (_sbss), r1 = end (_ebss) */
    ldr   r0, =_sbss
    ldr   r1, =_ebss
    movs  r2, #0
    b     ZeroCheck

ZeroLoop:
    str   r2, [r0]
    adds  r0, r0, #4

ZeroCheck:
    cmp   r0, r1
    blo   ZeroLoop

    /* Clock / peripheral init */
    bl    SystemInit

    /* Run C static constructors + newlib init */
    bl    __libc_init_array

    /* Call application */
    bl    main

    /* Trap if main returns */
LoopForever:
    b     LoopForever

.size Reset_Handler, .-Reset_Handler


/* ========== WEAK SystemInit (user can override) ========== */
.section .text.SystemInit
.weak SystemInit
.thumb_func
.type SystemInit, %function
SystemInit:
    bx    lr
.size SystemInit, .-SystemInit


/* ========== DEFAULT HANDLER ========== */
.section .text.Default_Handler,"ax",%progbits
.thumb_func
.type Default_Handler, %function
Default_Handler:
    b     Default_Handler
.size Default_Handler, .-Default_Handler


/* ========== WEAK ALIASES ========== */
.weak NMI_Handler
.thumb_set NMI_Handler, Default_Handler

.weak HardFault_Handler
.thumb_set HardFault_Handler, Default_Handler

.weak SVC_Handler
.thumb_set SVC_Handler, Default_Handler

.weak PendSV_Handler
.thumb_set PendSV_Handler, Default_Handler

.weak SysTick_Handler
.thumb_set SysTick_Handler, Default_Handler

.weak WWDG_IRQHandler
.thumb_set WWDG_IRQHandler, Default_Handler
.weak PVD_IRQHandler
.thumb_set PVD_IRQHandler, Default_Handler
.weak RTC_TAMP_IRQHandler
.thumb_set RTC_TAMP_IRQHandler, Default_Handler
.weak FLASH_IRQHandler
.thumb_set FLASH_IRQHandler, Default_Handler
.weak RCC_IRQHandler
.thumb_set RCC_IRQHandler, Default_Handler
.weak EXTI0_1_IRQHandler
.thumb_set EXTI0_1_IRQHandler, Default_Handler
.weak EXTI2_3_IRQHandler
.thumb_set EXTI2_3_IRQHandler, Default_Handler
.weak EXTI4_15_IRQHandler
.thumb_set EXTI4_15_IRQHandler, Default_Handler
.weak DMA1_Channel1_IRQHandler
.thumb_set DMA1_Channel1_IRQHandler, Default_Handler
.weak DMA1_Channel2_3_IRQHandler
.thumb_set DMA1_Channel2_3_IRQHandler, Default_Handler
.weak DMA1_Ch4_7_IRQHandler
.thumb_set DMA1_Ch4_7_IRQHandler, Default_Handler
.weak ADC1_IRQHandler
.thumb_set ADC1_IRQHandler, Default_Handler
.weak TIM1_BRK_UP_TRG_COM_IRQHandler
.thumb_set TIM1_BRK_UP_TRG_COM_IRQHandler, Default_Handler
.weak TIM1_CC_IRQHandler
.thumb_set TIM1_CC_IRQHandler, Default_Handler
.weak TIM3_IRQHandler
.thumb_set TIM3_IRQHandler, Default_Handler
.weak TIM6_IRQHandler
.thumb_set TIM6_IRQHandler, Default_Handler
.weak TIM7_IRQHandler
.thumb_set TIM7_IRQHandler, Default_Handler
.weak TIM14_IRQHandler
.thumb_set TIM14_IRQHandler, Default_Handler
.weak TIM15_IRQHandler
.thumb_set TIM15_IRQHandler, Default_Handler
.weak TIM16_IRQHandler
.thumb_set TIM16_IRQHandler, Default_Handler
.weak TIM17_IRQHandler
.thumb_set TIM17_IRQHandler, Default_Handler
.weak I2C1_IRQHandler
.thumb_set I2C1_IRQHandler, Default_Handler
.weak I2C2_IRQHandler
.thumb_set I2C2_IRQHandler, Default_Handler
.weak SPI1_IRQHandler
.thumb_set SPI1_IRQHandler, Default_Handler
.weak SPI2_IRQHandler
.thumb_set SPI2_IRQHandler, Default_Handler
.weak USART1_IRQHandler
.thumb_set USART1_IRQHandler, Default_Handler
.weak USART2_IRQHandler
.thumb_set USART2_IRQHandler, Default_Handler
.weak USART3_4_IRQHandler
.thumb_set USART3_4_IRQHandler, Default_Handler
.weak USB_IRQHandler
.thumb_set USB_IRQHandler, Default_Handler
EOF

# --------------------------------------------------------------------------
# STM32C071RB.ld
# Fixes vs original:
# - _sidata defined as LOADADDR(.data) inside SECTIONS (not after), which is
#   the correct GLD syntax — placing it outside SECTIONS is undefined behaviour
#   in some linker versions.
# - .ARM.exidx explicitly kept (even if empty) so ld doesn't warn; then
#   discarded. Some ld versions error if you /DISCARD/ a section that has
#   no KEEP and gc-sections removes it first.
# - heap/stack section uses NOLOAD and a size assert to catch overflow.
# - Separate _Min_Heap_Size / _Min_Stack_Size symbols so user can override.
# --------------------------------------------------------------------------
cat > STM32C071RB.ld << 'EOF'
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
EOF

# --------------------------------------------------------------------------
# Makefile
# Fixes vs original:
# - ASFLAGS must NOT include -x assembler-with-cpp when passed via $(CC)
#   for plain .s files (no cpp needed); only .S files need it. Using it on
#   .s is harmless but flagged here for clarity — kept as opt-in comment.
# - Dependency (.d) files generated with -MMD -MP so incremental builds
#   correctly detect header changes.
# - $(BUILD_DIR) order-only prerequisite on every compile rule prevents
#   spurious rebuilds.
# - startup .s lives at project root, not inside SOURCE/, so its obj path
#   is handled separately to avoid a double-slash in the patsubst.
# - 'size' target added — shows section sizes after link, useful sanity check.
# --------------------------------------------------------------------------
cat > Makefile << 'EOF'
TARGET    = main
CC        = arm-none-eabi-gcc
OBJCOPY   = arm-none-eabi-objcopy
SIZE      = arm-none-eabi-size

PROJ_DIR  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD_DIR := $(PROJ_DIR)build

SRCS_C    := $(wildcard $(PROJ_DIR)SOURCE/*.c)
# .s files inside SOURCE/ (user assembly)
SRCS_S    := $(wildcard $(PROJ_DIR)SOURCE/*.s)
# Startup lives at project root — kept separate to get a clean obj path
STARTUP_S := $(PROJ_DIR)startup_stm32c071xx.s

OBJS_C    := $(patsubst $(PROJ_DIR)%.c, $(BUILD_DIR)/%.o, $(SRCS_C))
OBJS_S    := $(patsubst $(PROJ_DIR)%.s, $(BUILD_DIR)/%.o, $(SRCS_S))
OBJS_ST   := $(BUILD_DIR)/startup_stm32c071xx.o
OBJS      := $(OBJS_C) $(OBJS_S) $(OBJS_ST)

LDSCRIPT  := $(PROJ_DIR)STM32C071RB.ld

CFLAGS    := -mcpu=cortex-m0plus -mthumb -Og -g3 -Wall -Wextra \
             -ffunction-sections -fdata-sections \
             -MMD -MP \
             -I$(PROJ_DIR)INCLUDE

# Plain .s files: no C preprocessor needed.
# If your .s files use #include or #define, change to -x assembler-with-cpp
ASFLAGS   := -mcpu=cortex-m0plus -mthumb -g3

LDFLAGS   := -T$(LDSCRIPT) -mcpu=cortex-m0plus -mthumb \
             --specs=nano.specs --specs=nosys.specs \
             -Wl,--gc-sections,-Map=$(BUILD_DIR)/$(TARGET).map

all: $(BUILD_DIR)/$(TARGET).elf $(BUILD_DIR)/$(TARGET).bin
	@$(SIZE) $<

# Link
$(BUILD_DIR)/$(TARGET).elf: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

# Binary
$(BUILD_DIR)/$(TARGET).bin: $(BUILD_DIR)/$(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Compile C (with dependency tracking)
$(BUILD_DIR)/%.o: $(PROJ_DIR)%.c | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

# Assemble SOURCE/*.s
$(BUILD_DIR)/%.o: $(PROJ_DIR)%.s | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c -o $@ $<

# Assemble startup (root-level .s — explicit rule avoids path clash)
$(OBJS_ST): $(STARTUP_S) | $(BUILD_DIR)
	$(CC) $(ASFLAGS) -c -o $@ $<

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Pull in auto-generated dependency files
-include $(OBJS_C:.o=.d)

flash: $(BUILD_DIR)/$(TARGET).bin
	openocd -f "$(PROJ_DIR)openocd.cfg" \
	        -c "program \"$<\" 0x08000000 verify reset exit"

debug: $(BUILD_DIR)/$(TARGET).elf
	bash "$(PROJ_DIR)debug.sh"

size: $(BUILD_DIR)/$(TARGET).elf
	$(SIZE) $<

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all flash debug size clean
EOF

# --------------------------------------------------------------------------
# openocd.cfg
# Fix: Removed 'gdb_breakpoint_override hard' — deprecated in OpenOCD>=0.12,
#      causes a startup error. GDB negotiates BP type with the target itself.
# --------------------------------------------------------------------------
cat > openocd.cfg << 'EOF'
source [find interface/stlink.cfg]

transport select swd

adapter speed 2000

reset_config srst_only srst_nogate
adapter srst pulse_width 100

source [find target/stm32c0x.cfg]

gdb_memory_map enable
gdb_flash_program enable
EOF

# --------------------------------------------------------------------------
# debug/debug.gdb
# Fix: Added 'set mem inaccessible-by-default off' — prevents GDB errors
#      when reading peripheral registers outside the memory map.
# Fix: Added 'set print pretty on' for readable struct output.
# Order: load → break → continue (correct, same as original).
# --------------------------------------------------------------------------
mkdir -p debug

wget -q https://raw.githubusercontent.com/cyrus-and/gdb-dashboard/master/.gdbinit \
    -O debug/gdb-dashboard.gdb \
    || { echo ">> WARNING: Could not download gdb-dashboard. Continuing without it."; touch debug/gdb-dashboard.gdb; }

cat > debug/debug.gdb << 'EOF'
set mem inaccessible-by-default off
set print pretty on

target remote localhost:3333

monitor reset halt

load

break main

continue
EOF

# --------------------------------------------------------------------------
# debug.sh
# Fix: Added explicit READY flag — original could silently fall through the
#      loop and launch GDB even if OpenOCD never became ready.
# Fix: Renamed loop var to _i to avoid shadowing outer scope under set -u.
# Fix: GDB sources gdb-dashboard BEFORE debug.gdb so dashboard is init'd
#      before our commands run (order matters for the dashboard plugin).
# --------------------------------------------------------------------------
cat > debug.sh << 'EOF'
#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ">> Starting OpenOCD..."

openocd -f openocd.cfg > openocd.log 2>&1 &
OCD_PID=$!

cleanup() {
    echo ">> Stopping OpenOCD (pid $OCD_PID)..."
    kill "${OCD_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo ">> Waiting for OpenOCD to be ready (5 s timeout)..."

READY=0
for _i in $(seq 1 50); do
    if ! kill -0 "${OCD_PID}" 2>/dev/null; then
        echo "ERROR: OpenOCD exited unexpectedly. Log:"
        cat openocd.log >&2
        exit 1
    fi
    if grep -q "Listening on port 3333" openocd.log 2>/dev/null; then
        READY=1
        echo ">> OpenOCD ready"
        break
    fi
    sleep 0.1
done

if [[ "$READY" -eq 0 ]]; then
    echo "ERROR: OpenOCD did not become ready within 5 s. Log:"
    cat openocd.log >&2
    exit 1
fi

echo ">> Starting GDB..."

arm-none-eabi-gdb "$SCRIPT_DIR/build/main.elf" -q \
    -ex "set auto-load safe-path $SCRIPT_DIR" \
    -x "$SCRIPT_DIR/debug/gdb-dashboard.gdb" \
    -x "$SCRIPT_DIR/debug/debug.gdb"
EOF

chmod +x debug.sh

# --------------------------------------------------------------------------
# Project skeleton
# --------------------------------------------------------------------------
mkdir -p SOURCE INCLUDE

# Only write a placeholder main.c if none exists yet
if [[ ! -f SOURCE/main.c ]]; then
cat > SOURCE/main.c << 'EOF'
/* Replace with your application code */
int main(void)
{
    while (1) {}
}
EOF
fi

echo ""
echo ">> Done. Project structure:"
echo "   INCLUDE/               <- drop .h headers here"
echo "   SOURCE/                <- all .c / .s source files"
echo "   SOURCE/main.c"
echo "   startup_stm32c071xx.s"
echo "   STM32C071RB.ld"
echo "   Makefile"
echo "   openocd.cfg"
echo "   debug.sh"
echo "   debug/debug.gdb"
echo "   debug/gdb-dashboard.gdb"
echo ""
echo ">> Run:   make"
echo ">> Flash: make flash"
echo ">> Debug: make debug"
echo ">> Sizes: make size"
