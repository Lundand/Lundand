--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local SharedRecords = require(Server.Data.SharedRecords)
local ShopRules = require(Server.Domain.ShopRules)
local Content = require(Shared.Content)

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in pairs(value) do
		result[key] = deepCopy(inner)
	end
	return result
end

-- A stand-in for a DataStore: copies on every read and write, and can fail the next few calls.
local function fakeStore(): any
	local store: any = { data = {}, failures = 0 }
	function store:UpdateAsync(key: string, transform: (any) -> any): any
		if self.failures > 0 then
			self.failures -= 1
			error("request throttled")
		end
		local updated = transform(deepCopy(self.data[key]))
		if updated == nil then
			return nil
		end
		self.data[key] = deepCopy(updated)
		return deepCopy(updated)
	end
	function store:GetAsync(key: string): any
		if self.failures > 0 then
			self.failures -= 1
			error("request throttled")
		end
		return deepCopy(self.data[key])
	end
	return store
end

local function server(store: any, clock: any, waits: {number}?): any
	return SharedRecords.new(store, {
		ttl = 30,
		now = function()
			return clock.t
		end,
		wait = function(seconds: number)
			if waits ~= nil then
				table.insert(waits, seconds)
			end
		end,
	})
end

return function(t)
	t.test("changes run inside the store and return the rules' answer", function()
		local store, clock = fakeStore(), { t = 0 }
		local records = server(store, clock)
		local ok, answer = records:update("counter", function(current: any)
			local record = current or { value = 0 }
			record.value += 1
			return record, record.value
		end)
		t.truthy(ok)
		t.equal(answer, 1)
		t.equal(store.data.counter.value, 1)
		local cancelled, reason = records:update("counter", function(current: any)
			return nil, "nothing to do"
		end)
		t.truthy(cancelled)
		t.equal(reason, "nothing to do")
		t.equal(store.data.counter.value, 1, "a cancelled change writes nothing")
	end)

	t.test("failed calls are retried with a growing delay, then reported", function()
		local store, clock, waits = fakeStore(), { t = 0 }, {}
		local records = server(store, clock, waits)
		store.failures = 2
		t.truthy(records:update("k", function()
			return { v = 1 }, true
		end))
		t.deepEqual(waits, { 0.5, 1 })
		store.failures = 10
		local ok, err = records:update("k", function()
			return { v = 2 }, true
		end)
		t.falsy(ok)
		t.truthy(string.find(tostring(err), "throttled", 1, true))
		t.equal(store.data.k.v, 1)
	end)

	t.test("reads are cached briefly and refreshed after another server's change", function()
		local store, clock = fakeStore(), { t = 0 }
		local serverA, serverB = server(store, clock), server(store, clock)
		serverA:update("guild", function()
			return { level = 1 }, nil
		end)
		local _, first = serverB:read("guild")
		t.equal(first.level, 1)
		serverA:update("guild", function(current: any)
			current.level = 2
			return current, nil
		end)
		local _, stale = serverB:read("guild")
		t.equal(stale.level, 1, "cached")
		serverB:invalidate("guild")
		local _, fresh = serverB:read("guild")
		t.equal(fresh.level, 2, "after the announcement")
		clock.t = 31
		serverA:update("guild", function(current: any)
			current.level = 3
			return current, nil
		end)
		local _, expired = serverB:read("guild")
		t.equal(expired.level, 3, "after the cache expires")
	end)

	t.test("a shop operation through shared records applies once, even if its first answer is lost", function()
		local store, clock = fakeStore(), { t = 0 }
		local records = server(store, clock)
		local rules = Content.economy.playerShops
		records:update("shop:s1", function()
			return ShopRules.newShop("s1", 1, "Owner"), nil
		end)
		local op = { id = "order-1", kind = "Order", by = 1, itemId = "CopperOre", quantity = 10, price = 2, escrow = 20 }
		local function deliver(): any
			local _, answer = records:update("shop:s1", function(shop: any)
				local result = ShopRules.apply(shop, op, rules)
				return shop, result
			end)
			return answer
		end
		local first = deliver()
		local again = deliver()
		t.truthy(first.accepted)
		t.deepEqual(again, first, "same answer on the retry")
		local count = 0
		for _ in pairs(store.data["shop:s1"].orders) do
			count += 1
		end
		t.equal(count, 1, "the order exists once")
	end)

	t.test("the in-memory stand-in used in Studio behaves like a store", function()
		local MemoryRecordStore = require(Server.Data.MemoryRecordStore)
		local clock = { t = 0 }
		local records = server(MemoryRecordStore.new(), clock)
		local _, first = records:update("shop:s1", function(current: any)
			local shop = current or { sales = 0 }
			shop.sales += 1
			return shop, shop.sales
		end)
		local _, second = records:update("shop:s1", function(current: any)
			current.sales += 1
			return current, current.sales
		end)
		t.equal(first, 1)
		t.equal(second, 2)
		local _, stored = records:read("shop:s1", 0)
		t.equal(stored.sales, 2)
		stored.sales = 99
		local _, again = records:read("shop:s1", 0)
		t.equal(again.sales, 2, "reads are copies")
	end)
end
