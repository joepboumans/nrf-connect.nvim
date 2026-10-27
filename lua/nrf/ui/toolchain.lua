-- Default UI for `:Nrf toolchain list|select|install <version>`.
local ncs = require("nrf.toolchain")

local M = {}

M.actions = { "list", "select", "install" }

local function notify(msg, level)
	vim.notify("nrf: " .. msg, level or vim.log.levels.INFO)
end

local function label(tc)
	return ("%s  (%s)"):format(tc.name, tc.path)
end

local none = "no NCS toolchains found; try :Nrf toolchain install <version>"

---List installed NCS toolchains, marking the active Build configuration's Toolchain. Asks nrfutil again.
function M.list()
	ncs.refresh()
	local subject = require("nrf.ui.target").subject()
	local active = subject and require("zephyr.toolchain").active(subject)
	local lines = {}
	for _, tc in ipairs(ncs.find()) do
		local mark = active and tc.id == active.id and "* " or "  "
		table.insert(lines, mark .. label(tc))
	end
	notify(#lines > 0 and ("NCS toolchains:\n" .. table.concat(lines, "\n")) or none)
end

---Pick an NCS toolchain for the active Build configuration (of the current App,
---else of the Workspace's Active app). Any installed toolchain can be picked,
---whatever NCS version the Workspace pins.
function M.select()
	local ws, app, cfg = require("nrf.ui.target").find()
	if not ws and not app then
		return notify("not inside a west workspace", vim.log.levels.ERROR)
	end
	if not cfg then
		return notify("no build configuration yet; try :Zephyr build new", vim.log.levels.WARN)
	end
	local all = ncs.find()
	if #all == 0 then
		return notify(none, vim.log.levels.WARN)
	end
	vim.ui.select(all, { prompt = "NCS toolchain for " .. cfg.name, format_item = label }, function(choice)
		if choice then
			require("zephyr.toolchain").activate(app, cfg, choice)
			notify(("toolchain of %s: %s"):format(cfg.name, choice.name))
		end
	end)
end

---@param version string|nil
function M.install(version)
	if not version then
		return notify("usage: :Nrf toolchain install <version>, e.g. v3.0.2", vim.log.levels.ERROR)
	end
	notify("installing NCS toolchain " .. version .. " ...")
	ncs.install({ version = version }, function(ok, msg)
		notify(msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
	end)
end

---@param args string[]
function M.run(args)
	local action = args[1] or "select"
	if action == "list" then
		M.list()
	elseif action == "select" then
		M.select()
	elseif action == "install" then
		M.install(args[2])
	else
		notify(("unknown action '%s'; use %s"):format(action, table.concat(M.actions, "|")), vim.log.levels.ERROR)
	end
end

return M
