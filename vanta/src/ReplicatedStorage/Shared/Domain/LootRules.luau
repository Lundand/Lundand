--!strict
-- Equipment drops (owner's equipment specification; L-60). Drops are extremely rare so most gear is bought from
-- smiths or crafted. Three separate rolls: whether any equipment drops at all (one roll per kill), its rarity given a
-- drop (never Legendary from ordinary drops), and which item. A dropped item takes the enemy's level.
local LootRules = {}
local ORDER = { "Common", "Uncommon", "Rare", "Epic" }

function LootRules.tier(enemyDef: any): string
	return if enemyDef.boss then "Boss" elseif enemyDef.elite then "Elite" else "Normal"
end

-- Whether an item's drop sources (loot table names or enemy ids, def.drop.sources) include this enemy.
local function sourcedFrom(def: any, enemyId: string?, lootTable: string?): boolean
	for _, source in ipairs((def.drop and def.drop.sources) or {}) do
		if source == enemyId or source == lootTable then
			return true
		end
	end
	return false
end

-- Equipment that can drop from this enemy, in a stable order: items whose drop sources name it (weapon progression),
-- plus items with no drop sources at all (the original rule: any real equipment, not development-only, not noDrop).
-- Named drops are excluded here; they roll on their own (LootRules.roll).
function LootRules.pool(items: any, enemyId: string?, lootTable: string?): {string}
	local pool = {}
	for id, def in pairs(items) do
		if def.kind == "Equipment" and not def.developmentOnly and def.noDrop ~= true then
			if def.drop == nil or (not def.drop.named and sourcedFrom(def, enemyId, lootTable)) then
				table.insert(pool, id)
			end
		end
	end
	table.sort(pool)
	return pool
end

-- A rarity from the tier's weights (Normal / Elite / Boss in Config.Gear.drops).
local function pickRarity(drops: any, tier: string, random: () -> number): string
	local weights = drops.rarityWeights[tier] or {}
	local total = 0
	for _, rarity in ipairs(ORDER) do
		total += weights[rarity] or 0
	end
	local pick, chosen = random() * total, ORDER[1]
	for _, rarity in ipairs(ORDER) do
		pick -= weights[rarity] or 0
		if pick < 0 then
			chosen = rarity
			break
		end
	end
	return chosen
end

-- `enemyId` (optional) lets named drops and sourced pools find their enemy.
function LootRules.roll(enemyDef: any, items: any, drops: any, levelCap: number, random: () -> number, enemyId: string?): any?
	local tier = LootRules.tier(enemyDef)
	-- named weapons: their own chance on their own enemy, with a fixed rarity and their designed item level
	if enemyId ~= nil then
		local named = {}
		for id, def in pairs(items) do
			if def.drop and def.drop.named and sourcedFrom(def, enemyId, enemyDef.lootTable) then
				table.insert(named, id)
			end
		end
		table.sort(named)
		for _, id in ipairs(named) do
			local def = items[id]
			if random() < (def.drop.chance or 0) then
				-- named weapons roll their rarity like any drop of this enemy's tier (Epic is the chase)
				return { itemId = id, rarity = pickRarity(drops, tier, random), itemLevel = math.clamp(def.itemLevel or 1, 1, levelCap), named = true }
			end
		end
	end
	if random() >= (drops.equipmentChance[tier] or 0) then
		return nil
	end
	local pool = LootRules.pool(items, enemyId, enemyDef.lootTable)
	if #pool == 0 then
		return nil
	end
	local itemId = pool[math.min(#pool, math.floor(random() * #pool) + 1)]
	local weights = drops.rarityWeights[tier] or {}
	local total = 0
	for _, rarity in ipairs(ORDER) do
		total += weights[rarity] or 0
	end
	local pick, chosen = random() * total, ORDER[1]
	for _, rarity in ipairs(ORDER) do
		pick -= weights[rarity] or 0
		if pick < 0 then
			chosen = rarity
			break
		end
	end
	-- designed weapons keep their own item level; unannotated items take the enemy's level (original rule)
	local def = items[itemId]
	local level = if def.drop ~= nil and def.itemLevel ~= nil then def.itemLevel else (enemyDef.level or 1)
	return { itemId = itemId, rarity = chosen, itemLevel = math.clamp(level, 1, levelCap) }
end

-- Materials and gold from an enemy's loot table: each material rolls on its own chance; gold is scaled by the
-- reward multiplier (level difference) and rounded. Returns { gold, items = { { itemId, amount } } }.
function LootRules.rollTable(lootTable: any, rewardScale: number, random: () -> number): any
	local result = { gold = 0, items = {} }
	if lootTable == nil then
		return result
	end
	if lootTable.gold ~= nil then
		local amount = lootTable.gold.min + math.floor(random() * (lootTable.gold.max - lootTable.gold.min + 1))
		result.gold = math.floor(amount * rewardScale + 0.5)
	end
	for _, entry in ipairs(lootTable.materials or {}) do
		if random() < entry.chance then
			local amount = entry.min + math.floor(random() * (entry.max - entry.min + 1))
			table.insert(result.items, { itemId = entry.itemId, amount = math.min(amount, entry.max) })
		end
	end
	return result
end

return LootRules
