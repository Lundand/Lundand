--!strict
-- Parties (L-42). Formed at the Adventurers' Guild party board (opened by the Party Clerk), kept while the
-- group travels, and shown to members as a compact panel only while they're in a party. Separate from
-- guilds. Health in the panel comes from the server. Parties live on this server for now; carrying them
-- across places arrives with dungeon instancing (M11).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Check = require(Shared.Util.Check)
local PartyRules = require(Server.Domain.PartyRules)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local HEALTH_INTERVAL = 0.5

local PartyService = {}
local services: any = nil
local state = PartyRules.newState()
local boardOpenUntil: {[Player]: number} = {}
local limiter = RateLimiter.new(6, 2, os.clock)

function PartyService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function playerFor(memberKey: string): Player?
	local userId = tonumber(memberKey)
	return userId and Players:GetPlayerByUserId(userId)
end

local function view(party: any): any
	local members = {}
	for _, memberKey in ipairs(party.order) do
		local player = playerFor(memberKey)
		local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		table.insert(members, {
			userId = tonumber(memberKey),
			name = party.members[memberKey].name,
			health = (humanoid and humanoid.Health) or 0,
			maxHealth = (humanoid and humanoid.MaxHealth) or 100,
			leader = tonumber(memberKey) == party.leader,
		})
	end
	return { id = party.id, goal = party.goal, members = members }
end

local function sendParty(party: any)
	local snapshot = view(party)
	for _, memberKey in ipairs(party.order) do
		local player = playerFor(memberKey)
		if player then
			Remotes.get("PartyState"):FireClient(player, snapshot)
		end
	end
end

local function sendBoard(player: Player)
	Remotes.get("OpenInterface"):FireClient(player, "PartyBoard", {
		parties = PartyRules.listOpen(state, Content.parties),
		goals = Content.parties.goals,
	})
end

-- Whether two players are in the same party (who may fight a personal encounter together).
function PartyService.sameParty(userIdA: number, userIdB: number): boolean
	local party = PartyRules.partyOf(state, userIdA)
	return party ~= nil and party.members[tostring(userIdB)] ~= nil
end

-- Called when the Party Clerk's conversation opens the board.
function PartyService.openBoard(player: Player)
	boardOpenUntil[player] = os.clock() + Content.parties.boardSessionSeconds
	sendBoard(player)
end

-- Updates the remaining members of a party, and clears the panel of anyone no longer in a party.
local function refresh(party: any, affected: {Player})
	if party ~= nil and state.parties[party.id] ~= nil then
		sendParty(party)
	end
	for _, player in ipairs(affected) do
		if PartyRules.partyOf(state, player.UserId) == nil then
			Remotes.get("PartyState"):FireClient(player, nil)
		end
	end
end

local function onRequest(player: Player, action: any, args: any)
	if not limiter:allow(player) or type(action) ~= "string" then
		return
	end
	if type(args) ~= "table" then
		args = {}
	end
	local rules = Content.parties
	local now = os.time()
	local atBoard = (boardOpenUntil[player] or 0) > os.clock()
	local before = PartyRules.partyOf(state, player.UserId)
	local affected = { player }
	local ok, err = false, "that's done at the Adventurers' Guild party board"
	if action == "List" and atBoard then
		sendBoard(player)
		return
	elseif action == "Create" and atBoard then
		ok, err = PartyRules.create(state, HttpService:GenerateGUID(false), player.UserId, player.DisplayName, args.goal, args.listed ~= false, now, rules)
	elseif action == "Join" and atBoard then
		ok, err = PartyRules.join(state, args.partyId, player.UserId, player.DisplayName, now, rules)
	elseif action == "Invite" then
		local target = Check.isPositiveInteger(args.userId) and Players:GetPlayerByUserId(args.userId)
		if not target then
			ok, err = false, "that player isn't here"
		else
			ok, err = PartyRules.invite(state, player.UserId, target.UserId, now, rules)
			if ok then
				local party = PartyRules.partyOf(state, player.UserId)
				Remotes.get("OpenInterface"):FireClient(target, "PartyInvite", { partyId = party.id, from = player.DisplayName })
			end
		end
	elseif action == "Accept" then
		ok, err = PartyRules.accept(state, args.partyId, player.UserId, player.DisplayName, now, rules)
	elseif action == "Leave" then
		ok, err = PartyRules.leave(state, player.UserId)
	elseif action == "Kick" then
		local target = Check.isPositiveInteger(args.userId) and Players:GetPlayerByUserId(args.userId)
		ok, err = PartyRules.kick(state, player.UserId, args.userId)
		if ok and target then
			table.insert(affected, target)
		end
	elseif action == "Promote" then
		ok, err = PartyRules.promote(state, player.UserId, args.userId)
	end
	if not ok then
		notify(player, "Party: " .. tostring(err))
		return
	end
	refresh(before, affected)
	refresh(PartyRules.partyOf(state, player.UserId), affected)
end

local function onPlayerRemoving(player: Player)
	boardOpenUntil[player] = nil
	limiter:forget(player)
	if PartyRules.partyOf(state, player.UserId) ~= nil then
		local _, remaining = PartyRules.leave(state, player.UserId)
		if remaining then
			sendParty(remaining)
		end
	end
end

function PartyService.start()
	Remotes.get("PartyRequest").OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	task.spawn(function()
		while true do
			task.wait(HEALTH_INTERVAL)
			for _, party in pairs(state.parties) do
				sendParty(party)
			end
		end
	end)
end

return PartyService
