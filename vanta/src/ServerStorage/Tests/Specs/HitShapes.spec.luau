--!strict
local HitShapes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Domain.HitShapes)

return function(t)
	t.test("lines hit targets along them, within range and radius", function()
		local origin, east = Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)
		t.truthy((HitShapes.line(origin, east, Vector3.new(20, 0, 1), 40, 2)))
		t.falsy((HitShapes.line(origin, east, Vector3.new(20, 0, 3), 40, 2)), "too far to the side")
		t.falsy((HitShapes.line(origin, east, Vector3.new(-5, 0, 0), 40, 2)), "behind")
		t.falsy((HitShapes.line(origin, east, Vector3.new(45, 0, 0), 40, 2)), "out of range")
		local _, along = HitShapes.line(origin, east, Vector3.new(12, 0, 0), 40, 2)
		t.equal(along, 12)
	end)

	t.test("areas and arcs", function()
		t.truthy(HitShapes.area(Vector3.new(10, 0, 10), Vector3.new(14, 5, 10), 5), "height ignored")
		t.falsy(HitShapes.area(Vector3.new(10, 0, 10), Vector3.new(16, 0, 10), 5))
		t.truthy(HitShapes.arc(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 0, -5), 8, 90))
		t.falsy(HitShapes.arc(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 0, 5), 8, 90), "behind")
		t.truthy(HitShapes.arc(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 0, 5), 8, 360), "all around")
	end)

	t.test("aimed points stay within reach", function()
		local clamped = HitShapes.clampTarget(Vector3.new(0, 2, 0), Vector3.new(100, 50, 0), 30)
		t.equal(clamped, Vector3.new(30, 2, 0))
		t.equal(HitShapes.clampTarget(Vector3.zero, Vector3.new(5, 0, 5), 30), Vector3.new(5, 0, 5))
	end)

	t.test("defences reduce damage, frontal ones only from the front, never beyond the cap", function()
		local defenses = { { reduction = 0.6, frontal = true, untilTime = 10 }, { reduction = 0.4, untilTime = 10 } }
		t.equal(HitShapes.reduction(defenses, 5, true, 0.75), 0.75, "capped")
		t.equal(HitShapes.reduction(defenses, 5, false, 0.75), 0.4, "shield faces away")
		t.equal(HitShapes.reduction(defenses, 11, true, 0.75), 0, "expired")
	end)
end
