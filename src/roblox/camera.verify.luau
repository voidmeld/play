--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Camera = require("./camera")
local Conversation = require("./conversation-camera")
local Verify = require("../../.lute/dependencies/verify/src/core")

local dynamics = Camera.create({
	MIN_ZOOM = 2,
	MAX_ZOOM = 30,
	CLASSIC_MIN_ZOOM = 0.5,
	CLASSIC_MAX_ZOOM = 12,
	SHOULDER_RIGHT = 2,
	SHOULDER_UP = 1,
	BASE_FOV = 70,
	MAX_FOV_WIDEN = 6,
	SPRINT_SPEED_RATIO = 1.15,
	STRUCTURE_ALPHA = 0.25,
	OBSTRUCTION_OMEGA = 8,
	OBSTRUCTION_PADDING = 0.15,
	SPRINT_LEAD = 0.1,
	SPRINT_SPAN = 0.3,
})
local core = Conversation.create({ newSpring = dynamics.newSpring, springStep = dynamics.springStep }, {
	gap = 20,
	minimumSpace = 100,
	omega = 7,
	minimumDistance = 8,
	coverage = 0.7,
	eyeLift = 0.6,
	angles = { 90, -90, 65, -65, 35, -35 },
	touchThresholdSquared = 4,
	stickThresholdSquared = 0.04,
})

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local function settle(state: Camera.Spring, target: number, rate: number): Camera.Spring
		for _ = 1, rate do
			state = dynamics.springStep(state, target, 7, 1 / rate)
		end
		return state
	end
	describe("camera dynamics", function()
		it("settles without overshoot and is stable across frame rates", function()
			local down, up = dynamics.newSpring(14), dynamics.newSpring(0)
			for _ = 1, 300 do
				down = dynamics.springStep(down, 6, 10, 1 / 60)
				up = dynamics.springStep(up, 1, 6, 1 / 60)
				expect(down.position >= 6 - 1e-6 and up.position <= 1 + 1e-6):toBe(true)
			end
			expect(math.abs(down.position - 6) < 0.001):toBe(true)
			expect(
				math.abs(settle(dynamics.newSpring(0), 5, 120).position - settle(dynamics.newSpring(0), 5, 30).position)
					< 1e-6
			):toBe(true)
			for _, dt in { 0, -1 } do
				expect(dynamics.springStep(up, 3, 6, dt)):toEqual(up)
			end
			expect(math.abs(settle(up, 0, 60).position) < 0.01):toBe(true)
		end)
		it("clamps shoulder and field of view while yielding to camera ownership", function()
			for _, blend in { -1, 0, 0.5, 1, 3 } do
				local x, y = dynamics.shoulderOffset(blend)
				expect(x):toBe(2 * math.clamp(blend, 0, 1))
				expect(y):toBe(math.clamp(blend, 0, 1))
			end
			for _, width in { -3, 0, 6, 40 } do
				expect(dynamics.fovTarget(width)):toBe(70 + math.clamp(width, 0, 6))
			end
			expect(dynamics.sprintWiden(19, 16, false) > 0 and dynamics.sprintWiden(19, 16, false) < 6):toBe(true)
			expect(dynamics.sprintWiden(10, 0, false)):toBe(0)
			expect(dynamics.sprintWiden(0, 16, true)):toBe(6)
			for _, state in
				{
					{ true, false, false, false },
					{ true, true, false, true },
					{ true, false, true, true },
					{ false, false, false, true },
				}
			do
				expect(dynamics.yields(state[1], state[2], state[3])):toBe(state[4])
			end
		end)
		it("pulls inward immediately and eases outward without crossing a roof", function()
			local eased = dynamics.smoothObstruction(2, 8, 1 / 60)
			expect(eased > 2 and eased < 8):toBe(true)
			expect(dynamics.smoothObstruction(8, 2, 1 / 60)):toBe(2)
			for _, sample in { { 2.5, 2.35 }, { 0.1, 0 }, { 20, 8 } } do
				expect(dynamics.obstructedDistance(8, sample[1])):toBe(sample[2])
			end
			expect(dynamics.obstructedDistance(8, nil)):toBe(8)
			local fast, slow = 2, 2
			for _ = 1, 120 do
				fast = dynamics.smoothObstruction(fast, 8, 1 / 120)
			end
			for _ = 1, 30 do
				slow = dynamics.smoothObstruction(slow, 8, 1 / 30)
			end
			expect(math.abs(fast - slow) < 1e-6):toBe(true)
		end)
	end)
	describe("conversation camera ownership", function()
		it("waits for streaming, survives temporary obstruction and releases until the next conversation", function()
			local state = core.step(core.new(), "speaker", false, false, 1)
			expect(state.blend.position):toBe(0)
			expect(state.released):toBe(false)
			state = core.step(state, "speaker", true, false, 1)
			expect(state.blend.position > 0.99):toBe(true)
			state = core.step(state, "speaker", false, false, 1 / 60)
			expect(state.released):toBe(false)
			state = core.step(state, "speaker", true, false, 1)
			expect(state.blend.position > 0.99):toBe(true)
			for _, departure in { false, true } do
				local released = core.step(state, "speaker", true, not departure, 1 / 60, departure)
				expect(released.released):toBe(true)
				released = core.step(released, "speaker", true, false, 1)
				expect(released.blend.position < 0.01):toBe(true)
				released = core.step(released, "other", true, false, 1)
				expect(released.blend.position > 0.99):toBe(true)
			end
			local closed = core.step(state, nil, false, false, 1 / 60)
			expect(closed.blend.position > 0.9):toBe(true)
			expect(core.step(closed, nil, false, false, 1).blend.position < 0.01):toBe(true)
		end)
		it("recognizes camera gestures without treating processed taps or movement as camera input", function()
			for _, sample in
				{
					{ "MouseMovement", 4, 0, true, false, true },
					{ "MouseMovement", 4, 0, false, false, false },
					{ "MouseWheel", 0, 0, false, false, true },
					{ "Touch", 4, 0, false, false, true },
					{ "Touch", 4, 0, false, true, false },
					{ "Touch", 0, 0, false, false, false },
					{ "Thumbstick2", 0.5, 0, false, false, true },
					{ "Thumbstick2", 0.01, 0, false, false, false },
					{ "Keyboard", 1, 0, false, false, false },
				}
			do
				expect(
					core.cameraGesture(
						sample[1] :: string,
						sample[2] :: number,
						sample[3] :: number,
						sample[4] :: boolean,
						sample[5] :: boolean
					)
				):toBe(sample[6])
			end
		end)
	end)
end
