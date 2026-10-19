--!strict
-- Applies item and currency changes all-or-nothing under an operation ID (T-05). Changes are applied
-- to copies that are swapped in only when every change succeeded, so a failure leaves nothing behind.
-- An operation ID that was already applied is a no-op, which makes retries and double clicks safe.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Table = require(Shared.Util.Table)
local Check = require(Shared.Util.Check)
local Inventory = require(Shared.Domain.Inventory)

local Transaction = {}

Transaction.MAX_RECENT_OPERATIONS = 256
Transaction.MAX_AUDIT_ENTRIES = 50
Transaction.MAX_CHANGES = 64

function Transaction.wasApplied(profileData: any, operationId: string): boolean
	return profileData.recentOperations[operationId] ~= nil
end

-- Remembers an applied operation (bounded, oldest dropped first) and writes a short audit entry.
function Transaction.record(profileData: any, operationId: string, reason: any, characterId: string, now: number)
	local recent = profileData.recentOperations
	recent[operationId] = now
	local count = 0
	for _ in pairs(recent) do
		count += 1
	end
	local excess = count - Transaction.MAX_RECENT_OPERATIONS
	if excess > 0 then
		local entries = {}
		for id, time in pairs(recent) do
			if id ~= operationId then
				table.insert(entries, { id = id, time = time })
			end
		end
		table.sort(entries, function(a, b)
			if a.time == b.time then
				return a.id < b.id
			end
			return a.time < b.time
		end)
		for index = 1, excess do
			recent[entries[index].id] = nil
		end
	end
	local audit = profileData.audit
	table.insert(audit, { op = operationId, reason = tostring(reason), character = characterId, at = now })
	while #audit > Transaction.MAX_AUDIT_ENTRIES do
		table.remove(audit, 1)
	end
end

local function adjustCurrency(currencies: any, change: any, deps: any): (boolean, string?)
	local definition = deps.currencies[change.currency]
	if type(change.currency) ~= "string" or definition == nil then
		return false, "unknown currency"
	end
	if not Check.isInteger(change.amount) or change.amount == 0 then
		return false, "currency amount must be a non-zero whole number"
	end
	local balance = (currencies[change.currency] or 0) + change.amount
	if balance < 0 then
		return false, "not enough " .. change.currency
	end
	if balance > definition.max then
		return false, "currency limit reached"
	end
	currencies[change.currency] = balance
	return true, nil
end

-- Applies changes to the given working copies (no copying, no recording). Used by apply and Trade.
-- Change types:
--   GrantStack { itemId, amount, crafted? }    ConsumeItem { itemId, amount }
--   ConsumeStack { stackKey, amount }           GrantUnique { itemId, origin = { kind, source? }, crafted?, data? }
--   RemoveUnique { uid, itemId? }               AdjustCurrency { currency, amount }
--   InsertUnique { unique } (an existing item returning with its ID and records)
function Transaction.applyChanges(inventory: any, currencies: any, changes: any, operationId: string, deps: any): (boolean, any)
	if type(changes) ~= "table" or #changes == 0 or #changes > Transaction.MAX_CHANGES then
		return false, "invalid change list"
	end
	local created = {}
	for index, change in ipairs(changes) do
		local ok, err = false, "change must be a table"
		if type(change) == "table" then
			local kind = change.type
			if kind == "GrantStack" then
				ok, err = Inventory.addStack(inventory, deps.items, change.itemId, change.amount, change.crafted)
			elseif kind == "ConsumeItem" then
				ok, err = Inventory.removeItem(inventory, change.itemId, change.amount)
			elseif kind == "ConsumeStack" then
				ok, err = Inventory.removeStack(inventory, change.stackKey, change.amount)
			elseif kind == "GrantUnique" then
				local def = deps.items[change.itemId]
				if def == nil or type(change.origin) ~= "table" then
					ok, err = false, "unique items need a known item and an origin"
				else
					local unique = {
						uid = deps.newUid(),
						itemId = change.itemId,
						createdBy = operationId,
						origin = { kind = change.origin.kind, source = change.origin.source, at = deps.now() },
						crafted = Table.deepCopy(change.crafted),
						data = Table.deepCopy(change.data),
					}
					if def.binding == "OnPickup" then
						unique.boundTo = deps.ownerUserId
					end
					ok, err = Inventory.addUnique(inventory, deps.items, unique)
					if ok then
						table.insert(created, unique.uid)
					end
				end
			elseif kind == "InsertUnique" then
				-- An existing item coming back from a shop, with its original ID and permanent records (L-32).
				ok, err = Inventory.addUnique(inventory, deps.items, change.unique)
			elseif kind == "RemoveUnique" then
				local item = type(change.uid) == "string" and inventory.uniques[change.uid]
				if not item then
					ok, err = false, "item not found"
				elseif change.itemId ~= nil and item.itemId ~= change.itemId then
					ok, err = false, "item type mismatch"
				else
					inventory.uniques[change.uid] = nil
					ok, err = true, nil
				end
			elseif kind == "AdjustCurrency" then
				ok, err = adjustCurrency(currencies, change, deps)
			else
				ok, err = false, "unknown change type"
			end
		end
		if not ok then
			return false, string.format("change %d: %s", index, tostring(err))
		end
	end
	return true, created
end

-- deps: { items, currencies, newUid: () -> string, now: () -> number, ownerUserId: number? }
function Transaction.apply(profileData: any, characterId: string, operation: any, deps: any): (boolean, any)
	if type(operation) ~= "table" or not Check.isToken(operation.id, 100) then
		return false, "invalid operation id"
	end
	if Transaction.wasApplied(profileData, operation.id) then
		return true, { alreadyApplied = true, created = {} }
	end
	local character = profileData.characters[characterId]
	if character == nil then
		return false, "unknown character"
	end
	local inventory = Table.deepCopy(character.inventory)
	local currencies = Table.deepCopy(character.currencies)
	local ok, result = Transaction.applyChanges(inventory, currencies, operation.changes, operation.id, deps)
	if not ok then
		return false, result
	end
	character.inventory = inventory
	character.currencies = currencies
	Transaction.record(profileData, operation.id, operation.reason, characterId, deps.now())
	return true, { alreadyApplied = false, created = result }
end

return Transaction
