--!strict
-- Crafted item quality grades, lowest to highest (L-31). How quality is rolled arrives with crafting.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	order = { "Crude", "Standard", "Fine", "Superior", "Masterwork" },
})
