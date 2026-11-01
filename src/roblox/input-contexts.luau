--!strict

export type Template = { folder: string, name: string }
export type Surfaces = {
	template: (string, string) -> unknown?,
	existing: (string) -> unknown?,
	adopt: (unknown, string) -> unknown?,
}
local function mounted(phase: string, names: { string }, reason: string?)
	table.freeze(names)
	return table.freeze({ phase = phase, names = names, reason = reason })
end
export type Mounted = typeof(mounted("", {}, nil))

local Contexts = {}

function Contexts.mount(plan: { Template }, raw: Surfaces?, phases: { mounted: string, refused: string }): Mounted
	local function refusal(reason: string): Mounted
		return mounted(phases.refused, {}, reason)
	end
	if type(raw) ~= "table" then
		return refusal("surfaces_invalid")
	end
	local fields = raw
	if
		type(fields.template) ~= "function"
		or type(fields.existing) ~= "function"
		or type(fields.adopt) ~= "function"
	then
		return refusal("surfaces_invalid")
	end
	local surfaces = fields
	local names: { string } = {}
	for _, row in plan do
		local read, present = pcall(surfaces.existing, row.name)
		if not read then
			return refusal("existing_failed:" .. row.name)
		end
		if present == nil then
			local found, template = pcall(surfaces.template, row.folder, row.name)
			if not found or template == nil then
				return refusal("template_missing:" .. row.name)
			end
			local adopted, mounted = pcall(surfaces.adopt, template, row.name)
			if not adopted or mounted == nil then
				return refusal("adopt_failed:" .. row.name)
			end
		end
		table.insert(names, row.name)
	end
	return mounted(phases.mounted, names, nil)
end

function Contexts.create<N, A>(host: {
	find: (N, string) -> N?,
	wait: (N, string, number) -> N?,
	clock: () -> number,
	isContext: (N) -> boolean,
	asAction: (N) -> A?,
	name: (N) -> string,
	minimumWait: number,
})
	local Input = {}
	function Input.action(context: N, name: string): A
		local node = host.find(context, name)
		local action = if node ~= nil then host.asAction(node) else nil
		if action == nil then
			error(("InputActions: missing authored InputAction %q under %s"):format(name, host.name(context)), 3)
		end
		return action
	end
	function Input.context(root: N, path: { string }, required: { string }, deadline: number): N
		local function waitChild(parent: N, name: string): N
			local child = host.wait(parent, name, math.max(host.minimumWait, deadline - host.clock()))
			if child == nil then
				error("input context did not arrive: " .. table.concat(path, "/"), 2)
			end
			return child
		end
		local node: N = root
		for _, name in path do
			node = waitChild(node, name)
		end

		if not host.isContext(node) then
			error("input context has wrong class: " .. table.concat(path, "/"), 2)
		end
		for _, name in required do
			if host.wait(node, name, math.max(host.minimumWait, deadline - host.clock())) == nil then
				error("input action did not arrive: " .. name, 2)
			end
		end
		return node
	end
	return table.freeze(Input)
end

return table.freeze(Contexts)
