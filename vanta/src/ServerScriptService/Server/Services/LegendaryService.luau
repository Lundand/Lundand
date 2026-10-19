--!strict
-- Legendary Class Book activation requests (L-22). The client sends the book's ID and a request ID it
-- generated; the operation ID combines the user and request ID, so a repeated request does nothing.
-- Only one activation per player is processed at a time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Check = require(Shared.Util.Check)
local LegendaryActivation = require(Server.Domain.LegendaryActivation)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)
local DevAccess = require(ServerStorage:WaitForChild("ServerData").DevAccess)

local LegendaryService = {}
local services: any = nil
local inFlight: {[Player]: boolean} = {}
local limiter = RateLimiter.new(2, 0.2, os.clock)

function LegendaryService.init(allServices: any)
	services = allServices
end

local function developmentContentAllowed(): boolean
	return RunService:IsStudio() or table.find(DevAccess.developmentPlaceIds, game.PlaceId) ~= nil
end

function LegendaryService.activate(player: Player, bookUid: any, requestId: any): (boolean, any)
	if not Check.isToken(requestId, 40) then
		return false, "invalid request"
	end
	if inFlight[player] then
		return false, "an activation is already in progress"
	end
	local data = services.PlayerDataService.getData(player)
	if data == nil then
		return false, "data not loaded"
	end
	inFlight[player] = true
	local operationId = string.format("legendary:%d:%s", player.UserId, requestId)
	local success, ok, result = pcall(LegendaryActivation.activate, data, data.activeCharacterId, bookUid, operationId, {
		items = Content.items,
		classes = Content.classes,
		disciplines = Content.disciplines,
		progressionConfig = Content.progression,
		now = os.time,
		allowDevelopmentContent = developmentContentAllowed(),
	})
	inFlight[player] = nil
	if not success then
		warn("[Legendary] activation error: " .. tostring(ok))
		return false, "internal error; nothing was changed"
	end
	if ok and not result.alreadyApplied then
		services.PlayerDataService.requestSave(player)
		services.ProgressionService.onClassReplaced(player)
		services.InventoryService.sendSnapshot(player)
	end
	return ok, result
end

function LegendaryService.start()
	Remotes.get("ActivateLegendaryBook").OnServerEvent:Connect(function(player: Player, bookUid: any, requestId: any)
		if not limiter:allow(player) then
			return
		end
		local ok, result = LegendaryService.activate(player, bookUid, requestId)
		if ok and not result.alreadyApplied then
			Remotes.get("Notify"):FireClient(player, "Your legendary class has awakened. A new journey begins at level 1.")
		elseif not ok then
			Remotes.get("Notify"):FireClient(player, "Activation failed: " .. tostring(result))
		end
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		inFlight[player] = nil
		limiter:forget(player)
	end)
end

return LegendaryService
