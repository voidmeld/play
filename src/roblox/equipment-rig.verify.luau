--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Rig = require("./equipment-rig")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Owner = { disposed: boolean, resources: number }
local function ownership()
	local active: Owner? = nil
	local owners: { Owner } = {}
	local function settle<T...>(prior: Owner?, ok: boolean, ...: T...): T...
		active = prior
		if not ok then
			error((...), 0)
		end
		return ...
	end
	local ops: Rig.Ownership<Owner, number> = {
		current = function(): Owner?
			return active
		end,
		create = function(): Owner
			local owner = { disposed = false, resources = 0 }
			table.insert(owners, owner)
			return owner
		end,
		run = function<T...>(owner: Owner, build: () -> T...): T...
			local prior = active
			active = owner
			return settle(prior, pcall(build))
		end,
		dispose = function(owner: Owner)
			owner.disposed = true
			owner.resources = 0
		end,
		checkpoint = function(owner: Owner): number
			return owner.resources
		end,
		rollback = function(owner: Owner, checkpoint: number)
			owner.resources = checkpoint
		end,
	}
	return ops, owners
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("equipment ownership", function()
		it("rolls back refused and throwing attempts without disposing the surrounding owner", function()
			local ops = ownership()
			local lifetime = Rig.lifetime(ops, function(_node: string) end, function(_reason: string) end)
			local owner = ops.create()
			ops.run(owner, function()
				owner.resources = 1
				local result = lifetime.attempt(function(): string?
					owner.resources = 4
					return nil
				end)
				expect(result):toBeNil()
				expect(owner.resources):toBe(1)
				local ran = pcall(lifetime.attempt, function()
					owner.resources = 7
					error("failed")
				end)
				expect(ran):toBe(false)
				expect(owner.resources):toBe(1)
				expect(owner.disposed):toBe(false)
			end)
		end)
		it("disposes loose owners and stale external results and preserves the stale identity", function()
			local ops, owners = ownership()
			local adopted: { string } = {}
			local lifetime = Rig.lifetime(ops, function(node: string)
				table.insert(adopted, node)
			end, function(reason: string)
				error(reason)
			end)
			expect(lifetime.withOwner(function()
				return "built"
			end)):toBe("built")
			lifetime.disposeLoose()
			expect(owners[1].disposed):toBe(true)
			local ok, stale = pcall(lifetime.afterExternal, function()
				return false
			end, true, "mesh")
			expect(ok):toBe(false)
			expect(stale == lifetime.stale):toBe(true)
			expect(owners[2].disposed):toBe(true)
			expect(adopted):toEqual({ "mesh" })
		end)
	end)
	describe("equipment mesh joining", function()
		it("bounds joins, clears in-flight state after errors, and retains refusals", function()
			local now = 0
			local cache: Rig.MeshCache<number, string> = {
				peek = function(): string?
					return nil
				end,
				get = function(): string?
					error("build failed")
				end,
			}
			local joined = Rig.meshCache(cache, 2)
			local function step()
				now += 1
			end
			local function clock(): number
				return now
			end
			expect((pcall(joined.resolve, 1, step, clock))):toBe(false)
			expect(joined.isInFlight(1)):toBe(false)
			joined.refuse(1)
			expect(joined.isRefused(1)):toBe(true)
			expect((pcall(joined.resolve, 1, step, clock))):toBe(false)
			local bounded = Rig.meshCache({
				peek = function(_key: number): string?
					return nil
				end,
				get = function(_key: number): string?
					return coroutine.yield()
				end,
			}, 2)
			local builder = coroutine.create(function()
				bounded.resolve(2, step, clock)
			end)
			assert(coroutine.resume(builder))
			expect((pcall(bounded.resolve, 2, step, clock))):toBe(false)
			expect(now):toBe(2)
			assert(coroutine.resume(builder, "ready"))
			expect(bounded.isInFlight(2)):toBe(false)
		end)
	end)
	describe("equipment batch settlement", function()
		it("retains failed slots, retires successful siblings together and excludes reused pieces", function()
			local ownerA = { disposed = false, resources = 1 }
			local ownerB = { disposed = false, resources = 1 }
			local state = { accessoryOwners = { oldA = ownerA, siblingA = ownerA, oldB = ownerB } }
			local retiredOwners: { [Owner]: boolean } = {}
			local retiredPieces: { [string]: boolean } = {}
			local ops = ownership()
			local host: Rig.BatchHost<string, string, Owner> = {
				slot = function(application: string): string
					return application
				end,
				pieceSlot = function(piece: string): string?
					return if piece == "oldB" then "B" else "A"
				end,
				permitted = function(): string?
					return nil
				end,
				createOwner = ops.create,
				run = ops.run,
				dispose = ops.dispose,
				make = function(application: string): ({ string }?, string?)
					return if application == "B" then nil else { "newA" }, if application == "B" then "refused" else nil
				end,
				attach = function(): string?
					return nil
				end,
				assertCurrent = function() end,
				refused = function() end,
			}
			local applied, failures = Rig.applyBatch(
				host,
				state,
				{ "A", "B" },
				{},
				{},
				{ "oldA", "oldB" },
				retiredOwners,
				retiredPieces
			)
			expect(applied):toEqual({ "A" })
			expect(failures[1].reason):toBe("refused")
			expect(retiredOwners[ownerA]):toBe(true)
			expect(retiredPieces.siblingA):toBe(true)
			expect(retiredOwners[ownerB]):toBeNil()
			local reusedOwners: { [Owner]: boolean } = {}
			Rig.applyBatch(
				host,
				state,
				{ "A" },
				{ A = true },
				{ oldA = true, siblingA = true },
				{ "oldA" },
				reusedOwners,
				{}
			)
			expect((next(reusedOwners))):toBeNil()
		end)
	end)
end
