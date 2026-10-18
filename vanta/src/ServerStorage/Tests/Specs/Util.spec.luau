--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Table = require(Shared.Util.Table)
local Check = require(Shared.Util.Check)
local Signal = require(Shared.Util.Signal)

return function(t)
	t.test("deepCopy makes independent copies", function()
		local original = { a = { b = 1 }, list = { 1, 2, 3 } }
		local copy = Table.deepCopy(original)
		copy.a.b = 2
		table.insert(copy.list, 4)
		t.equal(original.a.b, 1)
		t.equal(#original.list, 3)
		t.truthy(Table.deepEqual(Table.deepCopy(original), original))
	end)

	t.test("replaceContents keeps the table reference", function()
		local target = { old = true }
		local reference = target
		Table.replaceContents(target, { fresh = 1 })
		t.equal(reference, target)
		t.equal(target.old, nil)
		t.equal(target.fresh, 1)
	end)

	t.test("number checks reject NaN, infinity and fractions", function()
		t.falsy(Check.isInteger(0 / 0), "NaN")
		t.falsy(Check.isInteger(math.huge), "infinity")
		t.falsy(Check.isInteger(1.5), "fraction")
		t.truthy(Check.isPositiveInteger(3))
		t.falsy(Check.isPositiveInteger(0))
		t.truthy(Check.isNonNegativeInteger(0))
		t.falsy(Check.isInteger("3"), "string")
	end)

	t.test("identifier and token checks", function()
		t.truthy(Check.isIdentifier("SwordArts"))
		t.falsy(Check.isIdentifier("9Lives"))
		t.falsy(Check.isIdentifier("has space"))
		t.falsy(Check.isIdentifier(string.rep("a", 65)))
		t.truthy(Check.isToken("legendary:123:abc-DEF.1"))
		t.falsy(Check.isToken("bad token"))
		t.falsy(Check.isToken(""))
	end)

	t.test("signal delivers to connected handlers only", function()
		local signal = Signal.new()
		local received = {}
		local connection = signal:Connect(function(value)
			table.insert(received, value)
		end)
		signal:Fire(1)
		connection.Disconnect()
		signal:Fire(2)
		t.deepEqual(received, { 1 })
	end)
end
