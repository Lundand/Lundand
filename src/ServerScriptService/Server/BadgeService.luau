--[[
	BadgeService — awards the Roblox badges in Config.Badges.
	* Every badge is a condition on the player's saved data, so progress made before a badge existed
	  (or while it had no ID yet) is awarded the next time the player joins.
	* Check(player) is called after the moments that can earn one (delivering a Core, unlocking a zone, kills,
	  steals, the Forge, upgrades, the Rift). It only talks to Roblox for badges that are newly earned.
	* While a badge's id is 0 nothing is awarded; in Studio the Output says which badge would have been earned.
]]

local RobloxBadges = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BadgeService = {}
local S: any

type Session = { owned: { [number]: boolean }, tried: { [string]: boolean }, ready: boolean }
local sessions: { [Player]: Session } = {}
local enabled: { [number]: boolean } = {} -- badge id -> IsEnabled (asked once per server)

local function bestRarity(data: any): number
	local best = 0
	for _, entry in data.best or {} do
		best = math.max(best, entry.r or 0)
	end
	return best
end

-- The condition for each badge key (see Config.Badges)
local EARNED: { [string]: (data: any) -> boolean } = {
	FirstCore = function(d)
		return (d.stats.delivered or 0) >= 1
	end,
	Rare = function(d)
		return bestRarity(d) >= 3
	end,
	Epic = function(d)
		return bestRarity(d) >= 4
	end,
	Legendary = function(d)
		return bestRarity(d) >= 5
	end,
	Mythic = function(d)
		return bestRarity(d) >= 6
	end,
	Divine = function(d)
		return bestRarity(d) >= 7
	end,
	Secret = function(d)
		return bestRarity(d) >= 8
	end,
	Forest = function(d)
		return (d.zones or 1) >= 2
	end,
	DarkForest = function(d)
		return (d.zones or 1) >= 3
	end,
	Desert = function(d)
		return (d.zones or 1) >= 4
	end,
	Frozen = function(d)
		return (d.zones or 1) >= 5
	end,
	Volcano = function(d)
		return (d.zones or 1) >= 6
	end,
	Wasteland = function(d)
		return (d.zones or 1) >= 7
	end,
	Void = function(d)
		return (d.zones or 1) >= 8
	end,
	Rift = function(d)
		return (d.rift or 0) > 0
	end,
	Boss = function(d)
		return (d.stats.bosses or 0) >= 1
	end,
	Kills1K = function(d)
		return (d.stats.kills or 0) >= 1000
	end,
	Kills25K = function(d)
		return (d.stats.kills or 0) >= 25000
	end,
	Steal = function(d)
		return (d.stats.stolen or 0) >= 1
	end,
	Forge = function(d)
		return (d.stats.forged or 0) >= 1
	end,
	CoreFarm = function(d)
		return (d.up.slots or 0) >= #Config.Upgrades.slots.costs
	end,
	GoldenBase = function(d)
		return (d.up.style or 0) >= #Config.Upgrades.style.levels
	end,
}
BadgeService.Conditions = EARNED

local function isEnabled(id: number): boolean
	if enabled[id] == nil then
		local ok, info = pcall(function()
			return RobloxBadges:GetBadgeInfoAsync(id)
		end)
		if not ok or type(info) ~= "table" then
			return true -- couldn't ask: try anyway, AwardBadgeAsync fails harmlessly
		end
		enabled[id] = info.IsEnabled ~= false
	end
	return enabled[id]
end

local function award(player: Player, session: Session, key: string, badge: any)
	session.tried[key] = true
	local id = tonumber(badge.id) or 0
	if id <= 0 then
		if RunService:IsStudio() then
			print(string.format("[Badges] %s earned \"%s\" (paste its badge ID into Config.Badges.%s.id to award it)", player.Name, badge.name or key, key))
		end
		return
	end
	if session.owned[id] or not isEnabled(id) then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return RobloxBadges:AwardBadgeAsync(player.UserId, id)
		end)
		if ok and result then
			session.owned[id] = true
			S.Player.Notify(player, "🏅 Badge unlocked: " .. (badge.name or key) .. "!", "success")
		elseif not ok then
			warn("[Badges] could not award " .. key .. ": " .. tostring(result))
			session.tried[key] = nil -- try again next time
		end
	end)
end

-- Awards every badge the player has earned but doesn't own yet
function BadgeService.Check(player: Player)
	local session = sessions[player]
	local data = S.Data.Get(player)
	if not session or not session.ready or not data then
		return
	end
	for key, badge in Config.Badges do
		local earned = EARNED[key]
		if earned and not session.tried[key] and earned(data) then
			award(player, session, key, badge)
		end
	end
end

-- Which configured badges the player already owns (10 per request), then a first Check
local function load(player: Player)
	local session: Session = { owned = {}, tried = {}, ready = false }
	sessions[player] = session
	local ids = {}
	for _, badge in Config.Badges do
		local id = tonumber(badge.id) or 0
		if id > 0 then
			table.insert(ids, id)
		end
	end
	for i = 1, #ids, 10 do
		local batch = table.move(ids, i, math.min(i + 9, #ids), 1, {})
		local ok, owned = pcall(function()
			return RobloxBadges:CheckUserBadgesAsync(player.UserId, batch)
		end)
		if ok and type(owned) == "table" then
			for _, id in owned do
				session.owned[id] = true
			end
		end
	end
	-- wait for the save to load before checking conditions
	for _ = 1, 60 do
		if S.Data.Get(player) or not player.Parent then
			break
		end
		task.wait(0.5)
	end
	session.ready = true
	BadgeService.Check(player)
end

function BadgeService.Init(services: any)
	S = services
end

function BadgeService.Start()
	for key in Config.Badges do
		if not EARNED[key] then
			warn("[Badges] Config.Badges." .. key .. " has no condition in BadgeService")
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return BadgeService
