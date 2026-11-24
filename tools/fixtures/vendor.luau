--!strict

local Engine = require("./engine")
local Exchange = require("../../src/core/vendors/exchange")

local Scene = {}

function Scene.new()
	local clock = Engine.clock()
	local prices: { [string]: number } = { food = 2, tool = 5, prize = 0 }
	local vendor: Exchange.Vendor = {
		id = "merchant",
		npcId = "speaker",
		wares = { { itemId = "food", price = 4, stock = 3 }, { itemId = "tool", price = 8 } },
	}
	local law = Exchange.vendor({
		maxQuantity = 10,
		maxStack = 20,
		buybackLimit = 2,
		buybackSeconds = 10,
		exists = function(id: string): boolean
			return prices[id] ~= nil
		end,
		sellValue = function(id: string): number?
			return if id ~= "prize" then prices[id] else nil
		end,
		add = function(inventory: Exchange.Inventory, id: string, count: number): Exchange.Inventory
			local result = table.clone(inventory)
			result[id] = (result[id] or 0) + count
			return result
		end,
		remove = function(inventory: Exchange.Inventory, id: string, count: number): (Exchange.Inventory, boolean)
			if (inventory[id] or 0) < count then
				return inventory, false
			end
			local result = table.clone(inventory)
			local remaining = result[id] - count
			result[id] = if remaining > 0 then remaining else nil
			return result, true
		end,
		canCarry = function(_before: Exchange.Inventory, after: Exchange.Inventory, bag: string?): boolean
			local count = 0
			for _ in after do
				count += 1
			end
			return count <= (if bag == "large" then 3 else 2)
		end,
	})
	return { law = law, clock = clock, vendor = vendor, prices = prices }
end

return table.freeze(Scene)
