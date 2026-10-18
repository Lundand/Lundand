--!strict
-- Character slots (L-45): list, create, select and delete characters. Deleting takes two steps: after the
-- request the server issues a short-lived token, and only a confirmation carrying it deletes anything.
-- Switching to another character respawns the player.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local AppearanceRules = require(Shared.Domain.AppearanceRules)
local CharacterSlots = require(Server.Domain.CharacterSlots)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local CharacterService = {}
local services: any = nil
local limiter = RateLimiter.new(3, 0.5, os.clock)

function CharacterService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function describeWait(seconds: number): string
	if seconds >= 86400 then
		return string.format("%d day(s)", math.ceil(seconds / 86400))
	end
	return string.format("%d hour(s)", math.max(1, math.ceil(seconds / 3600)))
end

local function newId(): string
	return (string.gsub(HttpService:GenerateGUID(false), "-", ""))
end

function CharacterService.view(player: Player): any
	local data = services.PlayerDataService.getData(player)
	if data == nil then
		return nil
	end
	local characters = {}
	for id, character in pairs(data.characters) do
		table.insert(characters, {
			id = id,
			classId = character.class.classId,
			level = CharacterProgression.level(character.level, Content.progression),
			createdAt = character.createdAt or 0,
			active = id == data.activeCharacterId,
			deletableAt = CharacterSlots.deletableAt(character, Content.characterSlots), -- for the interface (L-49)
		})
	end
	table.sort(characters, function(a, b)
		if a.createdAt == b.createdAt then
			return a.id < b.id
		end
		return a.createdAt < b.createdAt
	end)
	return { slots = CharacterSlots.unlockedSlots(data.account, Content.characterSlots), characters = characters }
end

-- Called on level-ups; opens configured extra slots for the account.
function CharacterService.recordLevel(player: Player, level: number)
	local data = services.PlayerDataService.getData(player)
	if data ~= nil and #CharacterSlots.recordLevel(data.account, level, Content.characterSlots) > 0 then
		notify(player, "A new character slot is open.")
	end
end

local function rgb(color: {number}): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Dresses the character from its saved appearance on the standard body, replacing the player's own avatar (L-38).
function CharacterService.applyAppearance(player: Player)
	local character = services.PlayerDataService.getCharacter(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil then
		return
	end
	local look = AppearanceRules.describe(character.appearance, Content.appearance)
	local description = Instance.new("HumanoidDescription")
	local skin = rgb(look.skin)
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = rgb(look.torso)
	description.LeftLegColor = rgb(look.legs)
	description.RightLegColor = rgb(look.legs)
	if look.hairAssetId > 0 then
		description.HairAccessory = tostring(look.hairAssetId)
	end
	if look.faceAssetId > 0 then
		description.Face = look.faceAssetId
	end
	pcall(function()
		humanoid:ApplyDescription(description)
	end)
end

local function offerCreation(player: Player)
	local character = services.PlayerDataService.getCharacter(player)
	if character ~= nil and not character.appearance.created then
		local current = AppearanceRules.default(Content.appearance)
		for field in pairs(AppearanceRules.FIELDS) do
			if character.appearance[field] ~= nil then
				current[field] = character.appearance[field]
			end
		end
		Remotes.get("OpenInterface"):FireClient(player, "CharacterCreation", { current = current })
	end
end

local function onRequest(player: Player, action: any, args: any)
	if not limiter:allow(player) or type(action) ~= "string" then
		return
	end
	if type(args) ~= "table" then
		args = {}
	end
	local data = services.PlayerDataService.getData(player)
	if data == nil then
		return
	end
	local rules = Content.characterSlots
	local now = os.time()
	local previousActive = data.activeCharacterId
	local ok, err = true, nil
	if action == "SetAppearance" then
		-- Creation only: choices preview on the body until the player confirms, then they are kept.
		local character = services.PlayerDataService.getCharacter(player)
		local valid, appearance = AppearanceRules.validate(args.appearance, Content.appearance)
		if character == nil or character.appearance.created or not valid then
			return
		end
		for field, value in pairs(appearance) do
			character.appearance[field] = value
		end
		if args.final == true then
			character.appearance.created = true
		end
		CharacterService.applyAppearance(player)
		return
	elseif action == "Create" then
		local id = newId()
		ok, err = CharacterSlots.create(data, id, now, rules)
		if ok then
			ok, err = CharacterSlots.select(data, id)
		end
	elseif action == "Select" then
		ok, err = CharacterSlots.select(data, args.characterId)
	elseif action == "RequestDelete" then
		local token = newId()
		ok, err = CharacterSlots.requestDeletion(data, args.characterId, token, now, rules)
		if ok then
			Remotes.get("OpenInterface"):FireClient(player, "ConfirmDelete", { characterId = args.characterId, token = token, seconds = rules.deletionConfirmSeconds })
		end
	elseif action == "ConfirmDelete" then
		ok, err = CharacterSlots.confirmDeletion(data, args.characterId, args.token, newId(), now, rules)
	elseif action ~= "List" then
		return
	end
	if not ok then
		local character = type(args.characterId) == "string" and data.characters[args.characterId]
		if err == "can't be deleted yet" and character then
			local remaining = CharacterSlots.deletableAt(character, rules) - now
			notify(player, "This character can be deleted in " .. describeWait(remaining) .. ".")
		else
			notify(player, "Characters: " .. tostring(err))
		end
		return
	end
	if data.activeCharacterId ~= previousActive then
		player:LoadCharacter()
		task.delay(1, offerCreation, player)
		services.ProgressionService.sendSnapshot(player)
		services.InventoryService.sendSnapshot(player)
	end
	Remotes.get("CharacterState"):FireClient(player, CharacterService.view(player))
end

function CharacterService.start()
	Remotes.get("CharacterRequest").OnServerEvent:Connect(onRequest)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(model: Model)
			model:WaitForChild("Humanoid", 10)
			for _ = 1, 50 do
				if services.PlayerDataService.getCharacter(player) ~= nil then
					break
				end
				task.wait(0.2)
			end
			CharacterService.applyAppearance(player)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	services.PlayerDataService.Loaded:Connect(function(player: Player)
		task.delay(2, offerCreation, player)
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		limiter:forget(player)
	end)
end

return CharacterService
