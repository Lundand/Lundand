--!strict
-- Party rules (L-42): groups of one to four, formed at the Adventurers' Guild party board and kept while
-- the group travels. Separate from guilds. State lives on the server; PartyService carries parties across
-- teleports once dungeon instancing exists.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)

local PartyRules = {}

local function key(userId: number): string
	return tostring(userId)
end

function PartyRules.newState()
	return { parties = {}, memberOf = {} }
end

function PartyRules.partyOf(state: any, userId: number): any
	local partyId = state.memberOf[key(userId)]
	return partyId and state.parties[partyId]
end

function PartyRules.size(party: any): number
	return #party.order
end

local function addMember(state: any, party: any, userId: number, name: string, now: number)
	party.members[key(userId)] = { name = name, joinedAt = now }
	table.insert(party.order, key(userId))
	party.invites[key(userId)] = nil
	state.memberOf[key(userId)] = party.id
end

function PartyRules.create(state: any, partyId: string, leaderUserId: number, leaderName: string, goal: any, listed: boolean, now: number, rules: any): (boolean, any)
	if state.memberOf[key(leaderUserId)] ~= nil then
		return false, "you're already in a party"
	end
	if state.parties[partyId] ~= nil then
		return false, "party id in use"
	end
	if type(goal) ~= "string" or table.find(rules.goals, goal) == nil then
		return false, "unknown party goal"
	end
	local party = { id = partyId, leader = leaderUserId, goal = goal, listed = listed == true, createdAt = now, order = {}, members = {}, invites = {} }
	state.parties[partyId] = party
	addMember(state, party, leaderUserId, leaderName, now)
	return true, party
end

-- Joining a listed party from the board.
function PartyRules.join(state: any, partyId: any, userId: number, name: string, now: number, rules: any): (boolean, string?)
	local party = type(partyId) == "string" and state.parties[partyId]
	if not party or not party.listed then
		return false, "that party isn't recruiting"
	end
	if state.memberOf[key(userId)] ~= nil then
		return false, "you're already in a party"
	end
	if PartyRules.size(party) >= rules.maxSize then
		return false, "the party is full"
	end
	addMember(state, party, userId, name, now)
	return true, nil
end

function PartyRules.invite(state: any, byUserId: number, targetUserId: any, now: number, rules: any): (boolean, string?)
	local party = PartyRules.partyOf(state, byUserId)
	if party == nil or party.leader ~= byUserId then
		return false, "only a party leader can invite"
	end
	if not Check.isPositiveInteger(targetUserId) or state.memberOf[key(targetUserId)] ~= nil then
		return false, "that player can't be invited"
	end
	if PartyRules.size(party) >= rules.maxSize then
		return false, "the party is full"
	end
	party.invites[key(targetUserId)] = now + rules.inviteSeconds
	return true, nil
end

function PartyRules.accept(state: any, partyId: any, userId: number, name: string, now: number, rules: any): (boolean, string?)
	local party = type(partyId) == "string" and state.parties[partyId]
	local expiresAt = party and party.invites[key(userId)]
	if not expiresAt or expiresAt <= now then
		return false, "no valid invitation"
	end
	if state.memberOf[key(userId)] ~= nil then
		return false, "you're already in a party"
	end
	if PartyRules.size(party) >= rules.maxSize then
		return false, "the party is full"
	end
	addMember(state, party, userId, name, now)
	return true, nil
end

-- Returns the party afterwards (nil when it was disbanded). A leaving leader hands over to the longest member.
function PartyRules.leave(state: any, userId: number): (boolean, any)
	local party = PartyRules.partyOf(state, userId)
	if party == nil then
		return false, "you're not in a party"
	end
	local memberKey = key(userId)
	party.members[memberKey] = nil
	table.remove(party.order, table.find(party.order, memberKey))
	state.memberOf[memberKey] = nil
	if #party.order == 0 then
		state.parties[party.id] = nil
		return true, nil
	end
	if party.leader == userId then
		party.leader = tonumber(party.order[1])
	end
	return true, party
end

function PartyRules.kick(state: any, byUserId: number, targetUserId: any): (boolean, string?)
	local party = PartyRules.partyOf(state, byUserId)
	if party == nil or party.leader ~= byUserId or targetUserId == byUserId then
		return false, "only the leader can remove other members"
	end
	if not Check.isPositiveInteger(targetUserId) or party.members[key(targetUserId)] == nil then
		return false, "that player isn't in your party"
	end
	PartyRules.leave(state, targetUserId)
	return true, nil
end

function PartyRules.promote(state: any, byUserId: number, targetUserId: any): (boolean, string?)
	local party = PartyRules.partyOf(state, byUserId)
	if party == nil or party.leader ~= byUserId then
		return false, "only the leader can hand over leadership"
	end
	if not Check.isPositiveInteger(targetUserId) or targetUserId == byUserId or party.members[key(targetUserId)] == nil then
		return false, "choose another member"
	end
	party.leader = targetUserId
	return true, nil
end

-- What the party board shows: listed parties with room left.
function PartyRules.listOpen(state: any, rules: any): {any}
	local list = {}
	for _, party in pairs(state.parties) do
		if party.listed and PartyRules.size(party) < rules.maxSize then
			local leader = party.members[key(party.leader)]
			table.insert(list, {
				id = party.id,
				leaderName = (leader and leader.name) or "?",
				size = PartyRules.size(party),
				maxSize = rules.maxSize,
				goal = party.goal,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

return PartyRules
