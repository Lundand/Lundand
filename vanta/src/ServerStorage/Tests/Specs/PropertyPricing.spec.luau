--!strict
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local PropertyPricing = require(Server.Domain.PropertyPricing)
local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)

local rules = Content.propertyRules

return function(t)
	t.test("a busier spot costs more, within the kind's range", function()
		local shop = { kind = "Shop", tier = "Market" }
		local quiet = PropertyPricing.priceOf(shop, 0, rules)
		local middling = PropertyPricing.priceOf(shop, 0.5, rules)
		local busy = PropertyPricing.priceOf(shop, 1, rules)
		t.truthy(quiet < middling and middling < busy, string.format("%d %d %d", quiet, middling, busy))
		t.equal(quiet, rules.pricesByTier.Market * rules.locationFactor.Shop[1])
		t.equal(busy, rules.pricesByTier.Market * rules.locationFactor.Shop[2])
	end)

	t.test("shops feel their spot more than homes do", function()
		local shopSpread = PropertyPricing.priceOf({ kind = "Shop", tier = "Market" }, 1, rules) / PropertyPricing.priceOf({ kind = "Shop", tier = "Market" }, 0, rules)
		local homeSpread = PropertyPricing.priceOf({ kind = "House", tier = "Townhouse" }, 1, rules) / PropertyPricing.priceOf({ kind = "House", tier = "Townhouse" }, 0, rules)
		t.truthy(shopSpread > homeSpread)
	end)

	t.test("prices are rounded, never zero, and an unknown spot costs the middle", function()
		local price = PropertyPricing.priceOf({ kind = "House", tier = "Modest" }, 0.123, rules)
		t.equal(price % rules.priceStep, 0)
		t.truthy(price > 0)
		local unknown = PropertyPricing.priceOf({ kind = "GuildHall", tier = "Hall" }, nil, rules)
		t.equal(unknown, PropertyPricing.priceOf({ kind = "GuildHall", tier = "Hall" }, 0.5, rules))
		t.equal(PropertyPricing.priceOf({ kind = "Shop", tier = "Market" }, 7, rules), PropertyPricing.priceOf({ kind = "Shop", tier = "Market" }, 1, rules), "clamped")
	end)

	t.test("foot traffic in words", function()
		t.equal(PropertyPricing.trafficLabel(0.9), "Busy")
		t.equal(PropertyPricing.trafficLabel(0.4), "Steady")
		t.equal(PropertyPricing.trafficLabel(0.1), "Quiet")
		t.equal(PropertyPricing.trafficLabel(nil), nil)
	end)
end
