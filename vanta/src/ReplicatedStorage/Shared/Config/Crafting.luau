--!strict
-- Crafting quality rule. A placeholder until O-13 is decided:
-- score = levels above the recipe's minimum * perLevel + facility qualityBonus + random * spread,
-- and the item gets the highest grade whose min the score reaches.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	quality = {
		perLevel = 0.05,
		spread = 0.5,
		grades = {
			{ grade = "Standard", min = 0 },
			{ grade = "Fine", min = 0.6 },
			{ grade = "Superior", min = 1.0 },
			{ grade = "Masterwork", min = 1.4 },
		},
	},
	-- Crafted rarity (L-60: smithing makes the best gear). Weights at the recipe's own level; each profession level
	-- above it multiplies the higher rarities' weights by (1 + levels x growth). A recipe's maxRarity caps the result
	-- (default Epic; top recipes allow Legendary). Legendary never exceeds legendaryCap of the odds.
	rarity = {
		base = { Common = 70, Uncommon = 22, Rare = 7, Epic = 1, Legendary = 0.2 },
		growth = { Common = -0.02, Uncommon = 0.08, Rare = 0.2, Epic = 0.35, Legendary = 0.4 }, -- Common fades with mastery (to a tenth at most)
		defaultMax = "Epic",
		legendaryCap = 0.05,
	},
	-- Profession XP from a craft falls off when the recipe is far below the crafter's level (no grinding trivial items).
	xpFalloff = { { levelsAbove = 10, share = 0 }, { levelsAbove = 5, share = 0.5 } },
})
