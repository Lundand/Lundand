--[[
	State — the client's copy of the player's profile (sent by the server on every change)
	and a small wrapper around the Request RemoteFunction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local State = {}

State.Data = nil :: any
local changed = Instance.new("BindableEvent")
local listeners = 0
State.MessageHandler = nil :: ((string, boolean) -> ())?

-- fn(data) runs now (if data exists) and on every update
function State.OnChange(fn: (any) -> ())
	listeners += 1
	changed.Event:Connect(fn)
	if State.Data then
		task.spawn(fn, State.Data)
	end
end

function State.Now(): number
	return workspace:GetServerTimeNow()
end

-- Calls a server action and shows its message (if any). Returns the result table.
function State.Request(action: string, args: { [string]: any }?): any
	local ok, result = pcall(function()
		return Net.Function("Request"):InvokeServer(action, args or {})
	end)
	if not ok or type(result) ~= "table" then
		result = { ok = false, msg = "Couldn't reach the server." }
	end
	if result.msg and result.msg ~= "" and State.MessageHandler then
		State.MessageHandler(result.msg, result.ok == true)
	end
	return result
end

function State.Action(action: string, args: { [string]: any }?)
	Net.Event("Action"):FireServer(action, args or {})
end

function State.Init()
	Net.Event("Sync").OnClientEvent:Connect(function(snapshot)
		State.Data = snapshot
		changed:Fire(snapshot)
	end)
end

return State
