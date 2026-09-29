--[[
	Items — shared helpers for zones, Cores and items.
	An item is stored as a string key "zone:slot:index:rarity", e.g. "6:w:2:5"
	= zone 6 (Volcano) weapon #2 (Demon Scythe), rarity 5 (Legendary).
	Power is derived from the key, so data stays tiny and balancing lives in Config.
]]

local Config = require(script.Parent.Config)

local Items = {}

Items.Slots = { "w", "c", "a" }
Items.SlotNames = { w = "Weapon", c = "Class", a = "Ability" }
Items.StyleNames = {
	sword = "Sword",
	katana = "Katana",
	greatsword = "Greatsword",
	scythe = "Scythe",
	daggers = "Daggers",
	spear = "Spear",
	hammer = "Hammer",
	bow = "Bow",
	staff = "Staff",
}
Items.StyleDesc = {
	sword = "Balanced swings",
	katana = "Fast attacks",
	greatsword = "Slow, huge hits",
	scythe = "Hits all around you",
	daggers = "Very fast stabs",
	spear = "Long reach",
	hammer = "Smashes all around you",
	bow = "Ranged shots",
	staff = "Ranged magic bursts",
}

local NUM_ZONES = #Config.Zones
local NUM_RARITIES = #Config.Rarities
Items.NumZones = NUM_ZONES
Items.NumRarities = NUM_RARITIES

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------
function Items.Rec(z: number): number
	if z <= 1 then
		return Config.Zones[1].rec
	end
	if z <= NUM_ZONES then
		return Config.Zones[z].rec
	end
	return Config.Zones[NUM_ZONES].rec * Config.Rift.Growth ^ (z - NUM_ZONES)
end

-- Power needed to walk through the gate into zone z
function Items.Required(z: number): number
	if z <= 1 then
		return 0
	end
	return Items.Rec(z) * Config.GateRequirement
end

function Items.ZoneName(z: number): string
	if z <= 0 then
		return "Spawn"
	end
	if z <= NUM_ZONES then
		return Config.Zones[z].name
	end
	return "Endless Zone " .. z
end

function Items.IsRift(z: number): boolean
	return z > NUM_ZONES
end

function Items.Richness(z: number): number
	if z >= 1 and z <= NUM_ZONES then
		return Config.Zones[z].richness or 1
	end
	return 1
end

function Items.CoreName(z: number): string
	if z <= NUM_ZONES then
		return Config.Zones[math.max(z, 1)].core
	end
	return Config.Rift.Core
end

function Items.CoreColor(z: number): Color3
	if z <= NUM_ZONES then
		return Config.Zones[math.max(z, 1)].coreColor
	end
	return Config.Rift.CoreColor
end

-- "LEGENDARY INFERNO CORE" / "RARE RIFT CORE (Z12)"
function Items.CoreTitle(z: number, r: number): string
	local title = string.upper(Config.Rarities[r].name .. " " .. Items.CoreName(z))
	if z > NUM_ZONES then
		title ..= " (Z" .. z .. ")"
	end
	return title
end

function Items.RarityName(r: number): string
	local rarity = Config.Rarities[r]
	return rarity and rarity.name or "?"
end

function Items.RarityColor(r: number): Color3
	local rarity = Config.Rarities[r]
	return rarity and rarity.color or Color3.new(1, 1, 1)
end

-- Extra monster toughness for a zone (see Config.Difficulty)
function Items.Difficulty(z: number): { speed: number, hp: number, dmg: number, cooldown: number, aggro: number }
	local d = Config.Difficulty
	local n = math.max(0, z - 1)
	return {
		speed = math.min(1 + d.Speed * n, d.MaxSpeed),
		hp = 1 + d.Health * n,
		dmg = 1 + d.Damage * n,
		cooldown = math.max(1 - d.AttackSpeed * n, d.MaxAttackSpeed),
		aggro = d.Aggro * n,
	}
end

-- Round big odds to 2 significant digits so they read nicely (1/16,666 -> 1/17,000)
function Items.Nice(n: number): number
	if n < 100 then
		return math.max(1, math.floor(n + 0.5))
	end
	local digits = math.floor(math.log10(n)) + 1
	local factor = 10 ^ (digits - 2)
	return math.floor(n / factor + 0.5) * factor
end

-- The drop table used in a zone (the Endless Rift has its own, starting at Rare)
function Items.DropTable(z: number, tier: string): { number }
	local tables = z > NUM_ZONES and Config.Rift.DropOdds or Config.DropOdds
	return tables[tier] or tables.normal
