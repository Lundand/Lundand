--!strict
-- Guild economy and progression (L-48), applied to the guild's shared record inside one version-checked
-- update. Guild level comes from guild XP earned through play, never from gold. Tax moves gold from a
-- member's reward to the treasury without creating or destroying any. Every change that may be retried
-- carries an operation ID and applies once. The treasury never goes negative, and maintenance can't charge
-- the same week twice because the paid-through week only moves forward inside the record.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)

local GuildEconomy = {}

local function can(record: any, userId: any, permission: string, rules: any): boolean
	local member = record.members[tostring(userId)]
	return member ~= nil and rules.permissions[member.rank][permission] == true
end

local function seen(record: any, operationId: any): boolean
	return record.operations ~= nil and record.operations[operationId] == true
end

local function remember(record: any, operationId: string, rules: any)
	record.operations = record.operations or {}
	record.operationOrder = record.operationOrder or {}
	record.operations[operationId] = true
	table.insert(record.operationOrder, operationId)
	while #record.operationOrder > rules.recentOperationsKept do
		record.operations[table.remove(record.operationOrder, 1)] = nil
	end
end

local function log(record: any, entry: any, rules: any)
	record.ledger = record.ledger or {}
	entry.balance = record.treasury
	table.insert(record.ledger, entry)
	while #record.ledger > rules.ledgerSize do
		table.remove(record.ledger, 1)
	end
end

-- Splits an eligible reward: the player keeps the rest, rounding in the player's favour.
function GuildEconomy.splitTax(amount: number, ratePercent: number): (number, number)
	local tax = math.floor(amount * ratePercent / 100)
	return amount - tax, tax
end

function GuildEconomy.setTaxRate(record: any, byUserId: number, rate: any, rules: any): (boolean, string?)
	if not can(record, byUserId, "setTax", rules) then
		return false, "not allowed"
	end
	if table.find(rules.taxRates, rate) == nil then
		return false, "that rate isn't offered"
	end
	record.taxRate = rate
	return true, nil
end

-- Credits tax delivered from a member's outbox, once per delivery.
function GuildEconomy.creditTax(record: any, operationId: string, amount: any, fromUserId: number, now: number, rules: any): (boolean, string?)
	if seen(record, operationId) then
		return true, nil
	end
	if not Check.isPositiveInteger(amount) then
		return false, "invalid amount"
	end
	remember(record, operationId, rules)
	record.treasury += amount
	log(record, { at = now, kind = "Tax", amount = amount, by = fromUserId }, rules)
	return true, nil
end

function GuildEconomy.spend(record: any, byUserId: number, operationId: string, amount: any, purpose: string, now: number, rules: any): (boolean, string?)
	if seen(record, operationId) then
		return true, nil
	end
	if not can(record, byUserId, "spend", rules) then
		return false, "not allowed"
	end
	if not Check.isPositiveInteger(amount) or amount > record.treasury then
		return false, "not enough in the treasury"
	end
	remember(record, operationId, rules)
	record.treasury -= amount
	log(record, { at = now, kind = "Spend", amount = -amount, by = byUserId, purpose = purpose }, rules)
	return true, nil
end

function GuildEconomy.level(xp: number, rules: any): number
	local level = 1
	for index, threshold in ipairs(rules.levelThresholds) do
		if xp < threshold then
			break
		end
		level = index + 1
	end
	return level
end

-- Guild XP only from configured gameplay sources, once per operation.
function GuildEconomy.addXp(record: any, operationId: string, amount: any, source: any, rules: any): (boolean, string?)
	if seen(record, operationId) then
		return true, nil
	end
	if type(source) ~= "string" or not rules.xpSources[source] then
		return false, "not a guild XP source"
	end
	if not Check.isPositiveInteger(amount) then
		return false, "invalid amount"
	end
	remember(record, operationId, rules)
	record.xp += amount
	return true, nil
end

-- Leaderboard order: level, then XP, then the older guild, then ID.
function GuildEconomy.rank(entries: {any}): {any}
	local ranked = table.clone(entries)
	table.sort(ranked, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		if a.xp ~= b.xp then
			return a.xp > b.xp
		end
		if a.createdAt ~= b.createdAt then
			return a.createdAt < b.createdAt
		end
		return a.id < b.id
	end)
	for index, entry in ipairs(ranked) do
		entry.rank = index
	end
	return ranked
