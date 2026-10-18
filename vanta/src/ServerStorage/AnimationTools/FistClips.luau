--!nonstrict
-- Fist set (Brawler): a knuckle guard on each hand, a boxing stance, and kicks. Same joint conventions as SwordClips.
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
	RightShoulder = { 50, 0, 14 }, RightElbow = { 118, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 50, 0, -14 }, LeftElbow = { 118, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CALM = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 6, 0, 10 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 6, 0, -10 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local kit = ClipKit.new("Fist", READY, CALM, {})
local K, IN, OUT, SOFT, LIN = kit.K, ClipKit.IN, ClipKit.OUT, ClipKit.SOFT, ClipKit.LIN
local Clips = {}
local STEP = { RightHip = { -10, 0, 8 }, LeftHip = { 10, 0, -8 }, RightKnee = { -18, 0, 0 }, LeftKnee = { -22, 0, 0 } }

-- Basic strikes (0.36 long, strike at 0.08; alternated): a left jab, a right cross, a left hook, a right uppercut.
Clips.FistJab = kit.clip("FistJab", 0.08, {
	K(0, {}), K(0.04, with(STEP, { LeftShoulder = { 60, 0, -10 }, LeftElbow = { 135, 0, 0 }, Waist = { 0, 22, 0 } }), OUT),
	K(0.08, with(STEP, { LeftShoulder = { 88, 0, -6 }, LeftElbow = { 2, 0, 0 }, Waist = { -4, 8, 0 }, Root = { 2, 6, 0, 0, -0.2, -0.45 }, LeftHip = { 24, 0, -8 }, LeftKnee = { -28, 0, 0 } }), IN),
	K(0.16, with(STEP, { LeftShoulder = { 90, 0, -6 }, LeftElbow = { 4, 0, 0 }, Waist = { -4, 8, 0 }, Root = { 2, 6, 0, 0, -0.2, -0.45 }, LeftHip = { 24, 0, -8 }, LeftKnee = { -28, 0, 0 } }), OUT), K(0.36, {}, SOFT),
}, { alternates = { "FistJab", "FistCross", "FistHook", "FistUpper" } })
Clips.FistCross = kit.clip("FistCross", 0.08, {
	K(0, {}), K(0.04, with(STEP, { RightShoulder = { 55, 0, 22 }, RightElbow = { 130, 0, 0 }, Waist = { 0, 36, 0 }, Root = { 0, 10, 0, 0, -0.1, 0.05 } }), OUT),
	K(0.08, with(STEP, { RightShoulder = { 88, 0, -8 }, RightElbow = { 2, 0, 0 }, Waist = { -6, -22, 0 }, Neck = { 0, 18, 0 }, Root = { 2, -14, 0, 0, -0.25, -0.6 }, LeftHip = { 28, 0, -8 }, LeftKnee = { -34, 0, 0 }, RightHip = { -22, 0, 8 }, RightKnee = { -10, 0, 0 } }), IN),
	K(0.17, with(STEP, { RightShoulder = { 90, 0, -8 }, RightElbow = { 4, 0, 0 }, Waist = { -6, -24, 0 }, Neck = { 0, 18, 0 }, Root = { 2, -16, 0, 0, -0.25, -0.62 }, LeftHip = { 28, 0, -8 }, LeftKnee = { -34, 0, 0 }, RightHip = { -22, 0, 8 }, RightKnee = { -10, 0, 0 } }), OUT), K(0.36, {}, SOFT),
})
Clips.FistHook = kit.clip("FistHook", 0.08, {
	K(0, {}), K(0.04, with(STEP, { LeftShoulder = { 72, 0, -74 }, LeftElbow = { 98, 0, 0 }, Waist = { 0, -30, 0 }, Root = { 0, -14, 0, 0, -0.15, 0 } }), OUT),
	K(0.08, with(STEP, { LeftShoulder = { 82, 0, -6 }, LeftElbow = { 96, 0, 0 }, Waist = { -4, 44, 0 }, Neck = { 0, -34, 0 }, Root = { 2, 30, 0, 0, -0.25, -0.3 }, LeftHip = { 16, 0, -8 }, LeftKnee = { -24, 0, 0 } }), IN),
	K(0.17, with(STEP, { LeftShoulder = { 84, 0, -2 }, LeftElbow = { 94, 0, 0 }, Waist = { -4, 50, 0 }, Neck = { 0, -38, 0 }, Root = { 2, 34, 0, 0, -0.25, -0.3 } }), OUT), K(0.36, {}, SOFT),
})
Clips.FistUpper = kit.clip("FistUpper", 0.08, {
	K(0, {}), K(0.04, with(STEP, { RightShoulder = { 18, 0, 12 }, RightElbow = { 125, 0, 0 }, Waist = { 8, 20, 0 }, Root = { 6, 6, 0, 0, -0.55, 0.05 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -48, 0, 0 } }), OUT),
	K(0.08, with(STEP, { RightShoulder = { 132, 0, 4 }, RightElbow = { 62, 0, 0 }, Waist = { 12, -14, 0 }, Neck = { 8, 10, 0 }, Root = { -2, -10, 0, 0, 0.12, -0.3 }, RightKnee = { -12, 0, 0 }, LeftKnee = { -14, 0, 0 } }), IN),
	K(0.17, with(STEP, { RightShoulder = { 138, 0, 4 }, RightElbow = { 56, 0, 0 }, Waist = { 14, -16, 0 }, Neck = { 8, 10, 0 }, Root = { -2, -12, 0, 0, 0.1, -0.3 } }), OUT), K(0.36, {}, SOFT),
})

-- Heavy Punch (windup 0.35): the whole body coils back, then a long overhand right.
local HAY_HIT = { Root = { 8, -30, 0, 0, -0.85, -1.0 }, Waist = { -24, -56, 0 }, Neck = { 6, 44, 0 }, RightShoulder = { 96, 0, -22 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 60, 0, -30 }, LeftElbow = { 110, 0, 0 }, RightHip = { -30, 0, 10 }, RightKnee = { -14, 0, 0 }, LeftHip = { 56, 0, -8 }, LeftKnee = { -70, 0, 0 } }
Clips.FistHaymaker = kit.clip("FistHaymaker", 0.35, {
	K(0, {}),
	K(0.22, { Root = { 6, 28, 0, 0, -0.6, 0.35 }, Waist = { 10, 54, 0 }, Neck = { 0, -40, 0 }, RightShoulder = { 150, 0, 54 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 50, 0, -30 }, LeftElbow = { 110, 0, 0 }, RightHip = { -6, 0, 8 }, RightKnee = { -50, 0, 0 }, LeftHip = { 10, 0, -8 }, LeftKnee = { -40, 0, 0 } }, SOFT),
	K(0.3, { Root = { 6, 32, 0, 0, -0.65, 0.4 }, Waist = { 12, 60, 0 }, Neck = { 0, -44, 0 }, RightShoulder = { 160, 0, 58 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 50, 0, -30 }, LeftElbow = { 110, 0, 0 }, RightHip = { -6, 0, 8 }, RightKnee = { -56, 0, 0 }, LeftHip = { 10, 0, -8 }, LeftKnee = { -44, 0, 0 } }, OUT),
	K(0.35, HAY_HIT, IN), K(0.5, with(HAY_HIT, { Waist = { -24, -62, 0 } }), LIN), K(0.62, with(HAY_HIT, { Root = { 4, -10, 0, 0, -0.3, -0.3 }, Waist = { -8, -20, 0 }, RightShoulder = { 70, 0, 10 } }), SOFT), K(0.75, {}, SOFT),
})

-- Sweeping Kick (windup 0.2): a low crouching spin with the leg flung out level, both arms out for balance.
local KICK = { Waist = { -6, 0, 0 }, RightShoulder = { 80, 0, 70 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 80, 0, -70 }, LeftElbow = { 10, 0, 0 }, RightHip = { 20, 0, 70 }, RightKnee = { -4, 0, 0 }, LeftHip = { 10, 0, -6 }, LeftKnee = { -60, 0, 0 } }
local function kick(yaw, extra) return with(with(KICK, { Root = { 6, yaw, 0, 0, -0.75, 0 } }), extra or {}) end
Clips.FistKick = kit.clip("FistKick", 0.20, {
	K(0, {}),
	K(0.1, with(kick(-120), { RightHip = { 10, 0, 20 }, RightKnee = { -70, 0, 0 }, RightShoulder = { 60, 0, 40 }, LeftShoulder = { 60, 0, -40 } }), SOFT),
	K(0.2, kick(20), IN), K(0.32, kick(200), LIN), K(0.42, kick(310), LIN),
	K(0.5, with(kick(362), { Root = { 4, 362, 0, 0, -0.4, 0 }, RightHip = { 10, 0, 20 }, RightKnee = { -40, 0, 0 } }), OUT), K(0.65, { Root = { 0, 360, 0 } }, SOFT),
})

-- Counter Stance (windup 0): crouched behind crossed forearms, held, then a slip back to guard.
local COVER = { Root = { 8, -4, 0, 0, -0.5, 0 }, Waist = { -12, 10, 0 }, Neck = { 12, -8, 0 }, RightShoulder = { 112, 0, -10 }, RightElbow = { 132, 0, 0 }, LeftShoulder = { 112, 0, 10 }, LeftElbow = { 132, 0, 0 }, RightHip = { 14, 0, 8 }, LeftHip = { 14, 0, -8 }, RightKnee = { -56, 0, 0 }, LeftKnee = { -56, 0, 0 } }
Clips.FistCounter = kit.clip("FistCounter", 0.05, {
	K(0, {}), K(0.07, COVER, { ease = "Cubic", dir = "Out", marker = "Hit" }), K(0.2, with(COVER, { Root = { 8, -4, 0, 0, -0.55, 0.04 } }), LIN), K(0.5, with(COVER, { Root = { 8, -4, 0, 0, -0.5, 0 } }), LIN), K(0.7, {}, SOFT),
})

-- Iron Fist Cataclysm (windup 0.6): a deep coil, a high leap with both fists overhead, then a double-fisted ground pound.
local POUND = { Root = { 10, 0, 0, 0, -1.15, -0.4 }, Waist = { -46, 0, 0 }, Neck = { 20, 0, 0 }, RightShoulder = { 34, 0, 12 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 34, 0, -12 }, LeftElbow = { 6, 0, 0 }, RightHip = { 50, 0, 20 }, LeftHip = { 50, 0, -20 }, RightKnee = { -86, 0, 0 }, LeftKnee = { -86, 0, 0 } }
Clips.FistPound = kit.clip("FistPound", 0.60, {
	K(0, {}),
	K(0.2, { Root = { 8, 0, 0, 0, -0.85, 0.15 }, Waist = { 6, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 0, 0, 20 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 0, 0, -20 }, LeftElbow = { 90, 0, 0 }, RightHip = { 20, 0, 12 }, LeftHip = { 20, 0, -12 }, RightKnee = { -82, 0, 0 }, LeftKnee = { -82, 0, 0 } }, SOFT),
	K(0.4, { Root = { 2, 0, 0, 0, 1.4, 0 }, Waist = { 12, 0, 0 }, Neck = { 22, 0, 0 }, RightShoulder = { 168, 0, 14 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 168, 0, -14 }, LeftElbow = { 20, 0, 0 }, RightHip = { 0, 0, 10 }, LeftHip = { 0, 0, -10 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -30, 0, 0 } }, OUT),
	K(0.52, { Root = { 6, 0, 0, 0, 1.6, 0 }, Waist = { 14, 0, 0 }, Neck = { 24, 0, 0 }, RightShoulder = { 172, 0, 14 }, RightElbow = { 14, 0, 0 }, LeftShoulder = { 172, 0, -14 }, LeftElbow = { 14, 0, 0 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 } }, LIN),
	K(0.6, POUND, IN), K(1.0, POUND, LIN), K(1.15, with(POUND, { Root = { 4, 0, 0, 0, -0.5, -0.1 }, Waist = { -14, 0, 0 } }), SOFT), K(1.3, {}, SOFT),
})

kit.equipUnequip(Clips, {
	{ t = 0.16, j = { RightShoulder = { 60, 0, -20 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 60, 0, 20 }, LeftElbow = { 100, 0, 0 }, Waist = { -4, 0, 0 } } },
	{ t = 0.3, j = { RightShoulder = { 80, 0, 70 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 80, 0, -70 }, LeftElbow = { 20, 0, 0 }, Waist = { -6, 0, 0 }, Neck = { 6, 0, 0 } } },
	{ t = 0.46, j = { RightShoulder = { 52, 0, 14 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 52, 0, -14 }, LeftElbow = { 120, 0, 0 }, Waist = { 4, 14, 0 } } },
})
Clips.FistIdle = kit.breathe(CALM, "FistIdle", 3.0, false)
Clips.FistCombatIdle = kit.breathe(READY, "FistCombatIdle", 2.0, false)
kit.addVariants(Clips)

Clips.order = kit.order({ "FistJab", "FistCross", "FistHook", "FistUpper", "FistHaymaker", "FistKick", "FistCounter", "FistPound" })

return Clips
