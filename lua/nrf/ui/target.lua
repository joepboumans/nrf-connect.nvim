-- The Build configuration whose Toolchain the default UI shows and changes:
-- the active one of the App around the current file, else of the Workspace's
-- Active app (both kept by zephyr.nvim).
local M = {}

---@return zephyr.Workspace|nil ws, zephyr.App|nil app, zephyr.BuildConfig|nil cfg
function M.find()
	local ws = require("zephyr.workspace").find()
	local app_mod = require("zephyr.app")
	local app = app_mod.find() or (ws and app_mod.active(ws)) or nil
	local cfg = app and require("zephyr.build_config").active(app) or nil
	return ws, app, cfg
end

---What zephyr.toolchain.active() takes: the App when there is one, else the Workspace.
---@return zephyr.App|zephyr.Workspace|nil
function M.subject()
	local ws, app = M.find()
	return app or ws
end

return M
