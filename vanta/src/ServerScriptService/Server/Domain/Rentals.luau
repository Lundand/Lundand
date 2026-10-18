--!strict
-- Inn rooms (L-29). The inn is shared; each rented room is a private instance. Renting charges gold and
-- creates or extends the rental in one step under an operation ID, so a repeated request does nothing.
-- Only the renter and people they invite may enter. Prices and limits are placeholders (O-11).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)
local Transaction = require(script.Parent.Transaction)

local Rentals = {}

function Rentals.activeRental(account: any, now: number): (string?, any)
	for innId, rental in pairs(account.rentals) do
		if rental.expiresAt > now then
			return innId, rental
		end
	end
	return nil, nil
end

function Rentals.rent(profileData: any, characterId: string, innId: any, days: any, operationId: any, inns: any, rules: any, deps: any): (boolean, any)
	if type(innId) ~= "string" or inns[innId] == nil then
		return false, "unknown inn"
	end
	if not Check.isPositiveInteger(days) or days > rules.maxDays then
		return false, "invalid number of days"
	end
	if not Check.isToken(operationId, 80) then
		return false, "invalid operation id"
	end
	if Transaction.wasApplied(profileData, operationId) then
		return true, { alreadyApplied = true }
	end
	local account = profileData.account
	local now = deps.now()
	local activeInn, active = Rentals.activeRental(account, now)
	if activeInn ~= nil and activeInn ~= innId then
		return false, "you already rent a room at another inn"
	end
	local start = now
	if active ~= nil then
		start = active.expiresAt
	end
	local expiresAt = start + days * rules.dayLengthSeconds
	if expiresAt - now > rules.maxDays * rules.dayLengthSeconds then
		return false, "rentals can't run longer than the maximum"
	end
	local price = days * rules.pricePerDay
	local ok, result = Transaction.apply(profileData, characterId, {
		id = operationId,
		reason = "InnRental",
		changes = { { type = "AdjustCurrency", currency = "Gold", amount = -price } },
	}, deps)
	if not ok then
		return false, result
	end
	if active ~= nil then
		active.expiresAt = expiresAt
	else
		account.rentals[innId] = { expiresAt = expiresAt, invited = {} }
	end
	return true, { alreadyApplied = false, expiresAt = expiresAt, price = price }
end

function Rentals.invite(account: any, innId: string, visitorUserId: any, now: number, rules: any): (boolean, string?)
	local rental = account.rentals[innId]
	if rental == nil or rental.expiresAt <= now then
		return false, "no active rental here"
	end
	if not Check.isPositiveInteger(visitorUserId) then
		return false, "invalid player"
	end
	local key = tostring(visitorUserId)
	local count = 0
	for _ in pairs(rental.invited) do
		count += 1
	end
	if not rental.invited[key] and count >= rules.maxInvited then
		return false, "too many guests"
	end
	rental.invited[key] = true
	return true, nil
end

function Rentals.revoke(account: any, innId: string, visitorUserId: number): boolean
	local rental = account.rentals[innId]
	if rental == nil or not rental.invited[tostring(visitorUserId)] then
		return false
	end
	rental.invited[tostring(visitorUserId)] = nil
	return true
end

function Rentals.canEnter(ownerAccount: any, ownerUserId: number, innId: string, visitorUserId: number, now: number): boolean
	local rental = ownerAccount.rentals[innId]
	if rental == nil or rental.expiresAt <= now then
		return false
	end
	return visitorUserId == ownerUserId or rental.invited[tostring(visitorUserId)] == true
end

function Rentals.pruneExpired(account: any, now: number): number
	local removed = 0
	for innId, rental in pairs(account.rentals) do
		if rental.expiresAt <= now then
			account.rentals[innId] = nil
			removed += 1
		end
	end
	return removed
end

return Rentals
