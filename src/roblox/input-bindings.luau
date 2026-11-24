--!strict

export type Action<C> = {
	id: string,
	context: C,
	keyboard: { string },
	gamepad: string?,
	chord: string?,
	release: boolean?,
	gamepadAlt: string?,
	touch: "thumbstick" | "button" | "screen",
	affordance: string,
}

local Module = {}

function Module.create<C>(actions: { Action<C> }, labels: { [string]: string }, modifier: string)
	local byId: { [string]: Action<C> } = {}
	for _, action in actions do
		byId[action.id] = action
	end
	local Bindings = { actions = table.freeze(actions), GAMEPAD_GAPS = table.freeze({}), CHORD_MODIFIER = modifier }
	function Bindings.get(id: string): Action<C>
		return assert(byId[id], "unknown input action " .. id)
	end
	function Bindings.keyboardNames(id: string): { string }
		return Bindings.get(id).keyboard
	end
	function Bindings.primaryKeyboard(id: string): string
		return Bindings.keyboardNames(id)[1]
	end
	function Bindings.gamepad(id: string): string?
		return Bindings.get(id).gamepad
	end
	function Bindings.matches(id: string, name: string): boolean
		local action = Bindings.get(id)
		return (action.chord == nil and action.gamepad == name) or table.find(action.keyboard, name) ~= nil
	end
	function Bindings.keyboardLabel(id: string): string
		local name = Bindings.primaryKeyboard(id)
		return labels[name] or name
	end
	function Bindings.gamepadLabel(id: string): string?
		local action = Bindings.get(id)
		if action.gamepad == nil then
			return nil
		end
		local button = labels[action.gamepad] or action.gamepad
		return if action.chord == nil then button else (labels[action.chord] or action.chord) .. "+" .. button
	end
	function Bindings.matchesCode<K>(id: string, code: unknown, keys: { [string]: K }): boolean
		local action = Bindings.get(id)
		if action.gamepad ~= nil and action.chord == nil and keys[action.gamepad] == code then
			return true
		end
		for _, name in action.keyboard do
			if keys[name] == code then
				return true
			end
		end
		return false
	end
	function Bindings.matchesInput<K>(id: string, code: unknown, keys: { [string]: K }, held: (string) -> boolean): boolean
		local action = Bindings.get(id)
		for _, name in action.keyboard do
			if keys[name] == code then
				return true
			end
		end
		return action.gamepad ~= nil and keys[action.gamepad] == code and (action.chord == nil or held(action.chord))
	end
	function Bindings.forContext(context: C): { Action<C> }
		local out: { Action<C> } = {}
		for _, action in actions do
			if action.context == context then
				table.insert(out, action)
			end
		end
		return out
	end
	return table.freeze(Bindings)
end

return table.freeze(Module)
