--!strict
-- Combat discipline mastery (L-17, L-18, T-13 to T-15). State is kept per discipline, not per class.
-- XP only comes from events the server has verified; repetition and a per-minute cap limit farming.
local Check = require(script.Parent.Parent.Util.Check)
local Curve = require(script.Parent.Curve)

local DisciplineMastery = {}

export type MilestoneState = { count: number, completed: boolean }
export type DrillState = { completions: number, day: number, dayCount: number }
export type State = { xp: number, milestones: {[string]: MilestoneState}, techniques: {[string]: boolean}, drills: {[string]: DrillState} }
export type Session = { recent: {[string]: {number}}, minuteStart: number, minuteXp: number }
export type EventResult = { accepted: boolean, reason: string?, xpGained: number, rankBefore: number, rankAfter: number, milestonesCompleted: {string}, techniquesUnlocked: {string} }

DisciplineMastery.EVENTS = table.freeze({ Hit = true, PerfectParry = true, ComboFinished = true, Kill = true, DrillCompleted = true })

function DisciplineMastery.newState(): State
	return { xp = 0, milestones = {}, techniques = {}, drills = {} }
end

-- Per-player runtime state used for anti-farming rules. Not saved.
function DisciplineMastery.newSession(): Session
	return { recent = {}, minuteStart = -1000000, minuteXp = 0 }
end

function DisciplineMastery.rank(state: State, def: any, grant: any): number
	return math.min(Curve.levelForXp(def.curve, state.xp), grant.maxRank)
end

-- XP stops at the class's rank ceiling for this discipline.
function DisciplineMastery.xpCap(def: any, grant: any): number
	return Curve.xpToReach(def.curve, math.min(grant.maxRank, Curve.maxLevel(def.curve)))
end

function DisciplineMastery.techniqueDefinitions(def: any, grant: any): {[string]: any}
	local result = {}
	for techniqueId, technique in pairs(def.techniques) do
		result[techniqueId] = technique
	end
	for techniqueId, technique in pairs(grant.extraTechniques or {}) do
		result[techniqueId] = technique
	end
	return result
end

function DisciplineMastery.milestonesDone(state: State, required: {string}?): boolean
	for _, milestoneId in ipairs(required or {}) do
		local progress = state.milestones[milestoneId]
		if progress == nil or not progress.completed then
			return false
		end
	end
	return true
end

-- Unlocks every technique whose rank and milestone requirements are met. Returns new IDs, sorted.
function DisciplineMastery.refreshTechniques(state: State, def: any, grant: any): {string}
	local rank = DisciplineMastery.rank(state, def, grant)
	local unlocked = {}
	for techniqueId, technique in pairs(DisciplineMastery.techniqueDefinitions(def, grant)) do
		if not state.techniques[techniqueId] and rank >= technique.rank and DisciplineMastery.milestonesDone(state, technique.milestones) then
			state.techniques[techniqueId] = true
			table.insert(unlocked, techniqueId)
		end
	end
	table.sort(unlocked)
	return unlocked
end

local function addXp(state: State, def: any, grant: any, amount: number): number
	local cap = DisciplineMastery.xpCap(def, grant)
	if amount <= 0 or state.xp >= cap then
		return 0
	end
	local newXp = math.min(state.xp + math.floor(amount), cap)
	local gained = newXp - state.xp
	state.xp = newXp
	return gained
end

local function targetProblem(event: any, rules: any): string?
	local target = event.target
	if type(target) ~= "table" then
		return "missing target"
	end
	if target.dummy then
		return "dummies only give mastery during drills"
	end
	if not target.hostile then
		return "target is not hostile"
	end
	if not Check.isFiniteNumber(target.level) or not Check.isFiniteNumber(event.characterLevel) then
		return "missing levels"
	end
	if target.level < event.characterLevel + rules.minTargetLevelOffset then
		return "target level too low"
	end
	return nil
end

local function repetitionMultiplier(session: Session, kind: string, event: any, rules: any): number
	if not rules.repetitionSources[kind] or event.techniqueId == nil then
		return 1
	end
	local repetition = rules.repetition
	local key = tostring(event.techniqueId) .. ":" .. tostring(event.step or 0)
	local cutoff = event.now - repetition.windowSeconds
	local kept = {}
	for _, time in ipairs(session.recent[key] or {}) do
		if time > cutoff then
			table.insert(kept, time)
		end
	end
	table.insert(kept, event.now)
	session.recent[key] = kept
	local extra = #kept - repetition.freeUses
	if extra <= 0 then
		return 1
	end
	return math.max(repetition.minimumMultiplier, 1 - repetition.decayPerUse * extra)
end

local function capPerMinute(session: Session, amount: number, now: number, rules: any): number
	if now - session.minuteStart >= 60 then
		session.minuteStart = now
		session.minuteXp = 0
	end
	local granted = math.min(amount, math.max(0, rules.xpPerMinuteCap - session.minuteXp))
	session.minuteXp += granted
	return granted
