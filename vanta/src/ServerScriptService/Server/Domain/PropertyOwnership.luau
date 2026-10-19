--!strict
-- Ownership rules for unique city properties (L-28, T-20). Each property has one shared record, which a
-- future PropertyService keeps in its own DataStore entry and changes only inside version-checked
-- updates; this module holds the rules so they can be tested offline. The record and the buyer's save
-- are separate documents, so buying is a short protocol:
--   1. reserve(record)          holds the property for one buyer for a short time
--   2. beginPurchase(profile)   takes the gold and notes the purchase as pending in the buyer's save
--   3. commit(record)           makes the buyer the owner
--   4. finishPurchase(profile)  turns the pending note into ownership in the buyer's save
-- If a server stops between steps, reconcile() settles the buyer's save from the records on their next
-- load: ownership is confirmed if the commit happened, otherwise the gold is refunded exactly once.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)
local Transaction = require(script.Parent.Transaction)

local PropertyOwnership = {}

function PropertyOwnership.newRecord(propertyId: string)
	return { propertyId = propertyId, version = 0, permissions = { mode = "Private", allowed = {} } }
end

-- Properties of a kind that the account owns or is in the middle of buying.
function PropertyOwnership.countOfKind(account: any, kind: string): number
	local count = 0
	for _, entry in pairs(account.properties) do
		if entry.kind == kind then
			count += 1
		end
	end
	for _, pending in pairs(account.pendingPurchases) do
		if pending.kind == kind then
			count += 1
		end
	end
	return count
end

function PropertyOwnership.canAcquire(account: any, property: any, rules: any): (boolean, string?)
	if property.kind == rules.guildHall.kind then
		return false, "guild halls are bought by a guild, from its treasury"
	end
	local limit = rules.limitsPerPlayer[property.kind]
	if limit ~= nil and PropertyOwnership.countOfKind(account, property.kind) >= limit then
		if property.kind == "House" then
			return false, "you already own a house"
		end
		return false, "you already own the maximum number of these properties"
	end
	return true, nil
end

-- Step 1, applied to the shared record.
function PropertyOwnership.reserve(record: any, userId: number, operationId: string, now: number, rules: any): (boolean, string?)
	if record.owner ~= nil then
		return false, "this property already has an owner"
	end
	local reservation = record.reservation
	if reservation ~= nil and reservation.expiresAt > now and reservation.operationId ~= operationId then
		return false, "someone else is buying this property"
	end
	record.reservation = { userId = userId, operationId = operationId, expiresAt = now + rules.reservationSeconds }
	record.version += 1
	return true, nil
end

-- Step 2, applied to the buyer's save. A repeated call with the same operation ID does nothing.
function PropertyOwnership.beginPurchase(profileData: any, characterId: string, property: any, price: any, operationId: any, rules: any, deps: any): (boolean, any)
	if not Check.isToken(operationId, 80) then
		return false, "invalid operation id"
	end
	local account = profileData.account
	if account.pendingPurchases[operationId] ~= nil then
		return true, { alreadyApplied = true }
	end
	local allowed, reason = PropertyOwnership.canAcquire(account, property, rules)
	if not allowed then
		return false, reason
	end
	if not Check.isNonNegativeInteger(price) then
		return false, "invalid price"
	end
	if price > 0 then
		local ok, result = Transaction.apply(profileData, characterId, {
			id = "property:" .. operationId,
			reason = "PropertyPurchase",
			changes = { { type = "AdjustCurrency", currency = "Gold", amount = -price } },
		}, deps)
		if not ok then
			return false, result
		end
	end
	account.pendingPurchases[operationId] = {
		propertyId = property.id,
		kind = property.kind,
		price = price,
		characterId = characterId,
		at = deps.now(),
	}
	return true, { alreadyApplied = false }
end

-- Step 3, applied to the shared record. An expired reservation still counts if nobody replaced it.
function PropertyOwnership.commit(record: any, userId: number, ownerName: string, operationId: string, now: number): (boolean, string?)
	if record.owner ~= nil then
		if record.owner.userId == userId and record.owner.operationId == operationId then
			return true, nil
		end
		return false, "this property already has an owner"
	end
	local reservation = record.reservation
	if reservation == nil or reservation.userId ~= userId or reservation.operationId ~= operationId then
		return false, "the reservation was lost"
	end
	record.owner = { userId = userId, name = ownerName, since = now, operationId = operationId }
	record.reservation = nil
	record.permissions = { mode = "Private", allowed = {} }
	record.version += 1
	return true, nil
