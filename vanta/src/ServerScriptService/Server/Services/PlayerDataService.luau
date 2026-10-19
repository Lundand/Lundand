--!strict
-- Loads, migrates, validates and saves player data (T-04, T-10).
-- Rule for other services: read data through getData/getCharacter when you need it, and never keep
-- references to tables inside a save between calls (transactions and activation swap them).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Table = require(Shared.Util.Table)
local Signal = require(Shared.Util.Signal)
local Content = require(Shared.Content)
local PlayerSchema = require(Server.Data.PlayerSchema)
local Migrations = require(Server.Data.Migrations)
local ProfileProviders = require(Server.Data.ProfileProviders)

local STORE_NAME = "PlayerData_v1"

local PlayerDataService = {}
PlayerDataService.Loaded = Signal.new() -- (player)
PlayerDataService.Releasing = Signal.new() -- (player)

local provider: any = nil
local sessions: {[Player]: any} = {}

-- Migrates and validates a copy; writes back into the live table only when everything succeeded.
local function prepare(session: any): (boolean, string?)
	local data = session.Data
	local ok, migrated = Migrations.run(Table.deepCopy(data), PlayerSchema.VERSION)
	if not ok then
		return false, migrated
	end
	local problems, warnings = PlayerSchema.validate(migrated, Content)
	if #problems > 0 then
		return false, problems[1]
	end
	for _, message in ipairs(warnings) do
		warn("[PlayerData] " .. message)
	end
	if migrated.schemaVersion ~= data.schemaVersion then
		Table.replaceContents(data, migrated)
	end
	if data.account.createdAt == 0 then
		data.account.createdAt = os.time()
	end
	return true, nil
end

local function onPlayerAdded(player: Player)
	local session = provider.startSession(player)
	if session == nil then
		if player.Parent == Players then
			player:Kick("Your data could not be loaded. Please rejoin.")
		end
		return
	end
	if player.Parent ~= Players then
		session.End()
		return
	end
	local ok, problem = prepare(session)
	if not ok then
		warn(string.format("[PlayerData] %d not loaded: %s", player.UserId, tostring(problem)))
		session.End()
		if problem == "save is newer than this server" then
			player:Kick("This server is out of date. Please rejoin.")
		else
			player:Kick("Your save could not be loaded safely and has not been changed. Please contact the developers.")
		end
		return
	end
	sessions[player] = session
	session.OnEnded(function()
		if sessions[player] == session then
			sessions[player] = nil
			PlayerDataService.Releasing:Fire(player)
			if player.Parent == Players then
				player:Kick("Your data was opened on another server. Please rejoin.")
			end
		end
	end)
	PlayerDataService.Loaded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	sessions[player] = nil
	PlayerDataService.Releasing:Fire(player)
	session.End()
end

function PlayerDataService.start()
	provider = ProfileProviders.create(STORE_NAME, PlayerSchema.template())
	if provider.kind == "Memory" then
		warn("[PlayerData] ProfileStore is not installed: using in-memory data. Nothing will be saved.")
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

function PlayerDataService.getData(player: Player): any
	local session = sessions[player]
	return session and session.Data
end

function PlayerDataService.getCharacter(player: Player): (any, string?)
	local data = PlayerDataService.getData(player)
	if data == nil then
		return nil, nil
	end
	return data.characters[data.activeCharacterId], data.activeCharacterId
end

function PlayerDataService.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function PlayerDataService.requestSave(player: Player)
	local session = sessions[player]
	if session then
		session.Save()
	end
end

function PlayerDataService.saveAndWait(player: Player, timeout: number): boolean
	local session = sessions[player]
	return session ~= nil and session.SaveAsync(timeout)
end

-- Development only (DevCommandsService): replaces the active character with a fresh one.
function PlayerDataService.resetCharacterForDevelopment(player: Player): boolean
	local data = PlayerDataService.getData(player)
	if data == nil then
		return false
	end
	data.characters[data.activeCharacterId] = PlayerSchema.newCharacter(data.activeCharacterId)
	return true
end

return PlayerDataService
