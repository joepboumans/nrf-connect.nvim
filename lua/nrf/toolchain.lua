-- NCS toolchain provider for zephyr.nvim, backed by `nrfutil`.
--
-- Supports `nrfutil sdk-manager toolchain ...` (NCS 3.0+) and the older
-- `nrfutil toolchain-manager ...`, whichever is installed (sdk-manager first).
--
-- zephyr.nvim's registry calls find() and env() synchronously. Both run nrfutil
-- through zephyr.process and wait at most `M.timeout_ms` for it, and cache what
-- they get: find() until refresh() or an install, env() per toolchain for the
-- session. A timed-out or failed call caches an empty list (find) or nothing (env).
local process = require("zephyr.process")

local M = {}

M.provider_name = "ncs"

---How long a synchronous nrfutil call (detect, list, env) may take.
M.timeout_ms = 15000

---@class nrf.NcsToolchain: zephyr.Toolchain
---@field ncs_version string|nil NCS release tag the toolchain belongs to, e.g. "v2.6.1"
---@field bundle_id string toolchain bundle id (the directory name under `toolchains/`)

---@class nrf.NrfutilCommand
---@field name "sdk-manager"|"toolchain-manager"
---@field argv string[] prefix for toolchain subcommands, e.g. { "nrfutil", "sdk-manager", "toolchain" }

local cache = {}

---Forget cached nrfutil detection, toolchain list and environments.
function M.reset()
	cache = {}
end

---Forget the cached toolchain list so the next find() asks nrfutil again.
function M.refresh()
	cache.toolchains = nil
end

local function install_dir()
	local ok, nrf = pcall(require, "nrf")
	return ok and nrf.config and nrf.config.install_dir or nil
end

---Run `cmd` and wait for it, at most `M.timeout_ms`.
---@return vim.SystemCompleted
local function run_sync(cmd)
	local result
	process.run(cmd, { timeout = M.timeout_ms }, function(res)
		result = res
	end)
	local done = vim.wait(M.timeout_ms + 100, function()
		return result ~= nil
	end, 10)
	if not done then
		return { code = -1, signal = 0, stdout = "", stderr = "timed out after " .. M.timeout_ms .. " ms" }
	end
	return result
end

---Decode nrfutil's NDJSON output (one `{ type, data }` object per line), skipping lines that are not JSON.
---@param text string
---@return { type: string, data: table }[]
function M.decode_ndjson(text)
	local out = {}
	for line in vim.gsplit(text or "", "\n", { plain = true, trimempty = true }) do
		local ok, obj = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
		if ok and type(obj) == "table" and type(obj.type) == "string" then
			table.insert(out, obj)
		end
	end
	return out
end

---Which nrfutil command manages toolchains here, checked once per session.
---@return nrf.NrfutilCommand|nil
function M.command()
	if cache.command ~= nil then
		return cache.command or nil
	end
	cache.command = false
	if vim.fn.executable("nrfutil") == 1 then
		if run_sync({ "nrfutil", "sdk-manager", "--version" }).code == 0 then
			cache.command = { name = "sdk-manager", argv = { "nrfutil", "sdk-manager", "toolchain" } }
		elseif run_sync({ "nrfutil", "toolchain-manager", "--version" }).code == 0 then
			cache.command = { name = "toolchain-manager", argv = { "nrfutil", "toolchain-manager" } }
		end
	end
	return cache.command or nil
end

---Build `<toolchain command> <args...> [--install-dir D]`.
local function argv(command, args)
	local cmd = vim.list_extend(vim.deepcopy(command.argv), args)
	local dir = install_dir()
	if dir then
		vim.list_extend(cmd, { "--install-dir", vim.fs.normalize(dir) })
	end
	return cmd
end

local function to_toolchain(entry)
	if type(entry) ~= "table" or type(entry.path) ~= "string" then
		return nil
	end
	local path = vim.fs.normalize(entry.path)
	local version = entry.ncs_version or entry.ncsVersion or entry.version
	local bundle = entry.toolchain_bundle_id or entry.identifier or vim.fs.basename(path)
	return {
		provider = M.provider_name,
		id = "ncs-" .. (version or bundle) .. "@" .. path,
		name = "NCS toolchain " .. (version or bundle),
		version = version or bundle,
		path = path,
		ncs_version = version,
		bundle_id = bundle,
	}
end

---Parse `list --json` output into Toolchains.
---@param text string
---@return nrf.NcsToolchain[]
function M.parse_list(text)
	local out = {}
	for _, msg in ipairs(M.decode_ndjson(text)) do
		local data = msg.data
		if msg.type == "task_end" and type(data) == "table" then
			data = data.data
		end
		if type(data) == "table" and type(data.toolchains) == "table" then
			for _, entry in ipairs(data.toolchains) do
				table.insert(out, to_toolchain(entry))
			end
		end
	end
	return out
end

