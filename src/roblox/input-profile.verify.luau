--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Profiles = require("./input-profile")
local Verify = require("../../.lute/dependencies/verify/src/core")

local profiles: { [string]: Profiles.Profile } = {
	travel = {
		id = "travel",
		actions = {
			{ id = "move", keyboard = "WASD", gamepad = "Thumbstick1", touch = "thumbstick" },
			{ id = "select", keyboard = "Tab", gamepad = "ButtonR3", touch = "button" },
			{ id = "confirm", keyboard = "Return", gamepad = "ButtonA", touch = "screen" },
		},
	},
}

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local input = Profiles.create(profiles, { mounted = "mounted", refused = "refused" })
	local function fixture(fail: boolean?, owns: { string }?)
		local routed: { string } = {}
		local releases = 0
		local session = input.start({
			profile = "travel",
			owns = owns or { "move", "select", "confirm" },
			bind = function(_action: Profiles.Action, _touch: boolean, handler: (Profiles.Device) -> ()): () -> ()
				if fail then
					error("bind failed")
				end
				handler("touch")
				return function()
					releases += 1
				end
			end,
			thumbstick = function(handler: ({ x: number, y: number }) -> ()): () -> ()
				handler({ x = 0.5, y = -0.25 })
				return function()
					releases += 1
				end
			end,
			dispatch = function(id: string, device: Profiles.Device)
				table.insert(routed, id .. ":" .. device)
			end,
			intent = function(vector: { x: number, y: number }, device: Profiles.Device)
				table.insert(routed, tostring(vector.x) .. ":" .. device)
			end,
		})
		return session, routed, function()
			return releases
		end
	end
	describe("input profile lifecycle", function()
		it("routes buttons, screen actions and movement across devices and rejects input after stop", function()
			local session, routed, releases = fixture()
			expect(session.phase):toBe("mounted")
			assert(session.press and session.move and session.stop)
			for _, device in input.DEVICES do
				expect(session.press("confirm", device)):toBe(true)
				expect(session.move({ x = 1, y = 0 }, device)):toBe(true)
			end
			expect(routed):toEqual({
				"0.5:touch",
				"select:touch",
				"confirm:keyboard",
				"1:keyboard",
				"confirm:gamepad",
				"1:gamepad",
				"confirm:touch",
				"1:touch",
			})
			session.stop()
			session.stop()
			expect(releases()):toBe(2)
			expect(session.press("select", "touch")):toBe(false)
			expect(session.move({ x = 1, y = 0 }, "keyboard")):toBe(false)
		end)
		it("releases previously mounted resources when a later binding fails", function()
			local session, _routed, releases = fixture(true)
			expect(session.reason):toBe("action_bind_failed")
			expect(releases()):toBe(1)
		end)
		it("refuses malformed dependencies before mounting", function()
			for _, owns in { {}, { "unknown" }, { "move", "move" } } do
				local session = fixture(false, owns)
				expect(session.reason):toBe("owned_actions_invalid")
			end
			expect(input.start({ profile = "travel" }).reason):toBe("dependencies_invalid")
			local session = input.start({
				profile = "missing",
				owns = {},
				bind = false,
				thumbstick = false,
				dispatch = false,
				intent = false,
			})
			expect(session.reason):toBe("profile_unknown")
		end)
		it("independent consumers preserve parity and input classification", function()
			local second = Profiles.create(profiles, { mounted = "other", refused = "other_refused" })
			expect(second.parity(profiles.travel)):toBe(true)
			expect(second.deviceOfInputName("MouseButton1")):toBe("keyboard")
			expect(second.deviceOfInputName("Gamepad1")):toBe("gamepad")
			expect(second.deviceOfInputName("Touch")):toBe("touch")
			expect(second.deviceOfInputName("")):toBeNil()
		end)
	end)
end