end

-- Displayed 1-in-N odds for a rarity from a mob tier in a zone (without player luck); 0 = can't drop
function Items.Odds(z: number, r: number, tier: string): number
	local n = Items.DropTable(z, tier)[r] or 0
	if n <= 0 then
		return 0
	end
	return Items.Nice(n / Items.Richness(z))
end

-- Seconds a Core of rarity r from zone z takes to incubate (before upgrades)
function Items.IncubateTime(z: number, r: number): number
	local inc = Config.Rarities[r].incub
	local t = math.clamp((z - 1) / math.max(NUM_ZONES - 1, 1), 0, 1)
	return math.floor(inc[1] + (inc[2] - inc[1]) * t)
end

--------------------------------------------------------------------------------
-- Item keys
--------------------------------------------------------------------------------
function Items.SetIndex(z: number): number
	if z <= NUM_ZONES then
		return math.max(z, 0)
	end
	return NUM_ZONES + 1
end

function Items.Key(z: number, c: string, i: number, r: number): string
	return string.format("%d:%s:%d:%d", z, c, i, r)
end

function Items.Parse(key: string): (number?, string?, number?, number?)
	if type(key) ~= "string" then
		return nil, nil, nil, nil
	end
	local z, c, i, r = string.match(key, "^(%d+):(%a):(%d+):(%d+)$")
	if not z then
		return nil, nil, nil, nil
	end
	return tonumber(z), c, tonumber(i), tonumber(r)
end

-- Returns the item definition plus its parsed parts
function Items.Def(key: string): (any, number, string, number, number)
	local z, c, i, r = Items.Parse(key)
	if not z or not c or not i or not r then
		return nil, 0, "w", 0, 0
	end
	local set = Config.Items[Items.SetIndex(z)]
	local list = set and set[c]
	local def = list and list[i]
	return def, z, c, i, r
end

function Items.Valid(key: string): boolean
	local def, z, _, _, r = Items.Def(key)
	if not def then
		return false
	end
	if z == 0 then
		return r == 1
	end
	return r >= 1 and r <= NUM_RARITIES
end

function Items.Slot(key: string): string?
	local _, c = Items.Parse(key)
	return c
end

function Items.Power(key: string): number
	local def, z, c, _, r = Items.Def(key)
	if not def then
		return 0
	end
	if z == 0 then
		return Config.StarterPower[c] or 0
	end
	local zone = Config.Zones[z]
	local factor = (zone and zone.itemFactor) or Config.ItemBaseFactor
	return Items.Rec(z) * factor * Config.Rarities[r].mult * Config.ItemShare[c] * (def.var or 1)
end

function Items.Name(key: string): string
	local def = Items.Def(key)
	return def and def.name or "Unknown"
end

-- "Legendary Demon Scythe", "Epic Rift Bow (Z12)"
function Items.FullName(key: string): string
	local def, z, _, _, r = Items.Def(key)
	if not def then
		return "Unknown"
	end
	if z == 0 then
		return def.name
	end
	local name = Config.Rarities[r].name .. " " .. def.name
	if z > NUM_ZONES then
		name ..= " (Z" .. z .. ")"
	end
	return name
end

function Items.Rarity(key: string): number
	local _, _, _, r = Items.Parse(key)
	return r or 1
end

function Items.Zone(key: string): number
	local z = Items.Parse(key)
	return z or 0
end

function Items.Style(key: string): (any, string)
	local def = Items.Def(key)
	if def and def.style then
		return Config.WeaponStyles[def.style], def.style
	end
	return Config.WeaponStyles.sword, "sword"
end

function Items.Ability(key: string): (any, string)
	local def = Items.Def(key)
	if def and def.ability then
		return Config.Abilities[def.ability], def.ability
	end
	return Config.Abilities.dash, "dash"
end

-- Movement abilities are disabled while carrying a Core
Items.MovementAbility = { dash = true, shadowstep = true, warp = true }

-- Cooldown of an ability item; rarer copies recharge faster
function Items.AbilityCooldown(key: string): number
	local ability = Items.Ability(key)
	local r = Items.Rarity(key)
	local mult = math.max(0.4, 1 - (Config.AbilityRarityCooldown or 0) * (r - 1))
	return (ability.cd or 5) * mult
end

function Items.Mods(key: string): { [string]: number }
	local def = Items.Def(key)
	return (def and def.mods) or {}
end

