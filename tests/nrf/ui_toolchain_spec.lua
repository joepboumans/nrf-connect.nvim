local ui = require("nrf.ui.toolchain")
local ncs = require("nrf.toolchain")

local tcs = {
	{ provider = "ncs", id = "ncs-v3.0.2@/t/a", name = "NCS toolchain v3.0.2", version = "v3.0.2", path = "/t/a" },
	{ provider = "ncs", id = "ncs-fork@/t/b", name = "NCS toolchain b", version = "b", path = "/t/b" },
}

describe(":Nrf toolchain", function()
	local saved = {}
	local notes, activated

	before_each(function()
		notes, activated = {}, nil
		saved.find, saved.refresh, saved.install = ncs.find, ncs.refresh, ncs.install
		saved.notify, saved.select = vim.notify, vim.ui.select
		saved.ws_find = require("zephyr.workspace").find
		saved.target = require("nrf.ui.target").find
		require("nrf.ui.target").find = function()
			return { topdir = "/ws" }, { dir = "/ws/app" }, { dir = "/ws/app/build", name = "build" }
		end
		saved.activate, saved.active = require("zephyr.toolchain").activate, require("zephyr.toolchain").active
		ncs.find = function()
			return tcs
		end
		ncs.refresh = function() end
		vim.notify = function(msg, level)
			table.insert(notes, { msg = msg, level = level })
		end
		require("zephyr.workspace").find = function()
			return { topdir = "/ws" }
		end
		require("zephyr.toolchain").activate = function(app, cfg, tc)
			activated = { app = app.dir, build_dir = cfg.dir, id = tc.id }
		end
		require("zephyr.toolchain").active = function()
			return tcs[2], true
		end
	end)

	after_each(function()
		ncs.find, ncs.refresh, ncs.install = saved.find, saved.refresh, saved.install
		vim.notify, vim.ui.select = saved.notify, saved.select
		require("zephyr.workspace").find = saved.ws_find
		require("nrf.ui.target").find = saved.target
		require("zephyr.toolchain").activate, require("zephyr.toolchain").active = saved.activate, saved.active
	end)

	it("lists NCS toolchains and marks the active one", function()
		vim.cmd("Nrf toolchain list")
		assert.is_truthy(notes[1].msg:find("\n  NCS toolchain v3.0.2", 1, true))
		assert.is_truthy(notes[1].msg:find("\n* NCS toolchain b", 1, true))
	end)

	it("selects a toolchain for the active Build configuration through zephyr.toolchain.activate", function()
		vim.ui.select = function(items, _, on_choice)
			on_choice(items[2])
		end
		vim.cmd("Nrf toolchain select")
		assert.are.same({ app = "/ws/app", build_dir = "/ws/app/build", id = "ncs-fork@/t/b" }, activated)
	end)

	it("needs a Build configuration to select for", function()
		require("nrf.ui.target").find = function()
			return { topdir = "/ws" }, { dir = "/ws/app" }, nil
		end
		vim.cmd("Nrf toolchain select")
		assert.is_nil(activated)
		assert.matches(":Zephyr build new", notes[1].msg)
	end)

	it("installs a version", function()
		local got
		ncs.install = function(opts, cb)
			got = opts.version
			cb(true, "done")
		end
		vim.cmd("Nrf toolchain install v3.0.2")
		assert.are.equal("v3.0.2", got)
		assert.are.equal("nrf: done", notes[#notes].msg)
	end)

	it("needs a version to install", function()
		vim.cmd("Nrf toolchain install")
		assert.are.equal(vim.log.levels.ERROR, notes[1].level)
	end)

	it("completes actions", function()
		assert.are.same({ "list", "select", "install" }, vim.fn.getcompletion("Nrf toolchain ", "cmdline"))
		assert.are.same({ "toolchain" }, vim.fn.getcompletion("Nrf to", "cmdline"))
	end)
end)
