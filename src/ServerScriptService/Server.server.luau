--[[
	CORE HUNTERS — server entry point.
	Loads every service, gives each one the shared registry (Init), then starts them in order (Start).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- create all remotes before any client asks for them
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")).Event("Sync")

local S = {
	Data = require(script.DataService),
	World = require(script.WorldBuilder),
	Plots = require(script.PlotService),
	Player = require(script.PlayerService),
	Mobs = require(script.MobService),
	Combat = require(script.CombatService),
	Cores = require(script.CoreService),
	Incubators = require(script.IncubatorService),
	Shop = require(script.ShopService),
	Rift = require(script.RiftService),
	Boards = require(script.BoardService),
	Admin = require(script.AdminService),
	Badges = require(script.BadgeService),
}

local ORDER = { "Data", "World", "Plots", "Mobs", "Combat", "Cores", "Incubators", "Shop", "Rift", "Boards", "Admin", "Badges", "Player" }

for _, name in ORDER do
	S[name].Init(S)
end

for _, name in ORDER do
	local ok, err = pcall(S[name].Start)
	if not ok then
		warn("[Server] " .. name .. " failed to start: " .. tostring(err))
	end
end

workspace:SetAttribute("PvPMode", require(ReplicatedStorage.Shared.Config).PvP.Mode)
print("[CORE HUNTERS] Server ready")
