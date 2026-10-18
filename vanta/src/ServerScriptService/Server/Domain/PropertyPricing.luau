--!strict
-- What a property costs (L-28, L-54): its tier's price, moved by where it stands. The city layout gives each property
-- a foot-traffic score from 0 (a quiet back lane far from the square) to 1 (a main road by the square); the rules give
-- each kind of property a range of factors to scale by (shops the widest, since they live off passers-by).
local PropertyPricing = {}

-- The price, rounded to the rules' step. A property with no known spot (traffic nil) costs the middle of its range.
function PropertyPricing.priceOf(property: any, traffic: number?, rules: any): number
	local base = rules.pricesByTier[property.tier]
	local range = rules.locationFactor[property.kind] or { 1, 1 }
	local t = math.clamp(if traffic == nil then 0.5 else traffic, 0, 1)
	local factor = range[1] + (range[2] - range[1]) * t
	local step = rules.priceStep or 1
	return math.max(step, math.floor(base * factor / step + 0.5) * step)
end

-- How busy a spot is, in words, for the property window.
function PropertyPricing.trafficLabel(traffic: number?): string?
	if traffic == nil then
		return nil
	elseif traffic >= 0.6 then
		return "Busy"
	elseif traffic >= 0.3 then
		return "Steady"
	end
	return "Quiet"
end

return PropertyPricing
