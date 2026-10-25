local probes = require("nrf.probes")

local fixtures = vim.fn.getcwd() .. "/tests/fixtures/nrfutil/"

local function read(name)
	return table.concat(vim.fn.readfile(fixtures .. name), "\n") .. "\n"
end

describe("nrf.probes", function()
	local orig_run, calls

	before_each(function()
		orig_run = probes._run
		calls = {}
	end)

	after_each(function()
		probes._run = orig_run
	end)

	local function stub(res)
		probes._run = function(cmd, timeout)
			table.insert(calls, { cmd = cmd, timeout = timeout })
			return res
		end
	end

	it("runs `nrfutil device list --json` with a timeout", function()
		stub({ code = 0, stdout = read("device_list_empty.ndjson") })
		assert.are.same({}, probes.finder.find())
		assert.are.same({ "nrfutil", "device", "list", "--json" }, calls[1].cmd)
		assert.is_true(calls[1].timeout > 0)
	end)

	it("reads J-Link probes from the task_end line", function()
		stub({ code = 0, stdout = read("device_list_task_end.ndjson") })
		assert.are.same({
			{ finder = "nrfutil", serial = "1050012345", name = "nRF52840 DK (PCA10056)" },
			{ finder = "nrfutil", serial = "683456789", name = "J-Link 683456789" },
		}, probes.finder.find())
	end)

	it("reads J-Link probes from info lines", function()
		stub({ code = 0, stdout = read("device_list_info.ndjson") })
		assert.are.same({
			{ finder = "nrfutil", serial = "1051234567", name = "nRF5340 DK (PCA10095)" },
		}, probes.finder.find())
	end)

	it("names an unknown devkit by its board version", function()
		stub({
			code = 0,
			stdout = vim.json.encode({
				type = "info",
				data = {
					devices = {
						{ serialNumber = "123", traits = { jlink = true }, devkit = { boardVersion = "PCA99999" } },
					},
				},
			}),
		})
		assert.are.same({ { finder = "nrfutil", serial = "123", name = "PCA99999" } }, probes.finder.find())
	end)

	it("returns an empty list when nrfutil is missing", function()
		stub(nil)
		assert.are.same({}, probes.finder.find())
	end)

	it("returns an empty list on garbage or a failed run", function()
		stub({ code = 1, stdout = "not json\n{\"type\":\"task_end\",\"data\":{\"result\":\"fail\"}}\n" })
		assert.are.same({}, probes.finder.find())
	end)

	it("default runner reports a missing executable as nil", function()
		local path = vim.env.PATH
		vim.env.PATH = ""
		local res = orig_run({ "nrfutil", "device", "list", "--json" }, 1000)
		vim.env.PATH = path
		assert.is_nil(res)
	end)

	it("default runner starts nrfutil through zephyr.process.run with the timeout", function()
		local process = require("zephyr.process")
		local real_run, real_exe = process.run, vim.fn.executable
		local seen
		process.run = function(cmd, opts, on_exit)
			seen = { cmd = cmd, timeout = opts.timeout }
			on_exit({ code = 0, signal = 0, stdout = read("device_list_info.ndjson"), stderr = "" })
		end
		vim.fn.executable = function()
			return 1
		end
		local ok, found = pcall(probes.finder.find)
		process.run, vim.fn.executable = real_run, real_exe
		assert.is_true(ok, found)
		assert.are.same({ cmd = { "nrfutil", "device", "list", "--json" }, timeout = probes.timeout_ms }, seen)
		assert.are.equal(1, #found)
	end)
end)
