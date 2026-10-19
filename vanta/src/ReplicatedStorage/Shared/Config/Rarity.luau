--!strict
-- Class and item rarities, lowest to highest.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },
	-- Rarities the church awakening can roll (L-08). Legendary classes only come from class books (L-22).
	awakening = { Common = true, Uncommon = true, Rare = true, Epic = true,
		Unique = true },
	classTiers = { "Common", "Rare", "Unique", "Epic", "Legendary" }, -- class tiers (L-58); items use `order`
})
