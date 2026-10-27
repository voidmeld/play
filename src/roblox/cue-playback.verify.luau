--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Mixer = require("./cue-mixer")
local Playback = require("./cue-playback")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("cue playback", function()
		it("limits voices and retriggers with a clock seam and ducks only active families", function()
			local now = 0
			local mixer = Mixer.new({
				specFor = function(id: string): Mixer.MixSpec?
					return if id == "cue"
						then { family = "impact", maxVoices = 2, minIntervalSec = 0.1, voiceSec = 1 }
						else nil
				end,
				duck = function(): Mixer.DuckSpec
					return { bedGain = 0.5, voiceBedGain = 0.2, families = { "impact" } }
				end,
			}, function()
				return now
			end)
			expect(mixer:admit("missing")):toBe(false)
			expect(mixer:gate("missing")):toBe(true)
			expect(mixer:admit("cue")):toBe(true)
			expect(mixer:admit("cue")):toBe(false)
			now = 0.2
			expect(mixer:admit("cue")):toBe(true)
			now = 0.4
			expect(mixer:admit("cue")):toBe(false)
			expect(mixer:duckGain()):toBe(0.5)
			mixer:setVoiceActive(true)
			expect(mixer:duckGain()):toBe(0.2)
			mixer:setVoiceActive(false)
			now = 2
			expect(mixer:activeVoices("impact")):toBe(0)
			expect(mixer:duckGain()):toBe(1)
		end)
		it("plays admitted cue ids and retires native voices at the configured lifetime", function()
			local plays, disposed, delay = 0, 0, 0
			local retire: (() -> ())? = nil
			local target = ""
			local play = Playback.make({
				mountVoice = function(_name: string, _props: Playback.VoiceProps, at: string): (() -> (), string)
					target = at
					return function()
						disposed += 1
					end, "voice"
				end,
				play = function(_voice: string)
					plays += 1
				end,
				schedule = function(seconds: number, callback: () -> ())
					delay, retire = seconds, callback
				end,
				home = "home",
				tailSec = 0.5,
				admit = function(_id: string)
					return true
				end,
				catalog = {
					specFor = function(id: string): Playback.PlaySpec?
						return if id == "cue"
							then {
								soundId = "asset",
								volume = 0.5,
								spatial = true,
								rollOffMinDistance = 4,
								rollOffMaxDistance = 40,
								voiceSec = 1,
							}
							else nil
					end,
				},
			})
			expect(play("missing", "world")):toBe(false)
			expect(play("cue", "world")):toBe(true)
			expect(target):toBe("world")
			expect(plays):toBe(1)
			expect(delay):toBe(1.5)
			assert(retire)
			retire()
			expect(disposed):toBe(1)
		end)
		it("advances VFX from the injected render clock and disconnects at completion", function()
			local now, finished = 0, 0
			local disconnected = false
			local tick: () -> () = function() end
			local alphas: { number } = {}
			local animate = Playback.animator({
				clock = function()
					return now
				end,
				connect = function(callback: () -> ()): () -> ()
					tick = callback
					return function()
						disconnected = true
					end
				end,
			})
			animate(2, function(alpha: number)
				table.insert(alphas, alpha)
			end, function()
				finished += 1
			end)
			now = 1
			tick()
			now = 2
			tick()
			expect(alphas):toEqual({ 0, 0.5, 1 })
			expect(disconnected):toBe(true)
			expect(finished):toBe(1)
		end)
	end)
end
