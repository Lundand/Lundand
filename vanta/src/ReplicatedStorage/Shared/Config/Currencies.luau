--!strict
-- In-game currencies. Balances are whole numbers and can never go negative.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	Gold = { id = "Gold", displayName = "Gold", max = 1000000000000 },
})
