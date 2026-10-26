--!strict

local Clock = require("../test-scene/clock")
local DataStore = require("./data-store")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	suite:case("retries transient failures on the fake host clock and returns the committed result", function(t)
		local clock = Clock.new()
		local retry = DataStore.retryPolicy({ attempts = 4, baseDelay = 0.5, maxDelay = 8 })
		local calls = 0
		local ok, result = retry.run(
			function(): (boolean, string)
				calls += 1
				return calls == 3, if calls == 3 then "committed" else "offline"
			end,
			clock.advance,
			function(): number
				return 1
			end
		)
		t:expect(ok):toBe(true)
		t:expect(result):toBe("committed")
		t:expect(calls):toBe(3)
		t:expect(clock.clock()):toBe(1.5)
		t:expect(retry.delay(10, 0.5)):toBe(4)
	end)
	suite:case("exhausted attempts preserve failure instead of claiming a save", function(t)
		local clock = Clock.new()
		local retry = DataStore.retryPolicy({ attempts = 4, baseDelay = 0.5, maxDelay = 8 })
		local calls = 0
		local ok, result = retry.run(
			function(): (boolean, string)
				calls += 1
				return false, "offline"
			end,
			clock.advance,
			function(): number
				return 1
			end
		)
		t:expect(ok):toBe(false)
		t:expect(result):toBe("offline")
		t:expect(calls):toBe(4)
		t:expect(clock.clock()):toBe(3.5)
	end)
end