---Compare "v2.6.1"-style versions numerically, newest first; bundles without a version last.
local function newer(a, b)
	if (a.ncs_version == nil) ~= (b.ncs_version == nil) then
		return a.ncs_version ~= nil
	end
	local pa, pb = vim.split((a.version:gsub("^v", "")), "[.-]"), vim.split((b.version:gsub("^v", "")), "[.-]")
	for i = 1, math.max(#pa, #pb) do
		local x, y = tonumber(pa[i]) or 0, tonumber(pb[i]) or 0
		if x ~= y then
			return x > y
		end
	end
	return a.path < b.path
end

---Installed NCS toolchains, newest first. Cached; see refresh().
---@return nrf.NcsToolchain[]
function M.find()
	if cache.toolchains then
		return cache.toolchains
	end
	local found = {}
	local command = M.command()
	if command then
		local res = run_sync(argv(command, { "list", "--json" }))
		if res.code == 0 then
			found = M.parse_list(res.stdout)
			table.sort(found, newer)
		end
	end
	cache.toolchains = found
	return found
end

---Expand `$VAR` and `${VAR}` against `vars`, then Neovim's environment.
local function expand(value, vars)
	local function lookup(name)
		return vars[name] or vim.env[name] or ""
	end
	value = value:gsub("%${([%w_]+)}", lookup)
	return (value:gsub("%$([%a_][%w_]*)", lookup))
end

---Parse the `export VAR=value` lines that `env --as-script sh` prints.
---@param text string
---@return table<string, string>
function M.parse_env(text)
	local vars = {}
	for line in vim.gsplit(text or "", "\n", { plain = true }) do
		local name, value = vim.trim(line):match("^export%s+([%a_][%w_]*)=(.*)$")
		if name then
			local single = value:match("^'(.*)'$")
			if single then
				vars[name] = single
			else
				vars[name] = expand(value:match('^"(.*)"$') or value, vars)
			end
		end
	end
	return vars
end

---Arguments that pick `toolchain`: its NCS version, or its bundle id when it has none (e.g. for an NCS fork).
local function selector(toolchain)
	if toolchain.ncs_version then
		return { "--ncs-version", toolchain.ncs_version }
	end
	return { "--toolchain-bundle-id", toolchain.bundle_id or vim.fs.basename(toolchain.path) }
end

---Environment for building with `toolchain`, from `nrfutil ... env --as-script sh`. Cached per toolchain.
---It does not set ZEPHYR_BASE; west finds Zephyr from the Workspace.
---@param toolchain nrf.NcsToolchain
---@return table<string, string>|nil nil when nrfutil is missing or fails
function M.env(toolchain)
	cache.env = cache.env or {}
	if cache.env[toolchain.id] then
		return cache.env[toolchain.id]
	end
	local command = M.command()
	if not command then
		return nil
	end
	local args = vim.list_extend({ "env", "--as-script", "sh" }, selector(toolchain))
	local res = run_sync(argv(command, args))
	if res.code ~= 0 then
		return nil
	end
	local vars = M.parse_env(res.stdout)
	cache.env[toolchain.id] = vars
	return vars
end

---Normalize "3.0.2" to "v3.0.2"; leaves other strings alone.
local function tag(version)
	return version:match("^%d") and ("v" .. version) or version
end

---Install the NCS toolchain for an NCS version. Runs in the background.
---Emits `NrfToolchainInstalled` with `{ provider, version, path }` on success.
---@param opts { version: string }
---@param on_done fun(ok: boolean, message: string)
function M.install(opts, on_done)
	local command = M.command()
	if not command then
		return on_done(false, "nrfutil with sdk-manager or toolchain-manager not found")
	end
	if not opts.version or opts.version == "" then
		return on_done(false, "an NCS version is required, e.g. v3.0.2")
	end
	local version = tag(opts.version)
	process.run(argv(command, { "install", "--ncs-version", version, "--json" }), {}, function(res)
		local ok, message, path = res.code == 0, nil, nil
		for _, msg in ipairs(M.decode_ndjson(res.stdout)) do
			if msg.type == "task_end" and type(msg.data) == "table" then
				local data = msg.data
				if data.result == "fail" then
					ok = false
					message = data.error and data.error.description or data.message
				elseif data.task and type(data.task.data) == "table" then
					path = data.task.data.install_path or path
				end
			end
		end
		if not ok then
			local stderr = vim.trim(res.stderr or "")
			return on_done(false, message or (stderr ~= "" and stderr) or "nrfutil install failed")
		end
		M.refresh()
		require("nrf").emit("ToolchainInstalled", { provider = M.provider_name, version = version, path = path })
		on_done(true, "NCS toolchain " .. version .. " installed")
	end)
end

M.provider = {
	name = M.provider_name,
	find = function()
		return M.find()
	end,
	env = function(toolchain)
		return M.env(toolchain)
	end,
	install = function(opts, on_done)
		return M.install(opts, on_done)
	end,
}

return M
