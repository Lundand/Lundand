--!strict
-- Player save layout (T-10, L-22). Bump VERSION and add a step to Migrations whenever it changes.
-- Layers: account (survives everything), and per character: level, class, disciplines and legendary
-- (class progression), professions, inventory, equipment and currencies.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local ClassProgression = require(Shared.Domain.ClassProgression)
local DisciplineMastery = require(Shared.Domain.DisciplineMastery)
local ProfessionProgression = require(Shared.Domain.ProfessionProgression)
local Inventory = require(Shared.Domain.Inventory)

local PlayerSchema = {}

PlayerSchema.VERSION = 1
PlayerSchema.DEFAULT_CHARACTER_ID = "main"
PlayerSchema.INVENTORY_CAPACITY = 30
PlayerSchema.ACCOUNT_KEYS = table.freeze({
	"discoveries",
	"achievements",
	"titles",
	"entitlements",
	"receipts",
	"storage",
	"settings",
	"classHistory",
	"properties", -- owned properties: { [propertyId] = { kind, since, operationId } } (L-28)
	"pendingPurchases", -- property purchases between steps 2 and 4 (PropertyOwnership)
	"rentals", -- inn rooms: { [innId] = { expiresAt, invited } } (L-29)
	"guild", -- {} or { id, joinedAt } (L-30)
	"slots", -- character slot unlocks: { earned = { [unlockId] = true }, highestLevel } (L-45)
	"outbox", -- deliveries to shared records still to confirm: Rift donations, guild tax (L-47, L-48)
	"deletion", -- pending character deletion: { characterId, token, expiresAt } (L-45)
	"cosmetics", -- owned and equipped cosmetics, separate from item stats (L-34)
	"pets", -- cosmetic companions (L-35)
	"events", -- participation per event, such as Rift runs used (L-36)
})

function PlayerSchema.newCharacter(characterId: string)
	return {
		id = characterId,
		createdAt = 0,
		appearance = {}, -- character creation choices (L-38, L-45); empty until the character is created
		claims = {}, -- one-time rewards already given, such as the starting weapon (L-43)
		level = CharacterProgression.newState(),
		class = ClassProgression.newState(),
		disciplines = {},
		legendary = { active = false },
		professions = {},
		inventory = Inventory.newContainer(PlayerSchema.INVENTORY_CAPACITY),
		equipment = {},
		currencies = { Gold = 0 },
		nodeCooldowns = {},
		recipes = {}, -- learned recipes: { [recipeId] = true }
		quests = {}, -- { [questId] = { state = "Active" | "Completed", progress = {} } }
		story = {}, -- dialogue seen, journal entries and story flags (L-40)
	}
end

function PlayerSchema.template()
	local characterId = PlayerSchema.DEFAULT_CHARACTER_ID
	local account = { createdAt = 0 }
	for _, key in ipairs(PlayerSchema.ACCOUNT_KEYS) do
		account[key] = {}
	end
	return {
		schemaVersion = PlayerSchema.VERSION,
		account = account,
		activeCharacterId = characterId,
		characters = { [characterId] = PlayerSchema.newCharacter(characterId) },
		recentOperations = {},
		audit = {},
	}
end

local function validateCharacter(prefix: string, character: any, content: any, problems: {string}, warnings: {string})
	local function problem(message: any)
		table.insert(problems, prefix .. tostring(message))
	end
	if type(character) ~= "table" then
		problem("not a table")
		return
	end
	local ok, err = CharacterProgression.validateState(character.level, content.stats)
	if not ok then
		problem(err)
	end
	if type(character.level) == "table" and type(character.level.allocated) == "table" then
		for statId in pairs(character.level.allocated) do
			if content.stats.definitions[statId] == nil then
				table.insert(warnings, prefix .. "points on a retired stat will be refunded: " .. tostring(statId))
			end
		end
	end
	ok, err = ClassProgression.validateState(character.class, content.classes)
	if not ok then
		problem(err)
	elseif character.class.classId ~= nil and content.classes[character.class.classId] == nil then
		table.insert(warnings, prefix .. "unknown class kept: " .. tostring(character.class.classId))
	end
	if type(character.disciplines) ~= "table" then
		problem("disciplines missing")
	else
		for disciplineId, state in pairs(character.disciplines) do
			ok, err = DisciplineMastery.validateState(state)
			if not ok then
				problem(tostring(disciplineId) .. ": " .. tostring(err))
			end
			if content.disciplines[disciplineId] == nil then
				table.insert(warnings, prefix .. "unknown discipline kept: " .. tostring(disciplineId))
			end
		end
	end
	if type(character.professions) ~= "table" then
		problem("professions missing")
	else
		for professionId, state in pairs(character.professions) do
			ok, err = ProfessionProgression.validateState(state)
			if not ok then
				problem(tostring(professionId) .. ": " .. tostring(err))
			end
		end
	end
	local inventoryProblems, inventoryWarnings = Inventory.validateContainer(character.inventory, content.items)
	for _, message in ipairs(inventoryProblems) do
		problem(message)
	end
	for _, message in ipairs(inventoryWarnings) do
		table.insert(warnings, prefix .. message)
	end
	if type(character.currencies) ~= "table" then
		problem("currencies missing")
	else
		for currency, balance in pairs(character.currencies) do
			if not Check.isNonNegativeInteger(balance) then
				problem("invalid balance for " .. tostring(currency))
			end
		end
	end
	for _, key in ipairs({ "legendary", "equipment", "nodeCooldowns", "recipes", "quests", "story", "appearance", "claims" }) do
		if type(character[key]) ~= "table" then
			problem(key .. " missing")
		end
	end
end

-- Returns problems (the save must not be used) and warnings (kept as-is, logged).
function PlayerSchema.validate(data: any, content: any): ({string}, {string})
	local problems, warnings = {}, {}
	if type(data) ~= "table" then
		return { "save is not a table" }, warnings
	end
	if not Check.isPositiveInteger(data.schemaVersion) or data.schemaVersion > PlayerSchema.VERSION then
		table.insert(problems, "unsupported schema version")
	end
	if type(data.account) ~= "table" then
		table.insert(problems, "account missing")
	else
		for _, key in ipairs(PlayerSchema.ACCOUNT_KEYS) do
			if type(data.account[key]) ~= "table" then
				table.insert(problems, "account." .. key .. " missing")
			end
		end
	end
	if type(data.recentOperations) ~= "table" or type(data.audit) ~= "table" then
		table.insert(problems, "operation records missing")
	end
	if type(data.characters) ~= "table" then
		table.insert(problems, "characters missing")
		return problems, warnings
	end
	if type(data.characters[data.activeCharacterId]) ~= "table" then
		table.insert(problems, "active character missing")
	end
	for characterId, character in pairs(data.characters) do
		validateCharacter("character " .. tostring(characterId) .. ": ", character, content, problems, warnings)
	end
	return problems, warnings
end

return PlayerSchema
