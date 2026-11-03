--!strict

local ProfileSession = require("./persistence/profile-session")
local RecordStore = require("./persistence/record-store")
local SessionLock = require("./persistence/session-lock")
local StoreHost = require("./persistence/store-host")

export type ProfileSessionFlightKind = ProfileSession.FlightKind
export type ProfileSessionState = ProfileSession.State
export type ProfileSessionOutcome = ProfileSession.Outcome
export type ProfileSessionConfig = ProfileSession.Config
export type SessionLockLockState = SessionLock.LockState
export type SessionLockAcquireResult = SessionLock.AcquireResult
export type StoreHostOutcome = StoreHost.Outcome
export type StoreHostDrainOutcome = StoreHost.DrainOutcome
export type StoreHostOperation = StoreHost.Operation
export type StoreHostObservation = StoreHost.Observation
export type StoreHostObserver = StoreHost.Observer
export type StoreHostBudgetKind = StoreHost.BudgetKind
export type StoreHostQueuedWrite = StoreHost.QueuedWrite
export type StoreHostCircuit = StoreHost.Circuit
export type StoreHostRawStore = StoreHost.RawStore
export type StoreHostRealDependencies = StoreHost.RealDependencies
export type StoreHostMemoryStore = StoreHost.MemoryStore
export type StoreHostTestOptions = StoreHost.TestOptions
export type StoreHostStore = StoreHost.Store
export type StoreHostConfig = StoreHost.Config
export type RecordStoreAccepted<R> = RecordStore.Accepted<R>
export type RecordStoreRefused = RecordStore.Refused
export type RecordStoreOutcome<R> = RecordStore.Outcome<R>
export type RecordStoreView = RecordStore.View
export type RecordStoreConfig<R> = RecordStore.Config<R>
export type RecordStoreAPI<R> = RecordStore.API<R>
export type RecordStoreStore = RecordStore.Store
export type RecordStoreStoreOutcome = RecordStore.StoreOutcome

export type API = {
	read profile_session: typeof(ProfileSession),
	read session_lock: typeof(SessionLock),
	read store_host: typeof(StoreHost),
	read record_store: typeof(RecordStore),
}

local api: API = {
	profile_session = ProfileSession,
	session_lock = SessionLock,
	store_host = StoreHost,
	record_store = RecordStore,
}

return table.freeze(api)
