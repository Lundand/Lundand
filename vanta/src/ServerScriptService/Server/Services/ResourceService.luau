--!strict
-- Stamina and mana on the server (the owner's resource requirements). Each player's pool lives here, regenerates over
-- time, and is shown to clients as character attributes (Stamina, MaxStamina, Mana, MaxMana). Combat and abilities
-- spend through this service, which checks every cost. Pools are temporary combat state: not saved, and full again
-- after respawning.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Content)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local ItemStats = require(Shared.Domain.ItemStats)
local ResourceRules = require(Shared.Domain.ResourceRules)
local AbilityRules = require(Shared.Domain.AbilityRules)
local Resources = require(Shared.Config.Resources)

local ResourceService = {}
local services: any = nil
local pools: {[Player]: any} = {}

function ResourceService.init(allServices: any)
	services = allServices
end

local function maximums(player: Player): (number, number)
	local character = services.PlayerDataService.getCharacter(player)
	local maxStamina = 100
	if character ~= nil then
		maxStamina = CharacterProgression.derivedStats(character.level, Content.stats, ItemStats.equipmentBonuses(character.equipment, Content.items, Content.gear)).maxStamina or 100
	end
	return maxStamina, Resources.mana.max
end

local function poolFor(player: Player): any
	local pool = pools[player]
	if pool == nil then
		local maxStamina, maxMana = maximums(player)
		pool = ResourceRules.newPool(maxStamina, maxMana, os.clock())
		pool.meter = 0
		pools[player] = pool
	end
	return pool
end

function ResourceService.canAfford(player: Player, cost: any): boolean
	return ResourceRules.canAfford(poolFor(player), cost, os.clock(), Resources)
end

function ResourceService.spend(player: Player, cost: any): (boolean, string?)
	return ResourceRules.spend(poolFor(player), cost, os.clock(), Resources)
end

-- Restores stamina or mana (Soul Drain), never above the maximums.
function ResourceService.restore(player: Player, amounts: any)
	local pool = poolFor(player)
	ResourceRules.regenerate(pool, os.clock(), Resources)
	pool.stamina = math.min(pool.maxStamina, pool.stamina + (amounts.stamina or 0))
	pool.mana = math.min(pool.maxMana, pool.mana + (amounts.mana or 0))
end

-- The End Ability meter: filled in combat, emptied by the End Ability.
function ResourceService.meter(player: Player): number
	return poolFor(player).meter or 0
end

function ResourceService.addMeter(player: Player, amount: number)
	local pool = poolFor(player)
	pool.meter = AbilityRules.gainMeter(pool.meter or 0, amount, Resources.ultimate.max)
end

function ResourceService.spendMeter(player: Player, amount: number): boolean
	local pool = poolFor(player)
	if (pool.meter or 0) < amount then
		return false
	end
	pool.meter -= amount
	return true
end

local function show(player: Player)
	local model = player.Character
	local pool = pools[player]
	if model == nil or pool == nil then
		return
	end
	ResourceRules.regenerate(pool, os.clock(), Resources)
	local values = {
		Stamina = math.floor(pool.stamina),
		MaxStamina = math.floor(pool.maxStamina),
		Mana = math.floor(pool.mana),
		MaxMana = math.floor(pool.maxMana),
		Ultimate = math.floor(pool.meter or 0),
		UltimateMax = Resources.ultimate.max,
	}
	for name, value in pairs(values) do
		if model:GetAttribute(name) ~= value then
			model:SetAttribute(name, value)
		end
	end
end

function ResourceService.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			pools[player] = nil
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		pools[player] = nil
	end)
	task.spawn(function()
		local refreshAt = 0
		while true do
			task.wait(Resources.syncInterval)
			local now = os.clock()
			local refresh = now >= refreshAt
			if refresh then
				refreshAt = now + 2
			end
			for _, player in ipairs(Players:GetPlayers()) do
				if player.Character ~= nil then
					local pool = poolFor(player)
					if refresh then
						local maxStamina, maxMana = maximums(player)
						if maxStamina ~= pool.maxStamina or maxMana ~= pool.maxMana then
							ResourceRules.resize(pool, maxStamina, maxMana)
						end
					end
					show(player)
				end
			end
		end
	end)
end

return ResourceService
