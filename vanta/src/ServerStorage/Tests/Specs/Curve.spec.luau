--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Curve = require(Shared.Domain.Curve)

return function(t)
	local power = { kind = "Power", base = 100, exponent = 1.5, maxLevel = 10 }
	local steps = { kind = "Table", thresholds = { 0, 10, 30, 60 } }

	t.test("power curve starts at level 1 and the first step equals base", function()
		t.equal(Curve.levelForXp(power, 0), 1)
		t.equal(Curve.xpToReach(power, 2), 100)
		t.equal(Curve.levelForXp(power, 99), 1)
		t.equal(Curve.levelForXp(power, 100), 2)
	end)

	t.test("xpToReach and levelForXp agree at every level", function()
		for level = 1, power.maxLevel do
			local xp = Curve.xpToReach(power, level)
			t.equal(Curve.levelForXp(power, xp), level, "at level " .. level)
			if level > 1 then
				t.equal(Curve.levelForXp(power, xp - 1), level - 1, "just below level " .. level)
			end
		end
	end)

	t.test("levels stop at the max level", function()
		t.equal(Curve.levelForXp(power, 1000000000), 10)
		local level, into, needed = Curve.progress(power, 1000000000)
		t.equal(level, 10)
		t.truthy(into > 0)
		t.equal(needed, nil)
	end)

	t.test("progress reports XP into and needed for the current level", function()
		local level, into, needed = Curve.progress(steps, 15)
		t.equal(level, 2)
		t.equal(into, 5)
		t.equal(needed, 20)
	end)

	t.test("table curves use their thresholds", function()
		t.equal(Curve.levelForXp(steps, 9), 1)
		t.equal(Curve.levelForXp(steps, 10), 2)
		t.equal(Curve.levelForXp(steps, 60), 4)
		t.equal(Curve.maxLevel(steps), 4)
	end)

	t.test("validate rejects malformed curves", function()
		t.truthy(Curve.validate(power))
		t.truthy(Curve.validate(steps))
		t.falsy(Curve.validate({ kind = "Table", thresholds = { 5, 10 } }), "first threshold not 0")
		t.falsy(Curve.validate({ kind = "Table", thresholds = { 0, 10, 10 } }), "not increasing")
		t.falsy(Curve.validate({ kind = "Power", base = 0, exponent = 1, maxLevel = 5 }), "zero base")
		t.falsy(Curve.validate({ kind = "Power", base = 10, exponent = 1, maxLevel = 2.5 }), "fractional max")
		t.falsy(Curve.validate({ kind = "Mystery" }), "unknown kind")
	end)
end
