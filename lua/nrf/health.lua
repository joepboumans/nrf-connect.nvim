local M = {}

function M.check()
	vim.health.start("nrf-connect.nvim")
	if pcall(require, "zephyr") then
		vim.health.ok("zephyr.nvim found")
	else
		vim.health.error("zephyr.nvim not found", "Install joepboumans/zephyr.nvim and list it as a dependency")
		return
	end
	if vim.fn.executable("nrfutil") == 1 then
		local res = require("nrf.toolchain").run_sync({ "nrfutil", "--version" }, 5000)
		vim.health.ok(("`nrfutil` found (%s)"):format(vim.trim((res.stdout or ""):match("[^\n]*") or "")))
	else
		vim.health.warn("`nrfutil` not found on PATH; NCS toolchains and Nordic probes are unavailable")
	end

	vim.health.start("nrf-connect.nvim: NCS toolchains")
	local toolchain = require("nrf.toolchain")
	toolchain.reset()
	local command = toolchain.command()
	if not command then
		vim.health.warn(
			"Neither `nrfutil sdk-manager` nor `nrfutil toolchain-manager` is available",
			"Run `nrfutil install sdk-manager` (NCS 3.0+) or `nrfutil install toolchain-manager`"
		)
		return
	end
	vim.health.ok(("Using `%s` (%s)"):format(table.concat(command.argv, " "), command.version))
	local found = toolchain.find()
	if #found == 0 then
		vim.health.warn("No NCS toolchains installed", "Run `:Nrf toolchain install <version>`")
	end
	for _, tc in ipairs(found) do
		vim.health.info(("%s (%s)"):format(tc.name, tc.path))
	end
end

return M
