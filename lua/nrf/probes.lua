-- Nordic probe finder (`nrfutil device list`) for zephyr.nvim. Stub until step 7.
local M = {}

M.finder = {
	name = "nrfutil",
	---@return table[] connected probes
	find = function()
		return {}
	end,
}

return M
