--[[
	AdminService — testing tools (the Admin panel in the UI).
	Admins: anyone in Studio, the game owner (or group owner), and Config.Admins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))

local AdminService = {}
local S: any
local cache: { [Player]: boolean } = {}

function AdminService.IsAdmin(player: Player): boolean
	if cache[player] ~= nil then
		return cache[player]
	end
	local admin = RunService:IsStudio() or table.find(Config.Admins, player.UserId) ~= nil
	if not admin then
		if game.CreatorType == Enum.CreatorType.User then
			admin = player.UserId == game.CreatorId
		elseif game.CreatorType == Enum.CreatorType.Group then
			-- group owner (rank 255); add other staff to Config.Admins
			local ok, rank = pcall(function()
				return (player :: any):GetRankInGroup(game.CreatorId)
			end)
			admin = ok and rank >= 255
		end
	end
	cache[player] = admin
	return admin
end

local commands: { [string]: (Player, any) -> string? } = {}

commands.coins = function(player)
	local data = S.Data.Get(player)
	local amount = math.max(1e6, math.floor(S.Mobs.CoinValue(data.zones) * 5000))
	S.Player.AddCoins(player, amount)
	return "+" .. Util.Abbrev(amount) .. " Coins"
end

commands.fragments = function(player)
	S.Player.AddFragments(player, Config.Forge.cost)
	return "+" .. Util.Commas(Config.Forge.cost) .. " Fragments"
end

commands.core = function(player, args)
	local z = math.clamp(tonumber(args.z) or 1, 1, 30)
	local r = math.clamp(tonumber(args.r) or 1, 1, Items.NumRarities)
	S.Cores.GiveGround(player, z, r)
	return "Dropped a " .. Items.CoreTitle(z, r) .. " in front of you"
end

commands.item = function(player, args)
	local z = math.clamp(tonumber(args.z) or 1, 1, 30)
	local r = math.clamp(tonumber(args.r) or 1, 1, Items.NumRarities)
	local key = Items.Roll(z, r, Random.new())
	S.Player.GiveItem(player, key, true)
	return "Gave " .. Items.FullName(key)
end

commands.finish = function(player)
	S.Incubators.FinishAll(player)
	return "All incubators finished"
end

commands.train = function(player)
	local data = S.Data.Get(player)
	data.up.train = (data.up.train or 0) + 10
	S.Player.Invalidate(player)
	return "Power Training +10 levels"
end

commands.unlock = function(player)
	local data = S.Data.Get(player)
	data.zones = #Config.Zones
	player:SetAttribute("ZoneMax", data.zones)
	S.Player.UpdateZoneStat(player)
	S.Player.MarkDirty(player)
	return "All zones unlocked"
end

commands.tp = function(player, args)
	local zone = math.clamp(tonumber(args.zone) or 1, 1, #Config.Zones)
	local data = S.Data.Get(player)
	if zone > data.zones then
		data.zones = zone
		player:SetAttribute("ZoneMax", zone)
		S.Player.UpdateZoneStat(player)
	end
	S.Player.Teleport(player, CFrame.new(Util.ZoneEntry(zone)) * CFrame.Angles(0, -math.pi / 2, 0))
	return "Teleported to " .. Config.Zones[zone].name
end

commands.boss = function(player)
	local zone = Util.PlayerZone(player)
	if zone < 1 or zone > #Config.Zones then
		return "Stand in a main zone first"
	end
	return S.Mobs.SpawnBoss(zone) and "Boss spawned!" or "The boss is already alive (or the zone is asleep)"
end

commands.god = function(player)
	local character = player.Character
	if not character then
		return nil
	end
	local on = not character:GetAttribute("God")
	character:SetAttribute("God", on or nil)
	return on and "God mode ON" or "God mode OFF"
end

commands.luck = function(player)
	local data = S.Data.Get(player)
	data.boosts.luck = math.max(os.time(), data.boosts.luck or 0) + 1800
	S.Player.MarkDirty(player)
	return "x2 luck for 30 minutes"
end

commands.pvp = function()
	local modes = { "Off", "Limited", "Everywhere" }
	local index = table.find(modes, Config.PvP.Mode) or 1
	Config.PvP.Mode = modes[index % #modes + 1]
	workspace:SetAttribute("PvPMode", Config.PvP.Mode)
	S.Player.NotifyAll("PvP mode is now: " .. Config.PvP.Mode, "info")
	return "PvP mode: " .. Config.PvP.Mode
end

commands.pass = function(player, args)
	local name = tostring(args.name)
	if not Config.Passes[name] then
		return "Unknown pass"
	end
	S.Shop.GrantPass(player, name)
	return name .. " granted (this session)"
end

-- Test how the shop looks where Roblox restricts paid random items (Premium Cores, luck)
commands.policy = function(player)
	local on = S.Shop.ToggleRestricted(player)
	return on and "Paid random items: RESTRICTED (as in the UK, NL, BE, AU, BR)" or "Paid random items: allowed"
end

-- Opens one Premium Core for free (tests the reveal and the odds)
commands.premium = function(player)
	S.Shop.OpenPremium(player, 1)
	return "Opened a Premium Core"
end

commands.reset = function(player)
	S.Cores.OnLeave(player)
	S.Rift.OnLeave(player)
	local data = S.Data.Reset(player)
	if not data then
		return nil
	end
	data.carry = false
	S.Incubators.EnsureSlots(player)
	player:SetAttribute("ZoneMax", 1)
	S.Player.UpdateZoneStat(player)
	S.Player.Invalidate(player)
	S.Plots.RefreshIncubators(player)
	S.Plots.RefreshTrophies(player)
	S.Plots.RefreshStyle(player)
	S.Player.Spawn(player)
	return "Your data was reset"
end

function AdminService.Init(services: any)
	S = services
end

function AdminService.Start()
	S.Player.Handle("admin", function(player, args)
		if not AdminService.IsAdmin(player) then
			return { ok = false, msg = "Admins only." }
		end
		local command = commands[tostring(args.cmd)]
		if not command then
			return { ok = false, msg = "Unknown command." }
		end
		local msg = command(player, args)
		S.Player.MarkDirty(player)
		S.Badges.Check(player) -- e.g. zones unlocked from the panel (in Studio the Output lists earned badges)
		return { ok = true, msg = msg }
	end)
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return AdminService
