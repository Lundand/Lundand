--[[
	Net — creates (server) or waits for (client) every remote the game uses.

	Server -> Client:  Sync (profile snapshot), Notify (toasts/banners), FX (effects), Reveal (Core opening)
	Client -> Server:  Attack, Ability, Action (fire-and-forget), Request (RemoteFunction with a reply)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local EVENTS = { "Sync", "Notify", "FX", "Reveal", "Attack", "Ability", "Action" }
local FUNCTIONS = { "Request" }

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		local f: Folder
		if existing and existing:IsA("Folder") then
			f = existing
		else
			f = Instance.new("Folder")
			f.Name = "Remotes"
			f.Parent = ReplicatedStorage
		end
		for _, name in EVENTS do
			if not f:FindFirstChild(name) then
				local e = Instance.new("RemoteEvent")
				e.Name = name
				e.Parent = f
			end
		end
		for _, name in FUNCTIONS do
			if not f:FindFirstChild(name) then
				local rf = Instance.new("RemoteFunction")
				rf.Name = name
				rf.Parent = f
			end
		end
		folder = f
		return f
	end
	local f = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	folder = f
	return f
end

function Net.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Net
