--!nonstrict
-- Mace and shield set (Heavy Knight, Paladin): a slow, heavy style. The mace is in the right hand (grip -135, so its head points up and
-- forward in guard and down in a smash), the shield strapped to the left forearm, face out. Same joint conventions as SwordClips.
-- Clips with `hit` are scaled by the Animator so their strike lands on the ability's windup.
local Sword = (function()
	local copy = script.Parent.SwordClips:Clone()
	copy.Parent = script.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	assert(ok, result)
	return result
end)()
local Clips = {}
local Action = Enum.AnimationPriority.Action
local Movement = Enum.AnimationPriority.Movement

local ALL = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
local UPPER = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

-- Guard: shield up in front of the chest, mace cocked beside the shoulder.
local READY = {
	Waist = { 0, 16, 0 }, Neck = { 0, -14, 0 },
	RightShoulder = { 40, 0, 28 }, RightElbow = { 80, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 55, 0, -18 }, LeftElbow = { 100, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
-- Calm: the mace carried low at the side, the shield hanging.
local CALM = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 8, 0, 9 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 14, 0, -10 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 0, 0, 0 },
}

local function copy(v)
	return { v[1], v[2], v[3], v[4], v[5], v[6] }
end
local function K(t, over, o)
	o = o or {}
	local base = o.base or READY
	local j = {}
	for _, n in ipairs(o.upper and UPPER or ALL) do
		j[n] = copy(base[n] or { 0, 0, 0 })
	end
	for n, v in pairs(over or {}) do
		j[n] = v
	end
	return { t = t, j = j, ease = o.ease, dir = o.dir, marker = o.marker }
end
local IN = { ease = "Cubic", dir = "In", marker = "Hit" }
local OUT = { ease = "Cubic", dir = "Out" }
local SOFT = { ease = "Cubic", dir = "InOut" }
local LIN = { ease = "Linear", dir = "Out" }
local function with(base, extra)
	local out = {}
	for n, v in pairs(base) do out[n] = v end
	for n, v in pairs(extra or {}) do out[n] = v end
	return out
end

-- Basic attacks (0.8 long, strike at 0.22; the Animator alternates them). A: overhead smash. B: wide side swing.
local SMASH_WIND = { Root = { 6, -8, 0, 0, 0.06, 0.12 }, Waist = { 10, -12, 0 }, Neck = { 6, 12, 0 }, RightShoulder = { 150, 0, 14 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 }, LeftShoulder = { 70, 0, -30 }, LeftElbow = { 90, 0, 0 }, RightHip = { -8, 0, 0 }, RightKnee = { -14, 0, 0 }, LeftHip = { 6, 0, 0 }, LeftKnee = { -10, 0, 0 } }
local SMASH_HIT = { Root = { 6, 10, 0, 0, -0.65, -0.55 }, Waist = { -30, 14, 0 }, Neck = { 14, -14, 0 }, RightShoulder = { 30, 0, 5 }, RightElbow = { 5, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 60, 0, -34 }, LeftElbow = { 80, 0, 0 }, RightHip = { 52, 0, 4 }, RightKnee = { -68, 0, 0 }, LeftHip = { -28, 0, 0 }, LeftKnee = { -14, 0, 0 } }
Clips.MaceSmash = { name = "MaceSmash", priority = Action, hit = 0.22, alternates = { "MaceSmash", "MaceSwing" }, keys = {
	K(0, {}),
	K(0.12, SMASH_WIND, { ease = "Cubic", dir = "InOut" }),
	K(0.2, with(SMASH_WIND, { RightShoulder = { 162, 0, 14 }, Root = { 8, -8, 0, 0, 0.1, 0.15 } }), OUT),
	K(0.22, SMASH_HIT, IN),
	K(0.38, SMASH_HIT, LIN),
	K(0.58, with(SMASH_HIT, { Root = { 3, 8, 0, 0, -0.3, -0.25 }, Waist = { -12, 16, 0 }, RightShoulder = { 55, 0, 14 }, RightElbow = { 40, 0, 0 }, RightHip = { 26, 0, 0 }, RightKnee = { -34, 0, 0 } }), SOFT),
	K(0.8, {}, SOFT),
} }
local SWING_WIND = { Root = { 2, -34, 0, 0, -0.2, 0.1 }, Waist = { 0, -50, 0 }, Neck = { 0, 44, 0 }, RightShoulder = { 60, 0, 85 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 }, LeftShoulder = { 60, 0, -34 }, LeftElbow = { 90, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 }, RightHip = { 6, 0, 0 }, LeftHip = { 6, 0, 0 } }
local SWING_HIT = { Root = { 4, 32, 0, 0, -0.35, -0.3 }, Waist = { -10, 54, 0 }, Neck = { 0, -46, 0 }, RightShoulder = { 78, 0, -40 }, RightElbow = { 15, 0, 0 }, RightWrist = { -25, 0, 0 }, LeftShoulder = { 70, 0, -36 }, LeftElbow = { 80, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -16, 0, 0 } }
Clips.MaceSwing = { name = "MaceSwing", priority = Action, hit = 0.22, keys = {
	K(0, {}), K(0.14, SWING_WIND, SOFT), K(0.22, SWING_HIT, IN), K(0.36, with(SWING_HIT, { Waist = { -10, 62, 0 }, RightShoulder = { 78, 0, -62 } }), OUT), K(0.58, with(SWING_HIT, { Root = { 2, 14, 0, 0, -0.15, -0.1 }, Waist = { -4, 30, 0 }, RightShoulder = { 60, 0, 6 }, RightElbow = { 50, 0, 0 } }), SOFT), K(0.8, {}, SOFT),
} }

