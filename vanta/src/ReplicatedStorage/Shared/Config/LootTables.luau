--!strict
-- Material and gold drops per enemy loot table (owner's world specification). Each entry rolls on its own chance;
-- gold scales with the level-difference rule like experience, materials don't (they stay useful to crafters).
-- Equipment drops are separate and extremely rare (Gear.drops, L-60). Placeholders to tune.
local Table = require(script.Parent.Parent.Util.Table)

local function m(itemId: string, chance: number, min: number, max: number): any
	return { itemId = itemId, chance = chance, min = min, max = max }
end

return Table.deepFreeze({
	Wolves = { materials = { m("WolfPelt", 0.6, 1, 2), m("WolfFang", 0.3, 1, 1) } },
	Boars = { materials = { m("BoarHide", 0.7, 1, 2) } },
	WolfAlpha = { materials = { m("WolfPelt", 1, 2, 3), m("AlphaFang", 0.35, 1, 1) } },
	Thieves = { gold = { min = 2, max = 6 }, materials = { m("LeatherScraps", 0.4, 1, 2) } },
	Bandits = { gold = { min = 4, max = 10 }, materials = { m("ScrapMetal", 0.5, 1, 2), m("LeatherScraps", 0.3, 1, 1) } },
	Enforcer = { gold = { min = 15, max = 30 }, materials = { m("ScrapMetal", 1, 2, 3) } },
	HideoutLeader = { gold = { min = 60, max = 100 }, materials = { m("ScrapMetal", 1, 3, 5), m("LeaderSignet", 0.5, 1, 1) } },
	-- Mountain tables: placeholders until the mountain place and its materials exist
	MountainBeasts = { materials = { m("WolfPelt", 0.5, 1, 2) } },
	Goblins = { gold = { min = 8, max = 16 }, materials = { m("ScrapMetal", 0.6, 1, 2) } },
	Troll = { gold = { min = 30, max = 60 }, materials = { m("ScrapMetal", 1, 2, 4) } },
	Warlord = { gold = { min = 150, max = 250 }, materials = { m("ScrapMetal", 1, 4, 6), m("IronOre", 1, 3, 5) } },
})
