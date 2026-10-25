local toolchain = require("nrf.toolchain")
local process = require("zephyr.process")

local fixtures = vim.fn.fnamemodify("tests/fixtures/nrfutil", ":p")

local function fixture(name)
	local fd = assert(io.open(fixtures .. name, "r"))
	local text = fd:read("*a")
	fd:close()
	return text
end

-- Stub nrfutil: `responses` maps a joined argv to a result (or a function returning one).
local calls, responses
local real_run, real_executable

local function respond(cmd)
	local key = table.concat(cmd, " ")
	table.insert(calls, key)
	local r = responses[key]
	if type(r) == "function" then
		r = r()
	end
	return vim.tbl_extend("force", { code = 1, signal = 0, stdout = "", stderr = "unknown command" }, r or {})
end

local function has_sdk_manager()
	responses["nrfutil sdk-manager --version"] = { code = 0, stdout = "nrfutil-sdk-manager 1.4.0\n" }
end

local function has_toolchain_manager()
	responses["nrfutil toolchain-manager --version"] = { code = 0, stdout = "nrfutil-toolchain-manager 0.15.0\n" }
end

describe("NCS toolchain provider", function()
	before_each(function()
		calls, responses = {}, {}
		toolchain.reset()
		real_run, real_executable = process.run, vim.fn.executable
		process.run = function(cmd, _, on_exit)
			on_exit(respond(cmd))
		end
		vim.fn.executable = function(name)
			return name == "nrfutil" and 1 or real_executable(name)
		end
	end)

	after_each(function()
		process.run, vim.fn.executable = real_run, real_executable
		require("nrf").config.install_dir = nil
		toolchain.reset()
	end)

	describe("command()", function()
		it("prefers sdk-manager", function()
			has_sdk_manager()
			has_toolchain_manager()
			assert.are.same({ "nrfutil", "sdk-manager", "toolchain" }, toolchain.command().argv)
		end)

		it("falls back to toolchain-manager", function()
			has_toolchain_manager()
			assert.are.equal("toolchain-manager", toolchain.command().name)
		end)

		it("records the manager's version for :checkhealth", function()
			has_toolchain_manager()
			assert.are.equal("nrfutil-toolchain-manager 0.15.0", toolchain.command().version)
		end)

		it(":checkhealth nrf reports the manager version", function()
			has_sdk_manager()
			local oks = {}
			local real_ok = vim.health.ok
			vim.health.ok = function(msg)
				table.insert(oks, msg)
			end
			local ok, err = pcall(require("nrf.health").check)
			vim.health.ok = real_ok
			assert.is_true(ok, err)
			assert.is_truthy(vim.iter(oks):find(function(m)
				return m:find("nrfutil-sdk-manager 1.4.0", 1, true) ~= nil
			end))
		end)

		it("is nil without nrfutil and does not run it", function()
			vim.fn.executable = function()
				return 0
			end
			assert.is_nil(toolchain.command())
			assert.are.same({}, calls)
		end)

		it("is detected once", function()
			has_sdk_manager()
			toolchain.command()
			toolchain.command()
			assert.are.equal(1, #calls)
		end)
	end)

	describe("find()", function()
		it("lists toolchain-manager toolchains as zephyr.nvim Toolchains, newest first", function()
			has_toolchain_manager()
			responses["nrfutil toolchain-manager list --json"] = { code = 0, stdout = fixture("toolchain-manager-list.ndjson") }
			local found = toolchain.find()
			assert.are.same({
				provider = "ncs",
				id = "ncs-v2.9.0@/home/u/ncs/toolchains/2be090971e",
				name = "NCS toolchain v2.9.0",
				version = "v2.9.0",
				path = "/home/u/ncs/toolchains/2be090971e",
				ncs_version = "v2.9.0",
				bundle_id = "2be090971e",
			}, found[1])
			assert.are.equal("v2.6.1", found[2].version)
		end)

		it("lists sdk-manager toolchains, including one installed by bundle id only", function()
			has_sdk_manager()
			responses["nrfutil sdk-manager toolchain list --json"] =
				{ code = 0, stdout = fixture("sdk-manager-toolchain-list.ndjson") }
			local found = toolchain.find()
			assert.are.same({ "v3.0.2", "7cbc0036f4" }, vim.tbl_map(function(t)
				return t.version
			end, found))
			assert.is_nil(found[2].ncs_version)
			assert.are.equal("7cbc0036f4", found[2].bundle_id)
		end)

		it("passes the configured install dir", function()
			has_toolchain_manager()
			require("nrf").config.install_dir = "/opt/ncs"
			toolchain.find()
			assert.are.equal("nrfutil toolchain-manager list --json --install-dir /opt/ncs", calls[#calls])
		end)

		it("caches the list until refresh()", function()
			has_toolchain_manager()
			responses["nrfutil toolchain-manager list --json"] = { code = 0, stdout = fixture("toolchain-manager-list.ndjson") }
			toolchain.find()
			toolchain.find()
			assert.are.equal(3, #calls) -- detect (sdk-manager, toolchain-manager) + list
			toolchain.refresh()
			toolchain.find()
			assert.are.equal(4, #calls)
		end)

		it("is empty when nrfutil fails", function()
			has_toolchain_manager()
			assert.are.same({}, toolchain.find())
		end)

		it("gives up after the timeout when nrfutil never answers", function()
			local saved = toolchain.timeout_ms
			toolchain.timeout_ms = 20
			process.run = function() end
			local start = vim.uv.hrtime()
			assert.is_nil(toolchain.command())
			toolchain.timeout_ms = saved
			assert.is_true((vim.uv.hrtime() - start) / 1e6 < 1000)
		end)
	end)

	describe("env()", function()
		local tc = {
			provider = "ncs",
			id = "ncs-v2.6.1@/home/u/ncs/toolchains/b8b84efebd",
			version = "v2.6.1",
			ncs_version = "v2.6.1",
			bundle_id = "b8b84efebd",
			path = "/home/u/ncs/toolchains/b8b84efebd",
		}

		it("evaluates the env script for that toolchain", function()
			has_toolchain_manager()
			responses["nrfutil toolchain-manager env --as-script sh --ncs-version v2.6.1"] =
				{ code = 0, stdout = fixture("toolchain-env.sh") }
			local saved_path, saved_ld = vim.env.PATH, vim.env.LD_LIBRARY_PATH
			vim.env.PATH, vim.env.LD_LIBRARY_PATH = "/usr/bin", nil
			local env = toolchain.env(tc)
			vim.env.PATH, vim.env.LD_LIBRARY_PATH = saved_path, saved_ld
			local root = "/home/u/ncs/toolchains/b8b84efebd"
			assert.are.same({
				PATH = root .. "/bin:" .. root .. "/usr/bin:/usr/bin",
				LD_LIBRARY_PATH = root .. "/lib:",
				ZEPHYR_TOOLCHAIN_VARIANT = "zephyr",
				ZEPHYR_SDK_INSTALL_DIR = root .. "/opt/zephyr-sdk",
				PYTHONHOME = root .. "/usr/local",
				PYTHONPATH = root .. "/usr/local/lib/python3.9",
			}, env)
			assert.is_nil(env.ZEPHYR_BASE)
		end)

		it("picks a toolchain without an NCS version by bundle id (NCS fork)", function()
			has_sdk_manager()
			local key = "nrfutil sdk-manager toolchain env --as-script sh --toolchain-bundle-id 7cbc0036f4"
			responses[key] = { code = 0, stdout = "export ZEPHYR_TOOLCHAIN_VARIANT=zephyr\n" }
			local env = toolchain.env({ id = "fork", bundle_id = "7cbc0036f4", path = "/x/7cbc0036f4" })
			assert.are.same({ ZEPHYR_TOOLCHAIN_VARIANT = "zephyr" }, env)
		end)

		it("is cached per toolchain", function()
			has_toolchain_manager()
			responses["nrfutil toolchain-manager env --as-script sh --ncs-version v2.6.1"] =
				{ code = 0, stdout = "export A=1\n" }
			toolchain.env(tc)
			toolchain.env(tc)
			assert.are.equal(3, #calls) -- detect (sdk-manager, toolchain-manager) + env
		end)

		it("is nil and not cached when nrfutil fails", function()
			has_toolchain_manager()
			assert.is_nil(toolchain.env(tc))
			assert.is_nil(toolchain.env(tc))
			assert.are.equal(4, #calls) -- detect twice + env twice
		end)
	end)

	describe("install()", function()
		it("installs the toolchain for a version, refreshes the list and emits NrfToolchainInstalled", function()
			has_sdk_manager()
			local key = "nrfutil sdk-manager toolchain install --ncs-version v2.6.1 --json"
			responses[key] = { code = 0, stdout = fixture("install-success.ndjson") }
			toolchain.find() -- caches an empty list
			responses["nrfutil sdk-manager toolchain list --json"] =
				{ code = 0, stdout = fixture("toolchain-manager-list.ndjson") }
			local seen
			local id = vim.api.nvim_create_autocmd("User", {
				pattern = "NrfToolchainInstalled",
				callback = function(ev)
					seen = ev.data
				end,
			})
			local ok, msg
			toolchain.install({ version = "2.6.1" }, function(a, b)
				ok, msg = a, b
			end)
			vim.api.nvim_del_autocmd(id)
			assert.is_true(ok)
			assert.are.equal("NCS toolchain v2.6.1 installed", msg)
			assert.are.same({ provider = "ncs", version = "v2.6.1", path = "/home/u/ncs/toolchains/b8b84efebd" }, seen)
			assert.are.equal(2, #toolchain.find())
		end)

		it("reports nrfutil's error", function()
			has_toolchain_manager()
			responses["nrfutil toolchain-manager install --ncs-version v9.9.9 --json"] =
				{ code = 1, stdout = fixture("install-fail.ndjson") }
			local ok, msg
			toolchain.install({ version = "v9.9.9" }, function(a, b)
				ok, msg = a, b
			end)
			assert.is_false(ok)
			assert.are.equal("No toolchain found for NCS version v9.9.9", msg)
		end)

		it("fails without nrfutil", function()
			vim.fn.executable = function()
				return 0
			end
			local ok
			toolchain.install({ version = "v3.0.2" }, function(a)
				ok = a
			end)
			assert.is_false(ok)
		end)
	end)

	it("is registered with zephyr.nvim and activates for any Workspace", function()
		local registry = require("zephyr.registry")
		local state = require("zephyr.state")
		local saved = state.path
		state.path = vim.fn.tempname() .. "/state.json"
		registry._reset()
		require("nrf").setup()
		has_sdk_manager()
		responses["nrfutil sdk-manager toolchain list --json"] =
			{ code = 0, stdout = fixture("sdk-manager-toolchain-list.ndjson") }
		responses["nrfutil sdk-manager toolchain env --as-script sh --toolchain-bundle-id 7cbc0036f4"] =
			{ code = 0, stdout = "export FORK=1\n" }
		local zt = require("zephyr.toolchain")
		local ws = { topdir = "/ws/fork" }
		local fork_tc = vim.tbl_filter(function(t)
			return t.bundle_id == "7cbc0036f4"
		end, zt.list())[1]
		zt.activate(ws, fork_tc)
		local env = zt.env(ws)
		state.path = saved
		assert.are.same({ FORK = "1" }, env)
	end)
end)
