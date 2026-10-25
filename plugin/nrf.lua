if vim.g.loaded_nrf then
	return
end
vim.g.loaded_nrf = true

local subcommands = { "ncs", "toolchain" }

-- Implemented subcommands: handler and the words that can follow it.
local handlers = {
	toolchain = {
		run = function(args)
			require("nrf.ui.toolchain").run(args)
		end,
		actions = { "list", "select", "install" },
	},
}

local function matching(words, arglead)
	return vim.tbl_filter(function(w)
		return vim.startswith(w, arglead)
	end, words)
end

vim.api.nvim_create_user_command("Nrf", function(opts)
	local name = opts.fargs[1]
	if not vim.tbl_contains(subcommands, name) then
		vim.notify("Usage: :Nrf {" .. table.concat(subcommands, "|") .. "}", vim.log.levels.INFO)
		return
	end
	if handlers[name] then
		return handlers[name].run(vim.list_slice(opts.fargs, 2))
	end
	vim.notify(("nrf: '%s' is not implemented yet"):format(name), vim.log.levels.WARN)
end, {
	nargs = "*",
	desc = "nRF Connect: ncs, toolchain",
	complete = function(arglead, cmdline)
		local words = vim.split(vim.trim(cmdline), "%s+")
		local typed = #words - (arglead == "" and 0 or 1) -- words before the one being completed
		if typed <= 1 then
			return matching(subcommands, arglead)
		end
		local handler = handlers[words[2]]
		if typed == 2 and handler then
			return matching(handler.actions, arglead)
		end
		return {}
	end,
})
