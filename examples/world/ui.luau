--!strict

local Client = require("./roblox-client")
local Compose = require("../../.lute/dependencies/compose/src/core")
local Native = require("../../.lute/dependencies/compose/src/roblox")
local Protocol = require("./protocol")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Value = require("../../src/kernel/value")

type Props = { [unknown]: unknown }

local function operation(value: unknown, key: string): (...unknown) -> ...unknown
	local row = assert(Value.raw(value), "module_record_required")
	local callback = row[key]
	assert(type(callback) == "function", "module_operation_missing:" .. key)
	return function(...: unknown): ...unknown
		return Roblox.value.invoke(Roblox.value.value(callback), ...)
	end
end

local function mount(
	facet: unknown,
	runtime: Compose.Runtime,
	types: unknown,
	parent: Roblox.Instance,
	client: Client.Handle
)
	local bound = operation(facet, "bind")(Compose, Native)
	local app = operation(bound, "app")({
		runtime = runtime,
		types = types,
		parent = parent,
		name = "Play World",
		motionLevel = "none",
		focusRing = false,
	})
	local controls = assert(Value.raw(app)).UI
	local initial: Protocol.Response? = client.latest()
	local response = Compose.cell(initial)
	local stop = client.subscribe(function(value)
		local previous = response:peek()
		response:set({
			ok = value.ok,
			reason = value.reason,
			view = value.view or (if previous ~= nil then previous.view else nil),
			activity = value.activity or (if previous ~= nil then previous.activity else nil),
			line = value.line,
		})
	end)
	local function control(name: string, props: Props): unknown
		return (operation(controls, name)(props))
	end
	local function text(name: string, read: (Protocol.Response?) -> string): unknown
		return control("Text", {
			Name = name,
			text = function(use: Compose.Use)
				return read(use(response))
			end,
		})
	end
	local function button(name: string, label: string, intent: Protocol.Request): unknown
		return control("Button", {
			Name = name,
			label = label,
			onActivate = function()
				client.request(intent)
			end,
		})
	end
	local function panel(children: Props): unknown
		children.width = 340
		children.gap = "s"
		children.padding = "m"
		children.surface = "panel"
		children.corners = "panel"
		return control("VStack", children)
	end
	local equip: Protocol.EquipRequest = { kind = "equip", itemId = "training_sword" }
	local chat: Protocol.ChatRequest = { kind = "chat", text = "Hello" }
	local _, screen = operation(app, "mount")(function()
		return control("Screen", {
			gap = "m",
			control("Text", { text = "Play · Persistent world", textRole = "title" }),
			text("Status", function(value)
				return if value == nil
					then "Connecting"
					elseif value.ok then "Ready"
					else "Refused: " .. (value.reason or "unavailable")
			end),
			text("ChatLines", function(_value)
				local lines = client.lines()
				return if #lines > 0 then lines[#lines].text else "Nearby chat is quiet"
			end),
			control("HStack", {
				gap = "m",
				width = "fill",
				align = "start",
				panel({
					control("Text", { text = "Character & inventory", textRole = "heading" }),
					text("Character", function(value)
						local view = if value ~= nil then value.view else nil
						return if view ~= nil
							then view.displayName .. " · Level " .. tostring(view.level) .. " · XP " .. tostring(
								view.xp
							)
							else "Awaiting admission"
					end),
					text("Coin", function(value)
						return "Coin: " .. tostring(if value ~= nil and value.view ~= nil then value.view.coin else 0)
					end),
					text("Inventory", function(value)
						local rows: { string } = {}
						if value ~= nil and value.view ~= nil then
							for id, count in value.view.inventory do
								table.insert(rows, id .. " × " .. tostring(count))
							end
						end
						table.sort(rows)
						return "Bag: " .. table.concat(rows, ", ")
					end),
					text("Equipment", function(value)
						return "Hand: "
							.. (
								if value ~= nil and value.view ~= nil
									then value.view.equipment.hand or "empty"
									else "empty"
							)
					end),
					button("Equip", "Equip training sword", equip),
					button("Refresh", "Refresh world", { kind = "snapshot" }),
					button("Chat", "Greet nearby players", chat),
				}),
				panel({
					control("Text", { text = "Quest & combat", textRole = "heading" }),
					text("Quest", function(value)
						local view = if value ~= nil then value.view else nil
						return if view ~= nil
							then view.questStatus
								.. " · defeat "
								.. tostring(view.counts.defeat or 0)
								.. "/1 · collect "
								.. tostring(view.counts.collect or 0)
								.. "/1"
							else "Awaiting journal"
					end),
					text("Enemy", function(value)
						return "Enemy health: "
							.. tostring(if value ~= nil and value.activity ~= nil then value.activity.health else 30)
					end),
					button("Accept", "Accept supply quest", { kind = "accept" }),
					button("Attack", "Strike nearby enemy", { kind = "attack" }),
					control("Button", {
						Name = "Loot",
						label = "Collect earned loot",
						onActivate = function()
							local value = response:peek()
							local loot = if value ~= nil and value.view ~= nil then value.view.loot[1] else nil
							if loot ~= nil then
								client.request({ kind = "loot", defeatId = loot })
							end
						end,
					}),
					button("Claim", "Claim quest reward", { kind = "claim" }),
				}),
				panel({
					control("Text", { text = "Crafting & market", textRole = "heading" }),
					control("Text", { text = "1 copper ore → 1 shield" }),
					button("Craft", "Craft shield", { kind = "craft" }),
					text("Market", function(value)
						local listings = if value ~= nil and value.activity ~= nil then value.activity.listings else {}
						return "Shield listings: " .. tostring(#listings) .. " · 5 coin each"
					end),
					button("List", "List one shield", { kind = "list" }),
					button("Buy", "Buy one shield", { kind = "buy" }),
					control("Text", { text = "The market burns a 5% fee. Inventory, coin and book commit together." }),
				}),
			}),
		})
	end)
	runtime:settle()
	return {
		screen = Roblox.assertInstance(screen),
		dispose = function()
			stop()
			operation(app, "dispose")()
			response:dispose()
		end,
	}
end

return table.freeze({ mount = mount })
