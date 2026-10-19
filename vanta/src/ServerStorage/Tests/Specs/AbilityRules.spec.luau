--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AbilityRules = require(Shared.Domain.AbilityRules)
local Equipment = require(Shared.Domain.Equipment)
local Content = require(Shared.Content)

local swordmaster = Content.classes.Swordmaster

local function context(overrides: any?): any
	local base: any = { classDef = swordmaster, weaponType = "Sword", level = 10, now = 100, busyUntil = 0, staggeredUntil = 0, cooldowns = {}, meter = 0, canAfford = function() return true end }
	for key, value in pairs(overrides or {}) do
		base[key] = value
	end
	return base
end

return function(t)
	t.test("every class with abilities has four that exist, the fourth being its End Ability", function()
		for classId, def in pairs(Content.classes) do
			if def.abilities ~= nil then
				t.equal(#def.abilities, 4, classId)
				for slot, abilityId in ipairs(def.abilities) do
					local ability = Content.abilities[abilityId]
					t.truthy(ability ~= nil, abilityId)
					t.equal(ability.endAbility == true, slot == 4, abilityId)
				end
			end
		end
	end)

	t.test("abilities need the class, the level, the weapon, free hands, the cooldown and the costs", function()
		local cross = Content.abilities.CrossSlash
		t.truthy(AbilityRules.check(cross, "CrossSlash", context()))
		t.falsy(AbilityRules.check(cross, "Fireball", context()), "not in the loadout")
		t.falsy(AbilityRules.check(Content.abilities.BladeTempest, "BladeTempest", context({ level = 1, meter = 100 })), "level")
		t.falsy(AbilityRules.check(cross, "CrossSlash", context({ weaponType = "Bow" })), "wrong weapon")
		t.falsy(AbilityRules.check(cross, "CrossSlash", context({ busyUntil = 101 })), "busy")
		t.falsy(AbilityRules.check(cross, "CrossSlash", context({ cooldowns = { CrossSlash = 103 } })), "cooling down")
		t.falsy(AbilityRules.check(cross, "CrossSlash", context({ canAfford = function() return false end })), "costs")
		t.falsy(AbilityRules.check(Content.abilities.BladeTempest, "BladeTempest", context({ meter = 99 })), "meter")
		t.truthy(AbilityRules.check(Content.abilities.BladeTempest, "BladeTempest", context({ meter = 100 })))
	end)

	t.test("using an ability sets its cooldown and busy time, and schedules its hits", function()
		local state = { busyUntil = 0, cooldowns = {}, comboNext = "Combo2" }
		local ability = Content.abilities.CrossSlash
		local schedule = AbilityRules.start(state, ability, "CrossSlash", 10)
		t.equal(state.cooldowns.CrossSlash, 10 + ability.cooldown)
		t.equal(state.busyUntil, 10 + ability.windup + ability.active + ability.recovery)
		t.equal(state.comboNext, nil)
		t.equal(#schedule, 2)
		t.equal(schedule[2].delay, ability.windup + 0.18)
		t.equal(AbilityRules.gainMeter(95, 10, 100), 100)
	end)

	t.test("weapons are only equipped by classes that can use them", function()
		local character: any = { class = { classId = "Swordmaster" }, equipment = {}, inventory = { capacity = 10, stacks = {}, uniques = { u1 = { uid = "u1", itemId = "TrainingSword" } } } }
		t.truthy(Equipment.equip(character, "u1", Content.items, 1, Content.classes))
		character.equipment = {}
		character.inventory.uniques.u1 = { uid = "u1", itemId = "TrainingSword" }
		character.class.classId = nil
		local ok, reason = Equipment.equip(character, "u1", Content.items, 1, Content.classes)
		t.falsy(ok)
		t.truthy(reason ~= nil)
	end)

	t.test("marks and empowerment add damage for a limited number of hits and time", function()
		local target, attacker = {}, {}
		AbilityRules.applyMark(target, 7, { bonus = 0.3, hits = 2, seconds = 6 }, 0)
		AbilityRules.empower(attacker, { bonus = 0.5, hits = 1, seconds = 8 }, 0)
		t.equal(AbilityRules.consumeBonuses(target, attacker, 7, 1), 1.8, "mark and empowerment together")
		t.equal(AbilityRules.consumeBonuses(target, attacker, 7, 1), 1.3, "empowerment spent")
		t.equal(AbilityRules.consumeBonuses(target, attacker, 7, 1), 1, "mark spent")
		AbilityRules.applyMark(target, 7, { bonus = 0.3, hits = 5, seconds = 6 }, 0)
		t.equal(AbilityRules.consumeBonuses(target, attacker, 8, 1), 1, "only the marking attacker benefits")
		t.equal(AbilityRules.consumeBonuses(target, attacker, 7, 7), 1, "expired")
	end)
end
