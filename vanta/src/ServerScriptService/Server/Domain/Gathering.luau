--!strict
-- Resource gathering rules (L-11): requirements, gather time, drops and respawn. No engine calls;
-- GatheringService supplies positions, time and randomness.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)
local ItemRegistry = require(Shared.Domain.ItemRegistry)

local Gathering = {}

Gathering.INTERACTIONS = table.freeze({ Hold = true, Strike = true })

function Gathering.bestToolTier(inventory: any, items: any, toolType: string): number
	local best = 0
	for _, unique in pairs(inventory.uniques) do
		local def = items[unique.itemId]
		if def and def.kind == "Tool" and def.tool.toolType == toolType and def.tool.toolTier > best then
			best = def.tool.toolTier
		end
	end
	return best
end

function Gathering.check(node: any, toolTier: number, professionLevel: number): (boolean, string?)
	if node.tool ~= nil and toolTier < node.tool.minTier then
		return false, string.format("needs a tier %d %s", node.tool.minTier, string.lower(node.tool.toolType))
	end
	if professionLevel < node.minProfessionLevel then
		return false, string.format("needs %s level %d", node.profession, node.minProfessionLevel)
	end
	return true, nil
end

function Gathering.duration(node: any, toolTier: number, professionLevel: number): number
	local efficiency = node.efficiency
	local reduction = math.max(0, professionLevel - node.minProfessionLevel) * efficiency.perLevel
	if node.tool ~= nil then
		reduction += math.max(0, toolTier - node.tool.minTier) * efficiency.perToolTier
	end
	return node.baseDuration * (1 - math.min(reduction, efficiency.maxReduction))
end

-- random: returns a number in [0, 1).
function Gathering.rollDrops(node: any, random: () -> number): {any}
	local totals = {}
	for _, drop in ipairs(node.drops) do
		local chance = drop.chance or 1
		if chance >= 1 or random() < chance then
			local amount = math.min(drop.min + math.floor(random() * (drop.max - drop.min + 1)), drop.max)
			totals[drop.itemId] = (totals[drop.itemId] or 0) + amount
		end
	end
	local result = {}
	for itemId, amount in pairs(totals) do
		if amount > 0 then
			table.insert(result, { itemId = itemId, amount = amount })
		end
	end
	table.sort(result, function(a, b)
		return a.itemId < b.itemId
	end)
	return result
end

-- Runtime state for one placed node (not saved).
function Gathering.newNodeState()
	return { sharedReadyAt = 0, personal = {} }
end

function Gathering.readyAt(nodeState: any, node: any, userKey: string, savedReadyAt: number?): number
	if node.respawn.scope == "Shared" then
		return nodeState.sharedReadyAt
	end
	return math.max(nodeState.personal[userKey] or 0, savedReadyAt or 0)
end

function Gathering.markGathered(nodeState: any, node: any, userKey: string, now: number): number
	local readyAt = now + node.respawn.seconds
	if node.respawn.scope == "Shared" then
		nodeState.sharedReadyAt = readyAt
	else
		nodeState.personal[userKey] = readyAt
	end
	return readyAt
end

-- Removes expired saved cooldowns so saves don't grow forever. Returns how many were removed.
function Gathering.pruneCooldowns(cooldowns: {[string]: number}, now: number): number
	local removed = 0
	for nodeId, readyAt in pairs(cooldowns) do
		if readyAt <= now then
			cooldowns[nodeId] = nil
			removed += 1
		end
	end
	return removed
end

function Gathering.validateNodes(nodes: any, items: any, professions: any): {string}
	local problems = {}
	local function add(nodeId: any, message: string)
		table.insert(problems, "node " .. tostring(nodeId) .. ": " .. message)
	end
	for key, node in pairs(nodes) do
		if node.id ~= key then
			add(key, "id must match its key")
		end
		local profession = professions[node.profession]
		if profession == nil or profession.kind ~= "Gathering" then
			add(key, "needs a gathering profession")
		end
		if not Gathering.INTERACTIONS[node.interaction] then
			add(key, "unknown interaction")
		end
		if not Check.isFiniteNumber(node.baseDuration) or node.baseDuration <= 0 then
			add(key, "baseDuration must be positive")
		end
		if not Check.isPositiveInteger(node.minProfessionLevel) or not Check.isNonNegativeInteger(node.professionXp) then
			add(key, "needs a minimum level and whole-number XP")
		end
		local efficiency = node.efficiency
		if type(efficiency) ~= "table" or not Check.isFiniteNumber(efficiency.maxReduction) or efficiency.maxReduction < 0 or efficiency.maxReduction >= 1 then
			add(key, "efficiency.maxReduction must be in [0, 1)")
		end
		if node.tool ~= nil then
			local toolExists = false
			for _, def in pairs(items) do
				if def.kind == "Tool" and def.tool.toolType == node.tool.toolType then
					toolExists = true
				end
			end
			if not toolExists or not Check.isPositiveInteger(node.tool.minTier) then
				add(key, "requires a tool type that no item provides")
			end
		end
		if type(node.drops) ~= "table" or #node.drops == 0 then
			add(key, "needs drops")
		else
			for _, drop in ipairs(node.drops) do
				local def = items[drop.itemId]
				if def == nil or ItemRegistry.isUnique(def) then
					add(key, "drops must be known stackable items")
				end
				if not Check.isPositiveInteger(drop.min) or not Check.isPositiveInteger(drop.max) or drop.min > drop.max then
					add(key, "drop amounts must satisfy 1 <= min <= max")
				end
				if drop.chance ~= nil and (not Check.isFiniteNumber(drop.chance) or drop.chance <= 0 or drop.chance > 1) then
					add(key, "drop chance must be in (0, 1]")
				end
			end
		end
		local respawn = node.respawn
		if type(respawn) ~= "table" or (respawn.scope ~= "Personal" and respawn.scope ~= "Shared") or not Check.isPositiveInteger(respawn.seconds) then
			add(key, "respawn needs a scope and positive seconds")
		end
		if not Check.isFiniteNumber(node.maxDistance) or node.maxDistance <= 0 then
			add(key, "maxDistance must be positive")
		end
	end
	table.sort(problems)
	return problems
end

return Gathering
