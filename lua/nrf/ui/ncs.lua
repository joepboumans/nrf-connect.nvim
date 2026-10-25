-- Default UI for `:Nrf ncs`: show the NCS version and offer its matching toolchain.
local ncs = require("nrf.ncs")

local M = {}

local function notify(msg, level)
	vim.notify("nrf: " .. msg, level or vim.log.levels.INFO)
end

---Show the current Workspace's NCS version, whether it is official, and the Active
---toolchain; offer to activate the matching NCS toolchain when it is not active.
function M.show()
	local ws = require("zephyr.workspace").find()
	if not ws then
		return notify("not inside a west workspace", vim.log.levels.ERROR)
	end
	ncs.suggest_toolchain(ws, function(suggested, info, err)
		if not info then
			return notify("cannot find the NCS version: " .. (err or "unknown error"), vim.log.levels.ERROR)
		end
		local zt = require("zephyr.toolchain")
		local active = zt.active(ws)
		local lines = {
			("NCS version: %s (%s, from %s)"):format(
				info.version,
				info.official and "official release" or "custom revision",
				info.source
			),
			"Active toolchain: " .. (active and active.name or "none"),
		}
		if info.official and not suggested then
			local hint = "No NCS toolchain %s installed; run :Nrf toolchain install %s"
			table.insert(lines, hint:format(info.version, info.version))
		elseif not info.official then
			table.insert(lines, "Custom revision: pick a toolchain with :Nrf toolchain select")
		end
		notify(table.concat(lines, "\n"))
		if suggested and not (active and active.id == suggested.id) then
			local yes = "Activate " .. suggested.name
			vim.ui.select({ yes, "Keep the active toolchain" }, { prompt = "Matching NCS toolchain" }, function(choice)
				if choice == yes then
					zt.activate(ws, suggested)
					notify("active toolchain: " .. suggested.name)
				end
			end)
		end
	end)
end

---@param _ string[]
function M.run(_)
	M.show()
end

return M
