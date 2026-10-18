--!strict
-- Server entry point: creates remotes, then initializes and starts every service in dependency order.
local Server = script.Parent
local Remotes = require(Server.Net.Remotes)

-- The capital builds itself when the place has none yet, so a fresh place file plays straight away. It pauses
-- now and then while building; services start once it is done. Build it in Studio and save to skip this.
if workspace:FindFirstChild("City") == nil then
	require(Server.Tools.CityBuilder).build({ yield = true })
end

local ORDER = {
	"PlayerDataService",
	"SharedRecordService",
	"InventoryService",
	"ProgressionService",
	"QuestService",
	"DialogueService",
	"PartyService",
	"OnboardingService",
	"CharacterService",
	"ResourceService",
	"LootService",
	"SpawnService",
	"WorldService",
	"SummonService",
	"CombatService",
	"EnemyService",
	"CraftingService",
	"VendorService",
	"CosmeticShopService",
	"OutboxService",
	"PropertyService",
	"GuildService",
	"ShopService",
	"RiftService",
	"GatheringService",
	"LegendaryService",
	"MonetizationService",
	"DevCommandsService",
}

Remotes.setup()

local services = {}
for _, name in ipairs(ORDER) do
	services[name] = require(Server.Services[name])
end
for _, name in ipairs(ORDER) do
	if services[name].init then
		services[name].init(services)
	end
end
for _, name in ipairs(ORDER) do
	if services[name].start then
		services[name].start()
	end
end
print("[Server] services started")
