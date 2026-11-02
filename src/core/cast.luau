--!strict

local Queue = require("./cast/queue")

export type QueueConfig = Queue.Config
export type QueueEntry<T> = Queue.Entry<T>
export type QueueState<T> = Queue.State<T>
export type QueueWindows = Queue.Windows

export type API = {
	read queue: typeof(Queue),
}

local api: API = {
	queue = Queue,
}

return table.freeze(api)
