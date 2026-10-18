--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AppearanceRules = require(Shared.Domain.AppearanceRules)
local Content = require(Shared.Content)

local config = Content.appearance

return function(t)
	t.test("only listed choices are accepted", function()
		local ok, appearance = AppearanceRules.validate({ skinTone = "Olive", hairStyle = "Braided", hairColor = "Auburn", face = "Gentle" }, config)
		t.truthy(ok)
		t.equal(appearance.skinTone, "Olive")
		t.falsy(AppearanceRules.validate({ skinTone = "Green", hairStyle = "Short", hairColor = "Black", face = "Calm" }, config))
		t.falsy(AppearanceRules.validate({ skinTone = "Fair" }, config), "every field is needed")
		t.falsy(AppearanceRules.validate("Fair", config))
		local _, cleaned = AppearanceRules.validate({ skinTone = "Fair", hairStyle = "Short", hairColor = "Black", face = "Calm", speed = 99 }, config)
		t.equal(cleaned.speed, nil, "nothing else gets through")
	end)

	t.test("the body is dressed from the choice, with defaults for anything missing", function()
		local look = AppearanceRules.describe({ skinTone = "Deep", hairColor = "White" }, config)
		t.deepEqual(look.skin, { 95, 60, 40 })
		t.deepEqual(look.hairColor, { 235, 235, 230 })
		t.equal(look.hairAssetId, 0, "no hair asset chosen yet")
		local fallback = AppearanceRules.describe(nil, config)
		t.deepEqual(fallback.skin, config.skinTones[1].color)
	end)
end