-- The "1/N" label shown next to an item: odds of its rarity from a normal mob in its zone
function Items.OddsLabel(key: string): number
	local _, z, _, _, r = Items.Def(key)
	if z == 0 then
		return 1
	end
	return math.max(1, Items.Odds(z, r, "normal"))
end

local function pct(v: number): string
	local p = v * 100
	if math.abs(p - math.floor(p + 0.5)) < 0.05 then
		return string.format("%d%%", math.floor(p + 0.5))
	end
	return string.format("%.1f%%", p)
end

-- Short stat lines for the UI
function Items.Describe(key: string): { string }
	local def, _, c = Items.Def(key)
	local lines = {}
	if not def then
		return lines
	end
	if c == "w" then
		local style = Config.WeaponStyles[def.style]
		table.insert(lines, (Items.StyleNames[def.style] or "Weapon") .. " — " .. (Items.StyleDesc[def.style] or ""))
		if style then
			table.insert(lines, string.format("%.1f attacks/s • reach %d", style.rate, style.range))
		end
	elseif c == "c" then
		local any = false
		for mod, value in def.mods or {} do
			any = true
			local name = Config.ModNames[mod] or mod
			if mod == "carry" then
				table.insert(lines, "-" .. pct(value) .. " carry slowdown")
			elseif mod == "hazard" then
				table.insert(lines, pct(value) .. " lava/toxic resist")
			elseif mod == "regen" then
				table.insert(lines, "+" .. pct(value) .. " HP regen per second")
			else
				table.insert(lines, (value >= 0 and "+" or "") .. pct(value) .. " " .. name)
			end
		end
		if not any then
			table.insert(lines, "No bonuses yet")
		end
	elseif c == "a" then
		local ability = Config.Abilities[def.ability]
		if ability then
			table.insert(lines, ability.desc or "")
			local cd = Items.AbilityCooldown(key)
			table.insert(lines, string.format("Cooldown %ss", cd == math.floor(cd) and tostring(cd) or string.format("%.1f", cd)))
		end
	end
	return lines
end

--------------------------------------------------------------------------------
-- Rolling
--------------------------------------------------------------------------------
local function weightedIndex(weights: { number }, rng: Random): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local pick = rng:NextNumber() * total
	for i, w in weights do
		pick -= w
		if pick <= 0 then
			return i
		end
	end
	return #weights
end
Items.WeightedIndex = weightedIndex

-- Roll the item inside a Core. Returns key, final rarity, rarity bonus
function Items.Roll(z: number, rarity: number, rng: Random): (string, number, number)
	local upWeights = {}
	for i, entry in Config.OpenUpgrade do
		upWeights[i] = entry[2]
	end
	local bonus = Config.OpenUpgrade[weightedIndex(upWeights, rng)][1]
	local r = math.clamp(rarity + bonus, 1, NUM_RARITIES)

	local cats = { "w", "c", "a" }
	local catWeights = { Config.CategoryWeights.w, Config.CategoryWeights.c, Config.CategoryWeights.a }
	local c = cats[weightedIndex(catWeights, rng)]

	local list = Config.Items[Items.SetIndex(z)][c]
	local itemWeights = {}
	for i, def in list do
		itemWeights[i] = def.weight or 1
	end
	local i = weightedIndex(itemWeights, rng)
	return Items.Key(z, c, i, r), r, r - rarity
end

--------------------------------------------------------------------------------
-- Published odds (shown before any Robux purchase, see Config.PaidRandom)
--------------------------------------------------------------------------------
export type PoolEntry = { c: string, i: number, name: string, chance: number }

-- Every item in a zone's pool with its chance (0..1) of being the item inside a Core; the chances add up to 1
function Items.PoolOdds(z: number): { PoolEntry }
	local list: { PoolEntry } = {}
	local catTotal = Config.CategoryWeights.w + Config.CategoryWeights.c + Config.CategoryWeights.a
	local set = Config.Items[Items.SetIndex(z)]
	for _, c in Items.Slots do
		local defs = set[c]
		local total = 0
		for _, def in defs do
			total += def.weight or 1
		end
		for i, def in defs do
			local chance = (Config.CategoryWeights[c] / catTotal) * ((def.weight or 1) / total)
			table.insert(list, { c = c, i = i, name = def.name, chance = chance })
		end
	end
	return list
end

-- Premium Core rarity odds as { r, chance (0..1) }, rarest last
function Items.PremiumOdds(): { { r: number, chance: number } }
	local total = 0
	for _, e in Config.Premium.odds do
		total += e[2]
	end
	local list = {}
	for _, e in Config.Premium.odds do
		table.insert(list, { r = e[1], chance = e[2] / total })
	end
	return list
