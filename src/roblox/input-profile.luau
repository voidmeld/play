--!strict

local Value = require("../kernel/value")

export type Device = "keyboard" | "gamepad" | "touch"
export type TouchAffordance = "thumbstick" | "button" | "screen"

export type Action = {
	id: string,
	keyboard: string,
	gamepad: string,
	touch: TouchAffordance,
}

export type Profile = {
	id: string,
	actions: { Action },
}

local function session(
	phase: string,
	reason: string?,
	press: ((string, Device) -> boolean)?,
	move: ((unknown, Device) -> boolean)?,
	stop: (() -> ())?
)
	return table.freeze({ phase = phase, reason = reason, press = press, move = move, stop = stop })
end
export type Session = typeof(session("", nil, nil, nil, nil))

local DEVICES: { Device } = { "keyboard", "gamepad", "touch" }
table.freeze(DEVICES)
local TOUCH_AFFORDANCES: { [string]: boolean } = { thumbstick = true, button = true, screen = true }
local DEPENDENCY_FIELDS: { [string]: boolean } = {
	profile = true,
	owns = true,
	bind = true,
	thumbstick = true,
	dispatch = true,
	intent = true,
}

local function nonempty(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function validAction(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local row = assert(Value.raw(value))
	return (type(row.id) == "string" and nonempty(row.id))
		and (type(row.keyboard) == "string" and nonempty(row.keyboard))
		and (type(row.gamepad) == "string" and nonempty(row.gamepad))
		and type(row.touch) == "string"
		and TOUCH_AFFORDANCES[row.touch] == true
end

local Module = {}

function Module.create(profiles: { [string]: Profile }, phases: { mounted: string, refused: string })
	local Input = { DEVICES = DEVICES }
	function Input.profile(name: unknown): Profile?
		return if type(name) == "string" then profiles[name] else nil
	end

	function Input.reach(profile: unknown, device: unknown): { string }
		local reached: { string } = {}
		if type(profile) ~= "table" or (device ~= "keyboard" and device ~= "gamepad" and device ~= "touch") then
			return reached
		end
		local fields = assert(Value.raw(profile))
		if type(fields.actions) ~= "table" then
			return reached
		end
		for _, value in fields.actions do
			if type(value) == "table" then
				local action = assert(Value.raw(value))
				local binding = action[if device == "keyboard"
					then "keyboard"
					elseif device == "gamepad" then "gamepad"
					else "touch"]
				if
					(type(action.id) == "string" and nonempty(action.id))
					and (type(binding) == "string" and nonempty(binding))
					and (device ~= "touch" or TOUCH_AFFORDANCES[binding])
				then
					table.insert(reached, action.id)
				end
			end
		end
		table.sort(reached)
		return reached
	end

	function Input.parity(profile: unknown): boolean
		if type(profile) ~= "table" then
			return false
		end
		local actions = assert(Value.raw(profile)).actions
		if type(actions) ~= "table" or #actions == 0 then
			return false
		end
		for _, action in actions do
			if not validAction(action) then
				return false
			end
		end
		return true
	end

	function Input.coverage(profile: unknown, hosts: unknown): boolean
		if type(profile) ~= "table" or type(hosts) ~= "table" then
			return false
		end
		local fields = assert(Value.raw(profile))
		if type(fields.actions) ~= "table" then
			return false
		end
		local remaining: { [string]: boolean } = {}
		local count = 0
		for _, value in fields.actions do
			if not validAction(value) then
				return false
			end
			local action = assert(Value.raw(value))
			if remaining[assert(Value.opaque(action.id, math.huge))] ~= nil then
				return false
			end
			remaining[assert(Value.opaque(action.id, math.huge))] = true
			count += 1
		end
		local claimed = 0
		for _, owned in hosts do
			if type(owned) ~= "table" then
				return false
			end
			for _, id in owned do
				if type(id) ~= "string" or id == "" or remaining[id] ~= true then
					return false
				end
				remaining[id] = false
				claimed += 1
			end
		end
		return claimed == count
	end

	local function deviceOfInputName(name: unknown): Device?
		if type(name) ~= "string" or name == "" then
			return nil
		end
		if string.sub(name, 1, 7) == "Gamepad" then
			return "gamepad"
		end
		if string.sub(name, 1, 5) == "Touch" then
			return "touch"
		end
		if name == "Keyboard" or string.sub(name, 1, 5) == "Mouse" then
			return "keyboard"
		end
		return nil
	end

	Input.deviceOfInputName = deviceOfInputName

	local function refusal(reason: string): Session
		return session(phases.refused, reason, nil, nil, nil)
	end

	type Dependencies = {
		profile: unknown,
		owns: { string }?,
		bind: ((Action, boolean, (Device) -> ()) -> () -> ()) | false | nil,
		thumbstick: ((({ x: number, y: number }) -> ()) -> () -> ()) | false | nil,
		dispatch: ((string, Device) -> ()) | false | nil,
		intent: (({ x: number, y: number }, Device) -> ()) | false | nil,
	}

	function Input.start(rawDependencies: Dependencies): Session
		local fields = rawDependencies
		if Value.record(fields, DEPENDENCY_FIELDS, true) == nil then
			return refusal("dependencies_invalid")
		end
		local profile = Input.profile(fields.profile)
		if profile == nil then
			return refusal("profile_unknown")
		end
		if not Input.parity(profile) then
			return refusal("device_parity_broken")
		end
		if
			type(fields.owns) ~= "table"
			or type(fields.bind) ~= "function"
			or type(fields.thumbstick) ~= "function"
			or type(fields.dispatch) ~= "function"
			or type(fields.intent) ~= "function"
		then
			return refusal("dependencies_invalid")
		end
		local dependencies = fields
		local owned: { Action } = {}
		local byId: { [string]: Action } = {}
		for _, id in dependencies.owns do
			if type(id) ~= "string" or id == "" or byId[id] ~= nil then
				return refusal("owned_actions_invalid")
			end
			local found: Action? = nil
			for _, action in profile.actions do
				if action.id == id then
					found = action
				end
			end
			if found == nil then
				return refusal("owned_actions_invalid")
			end
			byId[id] = found
			table.insert(owned, found)
		end
		if #owned == 0 then
			return refusal("owned_actions_invalid")
		end

		local stopped = false
		local releases: { () -> () } = {}

		local function dispatch(id: string, device: Device): boolean
			if stopped or byId[id] == nil or table.find(DEVICES, device) == nil then
				return false
			end
			return (pcall(dependencies.dispatch, id, device))
		end

		local function move(vector: unknown, device: Device): boolean
			if stopped or byId.move == nil or table.find(DEVICES, device) == nil then
				return false
			end
			if type(vector) ~= "table" then
				return false
			end
			local fields = assert(Value.raw(vector))
			if type(fields.x) ~= "number" or type(fields.y) ~= "number" then
				return false
			end
			return (pcall(dependencies.intent, { x = fields.x, y = fields.y }, device))
		end

		local function stop()
			if stopped then
				return
			end
			stopped = true
			for index = #releases, 1, -1 do
				pcall(releases[index])
			end
			table.clear(releases)
		end

		for _, action in owned do
			if action.touch == "thumbstick" then
				local mounted, release = pcall(dependencies.thumbstick, function(vector: unknown)
					move(vector, "touch")
				end)
				if not mounted or type(release) ~= "function" then
					stop()
					return refusal("thumbstick_mount_failed")
				end
				table.insert(releases, release)
			elseif action.touch == "button" then
				local bound, release = pcall(dependencies.bind, action, true, function(device: Device)
					dispatch(action.id, device)
				end)
				if not bound or type(release) ~= "function" then
					stop()
					return refusal("action_bind_failed")
				end
				table.insert(releases, release)
			end
		end

		return session(phases.mounted, nil, dispatch, move, stop)
	end

	return table.freeze(Input)
end

return table.freeze(Module)
