--!strict
-- Player guild rules (L-30). Each guild has one shared record (members, ranks, invites, leader, version)
-- that a future GuildService keeps in its own DataStore entry and changes only inside version-checked
-- updates; a player's save keeps only account.guild. NPC guilds are world config, not records.
-- Guild names are player-written text: GuildService must pass them through Roblox text filtering before
-- anyone else sees them.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)

local GuildRules = {}

function GuildRules.validName(name: any, rules: any): (boolean, string?)
	if type(name) ~= "string" or #name < rules.nameMinLength or #name > rules.nameMaxLength then
		return false, string.format("names need %d to %d characters", rules.nameMinLength, rules.nameMaxLength)
	end
	if string.match(name, "^[%w][%w ]*[%w]$") == nil or string.find(name, "  ", 1, true) then
		return false, "letters, digits and single spaces only"
	end
	return true, nil
end

-- Key for the guild-name index, so names are unique regardless of letter case.
function GuildRules.nameKey(name: string): string
	return string.lower(name)
end

function GuildRules.newRecord(guildId: string, name: string, leaderUserId: number, leaderName: string, now: number)
	return {
		id = guildId,
		name = name,
		createdAt = now,
		version = 1,
		leaderUserId = leaderUserId,
		members = { [tostring(leaderUserId)] = { rank = "Leader", name = leaderName, joinedAt = now } },
		invites = {},
		disbanded = false,
		-- Economy and progression (L-48), changed only through GuildEconomy.
		emblemAssetId = 0,
		emblemChangedAt = 0,
		xp = 0,
		treasury = 0,
		taxRate = 0,
		upgrades = {},
		maintenance = { condition = "Maintained" },
		ledger = {},
	}
end

local function member(record: any, userId: any): any
	return record.members[tostring(userId)]
end

local function rankIndex(rules: any, rank: string): number
	return table.find(rules.ranks, rank) or (#rules.ranks + 1)
end

local function can(record: any, userId: any, permission: string, rules: any): boolean
	local entry = member(record, userId)
	return entry ~= nil and rules.permissions[entry.rank][permission] == true
end

function GuildRules.memberCount(record: any): number
	local count = 0
	for _ in pairs(record.members) do
		count += 1
	end
	return count
end

-- Founding a guild (L-54): not already in one, the founder's character level, and the founding fee in gold.
function GuildRules.canCreate(account: any, characterLevel: number, gold: number, rules: any): (boolean, string?)
	if not GuildRules.canJoin(account) then
		return false, "you're already in a guild"
	end
	if characterLevel < rules.minLeaderLevel then
		return false, string.format("founding a guild needs character level %d", rules.minLeaderLevel)
	end
	if gold < rules.creationCost then
		return false, string.format("founding a guild costs %d gold", rules.creationCost)
	end
	return true, nil
end

-- A player belongs to at most one guild; checked against their own save before creating or joining.
function GuildRules.canJoin(account: any): boolean
	return account.guild.id == nil and account.guild.pendingFounding == nil
end

function GuildRules.invite(record: any, byUserId: number, targetUserId: any, now: number, rules: any): (boolean, string?)
	if record.disbanded then
		return false, "the guild was disbanded"
	end
	if not can(record, byUserId, "invite", rules) then
		return false, "no permission to invite"
	end
	if not Check.isPositiveInteger(targetUserId) or member(record, targetUserId) ~= nil then
		return false, "that player can't be invited"
	end
	if GuildRules.memberCount(record) >= rules.maxMembers then
		return false, "the guild is full"
	end
	record.invites[tostring(targetUserId)] = { by = byUserId, expiresAt = now + rules.inviteSeconds }
	record.version += 1
	return true, nil
end

function GuildRules.accept(record: any, userId: number, name: string, now: number, rules: any): (boolean, string?)
	local invite = record.invites[tostring(userId)]
	if record.disbanded or invite == nil or invite.expiresAt <= now then
		return false, "no valid invitation"
	end
	if GuildRules.memberCount(record) >= rules.maxMembers then
		return false, "the guild is full"
	end
	record.invites[tostring(userId)] = nil
	record.members[tostring(userId)] = { rank = rules.ranks[#rules.ranks], name = name, joinedAt = now }
	record.version += 1
	return true, nil
end

function GuildRules.leave(record: any, userId: number): (boolean, string?)
	local entry = member(record, userId)
	if entry == nil then
		return false, "not a member"
	end
	if entry.rank == "Leader" and GuildRules.memberCount(record) > 1 then
		return false, "transfer leadership before leaving"
	end
	record.members[tostring(userId)] = nil
	if GuildRules.memberCount(record) == 0 then
		record.disbanded = true
	end
	record.version += 1
	return true, nil
end

function GuildRules.kick(record: any, byUserId: number, targetUserId: number, rules: any): (boolean, string?)
	local by, target = member(record, byUserId), member(record, targetUserId)
	if target == nil then
		return false, "not a member"
	end
	if not can(record, byUserId, "kick", rules) or rankIndex(rules, by.rank) >= rankIndex(rules, target.rank) then
		return false, "you can only remove members below your rank"
	end
	record.members[tostring(targetUserId)] = nil
	record.version += 1
	return true, nil
end

function GuildRules.setRank(record: any, byUserId: number, targetUserId: number, newRank: any, rules: any): (boolean, string?)
	local by, target = member(record, byUserId), member(record, targetUserId)
	if target == nil then
		return false, "not a member"
	end
	if newRank == "Leader" then
		return false, "use leadership transfer instead"
	end
	if type(newRank) ~= "string" or table.find(rules.ranks, newRank) == nil then
		return false, "unknown rank"
	end
	if not can(record, byUserId, "promote", rules) then
		return false, "no permission to change ranks"
	end
	local byIndex = rankIndex(rules, by.rank)
	if byIndex >= rankIndex(rules, target.rank) or byIndex >= rankIndex(rules, newRank) then
		return false, "you can only change ranks below your own"
	end
	target.rank = newRank
	record.version += 1
	return true, nil
end

function GuildRules.transferLeadership(record: any, byUserId: number, targetUserId: number, rules: any): (boolean, string?)
	local by, target = member(record, byUserId), member(record, targetUserId)
	if by == nil or by.rank ~= "Leader" then
		return false, "only the leader can transfer leadership"
	end
	if target == nil or byUserId == targetUserId then
		return false, "choose another member"
	end
	by.rank = rules.ranks[2]
	target.rank = "Leader"
	record.leaderUserId = targetUserId
	record.version += 1
	return true, nil
end

function GuildRules.disband(record: any, byUserId: number): (boolean, string?)
	local by = member(record, byUserId)
	if by == nil or by.rank ~= "Leader" then
		return false, "only the leader can disband the guild"
	end
	record.disbanded = true
	record.members = {}
	record.invites = {}
	record.version += 1
	return true, nil
end

-- On load: clears account.guild when the record no longer lists the player (removed or disbanded while
-- they were offline). An unreadable record (nil) changes nothing. Returns true if the save changed.
function GuildRules.reconcileMembership(account: any, record: any, userId: number): boolean
	if account.guild.id == nil or record == nil then
		return false
	end
	if record.disbanded or member(record, userId) == nil then
		account.guild = {}
		return true
	end
	return false
end

return GuildRules
