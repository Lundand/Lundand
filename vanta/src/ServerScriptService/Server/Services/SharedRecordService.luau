--!strict
-- Connects shared records to Roblox (T-23): one DataStore per kind of record, and change announcements through
-- MessagingService so other servers drop their cached copy. In Studio, API access must be enabled.
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

local SharedRecords = require(script.Parent.Parent.Data.SharedRecords)
local MemoryRecordStore = require(script.Parent.Parent.Data.MemoryRecordStore)

local TOPIC = "SharedRecordChanged"

local SharedRecordService = {}
local stores: {[string]: any} = {}
local warned = false

-- The real DataStore when it can be reached. In Studio, when it can't (an unpublished place, or API access off),
-- a temporary in-memory store, so these features can still be tried; live servers always use the DataStore.
local function openStore(name: string): any
	local opened, store = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if opened then
		local reachable = pcall(function()
			return store:GetAsync("__reachable")
		end)
		if reachable or not RunService:IsStudio() then
			return store
		end
	elseif not RunService:IsStudio() then
		error(store)
	end
	if not warned then
		warned = true
		warn("[SharedRecords] DataStores can't be reached. Publish the place and turn on Studio Access to API Services to use them. Until then buildings, guilds, shops and the Rift use temporary records that last only this session.")
	end
	return MemoryRecordStore.new()
end

function SharedRecordService.init(_services: any) end

function SharedRecordService.store(name: string): any
	local records = stores[name]
	if records == nil then
		records = SharedRecords.new(openStore(name), {
			now = os.clock,
			wait = task.wait,
			announce = function(key: string)
				task.spawn(function()
					pcall(function()
						MessagingService:PublishAsync(TOPIC, { store = name, key = key, from = game.JobId })
					end)
				end)
			end,
		})
		stores[name] = records
	end
	return records
end

function SharedRecordService.start()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message: any)
				local data = message.Data
				if type(data) == "table" and data.from ~= game.JobId and stores[data.store] ~= nil then
					stores[data.store]:invalidate(data.key)
				end
			end)
		end)
		if not ok then
			warn("[SharedRecords] change announcements unavailable: " .. tostring(err))
		end
	end)
end

return SharedRecordService
