--!strict
-- Trading settings (L-12, L-53). Placeholders.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- NPC vendors buy anything, at a low share of its value, so a player's buy order is usually the better deal.
	-- An item's value is its `value` field, or this table by tier.
	vendorBuyBack = { rate = 0.25, valueByTier = { 4, 10, 25, 60, 150 } },
	playerShops = {
		-- The royal market tax (L-55): the Crown takes this share of every player shop sale. Rounded down in the
		-- seller's favour; the gold leaves the game.
		marketTaxPercent = 3,
		maxListings = 20,
		maxOrders = 10,
		maxQuantity = 1000, -- per listing or buy order
		maxUnitPrice = 100000,
		recentOperationsKept = 500, -- answers remembered so a retried request applies once
	},
})