end

local function drillXp(state: State, drillId: string, drill: any, now: number): number
	local progress = state.drills[drillId]
	if progress == nil then
		progress = { completions = 0, day = -1, dayCount = 0 }
		state.drills[drillId] = progress
	end
	local day = math.floor(now / 86400)
	if progress.day ~= day then
		progress.day = day
		progress.dayCount = 0
	end
	progress.completions += 1
	if progress.completions == 1 then
		return drill.firstXp
	end
	if progress.dayCount >= drill.repeatsPerDay then
		return 0
	end
	progress.dayCount += 1
	return drill.repeatXp
end

local function milestoneMatches(milestone: any, event: any): boolean
	local target = event.target or {}
	if milestone.requireElite and not target.elite then
		return false
	end
	if milestone.requireMovingTarget and not target.moving then
		return false
	end
	if milestone.drillId ~= nil and milestone.drillId ~= event.drillId then
		return false
	end
	return true
end

-- event: { kind, techniqueId?, step?, target = { hostile, level, elite?, moving?, dummy? }, drillId?, now, characterLevel }
function DisciplineMastery.applyEvent(state: State, def: any, grant: any, event: any, session: Session, rules: any): EventResult
	local rankBefore = DisciplineMastery.rank(state, def, grant)
	local result = {
		accepted = false,
		reason = nil,
		xpGained = 0,
		rankBefore = rankBefore,
		rankAfter = rankBefore,
		milestonesCompleted = {},
		techniquesUnlocked = {},
	}
	if type(event) ~= "table" or not DisciplineMastery.EVENTS[event.kind] or not Check.isFiniteNumber(event.now) then
		result.reason = "invalid event"
		return result
	end
	local kind = event.kind
	if kind == "DrillCompleted" then
		local drill = def.drills[event.drillId or ""]
		if drill == nil then
			result.reason = "unknown drill"
			return result
		end
		result.xpGained += addXp(state, def, grant, drillXp(state, event.drillId, drill, event.now))
	else
		local problem = targetProblem(event, rules)
		if problem then
			result.reason = problem
			return result
		end
		if event.techniqueId ~= nil and not state.techniques[event.techniqueId] then
			result.reason = "technique not unlocked"
			return result
		end
		local amount = (def.xpSources[kind] or 0) * repetitionMultiplier(session, kind, event, rules)
		result.xpGained += addXp(state, def, grant, capPerMinute(session, amount, event.now, rules))
	end
	result.accepted = true

	for milestoneId, milestone in pairs(def.milestones) do
		if milestone.event == kind and milestoneMatches(milestone, event) then
			local progress = state.milestones[milestoneId]
			if progress == nil then
				progress = { count = 0, completed = false }
				state.milestones[milestoneId] = progress
			end
			if not progress.completed then
				progress.count += 1
				if progress.count >= milestone.count then
					progress.completed = true
					table.insert(result.milestonesCompleted, milestoneId)
					result.xpGained += addXp(state, def, grant, milestone.rewardXp or 0)
				end
			end
		end
	end
	table.sort(result.milestonesCompleted)
	result.techniquesUnlocked = DisciplineMastery.refreshTechniques(state, def, grant)
	result.rankAfter = DisciplineMastery.rank(state, def, grant)
	return result
end

-- Direct grants for quests and development tools. Still respects the rank ceiling.
function DisciplineMastery.grantXp(state: State, def: any, grant: any, amount: any): (number, {string})
	if not Check.isFiniteNumber(amount) or amount <= 0 then
		return 0, {}
	end
	local gained = addXp(state, def, grant, amount)
	return gained, DisciplineMastery.refreshTechniques(state, def, grant)
end

function DisciplineMastery.completeMilestone(state: State, def: any, grant: any, milestoneId: any): (boolean, string?)
	local milestone = def.milestones[milestoneId]
	if type(milestoneId) ~= "string" or milestone == nil then
		return false, "unknown milestone"
	end
	local progress = state.milestones[milestoneId]
	if progress and progress.completed then
		return false, "already completed"
	end
	state.milestones[milestoneId] = { count = milestone.count, completed = true }
	addXp(state, def, grant, milestone.rewardXp or 0)
	DisciplineMastery.refreshTechniques(state, def, grant)
	return true, nil
end

function DisciplineMastery.validateState(state: any): (boolean, string?)
	if type(state) ~= "table" then
		return false, "discipline state missing"
	end
	if not Check.isNonNegativeInteger(state.xp) then
		return false, "xp must be a non-negative whole number"
	end
	if type(state.milestones) ~= "table" or type(state.techniques) ~= "table" or type(state.drills) ~= "table" then
		return false, "discipline state is incomplete"
	end
	return true, nil
end

return DisciplineMastery
