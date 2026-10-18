--!strict
-- The opening (L-43). Characters that haven't awakened appear in the church. The chest by the church door
-- gives the starting weapon once. The awakening ritual plays on the awakened player's screen only; the
-- class is already saved on the server, so skipping the ritual changes nothing.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Onboarding = require(Server.Domain.Onboarding)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local CHEST_DISTANCE = 12

local OnboardingService = {}
local services: any = nil
local limiter = RateLimiter.new(4, 1, os.clock)

function OnboardingService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function marker(tag: string, attribute: string?, value: string?): BasePart?
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		if instance:IsA("BasePart") and (attribute == nil or instance:GetAttribute(attribute) == value) then
			return instance
		end
	end
	return nil
end

-- New characters appear in the church until they awaken. Waits for the save to load, and for Roblox to finish
-- placing the character at a spawn (a move made earlier gets overridden), then moves it.
local function placeCharacter(player: Player, model: Model)
	local character = nil
	for _ = 1, 50 do
		character = services.PlayerDataService.getCharacter(player)
		if character ~= nil or model.Parent == nil then
			break
		end
		task.wait(0.2)
	end
	if character == nil or Onboarding.spawnPoint(character) ~= "Church" then
		return
	end
	local point = marker("SpawnPoint", "SpawnId", "Church")
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if point == nil or root == nil then
		return
	end
	while model.Parent ~= nil and not model:IsDescendantOf(workspace) do
		task.wait()
	end
	task.wait(0.2)
	if model.Parent ~= nil then
		model:PivotTo(point.CFrame + Vector3.new(0, 3, 0))
	end
end

-- Called by DialogueService once the awakened class is saved.
function OnboardingService.playAwakening(player: Player, classId: string, quick: boolean)
	local circle = marker("RitualCircle")
	Remotes.get("AwakeningRitual"):FireClient(player, {
		classId = classId,
		className = Content.classes[classId].displayName,
		position = circle and circle.Position,
		quick = quick,
	})
end

local function openChest(player: Player, chest: BasePart)
	if not limiter:allow(player) then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local data = services.PlayerDataService.getData(player)
	if root == nil or data == nil or (root.Position - chest.Position).Magnitude > CHEST_DISTANCE then
		return
	end
	local ok, result = Onboarding.claimStarterWeapon(data, data.activeCharacterId, services.InventoryService.deps(player))
	if not ok then
		notify(player, tostring(result))
		return
	end
	local name = Content.items[result.itemId].displayName
	if result.equipped then
		notify(player, "You take the " .. name .. " and grip it in your hand.")
	else
		notify(player, "You take the " .. name .. ".")
	end
	services.InventoryService.sendSnapshot(player)
	services.CombatService.attachWeapon(player)
end

local function setupChest(chest: Instance)
	if not chest:IsA("BasePart") or chest:FindFirstChild("OpenPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Chest"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CHEST_DISTANCE - 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = chest
	prompt.Triggered:Connect(function(player: Player)
		openChest(player, chest)
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(model: Model)
		task.spawn(placeCharacter, player, model)
	end)
	if player.Character ~= nil then
		task.spawn(placeCharacter, player, player.Character)
	end
end

function OnboardingService.start()
	for _, chest in ipairs(CollectionService:GetTagged("StarterChest")) do
		setupChest(chest)
	end
	CollectionService:GetInstanceAddedSignal("StarterChest"):Connect(setupChest)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		limiter:forget(player)
	end)
end

return OnboardingService
