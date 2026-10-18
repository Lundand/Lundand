--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CrowdControl = require(Shared.Domain.CrowdControl)
local HitShapes = require(Shared.Domain.HitShapes)
local rules = { window = 15, falloff = 0.5, maxStacks = 3, maxSeconds = 4 }

return function(t)
	t.test("repeated control on one target lasts less each time, then not at all, until the window passes", function()
		local record = {}
		t.equal(CrowdControl.apply(record, 3, 0, rules), 3)
		t.equal(CrowdControl.apply(record, 3, 1, rules), 1.5)
		t.equal(CrowdControl.apply(record, 3, 2, rules), 0.75)
		t.equal(CrowdControl.apply(record, 3, 3, rules), 0, "immune after three")
		t.equal(CrowdControl.apply(record, 3, 20, rules), 3, "the window passed")
	end)

	t.test("no control lasts longer than the cap", function()
		t.equal(CrowdControl.apply({}, 10, 0, rules), 4)
	end)

	t.test("vulnerability (negative defence) raises damage taken, within a limit", function()
		t.equal(HitShapes.reduction({ { reduction = -0.25, untilTime = 10 } }, 5, true, 0.75), -0.25)
		t.equal(HitShapes.reduction({ { reduction = -2, untilTime = 10 } }, 5, true, 0.75), -0.5)
	end)
end
