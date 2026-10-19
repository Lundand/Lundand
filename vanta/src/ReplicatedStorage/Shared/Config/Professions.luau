--!strict
-- Professions (L-10, L-11). The list is provisional (O-06): Harvesting covers herbs and wood until decided.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	Mining = {
		id = "Mining",
		displayName = "Mining",
		kind = "Gathering",
		curve = { kind = "Power", base = 50, exponent = 1.5, maxLevel = 50 },
		unlocks = {
			{ id = "MiningEfficiency1", level = 5, displayName = "Faster mining" },
			{ id = "OreSense1", level = 10, displayName = "Sense nearby ore" },
		},
	},
	Harvesting = {
		id = "Harvesting",
		displayName = "Harvesting",
		kind = "Gathering",
		curve = { kind = "Power", base = 50, exponent = 1.5, maxLevel = 50 },
		unlocks = {
			{ id = "HarvestingEfficiency1", level = 5, displayName = "Faster harvesting" },
			{ id = "HerbSense1", level = 10, displayName = "Sense nearby herbs" },
		},
	},
	-- Woodcutting: foresters fell trees for timber (owner, 2026-10-16).
	Woodcutting = {
		id = "Woodcutting",
		displayName = "Woodcutting",
		kind = "Gathering",
		curve = { kind = "Power", base = 50, exponent = 1.5, maxLevel = 50 },
		unlocks = {
			{ id = "WoodcuttingEfficiency1", level = 5, displayName = "Faster chopping" },
			{ id = "TimberSense1", level = 10, displayName = "Sense good timber" },
		},
	},
	Blacksmithing = {
		id = "Blacksmithing",
		displayName = "Blacksmithing",
		kind = "Crafting",
		curve = { kind = "Power", base = 60, exponent = 1.5, maxLevel = 50 },
		unlocks = {},
	},
	Alchemy = {
		id = "Alchemy",
		displayName = "Alchemy",
		kind = "Crafting",
		curve = { kind = "Power", base = 60, exponent = 1.5, maxLevel = 50 },
		unlocks = {},
	},
})