end

-- Step 4, applied to the buyer's save.
function PropertyOwnership.finishPurchase(profileData: any, operationId: string): boolean
	local account = profileData.account
	local pending = account.pendingPurchases[operationId]
	if pending == nil then
		return false
	end
	account.properties[pending.propertyId] = { kind = pending.kind, since = pending.at, operationId = operationId }
	account.pendingPurchases[operationId] = nil
	return true
end

-- On load: settles the buyer's save against the shared records. recordFor(propertyId) returns the
-- current record, or nil if it can't be read right now (that purchase is then left for later).
-- Outcomes: Owned, Pending (still reserved for this buyer), Refunded, RefundFailed, Unknown, Lost.
function PropertyOwnership.reconcile(profileData: any, userId: number, recordFor: (string) -> any, deps: any): {any}
	local outcomes = {}
	local account = profileData.account
	local operationIds = {}
	for operationId in pairs(account.pendingPurchases) do
		table.insert(operationIds, operationId)
	end
	table.sort(operationIds)
	for _, operationId in ipairs(operationIds) do
		local pending = account.pendingPurchases[operationId]
		local record = recordFor(pending.propertyId)
		local outcome = "Unknown"
		if record ~= nil then
			if record.owner ~= nil and record.owner.userId == userId and record.owner.operationId == operationId then
				PropertyOwnership.finishPurchase(profileData, operationId)
				outcome = "Owned"
			elseif record.owner == nil and record.reservation ~= nil and record.reservation.operationId == operationId then
				outcome = "Pending"
			else
				local refunded = true
				if pending.price > 0 then
					refunded = Transaction.apply(profileData, pending.characterId, {
						id = "refund:" .. operationId,
						reason = "PropertyRefund",
						changes = { { type = "AdjustCurrency", currency = "Gold", amount = pending.price } },
					}, deps)
				end
				if refunded then
					account.pendingPurchases[operationId] = nil
					outcome = "Refunded"
				else
					outcome = "RefundFailed"
				end
			end
		end
		table.insert(outcomes, { operationId = operationId, propertyId = pending.propertyId, outcome = outcome })
	end
	-- Properties the records no longer give to this player (sold, transferred or reclaimed).
	for propertyId in pairs(account.properties) do
		local record = recordFor(propertyId)
		if record ~= nil and (record.owner == nil or record.owner.userId ~= userId) then
			account.properties[propertyId] = nil
			table.insert(outcomes, { propertyId = propertyId, outcome = "Lost" })
		end
	end
	return outcomes
end

function PropertyOwnership.setPermissions(record: any, userId: number, mode: any, allowed: any, rules: any): (boolean, string?)
	if record.owner == nil or record.owner.userId ~= userId then
		return false, "only the owner can change permissions"
	end
	if type(mode) ~= "string" or not rules.permissionModes[mode] then
		return false, "unknown permission mode"
	end
	local list = {}
	local count = 0
	if type(allowed) == "table" then
		for _, visitorId in ipairs(allowed) do
			if Check.isPositiveInteger(visitorId) then
				count += 1
				list[tostring(visitorId)] = true
			end
		end
	end
	if count > rules.maxAllowedVisitors then
		return false, "too many people on the list"
	end
	record.permissions = { mode = mode, allowed = list }
	record.version += 1
	return true, nil
end

-- Unowned properties can be viewed by anyone (for example, prospective buyers).
function PropertyOwnership.canEnter(record: any, visitorUserId: number, isFriend: boolean): boolean
	if record.owner == nil or record.owner.userId == visitorUserId then
		return true
	end
	local permissions = record.permissions
	if permissions.mode == "Public" or (permissions.mode == "Friends" and isFriend) then
		return true
	end
	return permissions.allowed[tostring(visitorUserId)] == true
end

return PropertyOwnership
