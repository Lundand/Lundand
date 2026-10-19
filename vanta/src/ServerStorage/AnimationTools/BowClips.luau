--!nonstrict
-- Bow set (Archer). The bow is in the LEFT hand, held upright with the string towards the archer; the right hand draws the
-- string. Keys carry `draw` (studs of string pull): the build step (Builder.solveDraw) places the right hand on the string for
-- each of them, so only the left arm, torso and legs are authored here. Cast-style clips carry `hit` (the release moment for
-- clips whose release is at the ability's windup). Same joint conventions as SwordClips.
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

-- Ready: the bow up in front (a little tilted), the right hand resting on the string. The right arm values here are only
-- starting guesses for the solver.
local READY = {
	Waist = { 0, -70, 0 }, Neck = { 0, 60, 0 },
	LeftShoulder = { 90, -20, -72 }, LeftElbow = { 6, 0, 0 }, LeftWrist = { 0, 0, 0 },
	RightShoulder = { 55, 0, -30 }, RightElbow = { 110, 0, 0 }, RightWrist = { 0, 0, 0 },
}
-- Calm: the bow carried upright at hip height in the left hand, the right arm at rest.
local CALM = {
	Waist = { 0, -10, 0 }, Neck = { 0, 8, 0 },
	LeftShoulder = { 20, 0, -12 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 0, 0, 0 },
	RightShoulder = { 6, 0, 10 }, RightElbow = { 24, 0, 0 }, RightWrist = { 0, 0, 0 },
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
	return { t = t, j = j, ease = o.ease, dir = o.dir, marker = o.marker, draw = o.draw }
end
local OUT = { ease = "Cubic", dir = "Out" }
local SOFT = { ease = "Cubic", dir = "InOut" }
local LIN = { ease = "Linear", dir = "Out" }
local function with(base, extra)
	local out = {}
	for n, v in pairs(base) do out[n] = v end
	for n, v in pairs(extra or {}) do out[n] = v end
	return out
end
local function opts(o, draw, marker)
	return { ease = o.ease, dir = o.dir, draw = draw, marker = marker }
end

-- A drawn pose: torso turned side-on, bow arm out, feet apart. `extra` overrides.
local function aim(extra)
	local pose = with({
		Root = { 0, -45, 0, 0, -0.12, 0 }, Waist = { 0, -35, 0 }, Neck = { 0, 70, 0 },
		LeftShoulder = { 90, -10, -90 }, LeftElbow = { 2, 0, 0 }, LeftWrist = { 0, 0, 0 },
		RightHip = { 0, 0, 14 }, LeftHip = { 0, 0, -14 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -10, 0, 0 },
	}, extra)
	-- the pelvis turns with the torso (side-on stance); keep an explicit yaw, and skip it while inverted in a flip
	local root = pose.Root
	local pitch = root[1] % 360
	if root[2] == 0 and (pitch < 60 or pitch > 300) then
		pose.Root = { root[1], -45, root[3], root[4], root[5], root[6] }
	end
	return pose
end

-- Basic shot (0.5 long, release at 0.12). A: standing shot. B: a crouching snap shot with the bow canted.
Clips.BowShot = { name = "BowShot", priority = Action, hit = 0.12, keys = {
	K(0, {}, { draw = 0 }),
	K(0.06, aim(), opts(OUT, 1.7)),
	K(0.12, aim({ LeftShoulder = { 90, -10, -95 }, Root = { 2, 0, 0, 0, -0.12, 0.08 } }), opts({ ease = "Cubic", dir = "In" }, 2.3, "Hit")),
	K(0.2, aim({ LeftShoulder = { 90, -10, -93 } }), opts(OUT, 1.0)),
	K(0.34, aim({ LeftShoulder = { 90, -10, -78 }, Waist = { 0, -42, 0 }, Neck = { 0, 36, 0 } }), opts(SOFT, 0.2)),
	K(0.5, {}, { ease = "Cubic", dir = "InOut", draw = 0 }),
} }
local CROUCH_AIM = { Root = { 8, 0, 0, 0, -0.7, 0 }, Waist = { 4, -35, 0 }, Neck = { 0, 70, 0 }, LeftShoulder = { 90, -10, -112 }, LeftElbow = { 2, 0, 0 }, RightHip = { 20, 0, 14 }, LeftHip = { 20, 0, -14 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -60, 0, 0 } }
Clips.BowShotB = { name = "BowShotB", priority = Action, hit = 0.12, keys = {
	K(0, {}, { draw = 0 }),
	K(0.06, aim(CROUCH_AIM), opts(OUT, 1.7)),
	K(0.12, aim(with(CROUCH_AIM, { Root = { 12, 0, 0, 0, -0.7, 0.1 }, LeftShoulder = { 90, -10, -118 } })), opts({ ease = "Cubic", dir = "In" }, 2.3, "Hit")),
	K(0.22, aim(with(CROUCH_AIM, { LeftShoulder = { 90, -10, -114 } })), opts(OUT, 1.0)),
	K(0.36, aim({ LeftShoulder = { 90, -10, -80 }, Root = { 4, 0, 0, 0, -0.3, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } }), opts(SOFT, 0.2)),
	K(0.5, {}, { ease = "Cubic", dir = "InOut", draw = 0 }),
} }

-- Quick Shot (windup 0.1, 0.35 long): a snap draw and release with almost no pause.
Clips.BowQuick = { name = "BowQuick", priority = Action, hit = 0.10, keys = {
	K(0, {}, { draw = 0 }),
	K(0.05, aim({ Root = { 2, 0, 0, 0, -0.2, 0.05 } }), opts(OUT, 1.6)),
	K(0.10, aim({ Root = { 2, 0, 0, 0, -0.2, 0.1 }, LeftShoulder = { 90, -10, -96 } }), opts({ ease = "Cubic", dir = "In" }, 2.2, "Hit")),
	K(0.18, aim({ LeftShoulder = { 90, -10, -92 } }), opts(OUT, 0.8)),
	K(0.35, {}, { ease = "Cubic", dir = "InOut", draw = 0 }),
} }

-- Piercing Arrow (windup 0.6, 0.95 long): a slow full draw that trembles, then a hard release with a heavy recoil.
local HEAVY = { Root = { 6, 0, 0, 0, -0.45, 0 }, RightHip = { 10, 0, 14 }, LeftHip = { 10, 0, -14 }, RightKnee = { -34, 0, 0 }, LeftKnee = { -34, 0, 0 } }
Clips.BowCharge = { name = "BowCharge", priority = Action, hit = 0.60, keys = {
	K(0, {}, { draw = 0 }),
	K(0.12, aim(with(HEAVY, { LeftShoulder = { 90, -10, -86 } })), opts(OUT, 0.6)),
	K(0.34, aim(with(HEAVY, { LeftShoulder = { 90, -10, -90 } })), opts(SOFT, 1.7)),
	K(0.46, aim(with(HEAVY, { LeftShoulder = { 91, 0, -5 }, Root = { 6, 0, 0, 0, -0.5, 0.02 } })), opts(LIN, 2.0)),
	K(0.52, aim(with(HEAVY, { LeftShoulder = { 90, 0, -7 }, Root = { 6, 0, 0, 0, -0.46, -0.02 } })), opts(LIN, 2.05)),
	K(0.57, aim(with(HEAVY, { LeftShoulder = { 91, 0, -5 }, Root = { 6, 0, 0, 0, -0.5, 0.02 } })), opts(LIN, 2.1)),
	K(0.60, aim(with(HEAVY, { Root = { 14, 0, 0, 0, -0.4, 0.3 }, LeftShoulder = { 90, -10, -100 }, Waist = { 6, -35, 0 } })), opts({ ease = "Cubic", dir = "In" }, 2.6, "Hit")),
	K(0.72, aim(with(HEAVY, { Root = { 8, 0, 0, 0, -0.4, 0.2 }, LeftShoulder = { 90, -10, -96 } })), opts(OUT, 0.9)),
	K(0.95, {}, { ease = "Cubic", dir = "InOut", draw = 0 }),
} }

-- Backstep Shot (windup 0.05; the dash lasts 0.2 s and the arrow leaves at 0.25): a crouch, a backflip, and a landing shot.
Clips.BowBackflip = { name = "BowBackflip", priority = Action, hit = 0.05, keys = {
	K(0, {}, { draw = 0 }),
	K(0.05, aim({ Root = { 10, 0, 0, 0, -0.7, 0.1 }, Waist = { 8, -30, 0 }, LeftShoulder = { 90, -10, -50 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightHip = { 20, 0, 6 }, LeftHip = { 20, 0, -6 } }), opts(OUT, 0.3, "Jump")),
	K(0.1, aim({ Root = { 100, 0, 0, 0, 0.5, 0.2 }, Waist = { -6, -20, 0 }, LeftShoulder = { 90, -10, -40 }, RightKnee = { -80, 0, 0 }, LeftKnee = { -80, 0, 0 }, RightHip = { 60, 0, 6 }, LeftHip = { 60, 0, -6 } }), opts(LIN, 0.3)),
	K(0.16, aim({ Root = { 215, 0, 0, 0, 0.75, 0.2 }, Waist = { -6, -20, 0 }, LeftShoulder = { 90, -10, -40 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { 50, 0, 6 }, LeftHip = { 50, 0, -6 } }), opts(LIN, 0.4)),
	K(0.22, aim({ Root = { 330, 0, 0, 0, 0.1, 0.1 }, Waist = { 0, -35, 0 }, LeftShoulder = { 90, -10, -88 }, RightKnee = { -40, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightHip = { 20, 0, 14 }, LeftHip = { 20, 0, -14 } }), opts(OUT, 1.6)),
	K(0.25, aim({ Root = { 362, 0, 0, 0, -0.5, 0.15 }, LeftShoulder = { 90, -10, -94 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -50, 0, 0 }, RightHip = { 20, 0, 14 }, LeftHip = { 20, 0, -14 } }), opts({ ease = "Cubic", dir = "In" }, 2.3, "Hit")),
	K(0.34, aim({ Root = { 360, 0, 0, 0, -0.45, 0.1 }, LeftShoulder = { 90, -10, -92 } }), opts(OUT, 1.0)),
	K(0.5, { Root = { 0, 360, 0 } }, { ease = "Cubic", dir = "InOut", draw = 0 }),
} }

-- Rain of Arrows (windup 0.8, 2.5 long): the bow is raised to the sky and five volleys leave at 0.8, 1.1, 1.4, 1.7 and 2.0.
local SKY = { Root = { 8, 0, 0, 0, -0.35, 0 }, Waist = { 14, -35, 0 }, Neck = { 28, 70, 0 }, LeftShoulder = { 90, -10, -158 }, LeftElbow = { 2, 0, 0 }, RightHip = { 6, 0, 14 }, LeftHip = { 6, 0, -14 }, RightKnee = { -28, 0, 0 }, LeftKnee = { -28, 0, 0 } }
local rain = { K(0, {}, { draw = 0 }), K(0.35, aim(with(SKY, { LeftShoulder = { 90, -10, -120 } })), opts(OUT, 1.0)) }
for index, at in ipairs({ 0.8, 1.1, 1.4, 1.7, 2.0 }) do
	local last = index == 5
	rain[#rain + 1] = K(at - 0.14, aim(with(SKY, { Root = { 8, 0, 0, 0, -0.4, 0 } })), opts(LIN, 1.9))
	rain[#rain + 1] = K(at, aim(with(SKY, { LeftShoulder = { 90, -10, -164 }, Root = { last and 16 or 10, 0, 0, 0, -0.3, last and 0.3 or 0.12 } })), opts({ ease = "Cubic", dir = "In" }, last and 2.7 or 2.4, "Hit"))
	if not last then
		rain[#rain + 1] = K(at + 0.07, aim(with(SKY, { LeftShoulder = { 90, -10, -160 } })), opts(OUT, 0.8))
	end
end
rain[#rain + 1] = K(2.2, aim(with(SKY, { LeftShoulder = { 90, -10, -140 }, Root = { 6, 0, 0, 0, -0.3, 0.1 } })), opts(SOFT, 0.6))
rain[#rain + 1] = K(2.5, {}, { ease = "Cubic", dir = "InOut", draw = 0 })
Clips.BowRain = { name = "BowRain", priority = Action, hit = 0.8, keys = rain }

-- Draw and sheathe.
Clips.BowEquip = { name = "BowEquip", priority = Action, keys = {
	K(0, {}, { base = CALM }),
	K(0.14, { RightShoulder = { 168, 0, 30 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 10, 0, -30 }, LeftElbow = { 40, 0, 0 }, Waist = { 6, 14, 0 }, Neck = { 12, 0, 0 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.3, { RightShoulder = { 95, 0, -20 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 85, 0, -10 }, LeftElbow = { 8, 0, 0 }, Waist = { 0, -34, 0 }, Neck = { 0, 28, 0 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.5, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }
Clips.BowUnequip = { name = "BowUnequip", priority = Action, keys = {
	K(0, {}, { draw = 0 }),
	K(0.18, { LeftShoulder = { 40, 0, -20 }, LeftElbow = { 40, 0, 0 }, RightShoulder = { 60, 0, 10 }, RightElbow = { 70, 0, 0 } }, SOFT),
	K(0.4, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }

-- Stances (upper body only, Movement priority). The combat stance keeps the right hand on the string.
local function breathe(base, name, length, onString)
	local mid = length / 2
	local function breath() return { Waist = { base.Waist[1] + 1.5, base.Waist[2], 0 }, Neck = { base.Neck[1] - 1.5, base.Neck[2], 0 }, LeftShoulder = { base.LeftShoulder[1] + 2, base.LeftShoulder[2], base.LeftShoulder[3] }, LeftElbow = { base.LeftElbow[1] + 3, 0, 0 } } end
	local first = K(0, {}, { base = base, upper = true, draw = onString and 0 or nil })
	local middle = K(mid, breath(), { base = base, upper = true, ease = "Cubic", dir = "InOut", draw = onString and 0.15 or nil })
	local last = K(length, {}, { base = base, upper = true, ease = "Cubic", dir = "InOut", draw = onString and 0 or nil })
	return { name = name, priority = Movement, loop = true, keys = { first, middle, last } }
end
Clips.BowIdle = breathe(CALM, "BowIdle", 3.2, false)
Clips.BowCombatIdle = breathe(READY, "BowCombatIdle", 2.4, true)

-- Dodges and reactions: the sword set's clips, re-based onto the bow stance (their first and last keys keep the right hand on
-- the string, so nothing pops when they end).
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
	out.keys[1].draw = 0
	out.keys[#out.keys].draw = 0
	return out
end
for _, name in ipairs({ "Dodge", "DodgeForward", "DodgeLeft", "DodgeRight", "HitReactLight", "HitReactHeavy", "Stagger" }) do
	Clips["Bow" .. name] = rebase(Sword[name], "Bow" .. name)
end

Clips.order = { "BowShot", "BowShotB", "BowQuick", "BowCharge", "BowBackflip", "BowRain", "BowEquip", "BowUnequip", "BowIdle", "BowCombatIdle", "BowDodge", "BowDodgeForward", "BowDodgeLeft", "BowDodgeRight", "BowHitReactLight", "BowHitReactHeavy", "BowStagger" }

return Clips
