--!nonstrict
-- Greatsword set (a two-handed sword: Swordmaster, Grand Swordmaster and Dragonblood Knight may wield one). It uses the same
-- combo, heavy, sweep, parry and riposte as the sword, with the same timings (the Animator picks the Greatsword version of a
-- sword clip when the character holds a greatsword), but two-handed: heavier, broader body movement, and the left hand
-- placed on the hilt in every key by the build step (Builder.solveTwoHand).
local function fresh(module)
	local copy = module:Clone()
	copy.Parent = module.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	assert(ok, result)
	return result
end
local ClipKit = fresh(script.Parent.ClipKit)
local Sword = fresh(script.Parent.SwordClips)
local with = ClipKit.with

local READY = {
	Waist = { 0, 16, 0 }, Neck = { 0, -14, 0 },
	RightShoulder = { 42, 0, -8 }, RightElbow = { 60, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 40, 0, -30 }, LeftElbow = { 80, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CALM = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 10, 0, 10 }, RightElbow = { 22, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 4, 0, -7 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local kit = ClipKit.new("Greatsword", READY, CALM, { twoHand = true })
local Clips = {}

local function deepCopyKeys(keys)
	local out = {}
	for index, key in ipairs(keys) do
		local j = {}
		for joint, value in pairs(key.j) do j[joint] = ClipKit.copy(value) end
		out[index] = { t = key.t, j = j, ease = key.ease, dir = key.dir, marker = key.marker }
	end
	return out
end

-- The sword's clip, made heavier: broader body turns and deeper dips, and the guard swapped for the two-handed ready pose.
local function heavy(name, source, turn, dip)
	local keys = deepCopyKeys(source.keys)
	for _, key in ipairs(keys) do
		for joint, value in pairs(key.j) do
			if joint == "Waist" then value[2] *= turn
			elseif joint == "Root" then
				value[2] *= turn
				if value[5] ~= nil and value[5] < 0 then value[5] *= dip end
				if value[6] ~= nil and value[6] < 0 then value[6] *= dip end
			end
		end
	end
	return { name = name, priority = ClipKit.Action, keys = keys, twoHand = true }
end
for _, entry in ipairs({
	{ "GreatswordCombo1", "SwordCombo1", 1.2, 1.3 }, { "GreatswordCombo2", "SwordCombo2", 1.2, 1.3 }, { "GreatswordCombo3", "SwordCombo3", 1.2, 1.4 },
	{ "GreatswordHeavy", "SwordHeavy", 1.2, 1.3 }, { "GreatswordSweep", "SwordSweep", 1.0, 1.1 }, { "GreatswordParry", "SwordParry", 1.0, 1.0 }, { "GreatswordRiposte", "SwordRiposte", 1.1, 1.2 },
}) do
	Clips[entry[1]] = heavy(entry[1], Sword[entry[2]], entry[3], entry[4])
end

kit.equipUnequip(Clips, {
	{ t = 0.2, j = { RightShoulder = { 140, 0, 30 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 120, 0, -20 }, LeftElbow = { 90, 0, 0 }, Waist = { 8, -10, 0 }, Neck = { 8, 0, 0 } } },
	{ t = 0.4, j = { RightShoulder = { 160, 0, 10 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 150, 0, -16 }, LeftElbow = { 60, 0, 0 }, Waist = { 14, 0, 0 }, Neck = { 12, 0, 0 } } },
	{ t = 0.6, j = { RightShoulder = { 46, 0, -6 }, RightElbow = { 56, 0, 0 }, LeftShoulder = { 40, 0, -30 }, LeftElbow = { 80, 0, 0 }, Waist = { -14, 16, 0 } }, ease = "Cubic", dir = "In" },
})
Clips.GreatswordIdle = kit.breathe(CALM, "GreatswordIdle", 3.4, false)
Clips.GreatswordCombatIdle = kit.breathe(READY, "GreatswordCombatIdle", 2.6, true)
kit.addVariants(Clips)

Clips.order = kit.order({ "GreatswordCombo1", "GreatswordCombo2", "GreatswordCombo3", "GreatswordHeavy", "GreatswordSweep", "GreatswordParry", "GreatswordRiposte" })

return Clips
