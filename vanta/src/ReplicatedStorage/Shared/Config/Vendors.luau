--!strict
-- NPC vendors (L-12): basic tools and supplies for gold, never above the first tier, so crafted goods stay
-- worth making. Each vendor is opened through its NPC's conversation.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	ForgeTools = {
		id = "ForgeTools",
		displayName = "The Forge Master's tools",
		npc = "ForgeMaster",
		-- the Watchman's Sword: the starter-band baseline sword (tier 1), always available (WEAPON_PROGRESSION_PLAN.md)
		stock = { { itemId = "CopperPickaxe", price = 40 }, { itemId = "CopperHatchet", price = 35 }, { itemId = "WatchmansSword", price = 75 } },
	},
	ApothecaryPotions = {
		id = "ApothecaryPotions",
		displayName = "The Apothecary's shelf",
		npc = "Apothecary",
		stock = { { itemId = "MinorHealthPotion", price = 15 } },
	},
})
