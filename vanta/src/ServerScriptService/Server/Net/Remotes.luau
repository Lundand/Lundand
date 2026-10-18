--!strict
-- Creates the RemoteEvents listed in Shared.Net.RemoteNames under ReplicatedStorage.Remotes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage:WaitForChild("Shared").Net.RemoteNames)

local Remotes = {}
local events: {[string]: RemoteEvent} = {}

function Remotes.setup()
	if ReplicatedStorage:FindFirstChild("Remotes") then
		error("Remotes already exist; setup must run once", 2)
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in pairs(RemoteNames) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		events[name] = remote
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.get(name: string): RemoteEvent
	local remote = events[name]
	if remote == nil then
		error("unknown remote " .. tostring(name), 2)
	end
	return remote
end

return Remotes
