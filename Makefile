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
