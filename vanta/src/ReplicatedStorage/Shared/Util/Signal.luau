--!strict
-- Minimal synchronous signal for events between server services.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	local handlers = self._handlers
	local entry = { handler = handler, connected = true }
	table.insert(handlers, entry)
	return {
		Disconnect = function()
			entry.connected = false
			local index = table.find(handlers, entry)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...: any)
	for _, entry in ipairs(table.clone(self._handlers)) do
		if entry.connected then
			entry.handler(...)
		end
	end
end

return Signal
