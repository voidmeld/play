--!strict

local Signal = {}

function Signal.new<T>()
	local listeners: { [(T) -> ()]: boolean } = {}
	return {
		connect = function(callback: (T) -> ()): () -> ()
			listeners[callback] = true
			return function()
				listeners[callback] = nil
			end
		end,
		fire = function(value: T)
			for callback in listeners do
				callback(value)
			end
		end,
		count = function(): number
			local count = 0
			for _ in listeners do
				count += 1
			end
			return count
		end,
	}
end

return table.freeze(Signal)
