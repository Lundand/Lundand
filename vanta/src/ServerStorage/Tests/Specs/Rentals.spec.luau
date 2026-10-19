--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local Rentals = require(Server.Domain.Rentals)
local Transaction = require(Server.Domain.Transaction)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local rules = Content.propertyRules.rental
local inns = { SquareInn = { id = "SquareInn" }, HarbourInn = { id = "HarbourInn" } }
local DAY = rules.dayLengthSeconds

local function renter(gold: number)
	local profile, deps = Fixtures.profile(), Fixtures.deps(1)
	Transaction.apply(profile, "main", { id = "setup", changes = { { type = "AdjustCurrency", currency = "Gold", amount = gold } } }, deps)
	return profile, deps
end

return function(t)
	t.test("renting charges once and sets the expiry", function()
		local profile, deps = renter(1000)
		local ok, result = Rentals.rent(profile, "main", "SquareInn", 2, "rent-1", inns, rules, deps)
		t.truthy(ok, tostring(result))
		t.equal(result.expiresAt, deps.now() + 2 * DAY)
		t.equal(Fixtures.character(profile).currencies.Gold, 1000 - 2 * rules.pricePerDay)
		local _, again = Rentals.rent(profile, "main", "SquareInn", 2, "rent-1", inns, rules, deps)
		t.truthy(again.alreadyApplied)
		t.equal(Fixtures.character(profile).currencies.Gold, 1000 - 2 * rules.pricePerDay)
	end)

	t.test("extensions add to the expiry up to the maximum", function()
		local profile, deps = renter(10000)
		Rentals.rent(profile, "main", "SquareInn", 3, "rent-1", inns, rules, deps)
		local ok, result = Rentals.rent(profile, "main", "SquareInn", 2, "rent-2", inns, rules, deps)
		t.truthy(ok)
		t.equal(result.expiresAt, deps.now() + 5 * DAY)
		t.falsy(Rentals.rent(profile, "main", "SquareInn", rules.maxDays, "rent-3", inns, rules, deps), "beyond the maximum")
	end)

	t.test("one room at a time, and no rental without the gold", function()
		local profile, deps = renter(1000)
		Rentals.rent(profile, "main", "SquareInn", 1, "rent-1", inns, rules, deps)
		t.falsy(Rentals.rent(profile, "main", "HarbourInn", 1, "rent-2", inns, rules, deps))
		local poor, poorDeps = renter(10)
		t.falsy(Rentals.rent(poor, "main", "SquareInn", 1, "rent-3", inns, rules, poorDeps))
		t.deepEqual(poor.account.rentals, {})
	end)

	t.test("only the renter and invited guests can enter, until the rental ends", function()
		local profile, deps = renter(1000)
		Rentals.rent(profile, "main", "SquareInn", 1, "rent-1", inns, rules, deps)
		local now = deps.now()
		local account = profile.account
		t.truthy(Rentals.canEnter(account, 1, "SquareInn", 1, now), "renter")
		t.falsy(Rentals.canEnter(account, 1, "SquareInn", 2, now), "stranger")
		t.truthy(Rentals.invite(account, "SquareInn", 2, now, rules))
		t.truthy(Rentals.canEnter(account, 1, "SquareInn", 2, now), "guest")
		t.truthy(Rentals.revoke(account, "SquareInn", 2))
		t.falsy(Rentals.canEnter(account, 1, "SquareInn", 2, now), "guest removed")
		t.falsy(Rentals.canEnter(account, 1, "SquareInn", 1, now + DAY), "expired")
		t.equal(Rentals.pruneExpired(account, now + DAY), 1)
	end)
end
