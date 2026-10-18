--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LayoutRules = require(ServerScriptService:WaitForChild("Server").Domain.LayoutRules)
local Layout = require(ServerStorage:WaitForChild("ServerData").CityLayout)
local Table = require(Shared.Util.Table)
local Content = require(Shared.Content)

local function has(problems: {string}, text: string): boolean
	for _, problem in ipairs(problems) do
		if string.find(problem, text, 1, true) then
			return true
		end
	end
	return false
end

return function(t)
	t.test("the shipped city layout is valid", function()
		t.deepEqual(LayoutRules.validate(Layout, Content.world, Content.npcs), {})
	end)

	t.test("every property and location in the world config is placed", function()
		local properties, locations = 0, 0
		for _, entry in ipairs(Layout.blocks) do
			if entry.propertyId then
				properties += 1
			end
			if entry.locationId then
				locations += 1
			end
		end
		t.equal(properties, Table.count(Content.world.properties))
		t.truthy(locations > 0)
	end)

	t.test("overlaps, missing placements and stray gates are reported", function()
		local broken = Table.deepCopy(Layout)
		for _, entry in ipairs(broken.blocks) do
			if entry.id == "Church" then
				entry.center = { 0, 0 }
			end
		end
		for index, entry in ipairs(broken.blocks) do
			if entry.propertyId == "SlumHouse08" then
				table.remove(broken.blocks, index)
				break
			end
		end
		broken.gates[1].center = { 0, 300 }
		broken.npcs[1].at = { 0, -150 }
		broken.markers[3].at = { 0, -150 }
		local problems = LayoutRules.validate(broken, Content.world, Content.npcs)
		t.truthy(has(problems, "HeartOfRealms overlaps Church"), table.concat(problems, "; "))
		t.truthy(has(problems, "property SlumHouse08 is not placed"))
		t.truthy(has(problems, "SouthGate is not on the city wall"))
		t.truthy(has(problems, "NPC TheKing should stand inside CastleKeep"))
		t.truthy(has(problems, "marker StarterChest should be inside Church"))
	end)
end
