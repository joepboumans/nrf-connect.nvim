-- The NCS version a Workspace's Manifest pins, and the NCS toolchain that matches it.
--
-- The version is the `nrf` project's revision as the Manifest writes it. When nrf is
-- the manifest repo itself (the default `west init -m sdk-nrf` layout) the Manifest
-- says nothing about it, so its checkout is used: `git describe --tags`, falling back
-- to nrf/VERSION.
local process = require("zephyr.process")

local M = {}

---@class nrf.NcsVersion
---@field version string e.g. "v3.0.2", a fork branch, a SHA or a `git describe` string
---@field official boolean true for an official release tag (vX.Y.Z, -rcN, -previewN, -devN)
---@field source "manifest"|"git"|"VERSION" where the version came from
---@field path string absolute path of the nrf checkout

-- Fields of `west list -f`, joined with "|" (west does not expand "\t").
M.list_format = "{name}|{path}|{revision}|{abspath}"

local official_patterns = {
	"^v%d+%.%d+%.%d+$",
	"^v%d+%.%d+%.%d+%-rc%d+$",
	"^v%d+%.%d+%.%d+%-preview%d*$",
	"^v%d+%.%d+%.%d+%-dev%d*$",
}

---Whether `revision` is an official NCS release tag rather than a custom revision.
---@param revision string|nil
---@return boolean
function M.is_official(revision)
	for _, pattern in ipairs(official_patterns) do
		if revision and revision:match(pattern) then
			return true
		end
	end
	return false
end

---Parse one line of `west list -f M.list_format`.
---@param text string
---@return { name: string, path: string, revision: string, abspath: string }|nil
function M.parse_list(text)
	for line in vim.gsplit(text or "", "\n", { plain = true, trimempty = true }) do
		local name, path, revision, abspath = vim.trim(line):match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
		if name then
			return { name = name, path = path, revision = revision, abspath = abspath }
		end
	end
	return nil
end

---Parse nrf/VERSION (`VERSION_MAJOR = 3` ...) into "v3.4.99" (plus "-EXTRAVERSION" when set).
---@param text string
---@return string|nil
function M.parse_version_file(text)
	local fields = {}
	for line in vim.gsplit(text or "", "\n", { plain = true }) do
		local key, value = line:match("^%s*([%u_]+)%s*=%s*(.-)%s*$")
		if key then
			fields[key] = value
		end
	end
	if not (fields.VERSION_MAJOR and fields.VERSION_MINOR) then
		return nil
	end
	local version = ("v%s.%s.%s"):format(fields.VERSION_MAJOR, fields.VERSION_MINOR, fields.PATCHLEVEL or "0")
	if fields.EXTRAVERSION and fields.EXTRAVERSION ~= "" then
		version = version .. "-" .. fields.EXTRAVERSION
	end
	return version
end

local function read(path)
	local fd = io.open(path, "r")
	if not fd then
		return nil
	end
	local text = fd:read("*a")
	fd:close()
	return text
end

local function failure(res, what)
	local msg = vim.trim(res.stderr ~= "" and res.stderr or res.stdout or "")
	return what .. " failed" .. (msg ~= "" and (": " .. msg) or "")
end

---The checked-out version of the manifest repo nrf: its tag, else nrf/VERSION.
local function checkout_version(path, cb)
	process.run({ "git", "-C", path, "describe", "--tags" }, {}, function(res)
		local described = res.code == 0 and vim.trim(res.stdout or "") or ""
		if described ~= "" then
			return cb({ version = described, official = M.is_official(described), source = "git", path = path })
		end
		-- No tag reachable (e.g. a shallow clone): VERSION names the release line, not a tag.
		local version = M.parse_version_file(read(vim.fs.joinpath(path, "VERSION")) or "")
		if version then
			return cb({ version = version, official = false, source = "VERSION", path = path })
		end
		cb(nil, failure(res, "git describe"))
	end)
end

---Find the NCS version of `workspace`. Runs west (and maybe git) in the background.
---@param workspace zephyr.Workspace
---@param cb fun(info: nrf.NcsVersion|nil, err: string|nil)
function M.version(workspace, cb)
	local cmd = { "west", "list", "-f", M.list_format, "nrf" }
	process.run(cmd, { cwd = workspace.topdir }, function(res)
		local project = res.code == 0 and M.parse_list(res.stdout) or nil
		if not project then
			return cb(nil, res.code == 0 and "no nrf project in the Manifest" or failure(res, "west list"))
		end
		if project.name == "manifest" then
			return checkout_version(project.abspath, cb)
		end
		cb({
			version = project.revision,
			official = M.is_official(project.revision),
			source = "manifest",
			path = project.abspath,
		})
	end)
end

