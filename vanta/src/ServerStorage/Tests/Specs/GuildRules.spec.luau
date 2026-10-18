--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GuildRules = require(ServerScriptService:WaitForChild("Server").Domain.GuildRules)
local Content = require(Shared.Content)

local rules = Content.guilds

-- Leader 1, officer 2, member 3, recruit 4.
local function guild()
	local record = GuildRules.newRecord("g1", "Iron Wolves", 1, "Leader", 0)
	for userId = 2, 4 do
		assert(GuildRules.invite(record, 1, userId, 0, rules))
		assert(GuildRules.accept(record, userId, "Player" .. userId, 1, rules))
	end
	assert(GuildRules.setRank(record, 1, 2, "Officer", rules))
	assert(GuildRules.setRank(record, 1, 3, "Member", rules))
	return record
end

return function(t)
	t.test("guild names follow the naming rules", function()
		t.truthy(GuildRules.validName("Iron Wolves", rules))
		t.falsy(GuildRules.validName("IW", rules), "too short")
		t.falsy(GuildRules.validName(" Iron", rules), "leading space")
		t.falsy(GuildRules.validName("Iron  Wolves", rules), "double space")
		t.falsy(GuildRules.validName("Iron_Wolves!", rules), "symbols")
		t.equal(GuildRules.nameKey("Iron Wolves"), GuildRules.nameKey("iron wolves"))
	end)

	t.test("invitations make recruits and expire", function()
		local record = GuildRules.newRecord("g1", "Iron Wolves", 1, "Leader", 0)
		t.truthy(GuildRules.invite(record, 1, 2, 0, rules))
		t.equal(GuildRules.accept(record, 2, "Two", 1, rules), true)
		t.equal(record.members["2"].rank, "Recruit")
		GuildRules.invite(record, 1, 3, 0, rules)
		t.falsy(GuildRules.accept(record, 3, "Three", rules.inviteSeconds + 1, rules), "expired")
		t.falsy(GuildRules.accept(record, 9, "Nine", 1, rules), "never invited")
		t.falsy(GuildRules.invite(record, 2, 5, 2, rules), "recruits can't invite")
	end)

	t.test("members can only act on ranks below their own", function()
		local record = guild()
		t.falsy(GuildRules.kick(record, 2, 1, rules), "officer can't remove the leader")
		t.falsy(GuildRules.kick(record, 3, 4, rules), "members can't remove anyone")
		t.falsy(GuildRules.setRank(record, 2, 3, "Officer", rules), "officer can't make an officer")
		t.truthy(GuildRules.setRank(record, 2, 4, "Member", rules))
		t.falsy(GuildRules.setRank(record, 1, 2, "Leader", rules), "leadership is transferred, not assigned")
		t.truthy(GuildRules.kick(record, 2, 4, rules))
		t.equal(record.members["4"], nil)
	end)

	t.test("leadership transfer, leaving and disbanding", function()
		local record = guild()
		t.falsy(GuildRules.leave(record, 1), "leader must transfer first")
		t.falsy(GuildRules.transferLeadership(record, 2, 3, rules), "only the leader")
		t.truthy(GuildRules.transferLeadership(record, 1, 2, rules))
		t.equal(record.leaderUserId, 2)
		t.equal(record.members["1"].rank, "Officer")
		t.truthy(GuildRules.leave(record, 1))
		t.falsy(GuildRules.disband(record, 3), "only the leader")
		t.truthy(GuildRules.disband(record, 2))
		t.truthy(record.disbanded)
		t.falsy(GuildRules.invite(record, 2, 9, 0, rules))
	end)

	t.test("every change bumps the record version", function()
		local record = GuildRules.newRecord("g1", "Iron Wolves", 1, "Leader", 0)
		local before = record.version
		GuildRules.invite(record, 1, 2, 0, rules)
		GuildRules.accept(record, 2, "Two", 1, rules)
		t.equal(record.version, before + 2)
	end)

	t.test("saves drop guilds that no longer list the player", function()
		local record = guild()
		local account = { guild = { id = "g1", joinedAt = 1 } }
		t.falsy(GuildRules.canJoin(account))
		t.falsy(GuildRules.reconcileMembership(account, record, 3), "still a member")
		t.falsy(GuildRules.reconcileMembership(account, nil, 3), "unreadable record changes nothing")
		GuildRules.kick(record, 1, 3, rules)
		t.truthy(GuildRules.reconcileMembership(account, record, 3))
		t.truthy(GuildRules.canJoin(account))
	end)
end
