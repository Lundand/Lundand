--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local Cosmetics = require(Shared.Domain.Cosmetics)
local Purchases = require(Server.Domain.Purchases)
local Outbox = require(Server.Domain.Outbox)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local catalogue = Content.cosmetics

local function configured(id: string, overrides: any?): any
	local item = table.clone(catalogue.items[id])
	item.productId = 1001
	for key, value in pairs(overrides or {}) do
		item[key] = value
	end
	return item
end

return function(t)
	t.test("availability: nothing is sold before its product exists or outside its dates", function()
		t.equal(Cosmetics.availability(catalogue.items.NavyWardenCloak, 0), "NotConfigured")
		t.equal(Cosmetics.availability(configured("NavyWardenCloak"), 0), "Available")
		local mask = configured("RiftTouchedMask")
		t.equal(Cosmetics.availability(mask, mask.startsAt - 1), "Upcoming")
		t.equal(Cosmetics.availability(mask, mask.startsAt), "Available")
		t.equal(Cosmetics.availability(mask, mask.endsAt), "Ended")
		t.equal(Cosmetics.availability(configured("NavyWardenCloak", { status = "Retired" }), 0), "Retired")
		t.equal(Cosmetics.label(mask), "LimitedTime")
		t.equal(Cosmetics.label(catalogue.items.NavyWardenCloak), "Permanent")
	end)

	t.test("owned items stay owned and wearable after they leave the shop", function()
		local profile = Fixtures.profile()
		local account, character = profile.account, Fixtures.character(profile)
		local cloak = configured("NavyWardenCloak")
		t.truthy(Cosmetics.canBuy(account, cloak, 0))
		t.falsy(Cosmetics.equip(account, character, "NavyWardenCloak", catalogue), "not owned yet")
		t.truthy(Cosmetics.grant(account, "NavyWardenCloak", "Purchase", 5))
		t.falsy(Cosmetics.grant(account, "NavyWardenCloak", "Purchase", 6), "granted once")
		t.falsy(Cosmetics.canBuy(account, cloak, 0), "already owned: no second prompt")
		t.truthy(Cosmetics.equip(account, character, "NavyWardenCloak", catalogue))
		t.equal(character.appearance.cosmetics.Cloak, "NavyWardenCloak")
		t.truthy(Cosmetics.unequip(character, "Cloak"))
		t.falsy(Cosmetics.unequip(character, "Cloak"))
	end)

	t.test("class-specific skins check the wearer's class", function()
		local profile = Fixtures.profile()
		local account, character = profile.account, Fixtures.character(profile)
		Cosmetics.grant(account, "SilverfangSwordSkin", "Purchase", 0)
		t.falsy(Cosmetics.equip(account, character, "SilverfangSwordSkin", catalogue), "no class yet")
		character.class.classId = "Swordmaster"
		t.truthy(Cosmetics.equip(account, character, "SilverfangSwordSkin", catalogue))
		t.equal(character.appearance.cosmetics["WeaponSkin.Sword"], "SilverfangSwordSkin")
	end)

	t.test("the receipt handler grants cosmetics and records donations exactly once", function()
		local profile = Fixtures.profile()
		local products = {
			{ id = "Cloak", kind = "Cosmetic", productId = 111, enabled = true, cosmeticId = "NavyWardenCloak" },
			{ id = "Donate100", kind = "RiftDonation", productId = 222, enabled = true, robux = 100 },
		}
		t.truthy(Purchases.grant(profile, "p1", 111, products, 5))
		t.truthy(Cosmetics.owns(profile.account, "NavyWardenCloak"))
		local _, again = Purchases.grant(profile, "p1", 111, products, 6)
		t.truthy(again.alreadyGranted)
		t.truthy(Purchases.grant(profile, "p2", 222, products, 7, { robuxSpent = 100, eventId = "RIFT_0001" }))
		Purchases.grant(profile, "p2", 222, products, 8, { robuxSpent = 100, eventId = "RIFT_0001" })
		local pending = Outbox.pending(profile.account)
		t.equal(#pending, 1, "a duplicate receipt adds nothing")
		t.equal(pending[1].entry.robux, 100)
		t.equal(pending[1].entry.eventId, "RIFT_0001")
		Outbox.complete(profile.account, "p2")
		t.equal(#Outbox.pending(profile.account), 0)
		t.falsy(Purchases.grant(profile, "p3", 0, Purchases.catalogue(Content.products, catalogue), 9), "unconfigured products can't be granted")
	end)

	t.test("the outbox delivers oldest first and keeps anything not yet fully settled", function()
		local account: any = {}
		Outbox.add(account, "a", { kind = "RiftDonation", at = 1 })
		Outbox.add(account, "b", { kind = "ShopSell", at = 2 })
		Outbox.add(account, "c", { kind = "ShopSell", at = 3 })
		Outbox.add(account, "d", { kind = "GuildTax", at = 4 })
		local order = {}
		local handlers = {
			RiftDonation = function(id: string)
				table.insert(order, id)
				return true, nil
			end,
			ShopSell = function(id: string)
				table.insert(order, id)
				return true, { { type = "AdjustCurrency", currency = "Gold", amount = 5 } }
			end,
		}
		local delivered = Outbox.deliver(account, handlers, function(id: string): boolean
			return id ~= "c"
		end)
		t.equal(delivered, 2)
		t.deepEqual(order, { "a", "b", "c" })
		local left = {}
		for _, item in ipairs(Outbox.pending(account)) do
			table.insert(left, item.id)
		end
		t.deepEqual(left, { "c", "d" }, "c couldn't settle yet; d has no handler yet")
	end)
end

