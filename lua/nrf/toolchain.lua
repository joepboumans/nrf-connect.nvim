-- NCS toolchain provider for zephyr.nvim. Stubs until build-order step 7.
local M = {}

M.provider = {
	name = "ncs",
	---@return table[] installed NCS toolchains
	find = function()
		return {}
	end,
	---@return table<string, string> environment for builds with this toolchain
	env = function(_toolchain)
		return {}
	end,
}

return M