end

-- One integer for an ordered cross-server leaderboard: level first, XP within the level.
function GuildEconomy.leaderboardScore(level: number, xp: number): number
	return level * 10000000000 + math.min(xp, 9999999999)
end

function GuildEconomy.validEmblemId(value: any): boolean
	return Check.isPositiveInteger(value) and value < 2 ^ 53
end

-- The ID format is all the server can check; whether Roblox approves and serves the image is only known
-- when it loads, so clients fall back to the default emblem when it doesn't.
function GuildEconomy.setEmblem(record: any, byUserId: number, assetId: any, now: number, rules: any): (boolean, string?)
	if not can(record, byUserId, "emblem", rules) then
		return false, "not allowed"
	end
	if assetId ~= 0 and not GuildEconomy.validEmblemId(assetId) then
		return false, "that isn't a valid asset ID"
	end
	if now - (record.emblemChangedAt or 0) < rules.emblem.changeCooldownSeconds then
		return false, "the emblem was changed recently"
	end
	record.emblemAssetId = assetId
	record.emblemChangedAt = now
	return true, nil
end

function GuildEconomy.hallStage(level: number, rules: any): (number, string)
	local index, name = 1, rules.hallStages[1].stage
	for stageIndex, stage in ipairs(rules.hallStages) do
		if level >= stage.level then
			index, name = stageIndex, stage.stage
		end
	end
	return index, name
end

local function upkeep(record: any, rules: any): number
	local stage = GuildEconomy.hallStage(GuildEconomy.level(record.xp, rules), rules)
	return rules.maintenance.costByStage[stage]
end

-- Charges the weeks that have passed, each once. Safe to run repeatedly and from any server. When the
-- treasury is short the hall becomes "Neglected"; the unpaid weeks are not owed later.
function GuildEconomy.settleMaintenance(record: any, now: number, rules: any): any
	local settings = rules.maintenance
	local period = math.floor(now / settings.periodSeconds)
	local state = record.maintenance
	if state.paidThrough == nil then
		state.paidThrough = period
		return { charged = 0, condition = state.condition }
	end
	if period <= state.paidThrough or state.condition == "Neglected" then
		return { charged = 0, condition = state.condition }
	end
	state.paidThrough = math.max(state.paidThrough, period - settings.maxCatchUpPeriods)
	local cost = upkeep(record, rules)
	local charged = 0
	while state.paidThrough < period do
		if record.treasury < cost then
			state.condition = "Neglected"
			state.paidThrough = period
			break
		end
		record.treasury -= cost
		charged += cost
		state.paidThrough += 1
	end
	if charged > 0 then
		log(record, { at = now, kind = "Maintenance", amount = -charged }, rules)
	end
	return { charged = charged, condition = state.condition }
end

-- What restoring a neglected hall costs: one week of upkeep.
function GuildEconomy.restoreCost(record: any, rules: any): number
	return upkeep(record, rules)
end

function GuildEconomy.restore(record: any, byUserId: number, now: number, rules: any): (boolean, string?)
	if record.maintenance.condition ~= "Neglected" then
		return false, "the hall is in good order"
	end
	if not can(record, byUserId, "spend", rules) then
		return false, "not allowed"
	end
	local cost = upkeep(record, rules)
	if record.treasury < cost then
		return false, "not enough in the treasury"
	end
	record.treasury -= cost
	record.maintenance.condition = "Maintained"
	record.maintenance.paidThrough = math.floor(now / rules.maintenance.periodSeconds)
	log(record, { at = now, kind = "Restore", amount = -cost, by = byUserId }, rules)
	return true, nil
end

