--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ItemStats = require(Shared.Domain.ItemStats)
local gear = require(Shared.Config.Gear)
local sword = { stats = { attackPower = 10 }, rarity = "Common" }

return function(t)
	t.test("item level matters more than rarity: a Common level 40 sword beats a Rare level 20 one", function()
		local common40 = ItemStats.compute(sword, { itemLevel = 40, rarity = "Common" }, gear).attackPower
		local rare20 = ItemStats.compute(sword, { itemLevel = 20, rarity = "Rare" }, gear).attackPower
		local epic20 = ItemStats.compute(sword, { itemLevel = 20, rarity = "Epic" }, gear).attackPower
		local common20 = ItemStats.compute(sword, { itemLevel = 20, rarity = "Common" }, gear).attackPower
		t.truthy(common40 > rare20, "level 40 Common over level 20 Rare")
		t.truthy(common20 < rare20 and rare20 < epic20, "rarity orders items of one level")
		t.equal(ItemStats.compute(sword, nil, gear).attackPower, 10, "a level 1 Common item has its base stats")
	end)

	t.test("bands, required level and armour weights", function()
		t.equal(ItemStats.band(1, gear), "Starter")
		t.equal(ItemStats.band(35, gear), "Elite")
		t.equal(ItemStats.band(60, gear), "Endgame")
		t.equal(ItemStats.requiredLevel(sword, { itemLevel = 27 }), 27)
		t.equal(ItemStats.requiredLevel({ requiredLevel = 5 }, { itemLevel = 27 }), 5)
		t.truthy(ItemStats.armorAllowed("HeavyKnight", "Heavy", gear))
		t.falsy(ItemStats.armorAllowed("Mage", "Heavy", gear))
		t.falsy(ItemStats.armorAllowed("Mage", "Medium", gear))
		t.truthy(ItemStats.armorAllowed("Rogue", "Medium", gear))
		t.truthy(ItemStats.armorAllowed("Mage", "Light", gear))
	end)

	t.test("every weapon family's subtypes have a full handling profile", function()
		for family, def in pairs(gear.weaponFamilies) do
			t.truthy(def.hands == 1 or def.hands == 2, family)
			for subtype, profile in pairs(def.subtypes) do
				t.truthy(profile.speed > 0 and profile.reach > 0 and profile.damage > 0, family .. "." .. subtype)
			end
		end
	end)
end
