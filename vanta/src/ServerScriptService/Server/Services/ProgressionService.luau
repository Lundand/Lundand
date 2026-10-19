--!strict
-- Character level and stats, class, discipline mastery and professions for each player (L-17).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Curve = require(Shared.Domain.Curve)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local ItemStats = require(Shared.Domain.ItemStats)
local ClassProgression = require(Shared.Domain.ClassProgression)
local DisciplineMastery = require(Shared.Domain.DisciplineMastery)
local ProfessionProgression = require(Shared.Domain.ProfessionProgression)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local ProgressionService = {}
local services: any = nil
local masterySessions: {[Player]: {[string]: any}} = {}
local limiter = RateLimiter.new(5, 2, os.clock)

function ProgressionService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function characterLevel(character: any): number
	return CharacterProgression.level(character.level, Content.progression)
end

-- Grants class unlocks and techniques whose requirements are now met. Safe to call at any time.
local function refresh(character: any)
	ClassProgression.refreshUnlocks(character.class, Content.classes, { characterLevel = characterLevel(character) })
	for disciplineId, grant in pairs(ClassProgression.disciplineGrants(character.class, Content.classes)) do
		local state = character.disciplines[disciplineId]
		if state == nil then
			state = DisciplineMastery.newState()
			character.disciplines[disciplineId] = state
		end
		DisciplineMastery.refreshTechniques(state, Content.disciplines[disciplineId], grant)
	end
end

function ProgressionService.snapshot(player: Player): any
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return nil
	end
	local level, xpInto, xpNeeded = Curve.progress(Content.progression.characterCurve, character.level.xp)
	local grants = ClassProgression.disciplineGrants(character.class, Content.classes)
	local disciplines = {}
	for disciplineId, state in pairs(character.disciplines) do
		local def = Content.disciplines[disciplineId]
		local grant = grants[disciplineId]
		if def and grant then
			local rank, into, needed = Curve.progress(def.curve, state.xp)
			disciplines[disciplineId] = {
				name = def.displayName,
				rank = math.min(rank, grant.maxRank),
				maxRank = grant.maxRank,
				xpInto = into,
				xpNeeded = needed,
				techniques = table.clone(state.techniques),
			}
		end
	end
	local professions = {}
	for professionId, def in pairs(Content.professions) do
		local state = character.professions[professionId] or ProfessionProgression.newState()
		local professionLevel, into, needed = Curve.progress(def.curve, state.xp)
		professions[professionId] = { name = def.displayName, level = professionLevel, xpInto = into, xpNeeded = needed }
	end
	local classDef = character.class.classId and Content.classes[character.class.classId]
	return {
		level = level,
		xpInto = xpInto,
		xpNeeded = xpNeeded,
		availablePoints = CharacterProgression.availablePoints(character.level, Content.stats, Content.progression),
		allocated = table.clone(character.level.allocated),
		derived = CharacterProgression.derivedStats(character.level, Content.stats, ItemStats.equipmentBonuses(character.equipment, Content.items, Content.gear)),
		xpBonus = character.level.xpBonus,
		classId = character.class.classId,
		className = classDef and classDef.displayName,
		classUnlocks = table.clone(character.class.unlocks),
		disciplines = disciplines,
		professions = professions,
		legendary = character.legendary.active == true,
	}
end

function ProgressionService.sendSnapshot(player: Player)
	local snapshot = ProgressionService.snapshot(player)
	if snapshot then
		Remotes.get("Snapshot"):FireClient(player, "Progression", snapshot)
	end
end

function ProgressionService.grantCharacterXp(player: Player, amount: any, reason: string): (boolean, any)
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return false, "data not loaded"
	end
	local ok, result = CharacterProgression.grantXp(character.level, amount, Content.stats, Content.progression)
	if ok then
		refresh(character)
		if result.levelAfter > result.levelBefore then
			notify(player, string.format("Level %d reached (+%d stat points)", result.levelAfter, result.pointsGained))
			services.CharacterService.recordLevel(player, result.levelAfter)
		end
		ProgressionService.sendSnapshot(player)
	end
	return ok, result
end

function ProgressionService.assignInitialClass(player: Player, classId: any, source: string): (boolean, any)
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return false, "data not loaded"
	end
	local ok, err = ClassProgression.assignInitialClass(character.class, classId, Content.classes, source, os.time())
	if ok then
		refresh(character)
		ProgressionService.sendSnapshot(player)
	end
	return ok, err
end

local function disciplineContext(player: Player, disciplineId: any)
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return nil
	end
	local grant = ClassProgression.disciplineGrants(character.class, Content.classes)[disciplineId]
	local def = Content.disciplines[disciplineId]
	local state = character.disciplines[disciplineId]
	if grant == nil or def == nil or state == nil then
		return nil
	end
	return { character = character, grant = grant, def = def, state = state }
end

