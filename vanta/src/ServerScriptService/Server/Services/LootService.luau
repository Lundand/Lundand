--!strict
-- Equipment drops on kills (L-60: extremely rare). Rolled on the server for each player credited with the kill;
-- the item is granted through a transaction with its rolled rarity and item level, or reported lost if bags are full.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Content)
local LootRules = require(Shared.Domain.LootRules)
local EnemyScaling = require(Shared.Domain.EnemyScaling)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local Remotes = require(script.Parent.Parent.Net.Remotes)

local LootService = {}
local services: any = nil
local random = Random.new()

function LootService.init(allServices: any)
	services = allServices
end

function LootService.onKill(player: Player, enemyId: string, def: any)
	-- Materials and gold from the enemy's loot table; gold scales with the level difference (world specification).
	local character = services.PlayerDataService.getCharacter(player)
	local playerLevel = if character then CharacterProgression.level(character.level, Content.progression) else 1
	local rewardScale = EnemyScaling.rewardMultiplier(playerLevel, def.level or 1, Content.enemyProgression)
	local rolled = LootRules.rollTable(Content.lootTables[def.lootTable or ""], rewardScale, function(): number
		return random:NextNumber()
	end)
	local changes, parts = {}, {}
	for _, entry in ipairs(rolled.items) do
		table.insert(changes, { type = "GrantStack", itemId = entry.itemId, amount = entry.amount })
		table.insert(parts, string.format("%d %s", entry.amount, Content.items[entry.itemId].displayName))
	end
	if rolled.gold > 0 then
		table.insert(changes, { type = "AdjustCurrency", currency = "Gold", amount = rolled.gold })
		table.insert(parts, string.format("%d gold", rolled.gold))
	end
	if #changes > 0 then
		if services.InventoryService.apply(player, "Loot", changes) then
			Remotes.get("Notify"):FireClient(player, "Loot: " .. table.concat(parts, ", "))
		elseif rolled.gold > 0 then
			services.InventoryService.apply(player, "Loot", { { type = "AdjustCurrency", currency = "Gold", amount = rolled.gold } })
			Remotes.get("Notify"):FireClient(player, string.format("Your bags are full; you take only the %d gold.", rolled.gold))
		end
	end
	-- Equipment: a separate, extremely rare roll (L-60).
	local drop = LootRules.roll(def, Content.items, Content.gear.drops, Content.gear.levelCap, function(): number
		return random:NextNumber()
	end, enemyId)
	if drop == nil then
		return
	end
	local ok = services.InventoryService.apply(player, "Loot", {
		{ type = "GrantUnique", itemId = drop.itemId, origin = { kind = "Drop", source = enemyId }, data = { rarity = drop.rarity, itemLevel = drop.itemLevel } },
	})
	local name = Content.items[drop.itemId].displayName
	Remotes.get("Notify"):FireClient(player, if ok
		then string.format(if drop.named then "Trophy: %s (%s, level %d)!" else "Rare find: %s (%s, level %d)!", name, drop.rarity, drop.itemLevel)
		else string.format("You found %s, but your bags are full.", name))
end

function LootService.start() end

return LootService
