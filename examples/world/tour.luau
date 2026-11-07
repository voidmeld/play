--!strict

local Simulator = require("./simulator")

local function run(demo: typeof(Simulator.new()))
	local first, second, observer = demo.clients[11], demo.clients[22], demo.clients[33]
	assert(first.text("Character") == "Traveler11 · Level 1 · XP 0")
	assert(observer.text("Quest") == "offered · defeat 0/1 · collect 0/1")
	demo.tap(33, "Buy")
	assert(observer.text("Status") == "Refused: insufficient_coin")
	for _, userId in { 11, 22 } do
		demo.tap(userId, "Accept")
		demo.tap(userId, "Equip")
	end
	local function earn(userId: number)
		for _ = 1, 3 do
			demo.tap(userId, "Attack")
			demo.step(0.25)
			demo.step(0.3)
		end
		demo.tap(userId, "Loot")
		demo.tap(userId, "Claim")
		local view = assert(assert(demo.clients[userId].client.latest()).view)
		assert(view.level == 2 and view.xp == 150 and view.coin == 25)
		assert(view.questStatus == "completed" and view.inventory.copper_ore == 1)
	end
	earn(11)
	demo.tap(11, "Craft")
	assert(assert(assert(first.client.latest()).view).inventory.shield == 2)
	demo.tap(11, "Craft")
	assert(first.text("Status") == "Refused: materials_missing")
	demo.tap(11, "List")
	assert(observer.text("Market") == "Shield listings: 1 · 5 coin each")
	demo.step(3)
	earn(22)
	demo.tap(22, "Buy")
	assert(assert(assert(second.client.latest()).view).coin == 20)
	assert(assert(assert(second.client.latest()).view).inventory.shield == 2)
	assert(first.text("Coin") == "Coin: 29")
	assert(observer.text("Market") == "Shield listings: 0 · 5 coin each")
	demo.tap(11, "Chat")
	assert(second.text("ChatLines") == "Hello Harbor")
	assert(second.text("Coin") == "Coin: 20")
	assert(observer.text("Quest") == "offered · defeat 0/1 · collect 0/1")
	return { sellerCoin = 29, buyerCoin = 20, burnedCoin = 1 }
end

return table.freeze({ run = run })
