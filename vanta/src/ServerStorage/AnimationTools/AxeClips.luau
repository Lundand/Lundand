--!nonstrict
-- Greataxe set (Worldbreaker Berserker): brutal, heavy, two-handed. Grip -135: with shoulder and elbow adding up to about 105 degrees the axe
-- head points up and forward, 170 points it up over the head, 10 drives it down and forward. The build step places the left
-- hand on the haft in every key, so only the right arm and the body are authored here.
local function fresh(module)
	local copy = module:Clone()
	copy.Parent = module.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	assert(ok, result)
	return result
end
local ClipKit = fresh(script.Parent.ClipKit)
local with = ClipKit.with

local READY = {
	Waist = { 0, 14, 0 }, Neck = { 0, -12, 0 },
	RightShoulder = { 35, 0, 8 }, RightElbow = { 70, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 40, 0, -30 }, LeftElbow = { 80, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CALM = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 18, 0, 12 }, RightElbow = { 80, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 8, 0, -9 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local kit = ClipKit.new("Axe", READY, CALM, { twoHand = true })
local K, IN, OUT, SOFT, LIN = kit.K, ClipKit.IN, ClipKit.OUT, ClipKit.SOFT, ClipKit.LIN
local Clips = {}

-- Basic attacks (0.95 long, strike at 0.30; alternated). A: overhead chop. B: horizontal cleave. C: rising upswing.
local CHOP_UP = { Root = { 10, -8, 0, 0, 0.06, 0.2 }, Waist = { 14, -12, 0 }, Neck = { 8, 12, 0 }, RightShoulder = { 150, 0, 6 }, RightElbow = { 25, 0, 0 }, RightHip = { -8, 0, 0 }, RightKnee = { -16, 0, 0 }, LeftHip = { 8, 0, 0 }, LeftKnee = { -10, 0, 0 } }
local CHOP_HIT = { Root = { 8, 10, 0, 0, -0.8, -0.65 }, Waist = { -36, 12, 0 }, Neck = { 14, -12, 0 }, RightShoulder = { 30, 0, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -20, 0, 0 }, RightHip = { 56, 0, 4 }, RightKnee = { -72, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -16, 0, 0 } }
Clips.AxeCleave = kit.clip("AxeCleave", 0.30, {
	K(0, {}), K(0.16, with(CHOP_UP, { RightShoulder = { 110, 0, 10 } }), SOFT), K(0.27, with(CHOP_UP, { RightShoulder = { 164, 0, 6 }, Root = { 12, -8, 0, 0, 0.12, 0.25 } }), OUT), K(0.3, CHOP_HIT, IN), K(0.5, CHOP_HIT, LIN),
	K(0.72, with(CHOP_HIT, { Root = { 4, 8, 0, 0, -0.3, -0.25 }, Waist = { -12, 14, 0 }, RightShoulder = { 55, 0, 10 }, RightElbow = { 40, 0, 0 }, RightHip = { 26, 0, 0 }, RightKnee = { -34, 0, 0 } }), SOFT), K(0.95, {}, SOFT),
}, { alternates = { "AxeCleave", "AxeCleaveSweep", "AxeCleaveRise" } })
local SWEEP_WIND = { Root = { 2, -38, 0, 0, -0.4, 0.12 }, Waist = { 0, -62, 0 }, Neck = { 0, 54, 0 }, RightShoulder = { 50, 0, 20 }, RightElbow = { 0, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftKnee = { -34, 0, 0 }, RightHip = { 10, 0, 0 }, LeftHip = { 6, 0, 0 } }
local SWEEP_HIT = { Root = { 6, 38, 0, 0, -0.5, -0.35 }, Waist = { -12, 64, 0 }, Neck = { 0, -56, 0 }, RightShoulder = { 50, 0, 20 }, RightElbow = { 0, 0, 0 }, RightKnee = { -44, 0, 0 }, LeftKnee = { -28, 0, 0 }, RightHip = { 34, 0, 0 }, LeftHip = { -22, 0, 0 } }
Clips.AxeCleaveSweep = kit.clip("AxeCleaveSweep", 0.30, {
	K(0, {}), K(0.2, SWEEP_WIND, SOFT), K(0.3, SWEEP_HIT, IN), K(0.46, with(SWEEP_HIT, { Root = { 6, 52, 0, 0, -0.5, -0.35 }, Waist = { -12, 76, 0 } }), OUT), K(0.7, with(SWEEP_HIT, { Root = { 2, 14, 0, 0, -0.2, -0.1 }, Waist = { -4, 34, 0 } }), SOFT), K(0.95, {}, SOFT),
})
local RISE_WIND = { Root = { 10, -20, 0, 0, -0.9, 0.2 }, Waist = { 14, -30, 0 }, Neck = { 6, 20, 0 }, RightShoulder = { 10, 0, 24 }, RightElbow = { 10, 0, 0 }, RightHip = { 14, 0, 6 }, RightKnee = { -70, 0, 0 }, LeftHip = { 14, 0, -6 }, LeftKnee = { -66, 0, 0 } }
local RISE_HIT = { Root = { -4, 16, 0, 0, -0.1, -0.6 }, Waist = { 16, 22, 0 }, Neck = { 14, -14, 0 }, RightShoulder = { 130, 0, -8 }, RightElbow = { 20, 0, 0 }, RightHip = { 40, 0, 3 }, RightKnee = { -46, 0, 0 }, LeftHip = { -26, 0, 0 }, LeftKnee = { -20, 0, 0 } }
Clips.AxeCleaveRise = kit.clip("AxeCleaveRise", 0.30, {
	K(0, {}), K(0.2, RISE_WIND, SOFT), K(0.3, RISE_HIT, IN), K(0.5, with(RISE_HIT, { RightShoulder = { 150, 0, -8 }, Waist = { 20, 24, 0 }, Root = { -6, 18, 0, 0, 0.1, -0.6 } }), OUT), K(0.72, with(RISE_HIT, { Root = { 4, 8, 0, 0, -0.3, -0.2 }, Waist = { -4, 16, 0 }, RightShoulder = { 70, 0, 10 }, RightElbow = { 40, 0, 0 } }), SOFT), K(0.95, {}, SOFT),
})

-- Bloodrush (windup 0.05, a 0.3 s dash, the swipe lands 0.25 in): the axe dragged back low in a charge, then a flat swipe.
local RUSH = { Root = { -14, 0, 0, 0, -0.3, -0.3 }, Waist = { -26, 20, 0 }, Neck = { 14, -12, 0 }, RightShoulder = { -14, 0, 14 }, RightElbow = { 14, 0, 0 }, RightHip = { 46, 0, 0 }, RightKnee = { -56, 0, 0 }, LeftHip = { -36, 0, 0 }, LeftKnee = { -26, 0, 0 } }
Clips.AxeRush = kit.clip("AxeRush", 0.05, {
	K(0, {}), K(0.05, RUSH, OUT), K(0.15, with(RUSH, { RightHip = { -34, 0, 0 }, LeftHip = { 42, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -56, 0, 0 } }), LIN),
	K(0.25, { Root = { 4, 40, 0, 0, -0.5, -0.6 }, Waist = { -14, 60, 0 }, Neck = { 0, -52, 0 }, RightShoulder = { 50, 0, 20 }, RightElbow = { 0, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -48, 0, 0 }, LeftHip = { -26, 0, 0 }, LeftKnee = { -26, 0, 0 } }, IN),
	K(0.4, { Root = { 4, 52, 0, 0, -0.4, -0.5 }, Waist = { -12, 72, 0 }, RightShoulder = { 50, 0, 20 }, RightElbow = { 0, 0, 0 } }, OUT), K(0.75, {}, SOFT),
})

-- Fury Breaker (windup 0.45): a deep crouch, a leap with the axe overhead, and a crashing chop.
Clips.AxeBreaker = kit.clip("AxeBreaker", 0.45, {
	K(0, {}),
	K(0.16, with(CHOP_UP, { Root = { 12, -10, 0, 0, -0.85, 0.2 }, RightShoulder = { 120, 0, 8 }, RightKnee = { -76, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { 20, 0, 0 }, LeftHip = { 18, 0, 0 } }), SOFT),
	K(0.32, with(CHOP_UP, { Root = { 8, -8, 0, 0, 1.0, 0.1 }, RightShoulder = { 168, 0, 8 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -46, 0, 0 } }), OUT),
	K(0.4, with(CHOP_UP, { Root = { 10, -8, 0, 0, 1.1, 0.1 }, RightShoulder = { 170, 0, 8 }, RightKnee = { -40, 0, 0 }, LeftKnee = { -36, 0, 0 } }), LIN),
	K(0.45, with(CHOP_HIT, { Root = { 12, 10, 0, 0, -1.0, -0.8 } }), IN),
	K(0.7, with(CHOP_HIT, { Root = { 12, 10, 0, 0, -1.0, -0.8 } }), LIN),
	K(0.88, with(CHOP_HIT, { Root = { 4, 8, 0, 0, -0.4, -0.3 }, Waist = { -14, 14, 0 }, RightShoulder = { 55, 0, 10 }, RightElbow = { 40, 0, 0 } }), SOFT),
	K(1.05, {}, SOFT),
})

-- Unyielding Rage (windup 0.2): the axe thrown overhead with a roar, the chest out, then slammed down beside the feet.
local ROAR = { Root = { 6, 0, 0, 0, 0.1, 0.1 }, Waist = { 18, 0, 0 }, Neck = { 34, 0, 0 }, RightShoulder = { 150, 0, 14 }, RightElbow = { 20, 0, 0 }, RightHip = { 0, 0, 8 }, LeftHip = { 0, 0, -8 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -20, 0, 0 } }
Clips.AxeRoar = kit.clip("AxeRoar", 0.20, {
	K(0, {}), K(0.1, ROAR, OUT), K(0.15, with(ROAR, { Neck = { 38, 4, 0 }, Waist = { 20, 3, 0 } }), LIN),
	K(0.2, with(CHOP_HIT, { Root = { 10, 0, 0, 0, -0.9, -0.4 }, RightHip = { 30, 0, 24 }, LeftHip = { 30, 0, -24 }, RightKnee = { -76, 0, 0 }, LeftKnee = { -76, 0, 0 } }), IN),
	K(0.5, with(CHOP_HIT, { Root = { 10, 0, 0, 0, -0.9, -0.4 }, RightHip = { 30, 0, 24 }, LeftHip = { 30, 0, -24 }, RightKnee = { -76, 0, 0 }, LeftKnee = { -76, 0, 0 } }), LIN), K(0.8, {}, SOFT),
})

-- Worldsplitter (windup 0.8): a deep coil, a full spin with the axe held out level, a rise with the axe overhead, then a ground-splitting blow.
local SPIN = { Waist = { -6, 0, 0 }, RightShoulder = { 50, 0, 20 }, RightElbow = { 0, 0, 0 }, RightHip = { 14, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { -8, 0, 0 }, LeftKnee = { -44, 0, 0 } }
local function spin(yaw) return with(SPIN, { Root = { 0, yaw, 0, 0, -0.55, 0 } }) end
Clips.AxeSplit = kit.clip("AxeSplit", 0.80, {
	K(0, {}),
	K(0.2, with(spin(-70), { Waist = { 0, -50, 0 }, Neck = { 0, 40, 0 } }), SOFT),
	K(0.34, spin(30), LIN), K(0.46, spin(150), LIN), K(0.58, spin(270), LIN), K(0.68, spin(380), LIN),
	K(0.74, with(CHOP_UP, { Root = { 6, 362, 0, 0, 0.5, 0.1 }, RightShoulder = { 168, 0, 8 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } }), OUT),
	K(0.8, with(CHOP_HIT, { Root = { 12, 360, 0, 0, -1.2, -0.8 } }), IN),
	K(1.2, with(CHOP_HIT, { Root = { 12, 360, 0, 0, -1.2, -0.8 } }), LIN),
	K(1.45, with(CHOP_HIT, { Root = { 4, 360, 0, 0, -0.5, -0.3 }, Waist = { -14, 14, 0 }, RightShoulder = { 55, 0, 10 }, RightElbow = { 40, 0, 0 } }), SOFT),
	K(1.7, { Root = { 0, 360, 0 } }, SOFT),
})

kit.equipUnequip(Clips, {
	{ t = 0.2, j = { RightShoulder = { 60, 0, 44 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 60, 0, 0 }, Waist = { 0, -14, 0 } } },
	{ t = 0.42, j = { RightShoulder = { 140, 0, 20 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 90, 0, -30 }, LeftElbow = { 50, 0, 0 }, Waist = { 10, 0, 0 } } },
	{ t = 0.62, j = { RightShoulder = { 36, 0, 8 }, RightElbow = { 66, 0, 0 }, LeftShoulder = { 40, 0, -30 }, LeftElbow = { 70, 0, 0 }, Waist = { -14, 16, 0 } }, ease = "Cubic", dir = "In" },
})
Clips.AxeIdle = kit.breathe(CALM, "AxeIdle", 3.6, false)
Clips.AxeCombatIdle = kit.breathe(READY, "AxeCombatIdle", 2.6, true)
kit.addVariants(Clips)

Clips.order = kit.order({ "AxeCleave", "AxeCleaveSweep", "AxeCleaveRise", "AxeRush", "AxeBreaker", "AxeRoar", "AxeSplit" })

return Clips
