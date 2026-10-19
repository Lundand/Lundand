--!strict
-- Server API for item and currency changes. Wraps Transaction with real IDs, time and the owner.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Inventory = require(Shared.Domain.Inventory)
local Transaction = require(Server.Domain.Transaction)
local DomainDeps = require(Server.Domain.DomainDeps)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)
local Equipment = require(Shared.Domain.Equipment)

local InventoryService = {}
local services: any = nil

function InventoryService.init(allServices: any)
	services = allServices
end

function InventoryService.deps(player: Player)
	return DomainDeps.build(player.UserId, function()
		return HttpService:GenerateGUID(false)
	end, os.time)
end

-- Applies changes under a caller-chosen operation ID (use for anything a client may repeat).
function InventoryService.applyWithId(player: Player, operationId: string, reason: string, changes: {any}): (boolean, any)
	local data = services.PlayerDataService.getData(player)
	if data == nil then
		return false, "data not loaded"
	end
	local operation = { id = operationId, reason = reason, changes = changes }
	local ok, result = Transaction.apply(data, data.activeCharacterId, operation, InventoryService.deps(player))
	if ok and not result.alreadyApplied then
		InventoryService.sendSnapshot(player)
	end
	return ok, result
end

-- Applies changes under a new operation ID.
function InventoryService.apply(player: Player, reason: string, changes: {any}): (boolean, any)
	return InventoryService.applyWithId(player, reason .. ":" .. HttpService:GenerateGUID(false), reason, changes)
end

local equipLimiter = RateLimiter.new(4, 2, os.clock)

local function describeEquipment(character: any): any
	local equipped = {}
	for slot, item in pairs(character.equipment) do
		local info = Inventory.describe(item, Content.items)
		info.uid = item.uid
		equipped[slot] = info
	end
	return equipped
end

function InventoryService.snapshot(player: Player): any
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return nil
	end
	local entries = {}
	for key, stack in pairs(character.inventory.stacks) do
		local info = Inventory.describe(stack, Content.items)
		info.key = key
		info.count = stack.count
		table.insert(entries, info)
	end
	for uid, unique in pairs(character.inventory.uniques) do
		local info = Inventory.describe(unique, Content.items)
		info.uid = uid
		info.count = 1
		table.insert(entries, info)
	end
	table.sort(entries, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	return {
		capacity = character.inventory.capacity,
		used = Inventory.slotsUsed(character.inventory, Content.items),
		entries = entries,
		currencies = table.clone(character.currencies),
		equipment = describeEquipment(character),
	}
end

function InventoryService.sendSnapshot(player: Player)
	local snapshot = InventoryService.snapshot(player)
	if snapshot then
		Remotes.get("Snapshot"):FireClient(player, "Inventory", snapshot)
	end
end

local function changeEquipment(player: Player, change: (any) -> (boolean, string?))
	if not equipLimiter:allow(player) then
		return
	end
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return
	end
	local ok, err = change(character)
	if not ok then
		Remotes.get("Notify"):FireClient(player, "Can't do that: " .. tostring(err))
		return
	end
	InventoryService.sendSnapshot(player)
	services.CombatService.attachWeapon(player)
end

function InventoryService.start()
	services.PlayerDataService.Loaded:Connect(InventoryService.sendSnapshot)
	Remotes.get("EquipItem").OnServerEvent:Connect(function(player: Player, uid: any)
		changeEquipment(player, function(character: any): (boolean, string?)
			return Equipment.equip(character, uid, Content.items, player.UserId, Content.classes, require(game:GetService("ReplicatedStorage").Shared.Domain.CharacterProgression).level(character.level, Content.progression), Content.gear)
		end)
	end)
	Remotes.get("UnequipItem").OnServerEvent:Connect(function(player: Player, slot: any)
		changeEquipment(player, function(character: any): (boolean, string?)
			return Equipment.unequip(character, slot, Content.items)
		end)
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		equipLimiter:forget(player)
	end)
end

return InventoryService
