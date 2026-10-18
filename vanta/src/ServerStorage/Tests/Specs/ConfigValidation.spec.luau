--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ConfigValidation = require(Shared.Domain.ConfigValidation)
local Table = require(Shared.Util.Table)
local Content = require(Shared.Content)

return function(t)
	t.test("the shipped config has no problems", function()
		local problems = ConfigValidation.validate(Content)
		t.deepEqual(problems, {})
	end)

	t.test("broken config is reported", function()
		local broken = Table.deepCopy(Content)
		broken.disciplines.SwordArts.techniques.HeavyStrike.rank = 99
		broken.disciplines.SwordArts.techniques.Riposte.milestones = { "NoSuchMilestone" }
		broken.classes.Swordmaster.disciplines.MissingArts = { maxRank = 1 }
		broken.classes.PlaceholderLegendary.awakeningWeight = 5
		broken.items.LegendaryBookPlaceholder.classBook.classId = "Swordmaster"
		broken.items.TrainingSword.maxStack = 5
		local problems = ConfigValidation.validate(broken)
		t.equal(#problems, 6, table.concat(problems, "; "))
	end)

	t.test("only cosmetics may be sold", function()
		local broken = Table.deepCopy(Content)
		broken.products.Boost = { id = "Boost", kind = "XpBoost", productId = 0, enabled = false }
		local problems = ConfigValidation.validate(broken)
		t.equal(#problems, 1, table.concat(problems, "; "))
	end)

	t.test("broken world and crafting config is reported", function()
		local broken = Table.deepCopy(Content)
		broken.world.locations.HeartOfRealms.district = "Atlantis"
		broken.world.locations.SouthGate.leadsTo = "Nowhere"
		broken.facilities.CityBlacksmith.locationId = "Moon"
		broken.facilities.CityAlchemist.recipes.TrainingSword = true
		broken.recipes.TrainingSword.inputs[1].itemId = "TrainingSword"
		local problems = ConfigValidation.validate(broken)
		t.equal(#problems, 5, table.concat(problems, "; "))
	end)
end
