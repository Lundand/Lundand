--[[
	DataService — loads and saves player profiles.
	* UpdateAsync + session lock: two servers can never overwrite each other's copy
	* autosave every 90 s, save on leave and on server shutdown (BindToClose)
	* Studio without "Enable Studio Access to API Services" still runs, with temporary data
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {}
local S: any

local STORE_NAME = "CoreHunters_Profiles_v1"
local LOCK_TIMEOUT = 150 -- seconds before another server's lock is considered stale
local AUTOSAVE_INTERVAL = 90

local store: DataStore? = nil
local storeError: string? = nil

type Profile = {
	data: any,
	temporary: boolean,
	saving: boolean,
	released: boolean,
}

local profiles: { [Player]: Profile } = {}

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in t do
		copy[k] = deepCopy(v)
	end
	return copy
end
DataService.DeepCopy = deepCopy

local function isArray(t: { [any]: any }): boolean
	return #t > 0 or next(t) == nil
end

-- Fill in keys that were added to the default profile after a player last saved
local function reconcile(target: any, template: any)
	for k, v in template do
		if target[k] == nil then
			target[k] = deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil and not isArray(v) then
			reconcile(target[k], v)
		end
	end
end

function DataService.Default(): any
	return {
		v = 1,
		coins = 0,
		fragments = 0,
		inv = { ["0:w:1:1"] = 1, ["0:c:1:1"] = 1, ["0:a:1:1"] = 1 }, -- [itemKey] = count
		eq = { w = "0:w:1:1", c = "0:c:1:1", a = "0:a:1:1" },
		inc = {}, -- incubator slots: false (empty) or { z, r, odds, mob, s = start, e = end }
		store = {}, -- secured Cores waiting for a free incubator
		up = { train = 0, luck = 0, slots = 0, speed = 0, storage = 0, carry = 0, style = 0 },
		zones = 1, -- highest main zone unlocked
		forgeZone = 1, -- zone of the last monster that gave Fragments (the Forge makes this zone's Core)
		rift = 0, -- highest Endless zone reached (0 = never entered)
		best = {}, -- rarest Cores discovered { z, r, odds, mob, t }
		stats = { kills = 0, cores = 0, delivered = 0, opened = 0, stolen = 0, lost = 0, deaths = 0, bosses = 0, forged = 0 },
		settings = { autoEquip = true, autoIncubate = true },
		boosts = { luck = 0 }, -- os.time() when the personal luck boost ends
		skips = { 0, 0, 0, 0, 0 }, -- unused instant-open credits per tier
		receipts = {}, -- recently processed Robux purchase ids
		carry = false, -- Core being carried when the player left (resumed on rejoin)
		joined = 0,
	}
end

local function key(player: Player): string
	return "p_" .. player.UserId
end

local function lockIsForeign(old: any): boolean
	return type(old) == "table"
		and type(old.lock) == "table"
		and old.lock.job ~= game.JobId
		and os.time() - (tonumber(old.lock.t) or 0) < LOCK_TIMEOUT
end

-- Yields. Returns the profile data (never nil while the player is still in game)
function DataService.Load(player: Player): any
	local profile: Profile = { data = nil, temporary = false, saving = false, released = false }
	local loaded = nil

	if store then
		local ds = store
		for attempt = 1, 6 do
			local ok, result = pcall(function()
				return ds:UpdateAsync(key(player), function(old)
					if lockIsForeign(old) and attempt < 5 then
						return nil -- still locked by another server; try again shortly
					end
					local data = old or DataService.Default()
					data.lock = { job = game.JobId, t = os.time() }
					return data
				end)
			end)
			if ok and type(result) == "table" and type(result.lock) == "table" and result.lock.job == game.JobId then
				loaded = result
				break
			end
			if not ok then
				warn("[Data] Load failed for " .. player.Name .. ": " .. tostring(result))
				if RunService:IsStudio() then
					break
				end
			end
			if not player.Parent then
				return nil
			end
			task.wait(ok and 4 or 2)
		end
	end

	if loaded then
		reconcile(loaded, DataService.Default())
		profile.data = loaded
	else
		profile.data = DataService.Default()
		profile.temporary = true
		if store and not RunService:IsStudio() then
			warn("[Data] Using TEMPORARY data for " .. player.Name .. " (progress will not save this session)")
		end
	end
	if profile.data.joined == 0 then
		profile.data.joined = os.time()
	end
	profiles[player] = profile
	return profile.data
end

function DataService.Get(player: Player): any
	local profile = profiles[player]
	return profile and profile.data
end

function DataService.IsTemporary(player: Player): boolean
	local profile = profiles[player]
	return profile == nil or profile.temporary
end

function DataService.StoreStatus(): string?
	return storeError
end

local function saveProfile(player: Player, profile: Profile, release: boolean)
	if profile.temporary or not store then
		return
	end
	local ds = store
	local started = os.clock()
	while profile.saving and os.clock() - started < 15 do
		task.wait(0.2)
	end
	profile.saving = true
	local data = profile.data
	local ok, err = pcall(function()
		ds:UpdateAsync(key(player), function(old)
			if lockIsForeign(old) then
				return nil -- another server owns this profile now; never overwrite it
			end
			if release then
				data.lock = nil
			else
				data.lock = { job = game.JobId, t = os.time() }
			end
			return data
		end)
	end)
	profile.saving = false
	if not ok then
		warn("[Data] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Saves in the background
function DataService.Save(player: Player)
	local profile = profiles[player]
	if profile and not profile.released then
		task.spawn(saveProfile, player, profile, false)
	end
end

-- Saves and yields until done
function DataService.SaveNow(player: Player)
	local profile = profiles[player]
	if profile and not profile.released then
		saveProfile(player, profile, false)
	end
end

-- Final save when a player leaves; releases the session lock
function DataService.Release(player: Player)
	local profile = profiles[player]
	if not profile or profile.released then
		return
	end
	profile.released = true
	saveProfile(player, profile, true)
	profiles[player] = nil
end

-- Admin/testing: wipe a profile back to defaults
function DataService.Reset(player: Player): any
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local fresh = DataService.Default()
	fresh.receipts = profile.data.receipts or {}
	fresh.joined = os.time()
	profile.data = fresh
	return fresh
end

function DataService.Init(services: any)
	S = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		local message = tostring(result)
		storeError = message
		warn("[Data] DataStores unavailable (" .. message .. "). Progress will not save.")
	end
end

function DataService.Start()
	-- Autosave
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				if player.Parent and not profile.released then
					if S.Player and S.Player.BeforeSave then
						S.Player.BeforeSave(player, false)
					end
					task.spawn(saveProfile, player, profile, false)
					task.wait(0.5)
				end
			end
		end
	end)

	-- Shutdown: save everyone before the server closes
	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			local profile = profiles[player]
			if profile and not profile.released then
				pending += 1
				task.spawn(function()
					pcall(function()
						if S.Player and S.Player.BeforeSave then
							S.Player.BeforeSave(player, true)
						end
					end)
					DataService.Release(player)
					pending -= 1
				end)
			end
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
