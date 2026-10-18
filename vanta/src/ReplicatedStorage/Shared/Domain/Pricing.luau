--!strict
-- What NPC vendors pay for an item (L-53): a low share of its value. Shared so shop windows can show it.
local Pricing = {}

function Pricing.value(def: any, buyBack: any): number
	if type(def.value) == "number" then
		return def.value
	end
	local tiers = buyBack.valueByTier
	return tiers[math.max(1, math.min(#tiers, def.tier or 1))]
end

function Pricing.vendorPays(def: any, buyBack: any): number
	return math.max(1, math.floor(Pricing.value(def, buyBack) * buyBack.rate))
end

return Pricing
