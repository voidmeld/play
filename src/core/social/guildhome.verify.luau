--!strict

local Module = require("./guildhome")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local current: Verify.Context? = nil
	local function expect(value: unknown): Verify.Expectation
		return assert(current):expect(value)
	end
	local function it(name: string, body: () -> ())
		suite:case(name, function(context)
			current = context
			body()
		end)
	end
	local function describe(_name: string, body: () -> ())
		body()
	end
	local settings =
		{ maxIdLength = 128, maxLabelLength = 64, maxSlots = 16, realms = { north = true, south = true, east = true } }
	local GuildHomeCore = Module.guildhome(settings)

	local ZONES = {
		{
			banners = {
				slots = {
					{ id = "woodland.banner", hubId = "woodland.village_courtyard", realmId = "north", label = "Gate" },
				},
			},
			hubs = {
				hubs = {
					{ id = "woodland.village_courtyard", tier = "primary" },
					{ id = "woodland.ruin_road_approach", tier = "secondary" },
				},
			},
			realmId = "north",
		},
		{
			banners = {
				slots = {
					{ id = "marsh.banner", hubId = "marsh.village_courtyard", realmId = "south", label = "Gate" },
				},
			},
			hubs = {
				hubs = {
					{ id = "marsh.village_courtyard", tier = "primary" },
					{ id = "marsh.ruin_road_approach", tier = "secondary" },
				},
			},
			realmId = "south",
		},
		{
			banners = {
				slots = {
					{ id = "highland.banner", hubId = "highland.village_courtyard", realmId = "east", label = "Gate" },
				},
			},
			hubs = {
				hubs = {
					{ id = "highland.village_courtyard", tier = "primary" },
					{ id = "highland.ruin_road_approach", tier = "secondary" },
				},
			},
			realmId = "east",
		},
	}

	local function primaryHubSlotRefusal(catalog: unknown, hubCatalog: typeof(ZONES[1].hubs)): string?
		local slots = GuildHomeCore.slots(catalog)
		if slots == nil then
			return "catalog_invalid"
		end
		local realms: { [string]: boolean } = {}
		for _, slot in slots do
			if realms[slot.realmId] then
				return "realm_duplicated"
			end
			realms[slot.realmId] = true
			local primary = false
			for _, hub in hubCatalog.hubs do
				if hub.id == slot.hubId and hub.tier == "primary" then
					primary = true
				end
			end
			if not primary then
				return "hub_not_primary"
			end
		end
		return nil
	end

	describe("GuildHomeCore authored banner slots", function()
		it("places exactly one home banner slot for each realm on its zone's primary hub", function()
			local seen: { [string]: string } = {}
			for _, zone in ZONES do
				expect((primaryHubSlotRefusal(zone.banners, zone.hubs))):toBeNil()
				local slot = GuildHomeCore.slotFor(zone.banners, zone.realmId)
				expect((slot ~= nil)):toBe(true)
				assert(slot ~= nil)
				expect(seen[slot.id]):toBeNil()
				seen[slot.id] = zone.realmId
			end
		end)

		it("offers no home slot to a realm whose hub is not in this zone", function()
			expect((GuildHomeCore.slotFor(ZONES[1].banners, "south"))):toBeNil()
			expect((GuildHomeCore.slotFor(ZONES[2].banners, "north"))):toBeNil()
			expect((GuildHomeCore.slotFor(ZONES[1].banners, "contested"))):toBeNil()
		end)

		it("refuses a slot bound to a secondary hub or an unknown field", function()
			local secondary = {
				slots = {
					{ id = "x.guild_banner", hubId = "woodland.ruin_road_approach", realmId = "north", label = "Road" },
				},
			}
			expect((primaryHubSlotRefusal(secondary, ZONES[1].hubs))):toBe("hub_not_primary")
			local extra = {
				slots = {
					{
						id = "x.guild_banner",
						hubId = "woodland.village_courtyard",
						realmId = "north",
						label = "Gate",
						power = 3,
					},
				},
			}
			expect((GuildHomeCore.slots(extra))):toBeNil()
			expect((GuildHomeCore.slotFor(extra, "north"))):toBeNil()
		end)

		it("refuses two slots for one realm in one zone", function()
			local doubled = {
				slots = {
					{ id = "a", hubId = "woodland.village_courtyard", realmId = "north", label = "A" },
					{ id = "b", hubId = "woodland.village_courtyard", realmId = "north", label = "B" },
				},
			}
			expect((primaryHubSlotRefusal(doubled, ZONES[1].hubs))):toBe("realm_duplicated")
		end)
	end)

	it("uses configured realm, slot, identifier and label bounds", function()
		local changes: { (Module.Config) -> () } = {
			function(cfg)
				cfg.maxSlots = 0
			end,
			function(cfg)
				cfg.maxIdLength = 1
			end,
			function(cfg)
				cfg.maxLabelLength = 1
			end,
			function(cfg)
				cfg.realms = { other = true }
			end,
		}
		for _, change in changes do
			local cfg: Module.Config = table.clone(settings)
			change(cfg)
			expect(Module.guildhome(cfg).slots(ZONES[1].banners)):toBeNil()
		end
	end)
end