-- Called by the combat system with events the server has verified (T-15).
function ProgressionService.reportCombatEvent(player: Player, disciplineId: any, event: any): any
	local context = disciplineContext(player, disciplineId)
	if context == nil or type(event) ~= "table" then
		return { accepted = false, reason = "discipline not available", milestonesCompleted = {}, techniquesUnlocked = {} }
	end
	event.characterLevel = characterLevel(context.character)
	event.now = workspace:GetServerTimeNow()
	local sessions = masterySessions[player]
	if sessions == nil then
		sessions = {}
		masterySessions[player] = sessions
	end
	local session = sessions[disciplineId]
	if session == nil then
		session = DisciplineMastery.newSession()
		sessions[disciplineId] = session
	end
	local result = DisciplineMastery.applyEvent(context.state, context.def, context.grant, event, session, Content.mastery)
	for _, techniqueId in ipairs(result.techniquesUnlocked) do
		notify(player, "New technique: " .. context.def.techniques[techniqueId].displayName)
	end
	if result.rankAfter ~= result.rankBefore or #result.techniquesUnlocked > 0 or #result.milestonesCompleted > 0 then
		ProgressionService.sendSnapshot(player)
	end
	return result
end

function ProgressionService.grantDisciplineXp(player: Player, disciplineId: any, amount: any): (boolean, any)
	local context = disciplineContext(player, disciplineId)
	if context == nil then
		return false, "discipline not available"
	end
	local gained, unlocked = DisciplineMastery.grantXp(context.state, context.def, context.grant, amount)
	ProgressionService.sendSnapshot(player)
	return true, { gained = gained, techniquesUnlocked = unlocked }
end

function ProgressionService.completeMilestone(player: Player, disciplineId: any, milestoneId: any): (boolean, any)
	local context = disciplineContext(player, disciplineId)
	if context == nil then
		return false, "discipline not available"
	end
	local ok, err = DisciplineMastery.completeMilestone(context.state, context.def, context.grant, milestoneId)
	ProgressionService.sendSnapshot(player)
	return ok, err
end

function ProgressionService.professionLevel(player: Player, professionId: string): number
	local character = services.PlayerDataService.getCharacter(player)
	local def = Content.professions[professionId]
	if character == nil or def == nil then
		return 0
	end
	local state = character.professions[professionId]
	if state == nil then
		return 1
	end
	return ProfessionProgression.level(state, def)
end

function ProgressionService.grantProfessionXp(player: Player, professionId: any, amount: any): (boolean, any)
	local character = services.PlayerDataService.getCharacter(player)
	local def = Content.professions[professionId]
	if character == nil or def == nil then
		return false, "profession not available"
	end
	local state = character.professions[professionId]
	if state == nil then
		state = ProfessionProgression.newState()
		character.professions[professionId] = state
	end
	local gained, before, after = ProfessionProgression.grantXp(state, def, amount)
	if after > before then
		notify(player, string.format("%s level %d", def.displayName, after))
	end
	ProgressionService.sendSnapshot(player)
	return true, { gained = gained, levelBefore = before, levelAfter = after }
end

-- After a Legendary Class Book activation replaced the class (LegendaryService).
function ProgressionService.onClassReplaced(player: Player)
	masterySessions[player] = nil
	local character = services.PlayerDataService.getCharacter(player)
	if character then
		refresh(character)
	end
	ProgressionService.sendSnapshot(player)
end

local function onAllocateStats(player: Player, request: any)
	if not limiter:allow(player) then
		return
	end
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return
	end
	local ok, err = CharacterProgression.allocate(character.level, request, Content.stats, Content.progression)
	if not ok then
		notify(player, "Could not allocate points: " .. tostring(err))
	end
	ProgressionService.sendSnapshot(player)
end

function ProgressionService.start()
	services.PlayerDataService.Loaded:Connect(function(player: Player)
		local character = services.PlayerDataService.getCharacter(player)
		if character == nil then
			return
		end
		local retired = CharacterProgression.dropUnknownStats(character.level, Content.stats)
		if retired > 0 then
			notify(player, string.format("%d stat points from a retired stat were refunded.", retired))
		end
		if CharacterProgression.isOverAllocated(character.level, Content.stats, Content.progression) then
			local refunded = CharacterProgression.resetAllocation(character.level)
			notify(player, string.format("Stat points were rebalanced: %d points refunded.", refunded))
		end
		refresh(character)
		ProgressionService.sendSnapshot(player)
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		masterySessions[player] = nil
		limiter:forget(player)
	end)
	Remotes.get("AllocateStats").OnServerEvent:Connect(onAllocateStats)
	Remotes.get("RequestSnapshot").OnServerEvent:Connect(function(player: Player)
		if limiter:allow(player) then
			ProgressionService.sendSnapshot(player)
			services.InventoryService.sendSnapshot(player)
		end
	end)
end

return ProgressionService