---The nrf checkout of `workspace`, found from the Manifest file without running
---west: the project named `nrf` (or `sdk-nrf`), else the manifest repository
---itself when it holds a VERSION file (the `west init -m sdk-nrf` layout).
---@param workspace zephyr.Workspace
---@return string|nil dir, zephyr.ManifestProject|nil project nil when nrf is the manifest repository
function M.nrf_dir(workspace)
	local zm = require("zephyr.manifest")
	local m = zm.of(workspace)
	if m then
		for _, name in ipairs({ "nrf", "sdk-nrf" }) do
			local p = zm.project(m, name)
			if p then
				return zm.project_dir(workspace, p), p
			end
		end
	end
	if workspace.manifest_dir and vim.uv.fs_stat(workspace.manifest_dir .. "/VERSION") then
		return workspace.manifest_dir, nil
	end
	return nil
end

---The first version-looking part of a revision: "vt-v2.9.2-v1.5" gives "v2.9.2".
---@param revision string|nil
---@return string|nil
function M.version_in(revision)
	local v = revision and revision:match("(%d+%.%d+%.%d+)")
	return v and ("v" .. v) or nil
end

---The NCS release a Workspace's checkout is, without running west or git:
---`<nrf>/VERSION` (a fork may pin a branch or SHA), else the version-looking
---part of the nrf revision in the Manifest.
---@param workspace zephyr.Workspace
---@return string|nil e.g. "v2.9.2"
function M.workspace_version(workspace)
	local dir, project = M.nrf_dir(workspace)
	local from_file = dir and M.parse_version_file(read(vim.fs.joinpath(dir, "VERSION")) or "")
	if from_file then
		return from_file:match("^v%d+%.%d+%.%d+")
	end
	return project and M.version_in(project.revision) or nil
end

---The installed NCS toolchain for an NCS version, if any.
---@param version string
---@return nrf.NcsToolchain|nil
function M.toolchain_for(version)
	local want = version:gsub("^v", "")
	for _, tc in ipairs(require("nrf.toolchain").find()) do
		if tc.ncs_version and tc.ncs_version:gsub("^v", "") == want then
			return tc
		end
	end
	return nil
end

---The installed NCS toolchain matching the Workspace's NCS version. nil for a custom
---revision (pick one with `:Nrf toolchain select`) or when none is installed.
---@param workspace zephyr.Workspace
---@param cb fun(toolchain: nrf.NcsToolchain|nil, info: nrf.NcsVersion|nil, err: string|nil)
function M.suggest_toolchain(workspace, cb)
	M.version(workspace, function(info, err)
		if not info then
			return cb(nil, nil, err)
		end
		cb(info.official and M.toolchain_for(info.version) or nil, info)
	end)
end

-- Last NCS version seen per Workspace topdir, this session only.
local seen = {}

---Forget the remembered NCS versions.
function M.reset()
	seen = {}
end

---The NCS version last seen for a Workspace, if any.
---@param topdir string
---@return string|nil
function M.last_seen(topdir)
	return seen[topdir]
end

local function notify(msg, level)
	vim.notify("nrf: " .. msg, level or vim.log.levels.INFO)
end

---Tell the user which toolchain fits the new version; never switches it.
local function suggest(workspace, info, old)
	local head = ("NCS version changed %s -> %s"):format(old, info.version)
	if not info.official then
		return notify(head .. " (custom revision); pick a toolchain with :Nrf toolchain select")
	end
	local tc = M.toolchain_for(info.version)
	if not tc then
		return notify(("%s; install its toolchain with :Nrf toolchain install %s"):format(head, info.version))
	end
	local active = require("zephyr.toolchain").active(workspace)
	if active and active.id == tc.id then
		return notify(head .. "; the active toolchain already matches")
	end
	notify(("%s; run :Nrf ncs to activate %s"):format(head, tc.name))
end

---Look up the NCS version of `workspace` and remember it. When it differs from the one
---seen before, emit `NrfNcsVersionChanged` and suggest the matching toolchain.
---@param workspace zephyr.Workspace
---@param cb? fun(info: nrf.NcsVersion|nil, changed: boolean)
function M.check(workspace, cb)
	M.version(workspace, function(info)
		local old = seen[workspace.topdir]
		local changed = info ~= nil and old ~= nil and old ~= info.version
		if info then
			seen[workspace.topdir] = info.version
		end
		if changed then
			require("nrf").emit(
				"NcsVersionChanged",
				{ workspace = workspace.topdir, old = old, new = info.version, official = info.official }
			)
			suggest(workspace, info, old)
		end
		if cb then
			cb(info, changed)
		end
	end)
end

---The Workspace whose Manifest is `file`, if it is one.
local function manifest_workspace(file)
	if file == "" then
		return nil
	end
	file = vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))
	local ws = require("zephyr.workspace").find(file)
	if ws and vim.fs.normalize(ws.manifest_file) == file then
		return ws
	end
	return nil
end

M.augroup = "nrf_ncs"

---Watch Manifests: remember the NCS version when one is opened and compare on save.
---@param enabled boolean false only clears the autocmds
function M.watch(enabled)
	local group = vim.api.nvim_create_augroup(M.augroup, { clear = true })
	if not enabled then
		return
	end
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		group = group,
		pattern = { "*.yml", "*.yaml" },
		desc = "nrf: track the NCS version a Manifest pins",
		callback = function(ev)
			local ws = manifest_workspace(ev.match)
			if ws then
				M.check(ws)
			end
		end,
	})
end

return M
