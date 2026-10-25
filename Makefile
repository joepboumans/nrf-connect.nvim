PLENARY_DIR ?= /tmp/plenary.nvim
ZEPHYR_DIR ?= ../zephyr.nvim
NVIM ?= nvim

.PHONY: test
test: $(PLENARY_DIR)
	PLENARY_DIR=$(PLENARY_DIR) ZEPHYR_DIR=$(abspath $(ZEPHYR_DIR)) $(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

$(PLENARY_DIR):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)
