--[[
	IncubatorService — secured Cores go into incubators (or storage if every slot is busy).
	* Common Cores crack open instantly on delivery; rarer ones take longer (Config.Rarities.incub)
	* Timers use os.time(), so they keep running while the player is offline
	* Opening rolls an item from the Core's loot pool, with a small chance to come out 1-2 rarities higher
	* Forge: spend Fragments for a guaranteed Uncommon+ Core of the zone you last fought in
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))

local IncubatorService = {}
local S: any
local RevealEvent: RemoteEvent

local MAX_SLOTS = 12
local rng = Random.new()
local notified: { [Player]: { [number]: number } } = {}

function IncubatorService.SlotCount(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 1
	end
	local bonus = S.Shop.HasPass(player, "ExtraIncubators") and (Config.Passes.ExtraIncubators.slots or 2) or 0
	return math.min(Items.SlotCount(data.up.slots or 0, bonus), MAX_SLOTS)
end

function IncubatorService.StorageCap(player: Player): number
	local data = S.Data.Get(player)
	return data and Items.StorageCap(data.up.storage or 0) or 12
end

function IncubatorService.SpeedMult(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 1
	end
	local mult = math.max(0.2, 1 - (data.up.speed or 0) * Config.Upgrades.speed.per)
	if S.Shop.HasPass(player, "FastIncubation") then
		mult *= Config.Passes.FastIncubation.mult or 0.7
	end
	return mult
end

-- The Forge makes a Core of the zone the player last fought in (never deeper than they have unlocked)
function IncubatorService.ForgeZone(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 1
	end
	return math.clamp(data.forgeZone or data.zones or 1, 1, math.clamp(data.zones or 1, 1, #Config.Zones))
end

function IncubatorService.EnsureSlots(player: Player)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	local count = IncubatorService.SlotCount(player)
	for i = 1, math.max(count, #data.inc) do
		if data.inc[i] == nil then
			data.inc[i] = false
		end
	end
end

function IncubatorService.FreeSlot(player: Player): number?
	local data = S.Data.Get(player)
	if not data then
		return nil
	end
	for i = 1, IncubatorService.SlotCount(player) do
		if not data.inc[i] then
			return i
		end
	end
	return nil
end

-- Can this player secure one more Core of rarity r?
-- Commons open straight into the inventory (or wait in storage if it's full).
-- Base full: the weakest stored Core that a Core of rarity r may push out (scrapped into Fragments)
local function weakestBelow(data: any, r: number): number?
	if not Config.Cores.ScrapWeakest then
		return nil
	end
	local best: number? = nil
	for i, entry in data.store do
		if entry.r < r and (best == nil or entry.r < data.store[best].r) then
			best = i
		end
	end
	return best
end

function IncubatorService.HasRoom(player: Player, r: number?): boolean
	local data = S.Data.Get(player)
	if not data then
		return false
	end
	local storageRoom = #data.store < IncubatorService.StorageCap(player)
	if (r or 2) <= 1 then
		return not S.Player.InventoryFull(player) or storageRoom
	end
	return IncubatorService.FreeSlot(player) ~= nil or storageRoom or weakestBelow(data, r or 2) ~= nil
end

local FULL_MESSAGE = "Your inventory is full! Sell items in the ITEMS menu to open more Cores."

function IncubatorService.ReadyCount(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 0
	end
	local n = 0
	local t = os.time()
	for i = 1, IncubatorService.SlotCount(player) do
		local entry = data.inc[i]
		if entry and t >= entry.e then
			n += 1
		end
	end
	return n
end

local function start(player: Player, slot: number, info: any)
	local data = S.Data.Get(player)
	local seconds = math.floor(Items.IncubateTime(info.z, info.r) * IncubatorService.SpeedMult(player))
	local t = os.time()
	data.inc[slot] = { z = info.z, r = info.r, odds = info.odds, mob = info.mob, s = t, e = t + seconds }
	S.Plots.RefreshIncubators(player)
	S.Player.MarkDirty(player)
end

-- Moves stored Cores into free incubators (when auto-incubate is on, or forced)
function IncubatorService.Fill(player: Player, force: boolean?)
	local data = S.Data.Get(player)
	if not data or (not force and data.settings.autoIncubate == false) then
		return
	end
	while #data.store > 0 do
		local slot = IncubatorService.FreeSlot(player)
		if not slot then
			break
		end
		start(player, slot, table.remove(data.store, 1))
	end
end

-- Rolls the item inside a Core and hands it to the player
local function openCore(player: Player, info: any)
	local data = S.Data.Get(player)
	local key, finalRarity, bonus = Items.Roll(info.z, info.r, rng)
	local before = S.Player.GetPower(player)
	local equipped = S.Player.GiveItem(player, key)
	local after = S.Player.GetPower(player)
	data.stats.opened += 1
	RevealEvent:FireClient(player, {
		z = info.z,
		r = info.r,
		odds = info.odds,
		key = key,
		rarity = finalRarity,
		bonus = bonus,
		equipped = equipped,
		before = before,
		after = after,
	})
	if finalRarity >= 5 then
		S.Player.NotifyAll(player.DisplayName .. " unboxed a " .. string.upper(Items.FullName(key)) .. "!", "announce", { rarity = finalRarity })
	end
	S.Player.MarkDirty(player)
end

-- Returns "opened", "incubating", "stored" or "full" (stored because the inventory is full)
function IncubatorService.AddCore(player: Player, info: any): string
	local data = S.Data.Get(player)
	if not data then
		return "stored"
	end
	if info.r <= 1 then
		if not S.Player.InventoryFull(player) then
			openCore(player, info)
			return "opened"
		end
		table.insert(data.store, { z = info.z, r = info.r, odds = info.odds, mob = info.mob })
		S.Player.MarkDirty(player)
		return "full"
	end
	local slot = IncubatorService.FreeSlot(player)
	if slot then
		start(player, slot, info)
		return "incubating"
	end
	local scrapped: string? = nil
	if #data.store >= IncubatorService.StorageCap(player) then
		local i = weakestBelow(data, info.r)
		if i then
			local old = table.remove(data.store, i)
			local fragments = Config.Cores.ScrapFragments[old.r] or 0
			S.Player.AddFragments(player, fragments)
			scrapped = string.format("Base full: your %s was scrapped for %d Fragments to make room.", Items.CoreTitle(old.z, old.r), fragments)
		end
	end
	table.insert(data.store, { z = info.z, r = info.r, odds = info.odds, mob = info.mob })
	S.Player.MarkDirty(player)
	if scrapped then
		S.Player.Notify(player, scrapped, "warn")
	end
	return "stored"
end

function IncubatorService.Open(player: Player, slot: number): (boolean, string?)
	local data = S.Data.Get(player)
	if not data then
		return false, "Loading..."
	end
	local entry = data.inc[slot]
	if not entry then
		return false, "That incubator is empty."
	end
	if os.time() < entry.e then
		return false, "Not ready yet (" .. Util.Clock(entry.e - os.time()) .. ")"
	end
	if S.Player.InventoryFull(player) then
		return false, FULL_MESSAGE
	end
	data.inc[slot] = false
	openCore(player, entry)
	IncubatorService.Fill(player)
	S.Plots.RefreshIncubators(player)
	return true, nil
end

function IncubatorService.OpenAll(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 0
	end
	local opened = 0
	local t = os.time()
	for i = 1, IncubatorService.SlotCount(player) do
		local entry = data.inc[i]
		if entry and t >= entry.e and not S.Player.InventoryFull(player) then
			data.inc[i] = false
			openCore(player, entry)
			opened += 1
		end
	end
	IncubatorService.Fill(player)
	S.Plots.RefreshIncubators(player)
	return opened
end

-- Robux: finish one incubator instantly
function IncubatorService.Skip(player: Player, slot: number): boolean
	local data = S.Data.Get(player)
	local entry = data and data.inc[slot]
	if not entry or os.time() >= entry.e then
		return false
	end
	entry.e = os.time()
	S.Plots.RefreshIncubators(player)
	S.Player.MarkDirty(player)
	return true
end

-- Remaining seconds on an incubator (0 if ready/empty)
function IncubatorService.Remaining(player: Player, slot: number): number
	local data = S.Data.Get(player)
	local entry = data and data.inc[slot]
	if not entry then
		return 0
	end
	return math.max(0, entry.e - os.time())
end

-- Robux: take time off every running incubator
function IncubatorService.TimeWarp(player: Player, seconds: number)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	for i = 1, #data.inc do
		local entry = data.inc[i]
		if entry then
			entry.e -= seconds
		end
	end
	S.Plots.RefreshIncubators(player)
	S.Player.MarkDirty(player)
end

function IncubatorService.FinishAll(player: Player)
	IncubatorService.TimeWarp(player, 10 ^ 9)
end

local function registerHandlers()
	S.Player.Handle("open", function(player, args)
		local ok, err = IncubatorService.Open(player, tonumber(args.slot) or 0)
		return { ok = ok, msg = err }
	end)

	S.Player.Handle("openAll", function(player)
		local n = IncubatorService.OpenAll(player)
		if S.Player.InventoryFull(player) and IncubatorService.ReadyCount(player) > 0 then
			return { ok = n > 0, msg = FULL_MESSAGE }
		end
		if n == 0 then
			return { ok = false, msg = "No Cores are ready yet." }
		end
		return { ok = true }
	end)

	S.Player.Handle("incubate", function(player, args)
		local data = S.Data.Get(player)
		local index = tonumber(args.index) or 0
		local info = data.store[index]
		if not info then
			return { ok = false, msg = "That Core isn't in storage." }
		end
		local slot = IncubatorService.FreeSlot(player)
		if not slot then
			return { ok = false, msg = "All incubators are busy." }
		end
		table.remove(data.store, index)
		start(player, slot, info)
		return { ok = true, msg = "Incubating " .. Items.CoreTitle(info.z, info.r) }
	end)

	S.Player.Handle("forge", function(player)
		local data = S.Data.Get(player)
		local cost = Config.Forge.cost
		if data.fragments < cost then
			return { ok = false, msg = "You need " .. cost .. " Fragments." }
		end
		if not IncubatorService.HasRoom(player, 2) then
			return { ok = false, msg = "Your base is full! Open Cores or upgrade Core Storage." }
		end
		local weights = {}
		for i, entry in Config.Forge.odds do
			weights[i] = entry[2]
		end
		local r = Config.Forge.odds[Items.WeightedIndex(weights, rng)][1]
		local z = IncubatorService.ForgeZone(player)
		data.fragments -= cost
		local info = { z = z, r = r, odds = Items.Odds(z, r, "normal"), mob = "The Forge" }
		local result = IncubatorService.AddCore(player, info)
		data.stats.forged = (data.stats.forged or 0) + 1
		S.Badges.Check(player)
		S.Player.MarkDirty(player)
		return { ok = true, msg = "Forged a " .. Items.CoreTitle(z, r) .. (result == "stored" and " (in storage)" or "!") }
	end)

	S.Player.Handle("useSkipCredit", function(player, args)
		local data = S.Data.Get(player)
		local slot = tonumber(args.slot) or 0
		local remaining = IncubatorService.Remaining(player, slot)
		if remaining <= 0 then
			return { ok = false, msg = "Nothing to skip there." }
		end
		for tier, product in Config.Products.Skips do
			if (data.skips[tier] or 0) > 0 and product.max >= remaining then
				data.skips[tier] -= 1
				IncubatorService.Skip(player, slot)
				return { ok = true, msg = "Skip used! Your Core is ready." }
			end
		end
		return { ok = false, msg = "You have no skip that covers this timer." }
	end)
end

function IncubatorService.Init(services: any)
	S = services
	RevealEvent = Net.Event("Reveal")
end

function IncubatorService.Start()
	registerHandlers()
	Players.PlayerRemoving:Connect(function(player)
		notified[player] = nil
	end)
	-- "Your Core is ready!" notifications
	task.spawn(function()
		while true do
			task.wait(1)
			local t = os.time()
			for _, player in Players:GetPlayers() do
				local data = S.Data.Get(player)
				if data then
					local seen = notified[player]
					if not seen then
						seen = {}
						notified[player] = seen
						-- don't spam on join for Cores that were already ready
						for i, entry in data.inc do
							if entry then
								seen[i] = entry.s
							end
						end
					end
					for i, entry in data.inc do
						if entry and t >= entry.e and seen[i] ~= entry.s then
							seen[i] = entry.s
							S.Player.Notify(player, "Your " .. Items.CoreTitle(entry.z, entry.r) .. " is ready to open!", "ready", { rarity = entry.r })
							S.Player.MarkDirty(player)
						end
					end
				end
			end
		end
	end)
end

return IncubatorService