end

-- The zone a Premium Core's item comes from: the deepest monster zone the player has unlocked
function Items.PremiumZone(zones: number?): number
	return math.clamp(math.floor(zones or 1), 1, NUM_ZONES)
end

-- The item inside a Core of an exact rarity (no chance to come out rarer, unlike Items.Roll)
function Items.RollItem(z: number, r: number, rng: Random): string
	local cats = { "w", "c", "a" }
	local catWeights = { Config.CategoryWeights.w, Config.CategoryWeights.c, Config.CategoryWeights.a }
	local c = cats[weightedIndex(catWeights, rng)]
	local list = Config.Items[Items.SetIndex(z)][c]
	local itemWeights = {}
	for i, def in list do
		itemWeights[i] = def.weight or 1
	end
	return Items.Key(z, c, weightedIndex(itemWeights, rng), r)
end

-- Rolls a Premium Core: returns the item key and its rarity
function Items.RollPremium(z: number, rng: Random): (string, number)
	local odds = Items.PremiumOdds()
	local weights = {}
	for k, e in odds do
		weights[k] = e.chance
	end
	local r = odds[weightedIndex(weights, rng)].r
	return Items.RollItem(z, r, rng), r
end

--[[
	What one kill drops, as chances (0..1) that add up to 1: out[r] for each rarity and out.none for no Core.
	`luck` is the player's total luck multiplier (PlayerService.GetLuck); the zone's richness is applied here.
	Mirrors CoreService.TryDrop, which tries the rarest Core first and stops at the first success.
]]
function Items.DropChances(z: number, tier: string, luck: number): { [any]: number }
	local odds = Items.DropTable(z, tier)
	local l = luck * Items.Richness(z)
	local out: { [any]: number } = {}
	local miss = 1
	for r = #odds, 1, -1 do
		local p = odds[r] > 0 and math.min(l / odds[r], 0.95) or 0
		out[r] = miss * p
		miss *= 1 - p
	end
	out.none = miss
	return out
end

-- Every possible item name in a zone's pool (for the opening animation)
function Items.PoolNames(z: number): { string }
	local names = {}
	local set = Config.Items[Items.SetIndex(z)]
	for _, c in Items.Slots do
		for _, def in set[c] do
			table.insert(names, def.name)
		end
	end
	return names
end

--------------------------------------------------------------------------------
-- Upgrades
--------------------------------------------------------------------------------
-- Coin cost of the next level (nil when maxed)
function Items.UpgradeCost(id: string, level: number): number?
	local u = Config.Upgrades[id]
	if not u then
		return nil
	end
	if u.costs then
		return u.costs[level + 1]
	end
	if level >= (u.max or math.huge) then
		return nil
	end
	return math.floor(u.base * u.growth ^ level)
end

function Items.MaxLevel(id: string): number
	local u = Config.Upgrades[id]
	if not u then
		return 0
	end
	if u.costs then
		return #u.costs
	end
	return u.max or math.huge
end

-- Incubator slots for an upgrade level (+ game pass bonus)
function Items.SlotCount(level: number, bonus: number): number
	local values = Config.Upgrades.slots.values
	return values[math.clamp(level + 1, 1, #values)] + bonus
end

function Items.StorageCap(level: number): number
	local u = Config.Upgrades.storage
	return u.start + math.clamp(level, 0, u.max) * u.per
end

-- Coins for one normal kill in a zone
function Items.CoinValue(zone: number): number
	local C = Config.Combat
	return math.max(1, C.BaseCoins * (Items.Rec(zone) / C.CoinReference) ^ C.CoinExponent)
end

-- Coins for selling one copy of an item (starter items can't be sold)
function Items.SellValue(key: string): number
	local z, _, _, r = Items.Parse(key)
	if not z or not r or z == 0 then
		return 0
	end
	return math.max(1, math.floor(Items.CoinValue(z) * (Config.Inventory.SellKills[r] or 1) + 0.5))
end

-- Items that count toward the inventory limit
function Items.InventoryCount(inv: { [string]: number }): number
	local n = 0
	for key, count in inv do
		if Items.Zone(key) > 0 then
			n += count
		end
	end
	return n
end

-- Sort helper: strongest first
function Items.SortKeys(keys: { string })
	table.sort(keys, function(a, b)
		local pa, pb = Items.Power(a), Items.Power(b)
		if pa == pb then
			return a < b
		end
		return pa > pb
	end)
	return keys
end

return Items
