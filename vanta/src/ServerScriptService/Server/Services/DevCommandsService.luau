--!strict
-- Development-only commands for testing before content exists (progression slice acceptance tests).
-- Available in Studio, or in places and for users listed in ServerData.DevAccess; nowhere else.
-- From the Studio MCP server (execute_luau in the server data model during a playtest):
--   local Dev = require(game.ServerScriptService.Server.Services.DevCommandsService)
--   print(Dev.run(game.Players:GetPlayers()[1], "grantXp", { amount = 500 }))
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local ItemRegistry = require(Shared.Domain.ItemRegistry)
local Remotes = require(Server.Net.Remotes)
local DevAccess = require(ServerStorage:WaitForChild("ServerData").DevAccess)

local DevCommandsService = {}
local services: any = nil
local commands = {}

function DevCommandsService.init(allServices: any)
	services = allServices
end

function DevCommandsService.isAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return table.find(DevAccess.developmentPlaceIds, game.PlaceId) ~= nil and table.find(DevAccess.allowedUserIds, player.UserId) ~= nil
end

function commands.grantXp(player: Player, args: any)
	return services.ProgressionService.grantCharacterXp(player, args.amount, "Development")
end

-- Until combat exists: report a kill to quests as the server would after a real one.
function commands.simulateKill(player: Player, args: any)
	if type(args.enemyId) ~= "string" or Content.enemies[args.enemyId] == nil then
		return false, "unknown enemy"
	end
	local count = math.clamp(math.floor(tonumber(args.count) or 1), 1, 10)
	services.QuestService.reportEvent(player, { kind = "Kill", target = args.enemyId, amount = count })
	return true, nil
end

-- Spawns an enemy 15 studs ahead, for combat testing before open-world spawns exist.
function commands.spawnEnemy(player: Player, args: any)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root == nil or type(args.enemyId) ~= "string" or Content.enemies[args.enemyId] == nil then
		return false, "unknown enemy"
	end
	task.spawn(services.EnemyService.spawn, args.enemyId, root.CFrame * CFrame.new(0, 0, -15), nil, nil)
	return true, nil
end

-- Marks a quest completed, to test content behind it (workshops, contracts) without playing it through.
function commands.completeQuest(player: Player, args: any)
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil or type(args.questId) ~= "string" or Content.quests[args.questId] == nil then
		return false, "unknown quest"
	end
	character.quests[args.questId] = { state = "Completed", progress = {}, completions = 1 }
	return true, nil
end

function commands.assignClass(player: Player, args: any)
	return services.ProgressionService.assignInitialClass(player, args.classId, "Development")
end

-- Development only: switch class to try each one (players change class only through class books). Gives the
-- class's starting weapon and respawns the character so class traits (health, speed) apply.
function commands.setClass(player: Player, args: any)
	local character = services.PlayerDataService.getCharacter(player)
	local classDef = type(args.classId) == "string" and Content.classes[args.classId]
	if character == nil or not classDef then
		return false, "unknown class"
	end
	character.class.classId = nil
	local ok, reason = services.ProgressionService.assignInitialClass(player, args.classId, "Development")
	if not ok then
		return false, reason
	end
	-- A weapon the new class can't use goes back to the inventory.
	local weapon = character.equipment.MainHand
	local weaponDef = weapon and Content.items[weapon.itemId]
	local weaponType = weaponDef and weaponDef.equipment and weaponDef.equipment.weaponType
	if weaponType ~= nil and (classDef.weaponTypes == nil or table.find(classDef.weaponTypes, weaponType) == nil) then
		require(game:GetService("ReplicatedStorage").Shared.Domain.Equipment).unequip(character, "MainHand", Content.items)
	end
	if classDef.startingWeapon ~= nil then
		commands.giveItem(player, { itemId = classDef.startingWeapon })
	end
	task.defer(function()
		player:LoadCharacter()
	end)
	return true, nil
end

function commands.grantDisciplineXp(player: Player, args: any)
	return services.ProgressionService.grantDisciplineXp(player, args.disciplineId, args.amount)
end

function commands.completeMilestone(player: Player, args: any)
	return services.ProgressionService.completeMilestone(player, args.disciplineId, args.milestoneId)
end

function commands.combatEvent(player: Player, args: any)
	local result = services.ProgressionService.reportCombatEvent(player, args.disciplineId, args.event)
	return result.accepted, result
end

function commands.grantProfessionXp(player: Player, args: any)
	return services.ProgressionService.grantProfessionXp(player, args.professionId, args.amount)
end

function commands.giveItem(player: Player, args: any)
	local def = Content.items[args.itemId]
	if def == nil then
		return false, "unknown item"
	end
	if ItemRegistry.isUnique(def) then
		return services.InventoryService.apply(player, "Dev", { { type = "GrantUnique", itemId = args.itemId, origin = { kind = "Development" } } })
	end
	return services.InventoryService.apply(player, "Dev", { { type = "GrantStack", itemId = args.itemId, amount = args.amount or 1 } })
end

function commands.giveGold(player: Player, args: any)
	return services.InventoryService.apply(player, "Dev", { { type = "AdjustCurrency", currency = "Gold", amount = args.amount } })
end

function commands.activateBook(player: Player, args: any)
	return services.LegendaryService.activate(player, args.bookUid, args.requestId or HttpService:GenerateGUID(false))
end

function commands.resetCharacter(player: Player, args: any)
	local ok = services.PlayerDataService.resetCharacterForDevelopment(player)
	services.ProgressionService.sendSnapshot(player)
	services.InventoryService.sendSnapshot(player)
	return ok, nil
end

function commands.snapshot(player: Player, args: any)
	return true, {
		progression = services.ProgressionService.snapshot(player),
		inventory = services.InventoryService.snapshot(player),
	}
end

function DevCommandsService.run(player: Player, name: any, args: any): (boolean, any)
	if not DevCommandsService.isAllowed(player) then
		return false, "development commands are not available here"
	end
	local command = type(name) == "string" and commands[name]
	if not command then
		return false, "unknown command"
	end
	if type(args) ~= "table" then
		args = {}
	end
	local success, ok, result = pcall(command, player, args)
	if not success then
		return false, "command error: " .. tostring(ok)
	end
	return ok, result
end

function DevCommandsService.start()
	Remotes.get("DevCommand").OnServerEvent:Connect(function(player: Player, name: any, args: any)
		local ok, result = DevCommandsService.run(player, name, args)
		local outcome = "ok"
		if not ok then
			outcome = tostring(result)
		end
		Remotes.get("Notify"):FireClient(player, string.format("[dev] %s: %s", tostring(name), outcome))
	end)
end

return DevCommandsService