-- Provoking Strike (windup 0.2): a shield bash straight ahead with the head thrown back, then a mace blow, as a challenge.
local BASH_HIT = { Root = { 6, -6, 0, 0, -0.4, -0.6 }, Waist = { -20, -14, 0 }, Neck = { 10, 10, 0 }, RightShoulder = { 60, 0, 40 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 88, 0, -8 }, LeftElbow = { 20, 0, 0 }, RightHip = { 50, 0, 3 }, RightKnee = { -56, 0, 0 }, LeftHip = { -32, 0, 0 }, LeftKnee = { -16, 0, 0 } }
Clips.MaceBash = { name = "MaceBash", priority = Action, hit = 0.20, keys = {
	K(0, {}),
	K(0.12, { Root = { 6, 10, 0, 0, -0.25, 0.2 }, Waist = { 8, 20, 0 }, Neck = { 12, -16, 0 }, RightShoulder = { 120, 0, 28 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 40, 0, -20 }, LeftElbow = { 130, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -30, 0, 0 } }, SOFT),
	K(0.2, BASH_HIT, IN),
	K(0.4, BASH_HIT, LIN),
	K(0.62, with(BASH_HIT, { Root = { 2, 0, 0, 0, -0.2, -0.2 }, Waist = { -8, 8, 0 }, LeftShoulder = { 70, 0, -14 }, LeftElbow = { 70, 0, 0 }, RightHip = { 20, 0, 0 }, RightKnee = { -24, 0, 0 } }), SOFT),
	K(0.8, {}, SOFT),
} }

