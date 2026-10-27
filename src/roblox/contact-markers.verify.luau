--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Markers = require("./contact-markers")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("animation contact markers", function()
		it("rejects stale tracks, presents once per stamp, and releases the last watcher", function()
			local at = 1
			local started: ((string) -> ())? = nil
			local marker: (() -> ())? = nil
			local released, presented = 0, 0
			local contacts = Markers.create({
				stamp = function(_character: string): (string?, number?)
					return "attack", at
				end,
				listen = function(_character: string, callback: (string) -> ()): () -> ()
					started = callback
					return function()
						released += 1
					end
				end,
				marker = function(_track: string, callback: () -> ()): () -> ()
					marker = callback
					return function()
						released += 1
					end
				end,
				admit = function(_character: string, _track: string, _id: string, _at: number): boolean
					return true
				end,
			})
			local release = contacts.watch("body")
			assert(started)
			started("clip")
			local cancel = contacts.onContact("body", "attack", 1, function()
				presented += 1
			end, true)
			expect(contacts.confirmed("body", "attack", 1)):toBe(true)
			assert(marker)
			marker()
			marker()
			expect(presented):toBe(1)
			at = 2
			local second = contacts.onContact("body", "attack", 2, function()
				presented += 1
			end, true)
			marker()
			expect(presented):toBe(1)
			contacts.retrigger("body", "clip", "attack", at)
			marker()
			expect(presented):toBe(2)
			cancel()
			second()
			release()
			release()
			expect(released):toBe(2)
		end)
	end)
end
