--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local LintBatches = require("./lint-batches")
local Verify = require("../../.lute/dependencies/verify/src/core")

local CRASH = "error: Cannot resume a non-thread reference"

local function files(count: number): { string }
	local out: { string } = {}
	for index = 1, count do
		table.insert(out, "src/file-" .. index .. ".luau")
	end
	return out
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("lint batches", function()
		it("splits files into fixed-size batches", function()
			local batches = LintBatches.batches(files(7), 3)
			expect(#batches):toBe(3)
			expect(#batches[1]):toBe(3)
			expect(#batches[3]):toBe(1)
		end)

		it("retries a batch only when the runtime crash signature appears", function()
			local calls = 0
			local ok = LintBatches.run({ "lint" }, files(2), function(_argv)
				calls += 1
				if calls == 1 then
					return { ok = false, stdout = "", stderr = CRASH }
				end
				return { ok = true, stdout = "", stderr = "" }
			end)
			expect(ok):toBe(true)
			expect(calls):toBe(2)
		end)

		it("fails immediately on real lint violations without retrying", function()
			local calls = 0
			local ok, report = LintBatches.run({ "lint" }, files(2), function(_argv)
				calls += 1
				return { ok = false, stdout = "warning: unused variable", stderr = "" }
			end)
			expect(ok):toBe(false)
			expect(calls):toBe(1)
			expect(string.find(report, "lint violations", 1, true) ~= nil):toBe(true)
		end)

		it("fails when the crash persists past the attempt limit", function()
			local calls = 0
			local ok, report = LintBatches.run({ "lint" }, files(1), function(_argv)
				calls += 1
				return { ok = false, stdout = "", stderr = CRASH }
			end)
			expect(ok):toBe(false)
			expect(calls):toBe(LintBatches.ATTEMPTS)
			expect(string.find(report, "persisted", 1, true) ~= nil):toBe(true)
		end)

		it("passes every file to some batch exactly once", function()
			local seen: { [string]: number } = {}
			LintBatches.run({ "lint" }, files(53), function(argv)
				for index = 2, #argv do
					seen[argv[index]] = (seen[argv[index]] or 0) + 1
				end
				return { ok = true, stdout = "", stderr = "" }
			end)
			local count = 0
			for _, times in seen do
				expect(times):toBe(1)
				count += 1
			end
			expect(count):toBe(53)
		end)
	end)
end
