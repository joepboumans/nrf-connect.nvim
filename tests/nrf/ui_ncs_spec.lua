local ncs = require("nrf.ncs")

local official = { version = "v3.0.2", official = true, source = "manifest", path = "/ws/nrf" }
local custom = { version = "my-fork", official = false, source = "manifest", path = "/ws/nrf" }
local tc_a = { provider = "ncs", id = "a", name = "NCS toolchain v3.0.2", version = "v3.0.2", path = "/t/a" }
local tc_b = { provider = "ncs", id = "b", name = "NCS toolchain v2.9.0", version = "v2.9.0", path = "/t/b" }

describe(":Nrf ncs", function()
	local saved = {}
	local notes, activated, prompted, suggestion, active

	before_each(function()
		notes, activated, prompted = {}, nil, nil
		local zt = require("zephyr.toolchain")
		saved.suggest, saved.notify, saved.select = ncs.suggest_toolchain, vim.notify, vim.ui.select
		saved.ws_find, saved.active, saved.activate = require("zephyr.workspace").find, zt.active, zt.activate
		ncs.suggest_toolchain = function(_, cb)
			cb(suggestion[1], suggestion[2])
		end
		vim.notify = function(msg, level)
			table.insert(notes, { msg = msg, level = level })
		end
		vim.ui.select = function(items, _, on_choice)
			prompted = items
			on_choice(items[1])
		end
		require("zephyr.workspace").find = function()
			return { topdir = "/ws" }
		end
		zt.active = function()
			return active
		end
		zt.activate = function(_, tc)
			activated = tc.id
		end
	end)

	after_each(function()
		local zt = require("zephyr.toolchain")
		ncs.suggest_toolchain, vim.notify, vim.ui.select = saved.suggest, saved.notify, saved.select
		require("zephyr.workspace").find, zt.active, zt.activate = saved.ws_find, saved.active, saved.activate
	end)

	it("shows the version and offers the matching toolchain", function()
		suggestion, active = { tc_a, official }, tc_b
		vim.cmd("Nrf ncs")
		assert.is_truthy(notes[1].msg:find("NCS version: v3.0.2 (official release", 1, true))
		assert.is_truthy(notes[1].msg:find("Active toolchain: NCS toolchain v2.9.0", 1, true))
		assert.are.equal("Activate NCS toolchain v3.0.2", prompted[1])
		assert.are.equal("a", activated)
	end)

	it("does not prompt when the matching toolchain is active", function()
		suggestion, active = { tc_a, official }, tc_a
		vim.cmd("Nrf ncs")
		assert.is_nil(prompted)
		assert.is_nil(activated)
	end)

	it("keeps the toolchain when the user declines", function()
		suggestion, active = { tc_a, official }, tc_b
		vim.ui.select = function(items, _, on_choice)
			on_choice(items[2])
		end
		vim.cmd("Nrf ncs")
		assert.is_nil(activated)
	end)

	it("reports a custom revision", function()
		suggestion, active = { nil, custom }, tc_b
		vim.cmd("Nrf ncs")
		assert.is_truthy(notes[1].msg:find("my-fork (custom revision", 1, true))
		assert.is_nil(prompted)
	end)

	it("reports errors", function()
		suggestion, active = { nil, nil }, nil
		ncs.suggest_toolchain = function(_, cb)
			cb(nil, nil, "west list failed")
		end
		vim.cmd("Nrf ncs")
		assert.are.equal(vim.log.levels.ERROR, notes[1].level)
	end)
end)
