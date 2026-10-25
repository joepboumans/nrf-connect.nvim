local ncs = require("nrf.ncs")
local process = require("zephyr.process")
local toolchain = require("nrf.toolchain")

local root = vim.fn.fnamemodify("tests/fixtures", ":p")

local function fixture(name)
	local fd = assert(io.open(root .. name, "r"))
	local text = fd:read("*a")
	fd:close()
	return text
end

local WEST = "west list -f " .. ncs.list_format .. " nrf"

-- Stub external commands: `responses` maps a joined argv to a result.
local calls, responses
local saved = {}

local function respond(cmd, opts)
	local key = table.concat(cmd, " ")
	table.insert(calls, { cmd = key, cwd = opts and opts.cwd })
	local default = { code = 1, signal = 0, stdout = "", stderr = "unknown command" }
	return vim.tbl_extend("force", default, responses[key] or {})
end

local function tc(version, path)
	local id = "ncs-" .. version .. "@" .. path
	local name = "NCS toolchain " .. version
	return { provider = "ncs", id = id, name = name, version = version, path = path, ncs_version = version }
end

local tcs = { tc("v3.1.0-rc1", "/t/a"), tc("v3.0.2", "/t/b") }

local function sync_version(ws)
	local got, err
	ncs.version(ws, function(info, e)
		got, err = info, e
	end)
	return got, err
end

