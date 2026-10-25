local M = {}

---@class nrf.Config
M.config = {}

---@param opts? nrf.Config
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	local ok, zephyr = pcall(require, "zephyr")
	if not ok then
		vim.notify("nrf-connect.nvim needs zephyr.nvim; see :checkhealth nrf", vim.log.levels.ERROR)
		return
	end
	zephyr.registry.register("toolchain_provider", require("nrf.toolchain").provider)
	zephyr.registry.register("probe_finder", require("nrf.probes").finder)
end

---Fire a `User` autocmd named `Nrf<Event>` with details in `ev.data`.
---@param event string e.g. "NcsVersionChanged"
---@param data? table
function M.emit(event, data)
	vim.api.nvim_exec_autocmds("User", { pattern = "Nrf" .. event, data = data or {} })
end

return M
