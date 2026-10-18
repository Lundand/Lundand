--!nonstrict
-- Gathering set: looping action clips played while a player holds a gathering prompt. Each loop starts and ends on the same
-- pose; the "Hit" marker is the moment of impact (sparks, wood chips, torn leaves). GatherMine is two-handed with a pickaxe (the
-- build step puts the left hand on the haft), GatherChop is one-handed with a hatchet, GatherHarvest is bare-handed.
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

local STAND = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 8, 0, 9 }, RightElbow = { 22, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 4, 0, -7 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local kit = ClipKit.new("Gather", STAND, STAND, {})
local K, IN, OUT, SOFT, LIN = kit.K, ClipKit.IN, ClipKit.OUT, ClipKit.SOFT, ClipKit.LIN
local Clips = {}

local function loop(name, keys, extra)
	return with({ name = name, priority = ClipKit.Action, loop = true, keys = keys }, extra or {})
end

-- Mining (1.3 s): the pickaxe raised high over the head, a hard swing into the rock in front, a jolt, and back up.
local MINE_UP = { Root = { 4, 0, 0, 0, 0.05, 0.1 }, Waist = { 12, 0, 0 }, Neck = { 8, 0, 0 }, RightShoulder = { 150, 0, -8 }, RightElbow = { 20, 0, 0 }, RightHip = { 4, 0, 10 }, LeftHip = { 4, 0, -10 }, RightKnee = { -18, 0, 0 }, LeftKnee = { -18, 0, 0 } }
local MINE_HIT = { Root = { 6, 0, 0, 0, -0.55, -0.5 }, Waist = { -34, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 35, 0, -8 }, RightElbow = { 0, 0, 0 }, RightWrist = { -30, 0, 0 }, RightHip = { 30, 0, 10 }, LeftHip = { -12, 0, -10 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -30, 0, 0 } }
Clips.GatherMine = loop("GatherMine", {
	K(0, MINE_UP), K(0.12, with(MINE_UP, { RightShoulder = { 160, 0, -8 }, Root = { 6, 0, 0, 0, 0.1, 0.12 } }), OUT), K(0.34, MINE_HIT, IN),
	K(0.46, with(MINE_HIT, { Root = { 5, 0, 0, 0, -0.45, -0.4 }, RightShoulder = { 46, 0, -8 }, Waist = { -26, 0, 0 } }), OUT), K(0.62, with(MINE_HIT, { Root = { 5, 0, 0, 0, -0.5, -0.45 }, RightShoulder = { 38, 0, -8 } }), LIN),
	K(0.95, with(MINE_UP, { RightShoulder = { 110, 0, -8 }, Root = { 4, 0, 0, 0, -0.2, 0 }, Waist = { 0, 0, 0 } }), SOFT), K(1.3, MINE_UP, SOFT),
}, { twoHand = true, action = true })

-- Woodcutting (1.1 s): a hatchet drawn up beside the head with the torso coiled, then a diagonal chop as the body turns into it.
local CHOP_WIND = { Root = { 2, -14, 0, 0, -0.1, 0.1 }, Waist = { 6, -32, 0 }, Neck = { 0, 26, 0 }, RightShoulder = { 85, 0, 40 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 70, 0, 0 }, RightHip = { 6, 0, 8 }, LeftHip = { 6, 0, -8 }, RightKnee = { -24, 0, 0 }, LeftKnee = { -24, 0, 0 } }
local CHOP_HIT = { Root = { 6, 14, 0, 0, -0.45, -0.4 }, Waist = { -20, 34, 0 }, Neck = { 6, -30, 0 }, RightShoulder = { 25, 0, -6 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 40, 0, -50 }, LeftElbow = { 50, 0, 0 }, RightHip = { 34, 0, 8 }, LeftHip = { -16, 0, -8 }, RightKnee = { -44, 0, 0 }, LeftKnee = { -24, 0, 0 } }
Clips.GatherChop = loop("GatherChop", {
	K(0, CHOP_WIND), K(0.1, with(CHOP_WIND, { RightShoulder = { 95, 0, 44 }, Waist = { 8, -36, 0 } }), OUT), K(0.28, CHOP_HIT, IN),
	K(0.4, with(CHOP_HIT, { Root = { 5, 12, 0, 0, -0.35, -0.3 }, RightShoulder = { 34, 0, -6 } }), OUT), K(0.52, with(CHOP_HIT, { Root = { 5, 12, 0, 0, -0.4, -0.35 }, RightShoulder = { 28, 0, -6 } }), LIN),
	K(0.82, with(CHOP_WIND, { Root = { 4, 4, 0, 0, -0.2, 0 }, Waist = { 0, 0, 0 }, RightShoulder = { 70, 0, 30 } }), SOFT), K(1.1, CHOP_WIND, SOFT),
}, { action = true })

-- Harvesting (1.8 s): a low squat, the right hand reaching down to the plant, a grip, a tug, and the pick dropped at the hip.
local SQUAT = { Root = { 12, 0, 0, 0, -0.7, 0.2 }, Waist = { -40, 10, 0 }, Neck = { 20, 0, 0 }, LeftShoulder = { 30, 0, -24 }, LeftElbow = { 60, 0, 0 }, RightHip = { 38, 0, 6 }, LeftHip = { 32, 0, -6 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -60, 0, 0 } }
local function reach(shoulder, elbow, wrist, extra) return with(with(SQUAT, { RightShoulder = shoulder, RightElbow = { elbow, 0, 0 }, RightWrist = { wrist, 0, 0 } }), extra or {}) end
Clips.GatherHarvest = loop("GatherHarvest", {
	K(0, reach({ 40, 0, -6 }, 30, 0)),
	K(0.4, reach({ 52, 0, -8 }, 18, 24, { Waist = { -46, 10, 0 } }), SOFT),
	K(0.55, reach({ 52, 0, -8 }, 14, 30, { Waist = { -46, 12, 0 } }), LIN),
	K(0.75, reach({ 74, 0, -4 }, 70, 10, { Waist = { -30, 6, 0 }, Neck = { 10, 0, 0 } }), { ease = "Cubic", dir = "In", marker = "Hit" }),
	K(1.2, reach({ 12, 0, -30 }, 92, 0, { Waist = { -34, -6, 0 } }), SOFT),
	K(1.8, reach({ 40, 0, -6 }, 30, 0), SOFT),
}, { action = true })

Clips.order = { "GatherMine", "GatherChop", "GatherHarvest" }

return Clips
