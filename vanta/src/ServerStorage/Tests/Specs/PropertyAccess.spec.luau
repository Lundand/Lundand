--!strict
local Server = game:GetService("ServerScriptService"):WaitForChild("Server")
local PropertyAccess = require(Server.Domain.PropertyAccess)
local PropertyOwnership = require(Server.Domain.PropertyOwnership)
local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)

local rules = Content.propertyRules

local function owned(mode: string, allowed: {number}?): any
	local record = PropertyOwnership.newRecord("TownHouse01")
	assert(PropertyOwnership.reserve(record, 1, "op-1", 0, rules))
	assert(PropertyOwnership.commit(record, 1, "Owner", "op-1", 0))
	assert(PropertyOwnership.setPermissions(record, 1, mode, allowed, rules))
	return record
end

return function(t)
	t.test("anyone may look round a house nobody owns", function()
		t.falsy(PropertyAccess.shouldEject(nil, 7, false))
		t.falsy(PropertyAccess.shouldEject(PropertyOwnership.newRecord("TownHouse01"), 7, false))
	end)

	t.test("a private home is for its owner and the people they allow", function()
		local record = owned("Private", { 9 })
		t.falsy(PropertyAccess.shouldEject(record, 1, false), "owner")
		t.falsy(PropertyAccess.shouldEject(record, 9, false), "on the list")
		t.truthy(PropertyAccess.shouldEject(record, 7, true), "a friend isn't enough when private")
	end)

	t.test("friends-only homes wait for the friendship check before turning anyone out", function()
		local record = owned("Friends")
		t.falsy(PropertyAccess.shouldEject(record, 7, nil), "not known yet")
		t.falsy(PropertyAccess.shouldEject(record, 7, true))
		t.truthy(PropertyAccess.shouldEject(record, 7, false))
	end)

	t.test("public homes are open to all", function()
		t.falsy(PropertyAccess.shouldEject(owned("Public"), 7, false))
	end)
end
