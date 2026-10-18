--!nonstrict
-- Sword moveset (benchmark). Authored against the timings in Config/Combat: the impact key of each attack lands on
-- its `windup`, and each clip's length equals windup + active + recovery. Marker "Hit" sits on the impact key.
-- Conventions: rotations in degrees; Waist +X leans back, -X leans forward; Waist +Y turns left (right shoulder forward);
-- RightShoulder +X raises forward, +Z swings out right, -Z across the body; hips +X forward, knees -X bend.
local Clips = {}
local Action = Enum.AnimationPriority.Action
-- Stances sit at Movement, above Roblox's default Idle/Core clips (including the avatar's own idle animation, which
-- would otherwise blend with ours at equal priority) and below Action. They pose the upper body only.
local Idle = Enum.AnimationPriority.Movement

local ALL = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
local UPPER = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

local GUARD = {
	Waist = { 0, 22, 0 }, Neck = { 0, -18, 0 },
	RightShoulder = { 52, 0, 22 }, RightElbow = { 72, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 18, 0, -28 }, LeftElbow = { 45, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local RELAXED = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 8, 0, 9 }, RightElbow = { 22, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 4, 0, -7 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { 0, 0, 0 },
}

local function copy(v)
	return { v[1], v[2], v[3], v[4], v[5], v[6] }
end

-- A key: base pose (guard by default) with overrides; every joint listed so blends stay predictable.
local function K(t, over, o)
	o = o or {}
	local base = o.base or GUARD
	local joints = o.upper and UPPER or ALL
	local j = {}
	for _, n in ipairs(joints) do
		j[n] = copy(base[n] or { 0, 0, 0 })
	end
	for n, v in pairs(over or {}) do
		j[n] = v
	end
	return { t = t, j = j, ease = o.ease, dir = o.dir, marker = o.marker }
end
local IN = { ease = "Cubic", dir = "In" }
local function withMarker(o, m)
	return { ease = o.ease, dir = o.dir, marker = m }
end

-- Light 1: right-high to left-low diagonal. Impact 0.12.
Clips.SwordCombo1 = { name = "SwordCombo1", priority = Action, keys = {
	K(0, {}),
	K(0.05, { Root = { 0, -12, 0, 0, -0.1, 0.05 }, Waist = { -4, -22, 0 }, Neck = { 0, 12, 0 }, RightShoulder = { 125, 0, 52 }, RightElbow = { 100, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 40, 0, -40 }, LeftElbow = { 60, 0, 0 }, RightHip = { -8, 0, 0 }, LeftHip = { 10, 0, 0 }, RightKnee = { -12, 0, 0 }, LeftKnee = { -15, 0, 0 } }),
	K(0.12, { Root = { 4, 14, 0, 0, -0.25, -0.35 }, Waist = { -12, 38, 0 }, Neck = { 0, -35, 0 }, RightShoulder = { 78, 0, -30 }, RightElbow = { 25, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 5, 0, -60 }, LeftElbow = { 40, 0, 0 }, RightHip = { 38, 0, 6 }, RightKnee = { -38, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -28, 0, 0 } }, withMarker(IN, "Hit")),
	K(0.19, { Root = { 6, 20, 0, 0, -0.2, -0.4 }, Waist = { -14, 52, 0 }, Neck = { 0, -42, 0 }, RightShoulder = { 65, 0, -52 }, RightElbow = { 20, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 5, 0, -62 }, LeftElbow = { 40, 0, 0 }, RightHip = { 38, 0, 6 }, RightKnee = { -38, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -28, 0, 0 } }),
	K(0.31, { Root = { 0, 6, 0, 0, -0.1, -0.15 }, Waist = { -6, 26, 0 }, RightShoulder = { 58, 0, -18 }, RightElbow = { 60, 0, 0 }, RightHip = { 18, 0, 0 }, RightKnee = { -18, 0, 0 }, LeftHip = { -10, 0, 0 }, LeftKnee = { -14, 0, 0 } }, { ease = "Cubic", dir = "InOut" }),
	K(0.46, {}, { ease = "Cubic", dir = "InOut" }),
} }

-- Light 2: backhand, left-low to right-high, stepping through with the other foot. Impact 0.12.
Clips.SwordCombo2 = { name = "SwordCombo2", priority = Action, keys = {
	K(0, {}),
	K(0.05, { Root = { 0, 22, 0, 0, -0.1, 0.05 }, Waist = { -4, 48, 0 }, Neck = { 0, -40, 0 }, RightShoulder = { 70, 0, -48 }, RightElbow = { 65, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 20, 0, -60 }, LeftElbow = { 45, 0, 0 }, RightHip = { 10, 0, 0 }, LeftHip = { -8, 0, 0 }, RightKnee = { -14, 0, 0 }, LeftKnee = { -12, 0, 0 } }),
	K(0.12, { Root = { 4, -18, 0, 0, -0.2, -0.3 }, Waist = { -8, -30, 0 }, Neck = { 0, 28, 0 }, RightShoulder = { 92, 0, 62 }, RightElbow = { 12, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 60, 0, 0 }, LeftHip = { 34, 0, -5 }, LeftKnee = { -34, 0, 0 }, RightHip = { -24, 0, 0 }, RightKnee = { -22, 0, 0 } }, withMarker(IN, "Hit")),
	K(0.19, { Root = { 5, -24, 0, 0, -0.18, -0.35 }, Waist = { -10, -45, 0 }, Neck = { 0, 40, 0 }, RightShoulder = { 85, 0, 85 }, RightElbow = { 10, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 60, 0, 0 }, LeftHip = { 34, 0, -5 }, LeftKnee = { -34, 0, 0 }, RightHip = { -24, 0, 0 }, RightKnee = { -22, 0, 0 } }),
	K(0.31, { Root = { 0, -6, 0, 0, -0.1, -0.12 }, Waist = { -4, 4, 0 }, RightShoulder = { 70, 0, 40 }, RightElbow = { 55, 0, 0 }, LeftHip = { 14, 0, 0 }, LeftKnee = { -16, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -10, 0, 0 } }, { ease = "Cubic", dir = "InOut" }),
	K(0.46, {}, { ease = "Cubic", dir = "InOut" }),
} }

-- Light 3 (finisher): rises, then a single committed diagonal chop with a deep lunge. Impact 0.18.
Clips.SwordCombo3 = { name = "SwordCombo3", priority = Action, keys = {
	K(0, {}),
	K(0.1, { Waist = { 10, -15, 0 }, Neck = { 0, 12, 0 }, Root = { 6, -8, 0, 0, -0.1, 0.15 }, RightShoulder = { 150, 0, 20 }, RightElbow = { 115, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 80, 0, -40 }, LeftElbow = { 70, 0, 0 }, RightKnee = { -18, 0, 0 }, LeftKnee = { -26, 0, 0 }, LeftHip = { -8, 0, 0 } }),
	K(0.14, { Waist = { 14, -22, 0 }, Neck = { 0, 18, 0 }, Root = { 8, -12, 0, 0, -0.18, 0.2 }, RightShoulder = { 168, 0, 15 }, RightElbow = { 120, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 84, 0, -42 }, LeftElbow = { 74, 0, 0 }, RightKnee = { -22, 0, 0 }, LeftKnee = { -32, 0, 0 }, LeftHip = { -10, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(0.18, { Waist = { -34, 28, 0 }, Neck = { 12, -34, 0 }, Root = { 8, 22, 0, 0, -0.55, -0.6 }, RightShoulder = { 32, 0, -28 }, RightElbow = { 8, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 35, 0, -45 }, LeftElbow = { 50, 0, 0 }, RightHip = { 52, 0, 4 }, RightKnee = { -62, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -20, 0, 0 } }, withMarker(IN, "Hit")),
	K(0.3, { Waist = { -30, 30, 0 }, Neck = { 10, -34, 0 }, Root = { 8, 24, 0, 0, -0.6, -0.65 }, RightShoulder = { 25, 0, -34 }, RightElbow = { 14, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 35, 0, -45 }, LeftElbow = { 50, 0, 0 }, RightHip = { 52, 0, 4 }, RightKnee = { -62, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -20, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(0.48, { Waist = { -12, 26, 0 }, Root = { 4, 10, 0, 0, -0.25, -0.3 }, RightShoulder = { 50, 0, -10 }, RightElbow = { 55, 0, 0 }, RightHip = { 24, 0, 0 }, RightKnee = { -26, 0, 0 }, LeftHip = { -14, 0, 0 }, LeftKnee = { -10, 0, 0 } }, { ease = "Cubic", dir = "InOut" }),
	K(0.73, {}, { ease = "Cubic", dir = "InOut" }),
} }

-- Heavy: two-handed overhead, a held beat of tension, then a crushing drop. Impact 0.45.
Clips.SwordHeavy = { name = "SwordHeavy", priority = Action, keys = {
	K(0, {}),
	K(0.18, { Waist = { 4, -10, 0 }, Neck = { 0, 10, 0 }, Root = { 2, -6, 0, 0, 0.04, 0 }, RightShoulder = { 110, 0, 30 }, RightElbow = { 90, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 95, 0, -20 }, LeftElbow = { 85, 0, 0 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -14, 0, 0 } }, { ease = "Quad", dir = "InOut" }),
	K(0.33, { Waist = { 16, -14, 0 }, Neck = { 0, 14, 0 }, Root = { 8, -8, 0, 0, 0.08, 0.1 }, RightShoulder = { 165, 0, 22 }, RightElbow = { 118, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 160, 0, -18 }, LeftElbow = { 110, 0, 0 }, RightHip = { -10, 0, 0 }, LeftHip = { 8, 0, 0 }, RightKnee = { -18, 0, 0 }, LeftKnee = { -18, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(0.41, { Waist = { 19, -17, 0 }, Neck = { 0, 16, 0 }, Root = { 9, -9, 0, 0, 0.02, 0.14 }, RightShoulder = { 169, 0, 22 }, RightElbow = { 122, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 164, 0, -18 }, LeftElbow = { 114, 0, 0 }, RightHip = { -12, 0, 0 }, LeftHip = { 10, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -22, 0, 0 } }, { ease = "Linear", dir = "Out" }),
	K(0.45, { Waist = { -38, 10, 0 }, Neck = { 22, -14, 0 }, Root = { 6, 6, 0, 0, -0.9, -0.7 }, RightShoulder = { 28, 0, 5 }, RightElbow = { 5, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 28, 0, -8 }, LeftElbow = { 30, 0, 0 }, RightHip = { 58, 0, 4 }, RightKnee = { -78, 0, 0 }, LeftHip = { -32, 0, 0 }, LeftKnee = { -12, 0, 0 } }, withMarker(IN, "Hit")),
	K(0.58, { Waist = { -34, 12, 0 }, Neck = { 20, -14, 0 }, Root = { 6, 8, 0, 0, -0.92, -0.75 }, RightShoulder = { 24, 0, 4 }, RightElbow = { 8, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 26, 0, -8 }, LeftElbow = { 32, 0, 0 }, RightHip = { 58, 0, 4 }, RightKnee = { -78, 0, 0 }, LeftHip = { -32, 0, 0 }, LeftKnee = { -12, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(0.82, { Waist = { -14, 20, 0 }, Root = { 3, 8, 0, 0, -0.4, -0.3 }, RightShoulder = { 46, 0, 14 }, RightElbow = { 60, 0, 0 }, RightHip = { 26, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftHip = { -14, 0, 0 }, LeftKnee = { -6, 0, 0 } }, { ease = "Cubic", dir = "InOut" }),
	K(1.1, {}, { ease = "Cubic", dir = "InOut" }),
} }

-- Crescent Sweep: crouch and wind, then a full-body spin with the blade held out level. Contact through 0.3-0.5.
local SPIN_ARM = { RightShoulder = { 90, 0, 92 }, RightElbow = { 6, 0, 0 }, RightWrist = { -6, 0, 0 }, LeftShoulder = { 20, 0, -80 }, LeftElbow = { 25, 0, 0 } }
local function spin(rootY, extra)
	local over = { Root = { 0, rootY, 0, 0, -0.5, 0 }, Waist = { -8, 0, 0 }, Neck = { 0, 0, 0 }, RightHip = { 14, 0, 0 }, RightKnee = { -42, 0, 0 }, LeftHip = { -10, 0, 0 }, LeftKnee = { -36, 0, 0 } }
	for n, v in pairs(SPIN_ARM) do over[n] = v end
	for n, v in pairs(extra or {}) do over[n] = v end
	return over
end
Clips.SwordSweep = { name = "SwordSweep", priority = Action, keys = {
	K(0, {}),
	K(0.13, spin(-55, { Waist = { -4, -45, 0 }, Neck = { 0, 40, 0 }, RightShoulder = { 70, 0, 100 }, Root = { 4, -55, 0, 0, -0.55, 0.1 } }), { ease = "Cubic", dir = "Out" }),
	K(0.22, spin(35), { ease = "Quad", dir = "In" }),
	K(0.3, spin(150), { ease = "Linear", dir = "Out", marker = "Hit" }),
	K(0.4, spin(260), { ease = "Linear", dir = "Out" }),
	K(0.5, spin(335), { ease = "Linear", dir = "Out" }),
	K(0.58, spin(366, { Waist = { -12, 10, 0 }, RightShoulder = { 80, 0, 50 }, RightElbow = { 40, 0, 0 }, Root = { 2, 366, 0, 0, -0.45, 0 } }), { ease = "Cubic", dir = "Out" }),
	K(0.95, {}, { ease = "Cubic", dir = "InOut" }),
} }

-- Parry: instant guard raise, the blade angled across the body; a small jolt on the deflect.
local PARRY = { Root = { -2, 10, 0, 0, -0.15, 0.15 }, Waist = { 2, 20, 0 }, Neck = { 0, -14, 0 }, RightShoulder = { 92, -10, -38 }, RightElbow = { 112, 0, 0 }, RightWrist = { -15, 0, 0 }, LeftShoulder = { 30, 0, -45 }, LeftElbow = { 50, 0, 0 }, RightHip = { -6, 0, 0 }, LeftHip = { -12, 0, 0 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -20, 0, 0 } }
Clips.SwordParry = { name = "SwordParry", priority = Action, keys = {
	K(0, {}),
	K(0.05, PARRY),
	K(0.14, { Root = { -4, 12, 0, 0, -0.15, 0.22 }, Waist = { 4, 22, 0 }, Neck = { 0, -14, 0 }, RightShoulder = { 96, -12, -26 }, RightElbow = { 104, 0, 0 }, RightWrist = { -15, 0, 0 }, LeftShoulder = { 30, 0, -45 }, LeftElbow = { 50, 0, 0 }, RightHip = { -6, 0, 0 }, LeftHip = { -12, 0, 0 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -20, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(0.28, PARRY, { ease = "Quad", dir = "InOut" }),
	K(0.6, {}, { ease = "Cubic", dir = "InOut" }),
} }

-- Riposte: begins from the parry pose, a quick coil, then a lunging thrust. Impact 0.08.
Clips.SwordRiposte = { name = "SwordRiposte", priority = Action, keys = {
	K(0, PARRY),
	K(0.04, { Root = { 0, 20, 0, 0, -0.1, 0.2 }, Waist = { 2, 30, 0 }, Neck = { 0, -26, 0 }, RightShoulder = { 75, 0, -12 }, RightElbow = { 135, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 20, 0, -60 }, LeftElbow = { 50, 0, 0 }, RightHip = { -4, 0, 0 }, LeftHip = { -14, 0, 0 }, RightKnee = { -12, 0, 0 }, LeftKnee = { -24, 0, 0 } }),
	K(0.08, { Root = { 6, -6, 0, 0, -0.45, -0.75 }, Waist = { -24, -6, 0 }, Neck = { 0, 6, 0 }, RightShoulder = { 92, 0, -4 }, RightElbow = { 4, 0, 0 }, RightWrist = { 0, 0, 0 }, LeftShoulder = { 20, 0, -70 }, LeftElbow = { 40, 0, 0 }, RightHip = { 55, 0, 3 }, RightKnee = { -62, 0, 0 }, LeftHip = { -38, 0, 0 }, LeftKnee = { -18, 0, 0 } }, withMarker(IN, "Hit")),
	K(0.2, { Root = { 6, -6, 0, 0, -0.46, -0.78 }, Waist = { -26, -6, 0 }, Neck = { 0, 6, 0 }, RightShoulder = { 92, 0, -4 }, RightElbow = { 6, 0, 0 }, RightWrist = { 0, 0, 0 }, LeftShoulder = { 20, 0, -72 }, LeftElbow = { 40, 0, 0 }, RightHip = { 55, 0, 3 }, RightKnee = { -62, 0, 0 }, LeftHip = { -38, 0, 0 }, LeftKnee = { -18, 0, 0 } }, { ease = "Linear", dir = "Out" }),
	K(0.34, { Root = { 2, 8, 0, 0, -0.25, -0.3 }, Waist = { -8, 20, 0 }, RightShoulder = { 70, 0, 8 }, RightElbow = { 80, 0, 0 }, RightHip = { 26, 0, 0 }, RightKnee = { -28, 0, 0 }, LeftHip = { -16, 0, 0 }, LeftKnee = { -10, 0, 0 } }, { ease = "Cubic", dir = "InOut" }),
	K(0.5, {}, { ease = "Cubic", dir = "InOut" }),
} }

-- Dodges. The motion itself is the client's LinearVelocity; these supply the body.
local FLY = { RightShoulder = { -25, 0, 28 }, LeftShoulder = { -25, 0, -28 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 } }
local function with(base, extra)
	local out = {}
	for n, v in pairs(base) do out[n] = v end
	for n, v in pairs(extra) do out[n] = v end
	return out
end
Clips.Dodge = { name = "Dodge", priority = Action, keys = { -- backstep
	K(0, {}),
	K(0.06, with(FLY, { Root = { 12, 0, 0, 0, 0.12, 0.2 }, Waist = { 8, 0, 0 }, Neck = { -6, -10, 0 }, RightHip = { 42, 0, 0 }, LeftHip = { 30, 0, 0 }, RightKnee = { -58, 0, 0 }, LeftKnee = { -45, 0, 0 } })),
	K(0.2, with(FLY, { Root = { 10, 0, 0, 0, 0.1, 0.1 }, Waist = { 6, 0, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { 24, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } }), { ease = "Quad", dir = "InOut" }),
	K(0.29, { Root = { -4, 0, 0, 0, -0.5, -0.05 }, Waist = { -10, 14, 0 }, RightHip = { 30, 0, 0 }, LeftHip = { 38, 0, 0 }, RightKnee = { -55, 0, 0 }, LeftKnee = { -64, 0, 0 } }, { ease = "Cubic", dir = "In" }),
	K(0.4, {}, { ease = "Cubic", dir = "Out" }),
} }
Clips.DodgeForward = { name = "DodgeForward", priority = Action, keys = { -- tuck roll
	K(0, {}),
	K(0.05, { Root = { -40, 0, 0, 0, -0.5, -0.1 }, Waist = { -20, 0, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 40, 0, 20 }, LeftShoulder = { 40, 0, -20 }, RightElbow = { 95, 0, 0 }, LeftElbow = { 95, 0, 0 }, RightHip = { 70, 0, 0 }, LeftHip = { 70, 0, 0 }, RightKnee = { -100, 0, 0 }, LeftKnee = { -100, 0, 0 } }, { ease = "Cubic", dir = "Out" }),
	K(0.11, { Root = { -140, 0, 0, 0, -0.7, 0 }, Waist = { -25, 0, 0 }, Neck = { -25, 0, 0 }, RightShoulder = { 40, 0, 20 }, LeftShoulder = { 40, 0, -20 }, RightElbow = { 95, 0, 0 }, LeftElbow = { 95, 0, 0 }, RightHip = { 80, 0, 0 }, LeftHip = { 80, 0, 0 }, RightKnee = { -110, 0, 0 }, LeftKnee = { -110, 0, 0 } }, { ease = "Linear", dir = "Out" }),
	K(0.18, { Root = { -230, 0, 0, 0, -0.7, 0 }, Waist = { -25, 0, 0 }, Neck = { -25, 0, 0 }, RightShoulder = { 40, 0, 20 }, LeftShoulder = { 40, 0, -20 }, RightElbow = { 95, 0, 0 }, LeftElbow = { 95, 0, 0 }, RightHip = { 80, 0, 0 }, LeftHip = { 80, 0, 0 }, RightKnee = { -110, 0, 0 }, LeftKnee = { -110, 0, 0 } }, { ease = "Linear", dir = "Out" }),
	K(0.25, { Root = { -320, 0, 0, 0, -0.6, 0 }, Waist = { -15, 0, 0 }, RightHip = { 60, 0, 0 }, LeftHip = { 55, 0, 0 }, RightKnee = { -90, 0, 0 }, LeftKnee = { -85, 0, 0 } }, { ease = "Linear", dir = "Out" }),
	K(0.31, { Root = { -360, 0, 0, 0, -0.45, -0.05 }, Waist = { -14, 18, 0 }, RightHip = { 40, 0, 0 }, LeftHip = { 30, 0, 0 }, RightKnee = { -62, 0, 0 }, LeftKnee = { -54, 0, 0 } }, { ease = "Cubic", dir = "Out" }),
	K(0.4, {}, { ease = "Cubic", dir = "Out" }),
} }
local function sidestep(sign, name)
	return { name = name, priority = Action, keys = {
		K(0, {}),
		K(0.06, { Root = { 0, 0, 18 * sign, 0, -0.15, 0 }, Waist = { 0, 22, -10 * sign }, Neck = { 0, -18, 6 * sign }, RightShoulder = { 40, 0, 40 }, LeftShoulder = { 30, 0, -40 }, RightHip = { 14, 0, 28 * sign - 28 }, LeftHip = { 14, 0, 28 * sign + 28 }, RightKnee = { -34, 0, 0 }, LeftKnee = { -34, 0, 0 } }),
		K(0.2, { Root = { 0, 0, 14 * sign, 0, -0.2, 0 }, Waist = { 0, 22, -8 * sign }, RightShoulder = { 46, 0, 34 }, LeftShoulder = { 30, 0, -36 }, RightHip = { 8, 0, 12 * sign - 12 }, LeftHip = { 8, 0, 12 * sign + 12 }, RightKnee = { -28, 0, 0 }, LeftKnee = { -28, 0, 0 } }, { ease = "Quad", dir = "InOut" }),
		K(0.29, { Root = { 0, 0, 0, 0, -0.4, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { 20, 0, 0 }, RightKnee = { -48, 0, 0 }, LeftKnee = { -48, 0, 0 } }, { ease = "Cubic", dir = "In" }),
		K(0.4, {}, { ease = "Cubic", dir = "Out" }),
	} }
end
Clips.DodgeLeft = sidestep(1, "DodgeLeft")
Clips.DodgeRight = sidestep(-1, "DodgeRight")

-- Reactions.
Clips.HitReactLight = { name = "HitReactLight", priority = Action, keys = {
	K(0, {}),
	K(0.05, { Root = { 5, 6, 0, 0, -0.05, 0.28 }, Waist = { 18, 10, 0 }, Neck = { 20, -8, 0 }, RightShoulder = { 28, 0, 36 }, RightElbow = { 55, 0, 0 }, LeftShoulder = { -10, 0, -48 }, LeftElbow = { 40, 0, 0 }, RightHip = { 6, 0, 0 }, LeftHip = { -6, 0, 0 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -16, 0, 0 } }),
	K(0.14, { Root = { 3, 4, 0, 0, -0.04, 0.2 }, Waist = { 12, 12, 0 }, Neck = { 12, -10, 0 }, RightShoulder = { 34, 0, 30 }, RightElbow = { 58, 0, 0 }, LeftShoulder = { 0, 0, -40 }, LeftElbow = { 44, 0, 0 }, RightKnee = { -8, 0, 0 }, LeftKnee = { -12, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(0.35, {}, { ease = "Cubic", dir = "InOut" }),
} }
Clips.HitReactHeavy = { name = "HitReactHeavy", priority = Action, keys = {
	K(0, {}),
	K(0.07, { Root = { 12, 8, 0, 0, -0.25, 0.65 }, Waist = { 32, 16, 0 }, Neck = { 30, -10, 0 }, RightShoulder = { 40, 0, 62 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 30, 0, -66 }, LeftElbow = { 36, 0, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { -22, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -36, 0, 0 } }),
	K(0.22, { Root = { 8, 6, 0, 0, -0.3, 0.5 }, Waist = { 24, 14, 0 }, Neck = { 22, -10, 0 }, RightShoulder = { 46, 0, 50 }, RightElbow = { 48, 0, 0 }, LeftShoulder = { 32, 0, -56 }, LeftElbow = { 40, 0, 0 }, RightHip = { 16, 0, 0 }, LeftHip = { -18, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftKnee = { -34, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(0.4, { Root = { 2, 8, 0, 0, -0.18, 0.2 }, Waist = { -8, 20, 0 }, RightHip = { 10, 0, 0 }, LeftHip = { -8, 0, 0 }, RightKnee = { -18, 0, 0 }, LeftKnee = { -18, 0, 0 } }, { ease = "Cubic", dir = "InOut" }),
	K(0.6, {}, { ease = "Cubic", dir = "InOut" }),
} }
-- Stagger: doubled over and off balance (parried or staggered enemies, and players when knocked off their guard).
local HUNCH = { Root = { -6, 0, 0, 0, -0.28, 0.1 }, Waist = { -26, 10, 0 }, Neck = { -14, 0, 0 }, RightShoulder = { 8, 0, 14 }, RightElbow = { 38, 0, 0 }, LeftShoulder = { 12, 0, -16 }, LeftElbow = { 36, 0, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { 6, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftKnee = { -30, 0, 0 } }
Clips.Stagger = { name = "Stagger", priority = Action, keys = {
	K(0, {}),
	K(0.1, HUNCH, { ease = "Cubic", dir = "Out" }),
	K(0.5, with(HUNCH, { Waist = { -22, -8, 0 }, Root = { -4, -4, 0, 0, -0.24, 0.05 } }), { ease = "Quad", dir = "InOut" }),
	K(0.78, with(HUNCH, { Waist = { -14, 10, 0 }, Root = { -2, 2, 0, 0, -0.14, 0.02 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -18, 0, 0 } }), { ease = "Quad", dir = "InOut" }),
	K(1.0, {}, { ease = "Cubic", dir = "InOut" }),
} }
-- Death: recoil, knees buckle, then falls onto the back and lies still.
Clips.Death = { name = "Death", priority = Action, keys = {
	K(0, {}),
	K(0.12, { Root = { 6, 8, 0, 0, -0.1, 0.4 }, Waist = { 22, 12, 0 }, Neck = { 22, -10, 0 }, RightShoulder = { 34, 0, 50 }, LeftShoulder = { 10, 0, -56 }, RightElbow = { 50, 0, 0 }, LeftElbow = { 40, 0, 0 }, RightKnee = { -18, 0, 0 }, LeftKnee = { -24, 0, 0 } }, { ease = "Cubic", dir = "Out" }),
	K(0.45, { Root = { 4, 6, 0, 0, -0.95, 0.35 }, Waist = { 6, 6, 0 }, Neck = { 10, 0, 0 }, RightShoulder = { 8, 0, 22 }, LeftShoulder = { 6, 0, -22 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 16, 0, 0 }, RightHip = { 52, 0, 0 }, LeftHip = { 40, 0, 0 }, RightKnee = { -108, 0, 0 }, LeftKnee = { -92, 0, 0 } }, { ease = "Cubic", dir = "In" }),
	K(0.9, { Root = { 58, 0, 0, 0, -1.2, 0.7 }, Waist = { 4, 0, 0 }, Neck = { 12, 0, 0 }, RightShoulder = { -26, 0, 44 }, LeftShoulder = { -30, 0, -46 }, RightElbow = { 30, 0, 0 }, LeftElbow = { 22, 0, 0 }, RightHip = { 48, 0, 6 }, LeftHip = { 28, 0, -6 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -50, 0, 0 } }, { ease = "Quad", dir = "In" }),
	K(1.15, { Root = { 90, 0, 0, 0, -1.6, 1.3 }, Waist = { 0, 0, 0 }, Neck = { 6, 12, 0 }, RightShoulder = { -34, 0, 58 }, LeftShoulder = { -38, 0, -58 }, RightElbow = { 16, 0, 0 }, LeftElbow = { 10, 0, 0 }, RightHip = { 4, 0, 6 }, LeftHip = { 2, 0, -6 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -22, 0, 0 } }, { ease = "Quad", dir = "Out" }),
	K(1.6, { Root = { 90, 0, 0, 0, -1.6, 1.3 }, Waist = { 0, 0, 0 }, Neck = { 8, 14, 0 }, RightShoulder = { -34, 0, 60 }, LeftShoulder = { -38, 0, -60 }, RightElbow = { 14, 0, 0 }, LeftElbow = { 8, 0, 0 }, RightHip = { 4, 0, 6 }, LeftHip = { 2, 0, -6 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -22, 0, 0 } }, { ease = "Linear", dir = "Out" }),
} }

-- Draw and sheathe.
Clips.SwordEquip = { name = "SwordEquip", priority = Action, keys = {
	K(0, {}, { base = RELAXED }),
	K(0.15, { RightShoulder = { -25, 0, 20 }, RightElbow = { 20, 0, 0 }, Waist = { 0, -8, 0 }, LeftShoulder = { 10, 0, -15 } }, { base = RELAXED, ease = "Cubic", dir = "Out" }),
	K(0.32, { RightShoulder = { 115, 0, 48 }, RightElbow = { 100, 0, 0 }, RightWrist = { -10, 0, 0 }, Waist = { -3, -18, 0 }, Neck = { 0, 14, 0 }, LeftShoulder = { 35, 0, -35 }, LeftElbow = { 40, 0, 0 } }, { base = RELAXED, ease = "Cubic", dir = "Out" }),
	K(0.48, { RightShoulder = { 85, 0, -8 }, RightElbow = { 30, 0, 0 }, RightWrist = { -10, 0, 0 }, Waist = { -8, 18, 0 }, Neck = { 0, -16, 0 }, LeftShoulder = { 20, 0, -45 }, LeftElbow = { 40, 0, 0 } }, { base = RELAXED, ease = "Cubic", dir = "In" }),
	K(0.7, {}, { base = RELAXED, ease = "Cubic", dir = "InOut" }), -- ends in the relaxed stance, matching SwordIdle
} }
Clips.SwordUnequip = { name = "SwordUnequip", priority = Action, keys = {
	K(0, {}),
	K(0.2, { RightShoulder = { 60, 0, 10 }, RightElbow = { 50, 0, 0 }, Waist = { 0, 8, 0 }, Neck = { 0, -6, 0 } }, { ease = "Cubic", dir = "InOut" }),
	K(0.5, {}, { base = RELAXED, ease = "Cubic", dir = "InOut" }),
} }

-- Stances: looping upper-body clips at Idle priority, so walking and running legs still play underneath.
local function breathe(base, name, length)
	local mid = length / 2
	return { name = name, priority = Idle, loop = true, keys = {
		K(0, {}, { base = base, upper = true }),
		K(mid, { Waist = { (base.Waist[1]) + 2, base.Waist[2], 0 }, Neck = { base.Neck[1] - 1.5, base.Neck[2], 0 }, RightShoulder = { base.RightShoulder[1] + 2.5, base.RightShoulder[2], base.RightShoulder[3] + 1.5 }, LeftShoulder = { base.LeftShoulder[1] + 2, base.LeftShoulder[2], base.LeftShoulder[3] - 1.5 }, RightElbow = { base.RightElbow[1] + 3, 0, 0 } }, { base = base, upper = true, ease = "Quad", dir = "InOut" }),
		K(length, {}, { base = base, upper = true, ease = "Quad", dir = "InOut" }),
	} }
end
Clips.SwordIdle = breathe(RELAXED, "SwordIdle", 3.2)
Clips.SwordCombatIdle = breathe(GUARD, "SwordCombatIdle", 2.4)

Clips.bases = { GUARD = GUARD, RELAXED = RELAXED } -- re-used by other weapon sets to re-base shared clips
Clips.order = { "SwordCombo1", "SwordCombo2", "SwordCombo3", "SwordHeavy", "SwordSweep", "SwordParry", "SwordRiposte", "Dodge", "DodgeForward", "DodgeLeft", "DodgeRight", "HitReactLight", "HitReactHeavy", "Stagger", "Death", "SwordEquip", "SwordUnequip", "SwordIdle", "SwordCombatIdle" }

return Clips
