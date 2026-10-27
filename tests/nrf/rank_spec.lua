local ncs = require("nrf.ncs")
local toolchain = require("nrf.toolchain")

local function tc(version)
	return {
		provider = "ncs",
		id = "ncs-" .. version .. "@/t/" .. version,
		name = "NCS toolchain " .. version,
		version = version,
		ncs_version = version,
		path = "/t/" .. version,
	}
end

-- Newest first, as toolchain.find() gives them.
local installed = { tc("v3.0.0"), tc("v2.9.2"), tc("v2.6.1") }

local function versions(list)
	return vim.tbl_map(function(t)
		return t.version
	end, list)
end

describe("ranking NCS toolchains for a Workspace", function()
	local topdir, ws

	before_each(function()
		topdir = vim.fs.normalize(vim.fn.tempname())
		vim.fn.mkdir(topdir .. "/.west", "p")
		vim.fn.mkdir(topdir .. "/app", "p")
		vim.fn.mkdir(topdir .. "/nrf", "p")
		vim.fn.writefile({ "[manifest]", "path = app", "file = west.yml" }, topdir .. "/.west/config")
		vim.fn.writefile({
			"manifest:",
			"  projects:",
			"    - name: nrf",
			"      revision: vt-v2.9.2-v1.5",
			"      import: true",
		}, topdir .. "/app/west.yml")
		vim.fn.writefile({ "VERSION_MAJOR = 2", "VERSION_MINOR = 9", "PATCHLEVEL = 2", "EXTRAVERSION =" }, topdir .. "/nrf/VERSION")
		ws = require("zephyr.workspace").find(topdir)
	end)

	after_each(function()
		vim.fn.delete(topdir, "rf")
	end)

	it("puts the toolchain matching nrf/VERSION first", function()
		assert.are.equal("v2.9.2", ncs.workspace_version(ws))
		assert.are.same({ "v2.9.2", "v3.0.0", "v2.6.1" }, versions(toolchain.rank(vim.deepcopy(installed), ws)))
	end)

	it("falls back to the version in the Manifest's nrf revision", function()
		vim.fn.delete(topdir .. "/nrf/VERSION")
		assert.are.equal("v2.9.2", ncs.workspace_version(ws))
		assert.are.equal("v2.9.2", toolchain.rank(vim.deepcopy(installed), ws)[1].version)
	end)

	it("keeps the newest first when none matches", function()
		vim.fn.writefile({ "VERSION_MAJOR = 3", "VERSION_MINOR = 4", "PATCHLEVEL = 99" }, topdir .. "/nrf/VERSION")
		assert.are.same({ "v3.0.0", "v2.9.2", "v2.6.1" }, versions(toolchain.rank(vim.deepcopy(installed), ws)))
	end)

	it("reads VERSION of nrf as the manifest repository", function()
		vim.fn.writefile({ "[manifest]", "path = nrf", "file = west.yml" }, topdir .. "/.west/config")
		vim.fn.writefile({ "manifest:", "  projects: []" }, topdir .. "/nrf/west.yml")
		ws = require("zephyr.workspace").find(topdir)
		assert.are.equal("v2.9.2", ncs.workspace_version(ws))
	end)

	it("makes zephyr.nvim default to the matching NCS toolchain over newer ones and the Zephyr SDK", function()
		local registry = require("zephyr.registry")
		local saved_find = toolchain.find
		toolchain.find = function()
			return vim.deepcopy(installed)
		end
		registry._reset()
		registry.register("toolchain_provider", require("zephyr.sdk").provider)
		registry.register("toolchain_provider", toolchain.provider)
		local default = require("zephyr.toolchain").default(ws)
		toolchain.find = saved_find
		assert.are.equal("v2.9.2", default.version)
		assert.are.equal("ncs", default.provider)
	end)

	it("pulls the version-looking part out of a fork's revision", function()
		assert.are.equal("v2.9.2", ncs.version_in("vt-v2.9.2-v1.5"))
		assert.are.equal("v3.0.2", ncs.version_in("v3.0.2"))
		assert.is_nil(ncs.version_in("main"))
	end)
end)
