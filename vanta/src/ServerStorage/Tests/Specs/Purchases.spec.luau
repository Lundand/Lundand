--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Purchases = require(ServerScriptService:WaitForChild("Server").Domain.Purchases)
local Fixtures = require(script.Parent.Parent.Fixtures)

return function(t)
	local products = {
		Aura = { id = "Aura", kind = "Cosmetic", productId = 12, enabled = true, entitlementId = "Aura" },
		Off = { id = "Off", kind = "Cosmetic", productId = 13, enabled = false, entitlementId = "Off" },
		Boost = { id = "Boost", kind = "XpBoost", productId = 11, enabled = true, multiplier = 1.5, durationSeconds = 3600 },
	}

	t.test("each purchase is granted exactly once", function()
		local profile = Fixtures.profile()
		t.truthy(Purchases.grant(profile, "p1", 12, products, 100))
		local ok, result = Purchases.grant(profile, "p1", 12, products, 200)
		t.truthy(ok)
		t.truthy(result.alreadyGranted)
		t.truthy(profile.account.entitlements.Aura)
	end)

	t.test("gameplay products, unknown products and disabled products grant nothing", function()
		local profile = Fixtures.profile()
		t.falsy(Purchases.grant(profile, "p1", 11, products, 1), "XP boosts are never sold (L-33)")
		t.falsy(Purchases.grant(profile, "p2", 13, products, 1), "disabled")
		t.falsy(Purchases.grant(profile, "p3", 99, products, 1), "unknown")
		t.falsy(Purchases.grant(profile, "", 12, products, 1), "bad purchase id")
		t.deepEqual(profile.account.receipts, {})
		t.deepEqual(profile.account.entitlements, {})
	end)

	t.test("receipt history stays bounded", function()
		local profile = Fixtures.profile()
		for index = 1, Purchases.MAX_RECEIPTS + 10 do
			Purchases.grant(profile, "p" .. index, 12, products, index)
		end
		local count = 0
		for _ in pairs(profile.account.receipts) do
			count += 1
		end
		t.equal(count, Purchases.MAX_RECEIPTS)
	end)
end