-- Buying the guild's hall (L-54): one per guild, from the treasury, once the guild reaches the required level.
function GuildEconomy.buyHall(record: any, byUserId: number, propertyId: string, price: number, operationId: string, now: number, rules: any): (boolean, string?)
	if seen(record, operationId) then
		return true, nil
	end
	if not can(record, byUserId, "spend", rules) then
		return false, "not allowed"
	end
	if record.hallPropertyId ~= nil then
		return false, "the guild already has a hall"
	end
	if GuildEconomy.level(record.xp, rules) < rules.hallRequiredLevel then
		return false, string.format("a guild hall needs guild level %d", rules.hallRequiredLevel)
	end
	if not Check.isPositiveInteger(price) or record.treasury < price then
		return false, "not enough in the treasury"
	end
	remember(record, operationId, rules)
	record.treasury -= price
	record.hallPropertyId = propertyId
	log(record, { at = now, kind = "Hall", amount = -price, by = byUserId, purpose = propertyId }, rules)
	return true, nil
end

-- If the hall was taken before the purchase finished, the treasury gets the price back.
function GuildEconomy.refundHall(record: any, price: number, now: number, rules: any)
	record.treasury += price
	log(record, { at = now, kind = "HallRefund", amount = price, purpose = record.hallPropertyId }, rules)
	record.hallPropertyId = nil
end

function GuildEconomy.buyUpgrade(record: any, byUserId: number, upgradeId: any, operationId: string, now: number, rules: any): (boolean, string?)
	if seen(record, operationId) then
		return true, nil
	end
	local upgrade = type(upgradeId) == "string" and rules.upgrades[upgradeId]
	if not upgrade then
		return false, "unknown upgrade"
	end
	if not can(record, byUserId, "upgrade", rules) then
		return false, "not allowed"
	end
	record.upgrades = record.upgrades or {}
	if record.upgrades[upgradeId] ~= nil then
		return false, "already built"
	end
	if GuildEconomy.level(record.xp, rules) < upgrade.requiredLevel then
		return false, "guild level too low"
	end
	if upgrade.requires ~= nil and record.upgrades[upgrade.requires] == nil then
		return false, "build " .. upgrade.requires .. " first"
	end
	if record.treasury < upgrade.cost then
		return false, "not enough in the treasury"
	end
	remember(record, operationId, rules)
	record.treasury -= upgrade.cost
	record.upgrades[upgradeId] = now
	log(record, { at = now, kind = "Upgrade", amount = -upgrade.cost, by = byUserId, purpose = upgradeId }, rules)
	return true, nil
end

-- What a member sees in the guild window, limited by their rank's permissions.
function GuildEconomy.summary(record: any, viewerUserId: number, rules: any): any
	local me = record.members[tostring(viewerUserId)]
	if me == nil then
		return nil
	end
	local permissions = rules.permissions[me.rank] or {}
	local level = GuildEconomy.level(record.xp, rules)
	local members = {}
	for key, member in pairs(record.members) do
		table.insert(members, { userId = tonumber(key), name = member.name, rank = member.rank })
	end
	table.sort(members, function(a, b)
		local rankA, rankB = table.find(rules.ranks, a.rank) or 99, table.find(rules.ranks, b.rank) or 99
		if rankA ~= rankB then
			return rankA < rankB
		end
		return a.name < b.name
	end)
	local upgrades = {}
	for id, upgrade in pairs(rules.upgrades) do
		table.insert(upgrades, {
			id = id,
			name = upgrade.displayName,
			cost = upgrade.cost,
			requiredLevel = upgrade.requiredLevel,
			requires = upgrade.requires,
			built = (record.upgrades or {})[id] ~= nil,
		})
	end
	table.sort(upgrades, function(a, b)
		if a.requiredLevel ~= b.requiredLevel then
			return a.requiredLevel < b.requiredLevel
		end
		return a.id < b.id
	end)
	local view: any = {
		id = record.id,
		name = record.name,
		emblemAssetId = record.emblemAssetId,
		level = level,
		xp = record.xp,
		nextLevelXp = rules.levelThresholds[level],
		members = members,
		myRank = me.rank,
		permissions = table.clone(permissions),
		taxRate = record.taxRate,
		hallPropertyId = record.hallPropertyId,
		maintenance = { condition = record.maintenance.condition, weeklyCost = upkeep(record, rules) },
		upgrades = upgrades,
	}
	if permissions.viewTreasury then
		view.treasury = record.treasury
		view.ledger = {}
		local ledger = record.ledger or {}
		for index = math.max(1, #ledger - 9), #ledger do
			table.insert(view.ledger, ledger[index])
		end
	end
	return view
end

return GuildEconomy
