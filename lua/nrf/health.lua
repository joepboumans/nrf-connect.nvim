local M = {}

function M.check()
	vim.health.start("nrf-connect.nvim")
	if pcall(require, "zephyr") then
		vim.health.ok("zephyr.nvim found")
	else
		vim.health.error("zephyr.nvim not found", "Install joepboumans/zephyr.nvim and list it as a dependency")
	end
	if vim.fn.executable("nrfutil") == 1 then
		local res = vim.system({ "nrfutil", "--version" }, { text = true }):wait(5000)
		vim.health.ok(("`nrfutil` found (%s)"):format(vim.trim((res.stdout or ""):match("[^\n]*") or "")))
	else
		vim.health.warn("`nrfutil` not found on PATH; NCS toolchains and Nordic probes are unavailable")
	end
end

return M
