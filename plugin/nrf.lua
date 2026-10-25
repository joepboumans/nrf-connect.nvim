if vim.g.loaded_nrf then
	return
end
vim.g.loaded_nrf = true

local subcommands = { "ncs", "toolchain" }

vim.api.nvim_create_user_command("Nrf", function(opts)
	local name = opts.fargs[1]
	if not vim.tbl_contains(subcommands, name) then
		vim.notify("Usage: :Nrf {" .. table.concat(subcommands, "|") .. "}", vim.log.levels.INFO)
		return
	end
	vim.notify(("nrf: '%s' is not implemented yet"):format(name), vim.log.levels.WARN)
end, {
	nargs = "*",
	desc = "nRF Connect: ncs, toolchain",
	complete = function(arglead, cmdline)
		if cmdline:match("^%s*Nrf!?%s+%S+%s") then
			return {}
		end
		return vim.tbl_filter(function(n)
			return vim.startswith(n, arglead)
		end, subcommands)
	end,
})
