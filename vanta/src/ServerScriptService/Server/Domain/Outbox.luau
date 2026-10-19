--!strict
-- Outbox (L-47, L-48). Effects on shared records, such as a Rift event's total or a guild treasury, that
-- must happen exactly once. They are written into the player's own save in the same step as the purchase
-- or reward that causes them, then delivered by a background worker that retries until the shared record
-- confirms. Shared records remember recent delivery IDs, so a retry after a crash applies once.
local Outbox = {}

function Outbox.add(account: any, id: string, entry: any): boolean
	account.outbox = account.outbox or {}
	if account.outbox[id] ~= nil then
		return false
	end
	account.outbox[id] = entry
	return true
end

-- Waiting deliveries, oldest first.
function Outbox.pending(account: any): {any}
	local list = {}
	for id, entry in pairs(account.outbox or {}) do
		table.insert(list, { id = id, entry = entry })
	end
	table.sort(list, function(a, b)
		if (a.entry.at or 0) == (b.entry.at or 0) then
			return a.id < b.id
		end
		return (a.entry.at or 0) < (b.entry.at or 0)
	end)
	return list
end

function Outbox.complete(account: any, id: string)
	if account.outbox ~= nil then
		account.outbox[id] = nil
	end
end

-- Delivers waiting entries, oldest first. handlers[kind](id, entry) returns true plus any changes the player's
-- save should receive, or false to try again later. settle(id, entry, changes) applies those changes to the
-- save and returns whether that worked. An entry leaves the outbox only when both steps have worked.
function Outbox.deliver(account: any, handlers: any, settle: (string, any, {any}) -> boolean): number
	local delivered = 0
	for _, item in ipairs(Outbox.pending(account)) do
		local handler = handlers[item.entry.kind]
		if handler ~= nil then
			local ok, changes = handler(item.id, item.entry)
			if ok and (changes == nil or #changes == 0 or settle(item.id, item.entry, changes)) then
				Outbox.complete(account, item.id)
				delivered += 1
			end
		end
	end
	return delivered
end

return Outbox
