--!nonstrict
-- Staff and spellcasting set. The staff is gripped at -135 degrees (like blades): hanging at the side the tip points down
-- and forward, in the ready stance it points up and forward, with the arm raised and the wrist flexed it points level.
-- Cast clips carry `hit` = the time of the release; the Animator speeds a clip up or slows it down so that moment lands on
-- each ability's own windup. Same joint conventions as SwordClips.
-- A fresh copy of the sword clips (Studio caches required modules, which would hide edits to them).
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

local READY = {
	Waist = { 0, 18, 0 }, Neck = { 0, -14, 0 },
	RightShoulder = { 45, 0, 20 }, RightElbow = { 60, 0, 0 }, RightWrist = { -5, 0, 0 },
	LeftShoulder = { 30, 0, -34 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CALM = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 8, 0, 9 }, RightElbow = { 18, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 4, 0, -7 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { 0, 0, 0 },
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

-- Basic spell attacks: three casts that the Animator alternates (see `alternates` in Config/Animations), so the most-used
-- attack doesn't repeat. The staff stays upright and is never swung like a blade: the spell comes from the free hand
-- and the body, with the staff as a focus. All release at 0.12.
local HOLD = { RightShoulder = { 35, 0, 26 }, RightElbow = { 82, 0, 0 }, RightWrist = { 0, 0, 0 } }
local function mix(base, extra)
	local out = {}
	for n, v in pairs(base) do out[n] = v end
	for n, v in pairs(extra) do out[n] = v end
	return out
end
-- A: scoop. The staff is drawn back low with a crouch, then scooped up and forward as the body rises into a lunge.
Clips.CastBolt = { name = "CastBolt", priority = Action, hit = 0.12, keys = {
	K(0, {}),
	K(0.07, { Root = { 6, -10, 0, 0, -0.35, 0.15 }, Waist = { 8, -16, 0 }, Neck = { 0, 12, 0 }, RightShoulder = { 20, 0, 28 }, RightElbow = { 8, 0, 0 }, RightWrist = { 0, 0, 0 }, RightHip = { -8, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftHip = { 6, 0, 0 }, LeftKnee = { -30, 0, 0 } }, OUT),
	K(0.12, { Root = { 4, 8, 0, 0, -0.3, -0.35 }, Waist = { -14, 12, 0 }, Neck = { 8, -12, 0 }, RightShoulder = { 70, 0, 20 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 }, RightHip = { 34, 0, 0 }, RightKnee = { -38, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -14, 0, 0 } }, IN),
	K(0.22, { Root = { 4, 8, 0, 0, -0.3, -0.38 }, Waist = { -16, 12, 0 }, Neck = { 8, -12, 0 }, RightShoulder = { 78, 0, 20 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 }, RightHip = { 34, 0, 0 }, RightKnee = { -38, 0, 0 }, LeftHip = { -22, 0, 0 }, LeftKnee = { -14, 0, 0 } }, OUT),
	K(0.38, { Root = { 0, 4, 0, 0, -0.1, -0.1 }, Waist = { -4, 10, 0 }, RightShoulder = { 55, 0, 24 }, RightElbow = { 62, 0, 0 }, RightHip = { 10, 0, 0 }, RightKnee = { -14, 0, 0 }, LeftHip = { -6, 0, 0 } }, SOFT),
	K(0.55, {}, SOFT),
} }
-- B: raise and drop. The staff is lifted straight up overhead, then brought down to the chest with a stomp as the off hand
-- throws the spell forward.
Clips.CastBoltRaise = { name = "CastBoltRaise", priority = Action, hit = 0.12, keys = {
	K(0, {}),
	K(0.07, { Root = { 2, 0, 0, 0, 0.1, 0 }, Waist = { 6, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 150, 0, 14 }, RightElbow = { 20, 0, 0 }, RightWrist = { -35, 0, 0 }, LeftShoulder = { 60, 0, -64 }, LeftElbow = { 40, 0, 0 } }, OUT),
	K(0.12, { Root = { 2, 8, 0, 0, -0.45, -0.1 }, Waist = { -14, 10, 0 }, Neck = { 8, -10, 0 }, RightShoulder = { 95, 0, 16 }, RightElbow = { 45, 0, 0 }, RightWrist = { -5, 0, 0 }, LeftShoulder = { 88, 0, -14 }, LeftElbow = { 6, 0, 0 }, LeftWrist = { -30, 0, 0 }, RightHip = { 20, 0, 0 }, RightKnee = { -36, 0, 0 }, LeftHip = { -8, 0, 0 }, LeftKnee = { -20, 0, 0 } }, IN),
	K(0.22, { Root = { 2, 8, 0, 0, -0.45, -0.12 }, Waist = { -14, 10, 0 }, Neck = { 8, -10, 0 }, RightShoulder = { 98, 0, 16 }, RightElbow = { 45, 0, 0 }, RightWrist = { -5, 0, 0 }, LeftShoulder = { 90, 0, -14 }, LeftElbow = { 6, 0, 0 }, LeftWrist = { -34, 0, 0 }, RightHip = { 20, 0, 0 }, RightKnee = { -36, 0, 0 }, LeftHip = { -8, 0, 0 }, LeftKnee = { -20, 0, 0 } }, OUT),
	K(0.38, { Root = { 0, 4, 0, 0, -0.12, 0 }, Waist = { -4, 14, 0 }, RightShoulder = { 60, 0, 22 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 60, 0, -30 }, LeftElbow = { 50, 0, 0 }, RightHip = { 8, 0, 0 }, RightKnee = { -14, 0, 0 } }, SOFT),
	K(0.55, {}, SOFT),
} }
-- C: channel. The staff is gathered in to the chest with a crouch, then both hands push it out and up as the body lunges.
Clips.CastBoltChannel = { name = "CastBoltChannel", priority = Action, hit = 0.12, keys = {
	K(0, {}),
	K(0.06, { Root = { 6, 0, 0, 0, -0.3, 0.15 }, Waist = { 10, 6, 0 }, Neck = { -4, -6, 0 }, RightShoulder = { 60, 0, 30 }, RightElbow = { 95, 0, 0 }, RightWrist = { 0, 0, 0 }, LeftShoulder = { 55, 0, -22 }, LeftElbow = { 100, 0, 0 }, RightHip = { -8, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftHip = { 6, 0, 0 }, LeftKnee = { -30, 0, 0 } }, OUT),
	K(0.12, { Root = { 6, 4, 0, 0, -0.5, -0.5 }, Waist = { -22, 6, 0 }, Neck = { 10, -8, 0 }, RightShoulder = { 76, 0, 12 }, RightElbow = { 14, 0, 0 }, RightWrist = { -8, 0, 0 }, LeftShoulder = { 82, 0, -20 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { -10, 0, 0 }, RightHip = { 50, 0, 3 }, RightKnee = { -56, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -16, 0, 0 } }, IN),
	K(0.2, { Root = { 6, 4, 0, 0, -0.5, -0.54 }, Waist = { -24, 6, 0 }, Neck = { 10, -8, 0 }, RightShoulder = { 80, 0, 12 }, RightElbow = { 14, 0, 0 }, RightWrist = { -8, 0, 0 }, LeftShoulder = { 84, 0, -20 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { -14, 0, 0 }, RightHip = { 50, 0, 3 }, RightKnee = { -56, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -16, 0, 0 } }, OUT),
	K(0.38, { Root = { 2, 4, 0, 0, -0.2, -0.2 }, Waist = { -8, 10, 0 }, RightShoulder = { 56, 0, 22 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 50, 0, -28 }, LeftElbow = { 60, 0, 0 }, RightHip = { 20, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftHip = { -12, 0, 0 } }, SOFT),
	K(0.55, {}, SOFT),
} }

-- (old) straight point-and-release, kept for reference; no longer built.
Clips.CastBoltPoint = { name = "CastBolt", priority = Action, hit = 0.12, keys = {
	K(0, {}),
	K(0.06, { Root = { 0, -14, 0, 0, -0.08, 0.05 }, Waist = { 2, -26, 0 }, Neck = { 0, 20, 0 }, RightShoulder = { 30, 0, 42 }, RightElbow = { 100, 0, 0 }, RightWrist = { 0, 0, 0 }, LeftShoulder = { 60, 0, -52 }, LeftElbow = { 40, 0, 0 }, RightHip = { -6, 0, 0 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -14, 0, 0 } }, OUT),
	K(0.12, { Root = { 2, 12, 0, 0, -0.12, -0.28 }, Waist = { -8, 24, 0 }, Neck = { 0, -26, 0 }, RightShoulder = { 85, 0, -6 }, RightElbow = { 6, 0, 0 }, RightWrist = { -36, 0, 0 }, LeftShoulder = { 34, 0, -74 }, LeftElbow = { 36, 0, 0 }, RightHip = { 22, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftHip = { -14, 0, 0 }, LeftKnee = { -16, 0, 0 } }, IN),
	K(0.2, { Root = { 2, 14, 0, 0, -0.1, -0.3 }, Waist = { -8, 26, 0 }, Neck = { 0, -26, 0 }, RightShoulder = { 88, 0, -8 }, RightElbow = { 6, 0, 0 }, RightWrist = { -38, 0, 0 }, LeftShoulder = { 30, 0, -80 }, LeftElbow = { 30, 0, 0 }, RightHip = { 22, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftHip = { -14, 0, 0 }, LeftKnee = { -16, 0, 0 } }, OUT),
	K(0.34, { Root = { 0, 8, 0, 0, -0.05, -0.1 }, Waist = { -2, 20, 0 }, RightShoulder = { 70, 0, 8 }, RightElbow = { 40, 0, 0 }, RightWrist = { -20, 0, 0 }, RightHip = { 8, 0, 0 }, RightKnee = { -8, 0, 0 }, LeftHip = { -6, 0, 0 } }, SOFT),
	K(0.55, {}, SOFT),
} }

-- Two-handed charge and thrust (lances, heavy bolts). Release at 0.30.
Clips.CastLance = { name = "CastLance", priority = Action, hit = 0.30, keys = {
	K(0, {}),
	K(0.16, { Root = { 4, -20, 0, 0, -0.25, 0.2 }, Waist = { 8, -36, 0 }, Neck = { 0, 26, 0 }, RightShoulder = { 25, 0, 30 }, RightElbow = { 120, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 55, 0, -34 }, LeftElbow = { 110, 0, 0 }, RightHip = { -8, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftHip = { 8, 0, 0 }, LeftKnee = { -22, 0, 0 } }, SOFT),
	K(0.26, { Root = { 5, -22, 0, 0, -0.3, 0.26 }, Waist = { 10, -40, 0 }, Neck = { 0, 28, 0 }, RightShoulder = { 22, 0, 30 }, RightElbow = { 126, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 52, 0, -34 }, LeftElbow = { 116, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -26, 0, 0 } }, LIN),
	K(0.3, { Root = { 6, 16, 0, 0, -0.5, -0.7 }, Waist = { -26, 12, 0 }, Neck = { 6, -22, 0 }, RightShoulder = { 96, 0, 6 }, RightElbow = { 0, 0, 0 }, RightWrist = { -8, 0, 0 }, LeftShoulder = { 88, 0, -26 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { 0, 0, 0 }, RightHip = { 52, 0, 3 }, RightKnee = { -58, 0, 0 }, LeftHip = { -34, 0, 0 }, LeftKnee = { -16, 0, 0 } }, IN),
	K(0.5, { Root = { 6, 16, 0, 0, -0.52, -0.74 }, Waist = { -28, 12, 0 }, Neck = { 6, -22, 0 }, RightShoulder = { 98, 0, 6 }, RightElbow = { 0, 0, 0 }, RightWrist = { -8, 0, 0 }, LeftShoulder = { 90, 0, -26 }, LeftElbow = { 8, 0, 0 }, RightHip = { 52, 0, 3 }, RightKnee = { -58, 0, 0 }, LeftHip = { -34, 0, 0 }, LeftKnee = { -16, 0, 0 } }, LIN),
	K(0.68, { Root = { 2, 8, 0, 0, -0.25, -0.3 }, Waist = { -10, 18, 0 }, RightShoulder = { 70, 0, 8 }, RightElbow = { 40, 0, 0 }, RightHip = { 24, 0, 0 }, RightKnee = { -26, 0, 0 }, LeftHip = { -14, 0, 0 }, LeftKnee = { -8, 0, 0 } }, SOFT),
	K(0.9, {}, SOFT),
} }

-- Staff raised high, then driven into the ground (area bursts). Impact at 0.35.
local SLAM = { Root = { 6, 6, 0, 0, -0.95, -0.55 }, Waist = { -38, 8, 0 }, Neck = { 22, -10, 0 }, RightShoulder = { 38, 0, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -34, 0, 0 }, LeftShoulder = { 34, 0, -20 }, LeftElbow = { 20, 0, 0 }, RightHip = { 58, 0, 6 }, RightKnee = { -74, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -14, 0, 0 } }
Clips.CastBurst = { name = "CastBurst", priority = Action, hit = 0.35, keys = {
	K(0, {}),
	K(0.18, { Root = { 0, 0, 0, 0, 0.12, 0 }, Waist = { 8, 0, 0 }, Neck = { 12, 0, 0 }, RightShoulder = { 140, 0, 28 }, RightElbow = { 40, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 130, 0, -30 }, LeftElbow = { 30, 0, 0 }, RightHip = { 0, 0, 4 }, LeftHip = { 0, 0, -4 } }, OUT),
	K(0.3, { Root = { 4, 0, 0, 0, 0.2, 0.08 }, Waist = { 14, 0, 0 }, Neck = { 18, 0, 0 }, RightShoulder = { 160, 0, 26 }, RightElbow = { 36, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 150, 0, -32 }, LeftElbow = { 24, 0, 0 }, RightHip = { 2, 0, 5 }, LeftHip = { 2, 0, -5 } }, OUT),
	K(0.35, SLAM, IN),
	K(0.55, SLAM, LIN),
	K(0.72, { Root = { 2, 4, 0, 0, -0.4, -0.2 }, Waist = { -16, 12, 0 }, RightShoulder = { 58, 0, 12 }, RightElbow = { 40, 0, 0 }, RightWrist = { -15, 0, 0 }, RightHip = { 26, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftHip = { -12, 0, 0 } }, SOFT),
	K(0.9, {}, SOFT),
} }

-- Ultimate: rises on toes, staff overhead, a full spin with arms spread, then drives the staff down. Release at 0.80.
local function spinPose(rootY, extra)
	local over = { Root = { 0, rootY, 0, 0, 0.3, 0 }, Waist = { 6, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 150, 0, 40 }, RightElbow = { 30, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 100, 0, -90 }, LeftElbow = { 10, 0, 0 }, RightHip = { 2, 0, 6 }, LeftHip = { 2, 0, -6 } }
	for n, v in pairs(extra or {}) do over[n] = v end
	return over
end
Clips.CastSigil = { name = "CastSigil", priority = Action, hit = 0.80, keys = {
	K(0, {}),
	K(0.25, { Root = { 6, -10, 0, 0, -0.35, 0.1 }, Waist = { 8, -20, 0 }, Neck = { 0, 16, 0 }, RightShoulder = { 70, 0, 40 }, RightElbow = { 90, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 60, 0, -50 }, LeftElbow = { 70, 0, 0 }, RightHip = { 6, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftKnee = { -34, 0, 0 } }, SOFT),
	K(0.4, spinPose(-20), { ease = "Cubic", dir = "Out" }),
	K(0.52, spinPose(60), LIN),
	K(0.64, spinPose(150), LIN),
	K(0.74, spinPose(250), LIN),
	K(0.8, spinPose(330, { Root = { 0, 330, 0, 0, 0.35, 0 } }), { ease = "Cubic", dir = "In", marker = "Hit" }),
	K(0.86, SLAM, { ease = "Cubic", dir = "In" }),
	K(1.25, SLAM, LIN),
	K(1.5, { Root = { 2, 4, 0, 0, -0.4, -0.2 }, Waist = { -14, 12, 0 }, RightShoulder = { 58, 0, 12 }, RightElbow = { 40, 0, 0 }, RightWrist = { -15, 0, 0 }, RightHip = { 26, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftHip = { -12, 0, 0 } }, SOFT),
	K(1.7, {}, SOFT),
} }

-- Self and ally spells (heals, wards, hastes): both arms open to the sky, a held beat, then a gentle lowering. Release at 0.25.
Clips.CastBuff = { name = "CastBuff", priority = Action, hit = 0.25, keys = {
	K(0, {}),
	K(0.14, { Root = { 0, 0, 0, 0, 0.08, 0 }, Waist = { 6, 0, 0 }, Neck = { 12, 0, 0 }, RightShoulder = { 90, 0, 50 }, RightElbow = { 60, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 80, 0, -50 }, LeftElbow = { 50, 0, 0 } }, OUT),
	K(0.25, { Root = { 2, 0, 0, 0, 0.16, 0.04 }, Waist = { 12, 0, 0 }, Neck = { 22, 0, 0 }, RightShoulder = { 125, 0, 48 }, RightElbow = { 20, 0, 0 }, RightWrist = { -12, 0, 0 }, LeftShoulder = { 115, 0, -50 }, LeftElbow = { 14, 0, 0 }, LeftWrist = { 20, 0, 0 } }, { ease = "Cubic", dir = "Out", marker = "Hit" }),
	K(0.5, { Root = { 2, 0, 0, 0, 0.16, 0.04 }, Waist = { 12, 0, 0 }, Neck = { 22, 0, 0 }, RightShoulder = { 128, 0, 50 }, RightElbow = { 20, 0, 0 }, RightWrist = { -12, 0, 0 }, LeftShoulder = { 118, 0, -52 }, LeftElbow = { 14, 0, 0 }, LeftWrist = { 20, 0, 0 } }, LIN),
	K(0.8, {}, SOFT),
} }

-- Summons and commands: a stamp, a sweeping arc of the staff, ending with a pointing gesture. Release at 0.30.
Clips.CastSummon = { name = "CastSummon", priority = Action, hit = 0.30, keys = {
	K(0, {}),
	K(0.12, { Root = { 4, -22, 0, 0, -0.3, 0.1 }, Waist = { 6, -34, 0 }, Neck = { 0, 24, 0 }, RightShoulder = { 20, 0, 60 }, RightElbow = { 40, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 70, 0, -60 }, LeftElbow = { 30, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftHip = { 6, 0, 0 }, LeftKnee = { -20, 0, 0 } }, SOFT),
	K(0.22, { Root = { 2, 0, 0, 0, -0.25, -0.1 }, Waist = { 0, -6, 0 }, RightShoulder = { 70, 0, 50 }, RightElbow = { 20, 0, 0 }, RightWrist = { -30, 0, 0 }, LeftShoulder = { 60, 0, -70 }, LeftElbow = { 20, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftKnee = { -24, 0, 0 } }, LIN),
	K(0.3, { Root = { 4, 20, 0, 0, -0.55, -0.55 }, Waist = { -20, 30, 0 }, Neck = { 4, -28, 0 }, RightShoulder = { 88, 0, -10 }, RightElbow = { 4, 0, 0 }, RightWrist = { -34, 0, 0 }, LeftShoulder = { 50, 0, -80 }, LeftElbow = { 14, 0, 0 }, LeftWrist = { 30, 0, 0 }, RightHip = { 44, 0, 3 }, RightKnee = { -50, 0, 0 }, LeftHip = { -28, 0, 0 }, LeftKnee = { -16, 0, 0 } }, IN),
	K(0.5, { Root = { 4, 20, 0, 0, -0.55, -0.58 }, Waist = { -20, 30, 0 }, Neck = { 4, -28, 0 }, RightShoulder = { 90, 0, -10 }, RightElbow = { 4, 0, 0 }, RightWrist = { -34, 0, 0 }, LeftShoulder = { 50, 0, -80 }, LeftElbow = { 14, 0, 0 }, LeftWrist = { 30, 0, 0 }, RightHip = { 44, 0, 3 }, RightKnee = { -50, 0, 0 }, LeftHip = { -28, 0, 0 }, LeftKnee = { -16, 0, 0 } }, LIN),
	K(0.9, {}, SOFT),
} }

-- Blink and short-range repositioning: a quick coil, a twisting vanish pose. Release at 0.05 (instant).
Clips.CastBlink = { name = "CastBlink", priority = Action, hit = 0.05, keys = {
	K(0, {}),
	K(0.05, { Root = { 6, -70, 0, 0, -0.5, 0 }, Waist = { 8, -40, 0 }, Neck = { 0, 40, 0 }, RightShoulder = { 20, 0, 70 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 40, 0, -70 }, LeftElbow = { 80, 0, 0 }, RightHip = { 14, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -50, 0, 0 } }, { ease = "Cubic", dir = "In", marker = "Hit" }),
	K(0.14, { Root = { 0, 80, 0, 0, -0.2, 0 }, Waist = { -6, 40, 0 }, Neck = { 0, -40, 0 }, RightShoulder = { 70, 0, 20 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 60, 0, -40 }, LeftElbow = { 50, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -26, 0, 0 } }, { ease = "Cubic", dir = "Out" }),
	K(0.45, {}, SOFT),
} }

-- Draw and sheathe.
Clips.StaffEquip = { name = "StaffEquip", priority = Action, keys = {
	K(0, {}, { base = CALM }),
	K(0.18, { RightShoulder = { 5, 0, 18 }, RightElbow = { 30, 0, 0 }, Waist = { 0, -8, 0 }, LeftShoulder = { 10, 0, -14 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.36, { RightShoulder = { 120, 0, 40 }, RightElbow = { 40, 0, 0 }, RightWrist = { -20, 0, 0 }, Waist = { 6, -14, 0 }, Neck = { 12, 0, 0 }, LeftShoulder = { 90, 0, -50 }, LeftElbow = { 40, 0, 0 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.54, { RightShoulder = { 70, 0, 14 }, RightElbow = { 30, 0, 0 }, RightWrist = { -30, 0, 0 }, Waist = { -6, 18, 0 }, Neck = { 0, -14, 0 }, LeftShoulder = { 40, 0, -50 }, LeftElbow = { 30, 0, 0 } }, { base = CALM, ease = "Cubic", dir = "In" }),
	K(0.75, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }
Clips.StaffUnequip = { name = "StaffUnequip", priority = Action, keys = {
	K(0, {}),
	K(0.22, { RightShoulder = { 60, 0, 12 }, RightElbow = { 40, 0, 0 }, Waist = { 0, 8, 0 } }, SOFT),
	K(0.5, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }

-- Stances (upper body only, Movement priority).
local function breathe(base, name, length)
	local mid = length / 2
	return { name = name, priority = Movement, loop = true, keys = {
		K(0, {}, { base = base, upper = true }),
		K(mid, { Waist = { base.Waist[1] + 2, base.Waist[2], 0 }, Neck = { base.Neck[1] - 1.5, base.Neck[2], 0 }, RightShoulder = { base.RightShoulder[1] + 2, base.RightShoulder[2], base.RightShoulder[3] + 1.5 }, LeftShoulder = { base.LeftShoulder[1] + 2.5, base.LeftShoulder[2], base.LeftShoulder[3] - 2 }, LeftElbow = { base.LeftElbow[1] + 4, 0, 0 }, LeftWrist = { 8, 0, 0 } }, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
		K(length, {}, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
	} }
end
Clips.StaffIdle = breathe(CALM, "StaffIdle", 3.4)
Clips.StaffCombatIdle = breathe(READY, "StaffCombatIdle", 2.6)

-- Dodges and reactions: the sword set's clips, re-based so they start and end in the staff stance (otherwise the arms
-- would snap to the sword guard when the clip ends).
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
	Clips["Staff" .. name] = rebase(Sword[name], "Staff" .. name)
end
-- Casts hold the staff in both hands: the build step (see Builder.solveTwoHand) places the left hand on the shaft in
-- every key of these clips, wherever the right hand takes the staff. Keys marked `free` are left as authored.
for _, name in ipairs({ "CastBolt", "CastBoltRaise", "CastBoltChannel", "CastLance", "CastBurst", "CastBuff", "CastSummon", "StaffCombatIdle" }) do
	Clips[name].twoHand = true
end

Clips.order = { "CastBolt", "CastBoltRaise", "CastBoltChannel", "CastLance", "CastBurst", "CastSigil", "CastBuff", "CastSummon", "CastBlink", "StaffEquip", "StaffUnequip", "StaffIdle", "StaffCombatIdle", "StaffDodge", "StaffDodgeForward", "StaffDodgeLeft", "StaffDodgeRight", "StaffHitReactLight", "StaffHitReactHeavy", "StaffStagger" }

return Clips