describe("nrf.ncs", function()
	before_each(function()
		calls, responses = {}, {}
		ncs.reset()
		saved.run, saved.find = process.run, toolchain.find
		process.run = function(cmd, opts, on_exit)
			on_exit(respond(cmd, opts))
		end
		toolchain.find = function()
			return tcs
		end
	end)

	after_each(function()
		process.run, toolchain.find = saved.run, saved.find
		ncs.reset()
	end)

	describe("is_official()", function()
		it("accepts release tags", function()
			for _, v in ipairs({ "v3.0.2", "v2.9.0-rc1", "v3.0.0-preview2", "v2.8.0-preview", "v3.2.0-dev1" }) do
				assert.is_true(ncs.is_official(v), v)
			end
		end)

		it("rejects branches, SHAs and describe strings", function()
			for _, v in ipairs({ "main", "my-fork", "1a2b3c4d5e6f", "v3.0.2-14-g1a2b3c4", "3.0.2", "HEAD" }) do
				assert.is_false(ncs.is_official(v), v)
			end
		end)
	end)

	it("parses nrf/VERSION", function()
		assert.are.equal("v3.4.99", ncs.parse_version_file(fixture("nrf-version/VERSION")))
		local rc = "VERSION_MAJOR = 3\nVERSION_MINOR = 0\nPATCHLEVEL = 0\nEXTRAVERSION = rc1\n"
		assert.are.equal("v3.0.0-rc1", ncs.parse_version_file(rc))
		assert.is_nil(ncs.parse_version_file("garbage"))
	end)

	describe("version()", function()
		it("reads the nrf revision from the Manifest when nrf is imported", function()
			responses[WEST] = { code = 0, stdout = fixture("west/list-nrf-imported.txt") }
			local info = sync_version({ topdir = "/ws" })
			assert.are.same({ version = "v3.0.2", official = true, source = "manifest", path = "/ws/nrf" }, info)
			assert.are.equal("/ws", calls[1].cwd)
		end)

		it("reports a fork branch as custom", function()
			responses[WEST] = { code = 0, stdout = fixture("west/list-nrf-fork.txt") }
			local info = sync_version({ topdir = "/ws" })
			assert.are.equal("my-fork-branch", info.version)
			assert.is_false(info.official)
		end)

		it("uses git describe when nrf is the manifest repo", function()
			responses[WEST] = { code = 0, stdout = fixture("west/list-nrf-manifest.txt") }
			responses["git -C /ws/nrf describe --tags"] = { code = 0, stdout = fixture("git/describe-tag.txt") }
			local info = sync_version({ topdir = "/ws" })
			assert.are.same({ version = "v3.1.0-rc1", official = true, source = "git", path = "/ws/nrf" }, info)
		end)

		it("treats commits past a tag as custom", function()
			responses[WEST] = { code = 0, stdout = fixture("west/list-nrf-manifest.txt") }
			responses["git -C /ws/nrf describe --tags"] = { code = 0, stdout = fixture("git/describe-ahead.txt") }
			local info = sync_version({ topdir = "/ws" })
			assert.are.equal("v3.0.2-14-g1a2b3c4d5e", info.version)
			assert.is_false(info.official)
		end)

		it("falls back to nrf/VERSION without tags", function()
			local nrf_dir = root .. "nrf-version"
			responses[WEST] = { code = 0, stdout = ("manifest|nrf|HEAD|%s\n"):format(nrf_dir) }
			responses["git -C " .. nrf_dir .. " describe --tags"] =
				{ code = 128, stderr = fixture("git/describe-no-tags.txt") }
			local info = sync_version({ topdir = "/ws" })
			assert.are.same({ version = "v3.4.99", official = false, source = "VERSION", path = nrf_dir }, info)
		end)

		it("reports west failures", function()
			responses[WEST] = { code = 1, stderr = "FATAL ERROR: no such project nrf" }
			local info, err = sync_version({ topdir = "/ws" })
			assert.is_nil(info)
			assert.is_truthy(err:find("no such project nrf", 1, true))
		end)
	end)

	describe("suggest_toolchain()", function()
		local function suggest()
			local got, info
			ncs.suggest_toolchain({ topdir = "/ws" }, function(tc, i)
				got, info = tc, i
			end)
			return got, info
		end

		it("matches an installed toolchain to an official version", function()
			responses[WEST] = { code = 0, stdout = fixture("west/list-nrf-imported.txt") }
			local tc, info = suggest()
			assert.are.equal("ncs-v3.0.2@/t/b", tc.id)
			assert.are.equal("v3.0.2", info.version)
		end)

		it("is nil for a custom revision", function()
			responses[WEST] = { code = 0, stdout = fixture("west/list-nrf-fork.txt") }
			local tc, info = suggest()
			assert.is_nil(tc)
			assert.are.equal("my-fork-branch", info.version)
		end)

		it("is nil when no toolchain is installed for the version", function()
			responses[WEST] = { code = 0, stdout = "nrf|nrf|v2.6.1|/ws/nrf\n" }
			assert.is_nil((suggest()))
		end)
	end)

	describe("watching the Manifest", function()
		local tmp, manifest, events, notes, au

		before_each(function()
			tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp .. "/.west", "p")
			vim.fn.mkdir(tmp .. "/app", "p")
			vim.fn.writefile({ "[manifest]", "path = app", "file = west.yml" }, tmp .. "/.west/config")
			manifest = vim.fs.normalize(tmp .. "/app/west.yml")
			vim.fn.writefile({ "manifest:" }, manifest)
			events, notes = {}, {}
			au = vim.api.nvim_create_autocmd("User", {
				pattern = "NrfNcsVersionChanged",
				callback = function(ev)
					table.insert(events, ev.data)
				end,
			})
			saved.notify, saved.active = vim.notify, require("zephyr.toolchain").active
			saved.activate = require("zephyr.toolchain").activate
			vim.notify = function(msg)
				table.insert(notes, msg)
			end
			require("zephyr.toolchain").active = function()
				return tcs[2]
			end
			require("zephyr.toolchain").activate = function()
				error("must not switch toolchains silently")
			end
			require("nrf").setup()
		end)

		after_each(function()
			vim.api.nvim_del_autocmd(au)
			vim.notify, require("zephyr.toolchain").active = saved.notify, saved.active
			require("zephyr.toolchain").activate = saved.activate
			vim.cmd("silent! %bwipeout!")
			vim.fn.delete(tmp, "rf")
			require("nrf").config.watch_manifest = true
		end)

		local function pins(rev)
			responses[WEST] = { code = 0, stdout = ("nrf|nrf|%s|%s/nrf\n"):format(rev, tmp) }
		end

		it("fires NrfNcsVersionChanged on save and suggests the toolchain", function()
			pins("v3.0.2")
			vim.cmd("edit " .. manifest)
			local topdir = vim.fs.normalize(tmp)
			assert.are.equal("v3.0.2", ncs.last_seen(topdir))
			pins("v3.1.0-rc1")
			vim.cmd("silent write")
			assert.are.same({ { workspace = topdir, old = "v3.0.2", new = "v3.1.0-rc1", official = true } }, events)
			assert.is_truthy(notes[#notes]:find("NCS toolchain v3.1.0-rc1", 1, true))
		end)

		it("stays quiet when the version did not change", function()
			pins("v3.0.2")
			vim.cmd("edit " .. manifest)
			vim.cmd("silent write")
			assert.are.same({}, events)
			assert.are.same({}, notes)
		end)

		it("ignores yml files that are not the Manifest", function()
			vim.cmd("edit " .. tmp .. "/app/other.yml")
			vim.cmd("silent write")
			assert.are.same({}, calls)
		end)

		it("can be disabled with watch_manifest = false", function()
			require("nrf").setup({ watch_manifest = false })
			pins("v3.0.2")
			vim.cmd("edit " .. manifest)
			assert.are.same({}, calls)
		end)
	end)
end)
