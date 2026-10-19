--!strict
-- Delivers players' outbox entries to shared records every few seconds (L-47, L-48, L-53), then settles any
-- answer back into their save under a one-time operation ID. Services register a handler for each kind.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Outbox = require(Server.Domain.Outbox)
local RiftDonations = require(Server.Domain.RiftDonations)
local Transaction = require(Server.Domain.Transaction)

local INTERVAL = 5

local OutboxService = {}
local services: any = nil
local handlers: {[string]: any} = {}
local busy: {[Player]: boolean} = {}

function OutboxService.init(allServices: any)
	services = allServices
end

function OutboxService.register(kind: string, handler: (string, any) -> (boolean, any))
	handlers[kind] = handler
end

-- Rift donations: counted once in their shard of the shared total. Opening the Rift arrives with RiftService.
local function deliverDonation(id: string, entry: any): (boolean, any)
	local shardKey = string.format("%s:%d", entry.eventId, RiftDonations.shardIndex(id, Content.riftEvents.shardCount))
	local ok = services.SharedRecordService.store("RiftShards"):update(shardKey, function(shard: any)
		local current = shard or RiftDonations.newShard()
		if not RiftDonations.addToShard(current, id, entry.robux) then
			return nil, true
		end
		return current, true
	end)
	return ok, nil
end

local function deliverFor(player: Player)
	local data = services.PlayerDataService.getData(player)
	if data == nil or busy[player] then
		return
	end
	busy[player] = true
	local ok, err = pcall(function()
		Outbox.deliver(data.account, handlers, function(id: string, entry: any, changes: {any}): boolean
			local characterId = data.activeCharacterId
			if entry.characterId ~= nil and data.characters[entry.characterId] ~= nil then
				characterId = entry.characterId
			end
			local applied = Transaction.apply(data, characterId, { id = "settle:" .. id, reason = "Outbox", changes = changes }, services.InventoryService.deps(player))
			if applied then
				services.InventoryService.sendSnapshot(player)
			end
			return applied
		end)
	end)
	busy[player] = nil
	if not ok then
		warn("[Outbox] delivery failed, will retry: " .. tostring(err))
	end
end

-- Delivers this player's waiting entries straight away (after a shop action), instead of within seconds.
function OutboxService.deliverNow(player: Player)
	deliverFor(player)
end

function OutboxService.start()
	OutboxService.register("RiftDonation", deliverDonation)
	Players.PlayerRemoving:Connect(function(player: Player)
		busy[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(deliverFor, player)
			end
		end
	end)
end

return OutboxService
