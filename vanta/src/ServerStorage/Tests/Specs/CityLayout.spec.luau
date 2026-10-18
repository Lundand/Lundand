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

local RESIDENTIAL = { Townhouse = true, Shack = true, Apartments = true, Mansion = true }
-- public institutions, essential businesses and story places: never for sale
local NOT_FOR_SALE = { Church = true, Guild = true, Inn = true, Tavern = true, SlumTavern = true, Keep = true, Library = true, Barracks = true, Chancery = true, Servants = true, Customs = true, FishMarket = true, Office = true, Forge = true, Apothecary = true, CraftGuild = true, Fountain = true, Smithy = true, Shop = true, Warehouse = true }

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
			properties += #(entry.units or {})
			if entry.locationId then
				locations += 1
			end
		end
		t.equal(properties, Table.count(Content.world.properties))
		t.truthy(locations > 0)
	end)

	t.test("most ordinary homes are for sale, and only buildings marked for sale have deeds", function()
		local homes, forSale = 0, 0
		for _, entry in ipairs(Layout.blocks) do
			local hasDeed = entry.propertyId ~= nil or entry.units ~= nil
			if entry.access == "Sale" then
				t.truthy(hasDeed, entry.id .. " is for sale without a deed")
			elseif entry.access ~= "Guild" then
				t.falsy(hasDeed, entry.id .. " has a deed but isn't for sale")
			end
			if RESIDENTIAL[entry.use] then
				homes += 1
				if entry.access == "Sale" then
					forSale += 1
				end
			end
		end
		t.truthy(homes > 200, "a capital, not a village: " .. homes .. " homes")
		t.truthy(forSale / homes > 0.6, string.format("%d of %d homes for sale", forSale, homes))
	end)

	t.test("public institutions and essential places can't be bought", function()
		for _, entry in ipairs(Layout.blocks) do
			if NOT_FOR_SALE[entry.use] then
				t.equal(entry.propertyId, nil, entry.id)
				t.equal(entry.units, nil, entry.id)
			end
		end
		for _, id in ipairs({ "Church", "AdventurersGuild", "SquareInn", "CastleKeep", "RoyalLibrary", "CrookedLantern" }) do
			local found = false
			for _, entry in ipairs(Layout.blocks) do
				if entry.id == id then
					found = true
					t.equal(entry.propertyId, nil, id)
				end
			end
			t.truthy(found, id .. " is in the city")
		end
	end)

	t.test("the hideout is reached from inside the slums", function()
		local tavern = nil
		for _, entry in ipairs(Layout.blocks) do
			if entry.id == Layout.hideout.entranceBlock then
				tavern = entry
			end
		end
		t.truthy(tavern ~= nil and tavern.trapdoor ~= nil and tavern.district == "Slums")
		for _, room in ipairs(Layout.hideout.rooms) do
			t.truthy(room.center[2] > 150, room.id .. " lies under the slums")
		end
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

	t.test("a door walled in by another building is reported", function()
		local broken = Table.deepCopy(Layout)
		local inn = nil
		for _, entry in ipairs(broken.blocks) do
			if entry.id == "SquareInn" then
				inn = entry
			end
		end
		local step = LayoutRules.doorStep(inn)
		table.insert(broken.blocks, { id = "Obstacle", center = step, size = { 12, 12 }, height = 10 })
		local problems = LayoutRules.validate(broken, Content.world, Content.npcs)
		t.truthy(has(problems, "SquareInn's door can't be reached from the gates"), table.concat(problems, "; "))
	end)
end