-- Judgment Strike (windup 0.25): a leaping overhead blow that comes down hard.
local JUDGMENT_WIND = with(SMASH_WIND, { Root = { 8, -8, 0, 0, 0.6, 0.1 }, RightShoulder = { 168, 0, 20 }, LeftShoulder = { 120, 0, -30 }, LeftElbow = { 60, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { 14, 0, 0 } })
Clips.MaceJudgment = { name = "MaceJudgment", priority = Action, hit = 0.25, keys = {
	K(0, {}),
	K(0.1, with(SMASH_WIND, { Root = { 8, -8, 0, 0, -0.5, 0.1 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -44, 0, 0 } }), SOFT),
	K(0.2, JUDGMENT_WIND, OUT),
	K(0.25, with(SMASH_HIT, { Root = { 8, 10, 0, 0, -0.95, -0.7 } }), IN),
	K(0.45, with(SMASH_HIT, { Root = { 8, 10, 0, 0, -0.95, -0.7 } }), LIN),
	K(0.66, with(SMASH_HIT, { Root = { 3, 8, 0, 0, -0.3, -0.2 }, Waist = { -12, 16, 0 }, RightShoulder = { 55, 0, 14 }, RightElbow = { 40, 0, 0 } }), SOFT),
	K(0.85, {}, SOFT),
} }

-- Shield Wall, Guardian's Intercession (windup 0): crouch behind the shield, thrust forward, mace pulled back.
local BRACE = { Root = { 6, -4, 0, 0, -0.5, -0.15 }, Waist = { -10, 8, 0 }, Neck = { 6, -8, 0 }, RightShoulder = { 20, 0, 36 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 82, 0, -6 }, LeftElbow = { 40, 0, 0 }, RightHip = { 18, 0, 8 }, LeftHip = { 18, 0, -8 }, RightKnee = { -58, 0, 0 }, LeftKnee = { -58, 0, 0 } }
Clips.MaceBrace = { name = "MaceBrace", priority = Action, hit = 0.05, keys = {
	K(0, {}), K(0.07, BRACE, OUT), K(0.3, BRACE, LIN), K(0.5, {}, SOFT),
} }

-- Bulwark Advance (windup 0): a stride with the shield thrust ahead and the body leaning in, mace trailing.
local CHARGE = { Root = { -8, 0, 0, 0, -0.2, -0.3 }, Waist = { -24, 8, 0 }, Neck = { 12, -6, 0 }, RightShoulder = { -20, 0, 24 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 82, 0, -4 }, LeftElbow = { 50, 0, 0 }, RightHip = { 44, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { -34, 0, 0 }, LeftKnee = { -20, 0, 0 } }
Clips.MaceCharge = { name = "MaceCharge", priority = Action, hit = 0.05, keys = {
	K(0, {}), K(0.07, CHARGE, OUT), K(0.3, with(CHARGE, { RightHip = { -30, 0, 0 }, LeftHip = { 40, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -50, 0, 0 } }), SOFT), K(0.5, {}, SOFT),
} }

-- Fortress of the Last Stand, Heaven's Last Bastion (windup 0.4): both arms raised, then a stomp that plants shield and mace.
local FORT_HIT = { Root = { 4, 0, 0, 0, -1.0, -0.2 }, Waist = { -24, 6, 0 }, Neck = { 12, -8, 0 }, RightShoulder = { 36, 0, 12 }, RightElbow = { 0, 0, 0 }, RightWrist = { -24, 0, 0 }, LeftShoulder = { 84, 0, -10 }, LeftElbow = { 36, 0, 0 }, RightHip = { 20, 0, 22 }, LeftHip = { 20, 0, -22 }, RightKnee = { -76, 0, 0 }, LeftKnee = { -76, 0, 0 } }
Clips.MaceFortress = { name = "MaceFortress", priority = Action, hit = 0.40, keys = {
	K(0, {}),
	K(0.2, { Root = { 2, 0, 0, 0, 0.3, 0 }, Waist = { 8, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 150, 0, 30 }, RightElbow = { 30, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 120, 0, -26 }, LeftElbow = { 60, 0, 0 } }, OUT),
	K(0.33, { Root = { 2, 0, 0, 0, 0.45, 0 }, Waist = { 12, 0, 0 }, Neck = { 18, 0, 0 }, RightShoulder = { 158, 0, 30 }, RightElbow = { 26, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 126, 0, -26 }, LeftElbow = { 54, 0, 0 } }, OUT),
	K(0.4, FORT_HIT, IN),
	K(0.8, FORT_HIT, LIN),
	K(1.1, {}, SOFT),
} }

-- Radiant Guard, Wings of Aegis (windup 0.1): shield and mace raised together overhead as a ward.
local RADIANT = { Root = { 2, 0, 0, 0, 0.1, 0 }, Waist = { 8, 0, 0 }, Neck = { 16, 0, 0 }, RightShoulder = { 150, 0, 24 }, RightElbow = { 24, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 140, 0, -24 }, LeftElbow = { 50, 0, 0 } }
Clips.MaceRadiant = { name = "MaceRadiant", priority = Action, hit = 0.10, keys = {
	K(0, {}), K(0.1, RADIANT, { ease = "Cubic", dir = "Out", marker = "Hit" }), K(0.35, RADIANT, LIN), K(0.6, {}, SOFT),
} }

-- Consecration (windup 0.3): the mace driven into the ground in a kneeling lunge.
local GROUND = { Root = { 8, 6, 0, 0, -1.1, -0.5 }, Waist = { -42, 10, 0 }, Neck = { 22, -10, 0 }, RightShoulder = { 28, 0, 6 }, RightElbow = { 0, 0, 0 }, RightWrist = { -22, 0, 0 }, LeftShoulder = { 50, 0, -30 }, LeftElbow = { 60, 0, 0 }, RightHip = { 66, 0, 4 }, RightKnee = { -92, 0, 0 }, LeftHip = { -40, 0, 0 }, LeftKnee = { -70, 0, 0 } }
Clips.MaceConsecrate = { name = "MaceConsecrate", priority = Action, hit = 0.30, keys = {
	K(0, {}),
	K(0.2, with(SMASH_WIND, { RightShoulder = { 158, 0, 14 } }), SOFT),
	K(0.3, GROUND, IN),
	K(0.62, GROUND, LIN),
	K(0.9, {}, SOFT),
} }

-- Light of the Covenant (windup 0.6): a slow rise onto the toes with arms thrown wide, a held beat, then a crashing slam.
local ASCEND = { Root = { 2, 0, 0, 0, 0.5, 0 }, Waist = { 14, 0, 0 }, Neck = { 28, 0, 0 }, RightShoulder = { 168, 0, 44 }, RightElbow = { 14, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 160, 0, -44 }, LeftElbow = { 24, 0, 0 }, RightHip = { 0, 0, 6 }, LeftHip = { 0, 0, -6 } }
Clips.MaceAscend = { name = "MaceAscend", priority = Action, hit = 0.60, keys = {
	K(0, {}),
	K(0.18, { Root = { 6, 0, 0, 0, -0.55, 0.05 }, Waist = { 4, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 70, 0, 34 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 70, 0, -34 }, LeftElbow = { 60, 0, 0 }, RightHip = { 14, 0, 8 }, LeftHip = { 14, 0, -8 }, RightKnee = { -62, 0, 0 }, LeftKnee = { -62, 0, 0 } }, SOFT),
	K(0.4, ASCEND, OUT),
	K(0.53, with(ASCEND, { Root = { 2, 0, 0, 0, 0.6, 0 } }), LIN),
	K(0.6, with(GROUND, { Root = { 10, 0, 0, 0, -1.2, -0.5 } }), IN),
	K(1.0, with(GROUND, { Root = { 10, 0, 0, 0, -1.2, -0.5 } }), LIN),
	K(1.35, { Root = { 2, 0, 0, 0, -0.4, 0 }, Waist = { -14, 14, 0 } }, SOFT),
	K(1.6, {}, SOFT),
} }

-- Draw and sheathe.
Clips.MaceEquip = { name = "MaceEquip", priority = Action, keys = {
	K(0, {}, { base = CALM }),
	K(0.2, { RightShoulder = { 120, 0, 40 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 70, 0, 0 }, Waist = { 4, 12, 0 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.4, { RightShoulder = { 140, 0, 14 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 60, 0, -14 }, LeftElbow = { 100, 0, 0 }, Waist = { 8, 10, 0 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.58, { RightShoulder = { 35, 0, 10 }, RightElbow = { 10, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 60, 0, -16 }, LeftElbow = { 90, 0, 0 }, Waist = { -14, 10, 0 } }, { base = CALM, ease = "Cubic", dir = "In" }),
	K(0.85, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }
Clips.MaceUnequip = { name = "MaceUnequip", priority = Action, keys = {
	K(0, {}),
	K(0.2, { RightShoulder = { 50, 0, 16 }, RightElbow = { 50, 0, 0 }, Waist = { 0, 6, 0 } }, SOFT),
	K(0.5, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }

-- Stances (upper body only, Movement priority).
local function breathe(base, name, length)
	local mid = length / 2
	return { name = name, priority = Movement, loop = true, keys = {
		K(0, {}, { base = base, upper = true }),
		K(mid, { Waist = { base.Waist[1] + 2, base.Waist[2], 0 }, Neck = { base.Neck[1] - 1.5, base.Neck[2], 0 }, RightShoulder = { base.RightShoulder[1] + 2, base.RightShoulder[2], base.RightShoulder[3] + 1 }, LeftShoulder = { base.LeftShoulder[1] + 3, base.LeftShoulder[2], base.LeftShoulder[3] }, LeftElbow = { base.LeftElbow[1] + 4, 0, 0 } }, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
		K(length, {}, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
	} }
end
Clips.MaceIdle = breathe(CALM, "MaceIdle", 3.4)
Clips.MaceCombatIdle = breathe(READY, "MaceCombatIdle", 2.6)

-- Dodges and reactions: the sword set's clips, re-based onto the mace stance.
local function same(a, b)
	return a ~= nil and b ~= nil and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and (a[4] or 0) == (b[4] or 0) and (a[5] or 0) == (b[5] or 0) and (a[6] or 0) == (b[6] or 0)
end
local function rebase(source, newName)
	local out = { name = newName, priority = source.priority, loop = source.loop, keys = {} }
	for index, key in ipairs(source.keys) do
		local j = {}
		for joint, value in pairs(key.j) do
			if same(value, Sword.bases.GUARD[joint] or { 0, 0, 0 }) and READY[joint] ~= nil then
				j[joint] = copy(READY[joint])
			else
				j[joint] = copy(value)
			end
		end
		out.keys[index] = { t = key.t, j = j, ease = key.ease, dir = key.dir, marker = key.marker }
	end
	return out
end
for _, name in ipairs({ "Dodge", "DodgeForward", "DodgeLeft", "DodgeRight", "HitReactLight", "HitReactHeavy", "Stagger" }) do
	Clips["Mace" .. name] = rebase(Sword[name], "Mace" .. name)
end
-- The shield arm stays up in front through the mace attacks, so the shield doesn't swing back with the body (the bash, brace,
-- charge, fortress and radiant clips move it on purpose).
for _, name in ipairs({ "MaceSmash", "MaceSwing", "MaceJudgment", "MaceConsecrate" }) do
	for _, key in ipairs(Clips[name].keys) do
		key.j.LeftShoulder = copy(READY.LeftShoulder)
		key.j.LeftElbow = copy(READY.LeftElbow)
	end
end
-- Bash: coil the shield arm only slightly before it drives forward.
for _, key in ipairs(Clips.MaceBash.keys) do
	if key.t < 0.15 then
		key.j.LeftShoulder = { 56, 0, -14 }
		key.j.LeftElbow = { 112, 0, 0 }
	end
end

Clips.order = { "MaceSmash", "MaceSwing", "MaceBash", "MaceJudgment", "MaceBrace", "MaceCharge", "MaceFortress", "MaceRadiant", "MaceConsecrate", "MaceAscend", "MaceEquip", "MaceUnequip", "MaceIdle", "MaceCombatIdle", "MaceDodge", "MaceDodgeForward", "MaceDodgeLeft", "MaceDodgeRight", "MaceHitReactLight", "MaceHitReactHeavy", "MaceStagger" }

return Clips
