--!strict

local Scene = require("../../tools/fixtures/character-leases")

local scene = Scene.new({
	schemaVersion = 3,
	maxRevision = 100,
	maxTime = 10000,
	maxFence = 100,
	characterIdLimit = 32,
	zoneIdLimit = 16,
	sessionIdLimit = 32,
	acquisitionIdLimit = 32,
	operationIdLimit = 32,
	fingerprintLimit = 64,
	migrate = function(value)
		return value
	end,
})
local function keyFor(id: string): string
	return "lease:" .. id
end
local repo, store = scene.repository, scene.store
local acquired = repo.acquire(store, keyFor, "character", "session", "acquisition", 0, 20)
assert(acquired.ok)
assert(acquired.value.revision == 1)
local witness =
	{ characterId = "character", operationId = "retirement", fingerprint = "identity", fence = 1, atUnix = 1 }
assert(repo.retire(store, keyFor, witness).ok)
assert(repo.acquire(store, keyFor, "character", "other", "other", 20, 20).reason == "character_retired")
assert(repo.release(store, keyFor, "character", "session", "acquisition", 1).ok)
assert(repo.restore(store, keyFor, witness).ok)
local admitted = repo.acquire(store, keyFor, "character", "new", "new", 21, 20)
assert(admitted.ok)
local claim = {
	characterId = "character",
	sessionId = "new",
	acquisitionId = "new",
	revision = admitted.value.revision,
	fence = admitted.value.revision - 1,
	atUnix = 21,
}
assert(repo.arrive(store, keyFor, claim).ok)
local writes = scene.writes()
assert(repo.arrive(store, keyFor, claim).ok)
assert(scene.writes() == writes)
print("Character leases: retirement, owner drain, restoration and arrival replay passed")
