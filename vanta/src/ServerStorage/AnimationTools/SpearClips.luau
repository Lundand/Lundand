--!nonstrict
-- Spear set (Thunder Sovereign): long reach, a two-handed grip. The grip is -135, so with the arm bent so that the shoulder and elbow
-- rotations add up to 45 degrees the spear points level, 135 degrees points it straight up, 0 points it down and forward. The build
-- step puts the left hand on the shaft in every key (Builder.solveTwoHand), so only the right arm and the body are authored here.
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
	Waist = { 0, 18, 0 }, Neck = { 0, -14, 0 },
	RightShoulder = { 40, 0, -10 }, RightElbow = { 55, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 30, 0, -40 }, LeftElbow = { 80, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CALM = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 50, 0, 16 }, RightElbow = { 85, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 8, 0, -9 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local kit = ClipKit.new("Spear", READY, CALM, { twoHand = true })
local K, IN, OUT, SOFT, LIN = kit.K, ClipKit.IN, ClipKit.OUT, ClipKit.SOFT, ClipKit.LIN
local Clips = {}

-- Basic attacks (0.55 long, strike at 0.15; the Animator alternates them). A: straight thrust. B: a sweep across the front.
-- C: a hop with a downward thrust.
local THRUST_WIND = { Root = { 4, -16, 0, 0, -0.35, 0.18 }, Waist = { 4, -30, 0 }, Neck = { 0, 24, 0 }, RightShoulder = { -10, 0, 0 }, RightElbow = { 55, 0, 0 }, RightHip = { -6, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftHip = { 8, 0, 0 }, LeftKnee = { -22, 0, 0 } }
local THRUST_HIT = { Root = { 6, 12, 0, 0, -0.55, -0.9 }, Waist = { -18, 12, 0 }, Neck = { 6, -14, 0 }, RightShoulder = { 45, 0, 0 }, RightElbow = { 0, 0, 0 }, RightHip = { 52, 0, 3 }, RightKnee = { -58, 0, 0 }, LeftHip = { -34, 0, 0 }, LeftKnee = { -16, 0, 0 } }
Clips.SpearThrust = kit.clip("SpearThrust", 0.15, {
	K(0, {}), K(0.08, THRUST_WIND, SOFT), K(0.15, THRUST_HIT, IN), K(0.26, THRUST_HIT, LIN), K(0.4, with(THRUST_HIT, { Root = { 4, 8, 0, 0, -0.3, -0.35 }, RightHip = { 28, 0, 0 }, RightKnee = { -30, 0, 0 } }), SOFT), K(0.55, {}, SOFT),
}, { alternates = { "SpearThrust", "SpearSweep", "SpearLeap" } })
local SWEEP_WIND = { Root = { 2, -34, 0, 0, -0.3, 0.1 }, Waist = { 0, -56, 0 }, Neck = { 0, 48, 0 }, RightShoulder = { 45, 0, 10 }, RightElbow = { 0, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightHip = { 10, 0, 0 }, LeftHip = { 6, 0, 0 } }
local SWEEP_HIT = { Root = { 4, 34, 0, 0, -0.4, -0.3 }, Waist = { -8, 58, 0 }, Neck = { 0, -50, 0 }, RightShoulder = { 45, 0, 10 }, RightElbow = { 0, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftKnee = { -26, 0, 0 }, RightHip = { 30, 0, 0 }, LeftHip = { -20, 0, 0 } }
Clips.SpearSweep = kit.clip("SpearSweep", 0.15, {
	K(0, {}), K(0.08, SWEEP_WIND, SOFT), K(0.15, SWEEP_HIT, IN), K(0.28, with(SWEEP_HIT, { Root = { 4, 46, 0, 0, -0.4, -0.3 }, Waist = { -8, 66, 0 } }), OUT), K(0.42, with(SWEEP_HIT, { Root = { 2, 12, 0, 0, -0.15, -0.1 }, Waist = { -4, 30, 0 } }), SOFT), K(0.55, {}, SOFT),
})
local LEAP_WIND = { Root = { 8, -6, 0, 0, -0.6, 0.1 }, Waist = { 8, -20, 0 }, Neck = { 6, 14, 0 }, RightShoulder = { 95, 0, 0 }, RightElbow = { 40, 0, 0 }, RightHip = { 10, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -60, 0, 0 } }
local LEAP_HIT = { Root = { -6, 8, 0, 0, 0.3, -1.2 }, Waist = { -26, 8, 0 }, Neck = { 8, -10, 0 }, RightShoulder = { 20, 0, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -8, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } }
Clips.SpearLeap = kit.clip("SpearLeap", 0.15, {
	K(0, {}), K(0.07, LEAP_WIND, OUT), K(0.15, LEAP_HIT, IN), K(0.26, with(LEAP_HIT, { Root = { -4, 8, 0, 0, -0.5, -1.3 } }), LIN), K(0.42, with(LEAP_HIT, { Root = { 2, 6, 0, 0, -0.3, -0.5 }, RightHip = { 20, 0, 0 }, RightKnee = { -30, 0, 0 } }), SOFT), K(0.55, {}, SOFT),
})

-- Thunder Thrust (windup 0.12): a deeper, harder lunge than the basic thrust.
local LUNGE_HIT = with(THRUST_HIT, { Root = { 6, 14, 0, 0, -0.75, -1.35 }, RightShoulder = { 48, 0, 0 }, RightHip = { 62, 0, 3 }, RightKnee = { -70, 0, 0 }, LeftHip = { -44, 0, 0 } })
Clips.SpearLunge = kit.clip("SpearLunge", 0.12, {
	K(0, {}), K(0.06, with(THRUST_WIND, { Waist = { 4, -42, 0 }, RightShoulder = { -14, 0, 0 }, RightElbow = { 62, 0, 0 } }), OUT), K(0.12, LUNGE_HIT, IN), K(0.3, LUNGE_HIT, LIN), K(0.45, with(LUNGE_HIT, { Root = { 4, 8, 0, 0, -0.35, -0.4 }, RightHip = { 28, 0, 0 }, RightKnee = { -30, 0, 0 } }), SOFT), K(0.6, {}, SOFT),
})

-- Stormstep (windup 0): the spear planted, then a spinning vault over it. The blink moves the character; this is the body.
Clips.SpearVault = kit.clip("SpearVault", 0.05, {
	K(0, {}),
	K(0.05, { Root = { 8, -40, 0, 0, -0.75, 0 }, Waist = { 8, -20, 0 }, RightShoulder = { 20, 0, 0 }, RightElbow = { 0, 0, 0 }, RightHip = { 36, 0, 0 }, RightKnee = { -80, 0, 0 }, LeftHip = { 36, 0, 0 }, LeftKnee = { -80, 0, 0 } }, { ease = "Cubic", dir = "In", marker = "Hit" }),
	K(0.14, { Root = { 2, 90, 0, 0, 0.85, 0 }, Waist = { 0, 10, 0 }, RightShoulder = { 100, 0, 0 }, RightElbow = { 40, 0, 0 }, RightHip = { 50, 0, 0 }, RightKnee = { -70, 0, 0 }, LeftHip = { 50, 0, 0 }, LeftKnee = { -70, 0, 0 } }, LIN),
	K(0.24, { Root = { 2, 240, 0, 0, 0.6, 0 }, Waist = { 0, 10, 0 }, RightShoulder = { 100, 0, 0 }, RightElbow = { 40, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { 30, 0, 0 }, LeftKnee = { -50, 0, 0 } }, LIN),
	K(0.34, { Root = { 6, 362, 0, 0, -0.4, -0.2 }, Waist = { -16, 14, 0 }, RightShoulder = { 30, 0, 0 }, RightElbow = { 10, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -50, 0, 0 } }, OUT),
	K(0.5, { Root = { 0, 360, 0 } }, SOFT),
})

-- Chain Spark (windup 0.25): the spear raised overhead and shaken as the charge builds, then jabbed forward and up.
local RAISED = { Root = { 2, 0, 0, 0, 0.12, 0 }, Waist = { 8, 0, 0 }, Neck = { 12, 0, 0 }, RightShoulder = { 150, 0, 6 }, RightElbow = { 20, 0, 0 }, RightHip = { 0, 0, 4 }, LeftHip = { 0, 0, -4 } }
Clips.SpearConduct = kit.clip("SpearConduct", 0.25, {
	K(0, {}), K(0.1, RAISED, OUT), K(0.15, with(RAISED, { RightShoulder = { 154, 0, 10 }, Waist = { 8, 4, 0 } }), LIN), K(0.2, with(RAISED, { RightShoulder = { 146, 0, 2 }, Waist = { 8, -4, 0 } }), LIN),
	K(0.25, { Root = { 6, 10, 0, 0, -0.45, -0.7 }, Waist = { -16, 10, 0 }, Neck = { 6, -12, 0 }, RightShoulder = { 70, 0, 0 }, RightElbow = { 0, 0, 0 }, RightHip = { 46, 0, 3 }, RightKnee = { -52, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -16, 0, 0 } }, IN),
	K(0.5, { Root = { 6, 10, 0, 0, -0.45, -0.72 }, Waist = { -16, 10, 0 }, Neck = { 6, -12, 0 }, RightShoulder = { 72, 0, 0 }, RightElbow = { 0, 0, 0 }, RightHip = { 46, 0, 3 }, RightKnee = { -52, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -16, 0, 0 } }, LIN), K(0.8, {}, SOFT),
})

-- Heaven's Spear (windup 0.6): a deep coil, a high leap with the spear raised, then a diving thrust to the ground.
local DIVE_HIT = { Root = { -34, 8, 0, 0, -0.6, -1.5 }, Waist = { -24, 8, 0 }, Neck = { 12, -10, 0 }, RightShoulder = { 22, 0, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -8, 0, 0 }, RightHip = { 56, 0, 3 }, RightKnee = { -66, 0, 0 }, LeftHip = { -36, 0, 0 }, LeftKnee = { -20, 0, 0 } }
Clips.SpearDive = kit.clip("SpearDive", 0.60, {
	K(0, {}),
	K(0.18, { Root = { 6, -20, 0, 0, -0.8, 0.2 }, Waist = { 6, -34, 0 }, Neck = { 0, 28, 0 }, RightShoulder = { -8, 0, 0 }, RightElbow = { 53, 0, 0 }, RightHip = { 6, 0, 0 }, RightKnee = { -76, 0, 0 }, LeftHip = { 6, 0, 0 }, LeftKnee = { -70, 0, 0 } }, SOFT),
	K(0.36, { Root = { 2, 0, 0, 0, 1.6, 0 }, Waist = { 8, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 110, 0, 6 }, RightElbow = { 25, 0, 0 }, RightHip = { 10, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -50, 0, 0 } }, OUT),
	K(0.5, { Root = { 6, 0, 0, 0, 2.0, -0.6 }, Waist = { 0, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 70, 0, 4 }, RightElbow = { 25, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftHip = { 20, 0, 0 }, LeftKnee = { -30, 0, 0 } }, LIN),
	K(0.6, DIVE_HIT, IN),
	K(1.0, DIVE_HIT, LIN),
	K(1.25, { Root = { 6, 8, 0, 0, -0.5, -0.5 }, Waist = { -14, 10, 0 }, RightShoulder = { 40, 0, 0 }, RightElbow = { 30, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -40, 0, 0 } }, SOFT),
	K(1.5, {}, SOFT),
})

-- Draw and sheathe: the spear spun up from the side and brought down level.
kit.equipUnequip(Clips, {
	{ t = 0.18, j = { RightShoulder = { 100, 0, 30 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 60, 0, 0 }, Waist = { 4, -10, 0 } } },
	{ t = 0.38, j = { RightShoulder = { 160, 0, 14 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 100, 0, -20 }, LeftElbow = { 40, 0, 0 }, Waist = { 8, 0, 0 }, Neck = { 12, 0, 0 } } },
	{ t = 0.58, j = { RightShoulder = { 46, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 60, 0, -20 }, LeftElbow = { 30, 0, 0 }, Waist = { -8, 16, 0 } }, ease = "Cubic", dir = "In" },
})
Clips.SpearIdle = kit.breathe(CALM, "SpearIdle", 3.4, false)
Clips.SpearCombatIdle = kit.breathe(READY, "SpearCombatIdle", 2.4, true)
kit.addVariants(Clips)

Clips.order = kit.order({ "SpearThrust", "SpearSweep", "SpearLeap", "SpearLunge", "SpearVault", "SpearConduct", "SpearDive" })

return Clips
