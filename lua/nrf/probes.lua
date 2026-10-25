-- Nordic probe finder for zephyr.nvim: lists J-Link Probes with `nrfutil device list --json`.
local M = {}

---How long find() waits for nrfutil before giving up.
M.timeout_ms = 5000

-- Readable names for common Nordic DK board versions (PCA numbers).
local devkits = {
	PCA10040 = "nRF52 DK",
	PCA10056 = "nRF52840 DK",
	PCA10100 = "nRF52833 DK",
	PCA10095 = "nRF5340 DK",
	PCA10090 = "nRF9160 DK",
	PCA10153 = "nRF9161 DK",
	PCA10143 = "nRF7002 DK",
	PCA10156 = "nRF54L15 DK",
	PCA10175 = "nRF54H20 DK",
}

---Run a command through zephyr.process and wait for it: the registry's find() is synchronous. Tests replace it.
---@param cmd string[]
---@param timeout integer milliseconds
---@return vim.SystemCompleted|nil res nil when the command is not installed
function M._run(cmd, timeout)
	if vim.fn.executable(cmd[1]) ~= 1 then
		return nil
	end
	return require("nrf.toolchain").run_sync(cmd, timeout)
end

---Device objects from nrfutil's NDJSON: `task_end` carries them at data.data.devices,
---`info` lines at data.devices.
---@param stdout string
---@return table[]
local function parse_devices(stdout)
	local devices = {}
	for line in vim.gsplit(stdout or "", "\n", { plain = true, trimempty = true }) do
		local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
		if ok and type(msg) == "table" and type(msg.data) == "table" then
			local list
			if msg.type == "task_end" and type(msg.data.data) == "table" then
				list = msg.data.data.devices
			elseif msg.type == "info" then
				list = msg.data.devices
			end
			if type(list) == "table" then
				vim.list_extend(devices, list)
			end
		end
	end
	return devices
end

---@param dev table nrfutil device object
---@return table|nil probe
local function to_probe(dev)
	local traits = type(dev.traits) == "table" and dev.traits or {}
	local sn = dev.serialNumber
	if not traits.jlink or type(sn) ~= "string" or sn == "" then
		return nil
	end
	-- nrfutil zero-pads J-Link serials; J-Link tools and `west flash --dev-id` use them without padding.
	local serial = sn:gsub("^0+(%d)", "%1")
	local board = type(dev.devkit) == "table" and dev.devkit.boardVersion or nil
	local name
	if type(board) == "string" and board ~= "" then
		name = devkits[board] and ("%s (%s)"):format(devkits[board], board) or board
	else
		name = "J-Link " .. serial
	end
	return { finder = "nrfutil", serial = serial, name = name }
end

M.finder = {
	name = "nrfutil",
	---Connected J-Link Probes. Blocks for up to `timeout_ms`; returns {} when nrfutil is missing or fails.
	---@return { finder: string, serial: string, name: string }[]
	find = function()
		local res = M._run({ "nrfutil", "device", "list", "--json" }, M.timeout_ms)
		if not res then
			return {}
		end
		local probes, seen = {}, {}
		for _, dev in ipairs(parse_devices(res.stdout)) do
			local probe = type(dev) == "table" and to_probe(dev) or nil
			if probe and not seen[probe.serial] then
				seen[probe.serial] = true
				table.insert(probes, probe)
			end
		end
		return probes
	end,
}

return M
