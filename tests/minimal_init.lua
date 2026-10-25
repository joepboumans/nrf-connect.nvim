local plenary = vim.env.PLENARY_DIR or "/tmp/plenary.nvim"
local zephyr = vim.env.ZEPHYR_DIR or "/tmp/zephyr.nvim"
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(zephyr)
vim.opt.rtp:prepend(plenary)
vim.cmd("runtime plugin/plenary.vim")
vim.cmd("runtime plugin/zephyr.lua")
vim.cmd("runtime plugin/nrf.lua")
