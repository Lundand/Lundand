--!nonstrict
-- Dagger set (Rogue, Shadowblade, Night Sovereign). Two daggers in a reverse grip: the blades lie along the forearms, so
-- every cut is a forearm sweep and every stab is a downward drive. Same joint conventions as SwordClips. Cast-style clips
-- carry `hit`, the moment of the first strike; the Animator scales a clip so that moment lands on the ability's windup.
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

-- Ready stance: fists up at the chest, elbows in, torso angled.
local READY = {
	Waist = { 0, 14, 0 }, Neck = { 0, -12, 0 },
	RightShoulder = { 50, 0, 14 }, RightElbow = { 105, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 50, 0, -14 }, LeftElbow = { 105, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CALM = {
	Waist = { 0, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 6, 0, 10 }, RightElbow = { 24, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 6, 0, -10 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 },
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

-- Strike poses. A strike by one arm swings from across the body to out at the side while the torso turns with it; the
-- other arm stays tucked near the chest. `sign` is 1 for the right arm, -1 for the left.
local function arm(sign, shoulder, elbow, extraWrist)
	local prefix = sign == 1 and "Right" or "Left"
	return { [prefix .. "Shoulder"] = shoulder, [prefix .. "Elbow"] = { elbow, 0, 0 }, [prefix .. "Wrist"] = extraWrist or { 0, 0, 0 } }
end
local function tucked(sign)
	local prefix = sign == 1 and "Left" or "Right" -- the arm that is NOT striking
	return { [prefix .. "Shoulder"] = { 46, 0, -14 * sign }, [prefix .. "Elbow"] = { 100, 0, 0 } }
end
-- windup: arm drawn across the body
local function across(sign, yaw)
	return with(with(tucked(sign), arm(sign, { 75, 0, -46 * sign }, 42)), { Waist = { 0, 42 * sign + (yaw or 0), 0 }, Neck = { 0, -30 * sign, 0 } })
end
-- impact: arm out at the side. variant: "mid", "high" or "low"
local function out(sign, variant, yaw)
	local shoulder, waistTilt, knee = { 72, 0, 58 * sign }, 0, 18
	if variant == "high" then shoulder, waistTilt = { 122, 0, 46 * sign }, 8
	elseif variant == "low" then shoulder, waistTilt, knee = { 34, 0, 52 * sign }, -16, 34 end
	local pose = with(with(tucked(sign), arm(sign, shoulder, 22)), { Waist = { waistTilt, -38 * sign + (yaw or 0), 0 }, Neck = { 0, 32 * sign, 0 } })
	pose.RightKnee = { -knee, 0, 0 }
	pose.LeftKnee = { -knee * 0.8, 0, 0 }
	pose.RightHip = { sign == 1 and knee * 0.8 or -knee * 0.4, 0, 0 }
	pose.LeftHip = { sign == -1 and knee * 0.8 or -knee * 0.4, 0, 0 }
	return pose
end

-- Basic attacks. Each is 0.34 long with the cut at 0.08 (the configured windup); the Animator alternates them.
-- A: right-hand cut. B: left-hand cut. C: both blades cross in an X.
Clips.DaggerSlash = { name = "DaggerSlash", priority = Action, hit = 0.08, keys = {
	K(0, {}), K(0.04, across(1), OUT), K(0.08, out(1, "mid"), IN), K(0.14, out(1, "mid", -8), OUT), K(0.34, {}, SOFT),
} }
Clips.DaggerSlashB = { name = "DaggerSlashB", priority = Action, hit = 0.08, keys = {
	K(0, {}), K(0.04, across(-1), OUT), K(0.08, out(-1, "mid"), IN), K(0.14, out(-1, "mid", 8), OUT), K(0.34, {}, SOFT),
} }
local CROSS_WIND = { Root = { 4, 0, 0, 0, -0.15, 0.1 }, Waist = { 6, 0, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 70, 0, 78 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 70, 0, -78 }, LeftElbow = { 30, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftKnee = { -20, 0, 0 } }
local CROSS_HIT = { Root = { 4, 0, 0, 0, -0.3, -0.4 }, Waist = { -18, 0, 0 }, Neck = { 6, 0, 0 }, RightShoulder = { 88, 0, -42 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 88, 0, 42 }, LeftElbow = { 24, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -34, 0, 0 }, LeftHip = { -20, 0, 0 }, LeftKnee = { -14, 0, 0 } }
Clips.DaggerCross = { name = "DaggerCross", priority = Action, hit = 0.08, keys = {
	K(0, {}), K(0.04, CROSS_WIND, OUT), K(0.08, CROSS_HIT, IN), K(0.16, with(CROSS_HIT, { RightShoulder = { 92, 0, -48 }, LeftShoulder = { 92, 0, 48 } }), OUT), K(0.34, {}, SOFT),
} }

-- TwinFang: a right cut, then a left cut 0.12 later (the ability's two hits are at 0.08 and 0.20).
Clips.DaggerFlurry = { name = "DaggerFlurry", priority = Action, hit = 0.08, keys = {
	K(0, {}), K(0.04, across(1), OUT), K(0.08, out(1, "mid"), IN), K(0.14, across(-1), OUT), K(0.2, out(-1, "mid"), { ease = "Cubic", dir = "In", marker = "Hit2" }),
	K(0.3, out(-1, "mid", 8), OUT), K(0.43, {}, SOFT),
} }

-- Marks (Expose Weakness, Marked Prey, Death Mark): a short hop, then the right fist drives the blade down. Strike at 0.10.
local PLUNGE_WIND = { Root = { 0, 10, 0, 0, 0.18, 0 }, Waist = { 8, 14, 0 }, Neck = { 8, -12, 0 }, RightShoulder = { 165, 0, 14 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 40, 0, -40 }, LeftElbow = { 80, 0, 0 }, RightHip = { 8, 0, 0 }, RightKnee = { -14, 0, 0 }, LeftHip = { 6, 0, 0 }, LeftKnee = { -16, 0, 0 } }
local PLUNGE_HIT = { Root = { 6, 12, 0, 0, -0.7, -0.55 }, Waist = { -34, 16, 0 }, Neck = { 14, -16, 0 }, RightShoulder = { 52, 0, 6 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 20, 0, -60 }, LeftElbow = { 50, 0, 0 }, RightHip = { 56, 0, 0 }, RightKnee = { -76, 0, 0 }, LeftHip = { -30, 0, 0 }, LeftKnee = { -20, 0, 0 } }
Clips.DaggerPlunge = { name = "DaggerPlunge", priority = Action, hit = 0.10, keys = {
	K(0, {}), K(0.06, PLUNGE_WIND, OUT), K(0.1, PLUNGE_HIT, IN), K(0.22, PLUNGE_HIT, LIN), K(0.4, {}, SOFT),
} }

-- Shadow movement: a low coil and a spinning vanish (blinks), and a cloak-sweep (Veil).
Clips.DaggerBlink = { name = "DaggerBlink", priority = Action, hit = 0.05, keys = {
	K(0, {}),
	K(0.05, { Root = { 8, -90, 0, 0, -0.75, 0 }, Waist = { 14, -30, 0 }, Neck = { 0, 30, 0 }, RightShoulder = { 60, 0, -40 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 60, 0, 40 }, LeftElbow = { 110, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -80, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -80, 0, 0 } }, { ease = "Cubic", dir = "In", marker = "Hit" }),
	K(0.14, { Root = { 8, 60, 0, 0, -0.75, 0 }, Waist = { 14, 30, 0 }, Neck = { 0, -30, 0 }, RightShoulder = { 60, 0, -40 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 60, 0, 40 }, LeftElbow = { 110, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -80, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -80, 0, 0 } }, LIN),
	K(0.24, { Root = { 4, 150, 0, 0, -0.5, 0 }, Waist = { 8, 10, 0 }, RightShoulder = { 70, 0, 50 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 70, 0, -50 }, LeftElbow = { 40, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftKnee = { -50, 0, 0 } }, LIN),
	K(0.45, {}, SOFT),
} }
Clips.DaggerVeil = { name = "DaggerVeil", priority = Action, hit = 0.05, keys = {
	K(0, {}),
	K(0.05, { Root = { 12, 0, 0, 0, -0.5, 0.1 }, Waist = { -16, 0, 0 }, Neck = { 14, 0, 0 }, RightShoulder = { 112, 0, -38 }, RightElbow = { 125, 0, 0 }, LeftShoulder = { 112, 0, 38 }, LeftElbow = { 125, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -54, 0, 0 }, LeftHip = { 30, 0, 0 }, LeftKnee = { -54, 0, 0 } }, { ease = "Cubic", dir = "Out", marker = "Hit" }),
	K(0.2, { Root = { 12, 0, 0, 0, -0.55, 0.1 }, Waist = { -18, 0, 0 }, Neck = { 16, 0, 0 }, RightShoulder = { 118, 0, -44 }, RightElbow = { 130, 0, 0 }, LeftShoulder = { 118, 0, 44 }, LeftElbow = { 130, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -54, 0, 0 }, LeftHip = { 30, 0, 0 }, LeftKnee = { -54, 0, 0 } }, LIN),
	K(0.34, { Root = { 4, 0, 0, 0, -0.25, 0 }, Waist = { -6, 8, 0 }, RightShoulder = { 70, 0, 60 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 70, 0, -60 }, LeftElbow = { 60, 0, 0 }, RightKnee = { -26, 0, 0 }, LeftKnee = { -26, 0, 0 } }, SOFT),
	K(0.5, {}, SOFT),
} }

-- Ultimates. `flurry` builds a run of cuts at the given times (side alternates, heights vary, the body spins by `spin` degrees
-- per cut), then a two-fisted overhead finishing blow at `finalAt`.
local function flurry(name, firstAt, cuts, finalAt, spin, length, variants)
	local keys = { K(0, {}), K(firstAt * 0.5, with(across(1), { Root = { 6, 0, 0, 0, -0.35, 0.1 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -26, 0, 0 } }), OUT) }
	local yaw = 0
	for index, at in ipairs(cuts) do
		local sign = index % 2 == 1 and 1 or -1
		yaw += spin
		local pose = out(sign, variants[(index - 1) % #variants + 1])
		pose.Root = { 4, yaw, 0, 0, -0.25, -0.2 }
		keys[#keys + 1] = K(at, pose, { ease = index == 1 and "Cubic" or "Linear", dir = index == 1 and "In" or "Out", marker = index == 1 and "Hit" or nil })
	end
	-- finishing blow: both fists overhead (a hop), then driven down into a deep lunge
	keys[#keys + 1] = K(finalAt - 0.14, with(PLUNGE_WIND, { Root = { 0, yaw, 0, 0, 0.45, 0 }, RightShoulder = { 168, 0, 22 }, LeftShoulder = { 168, 0, -22 }, LeftElbow = { 70, 0, 0 } }), OUT)
	keys[#keys + 1] = K(finalAt, with(PLUNGE_HIT, { Root = { 6, yaw, 0, 0, -0.85, -0.6 }, LeftShoulder = { 52, 0, -6 }, LeftElbow = { 20, 0, 0 } }), IN)
	keys[#keys + 1] = K(finalAt + 0.18, with(PLUNGE_HIT, { Root = { 6, yaw, 0, 0, -0.85, -0.6 }, LeftShoulder = { 52, 0, -6 }, LeftElbow = { 20, 0, 0 } }), LIN)
	keys[#keys + 1] = K(finalAt + 0.4, { Root = { 2, yaw, 0, 0, -0.3, 0 }, Waist = { -10, 14, 0 } }, SOFT)
	-- unwind the accumulated spin through the last stretch by ending exactly on a full turn
	local full = math.ceil(yaw / 360) * 360
	keys[#keys].j.Root = { 2, math.min(full, yaw + 170), 0, 0, -0.3, 0 }
	keys[#keys + 1] = K(length, { Root = { 0, full, 0 } }, SOFT)
	return { name = name, priority = Action, hit = firstAt, keys = keys }
end
-- Execution Dance: six flowing cuts with a pirouette between them, then the finisher at 1.10.
Clips.DaggerDance = flurry("DaggerDance", 0.15, { 0.15, 0.3, 0.45, 0.6, 0.75, 0.9 }, 1.10, 60, 1.55, { "mid", "high", "low" })
-- Shadow Execution: five fast cuts from a planted stance, then the finisher at 0.95.
Clips.DaggerShadowStrike = flurry("DaggerShadowStrike", 0.10, { 0.10, 0.24, 0.38, 0.52, 0.66 }, 0.95, 0, 1.5, { "mid", "low", "high" })
-- Thousand Cuts: a frenzy of eight cuts, 0.1 apart, then the finisher at 1.0.
Clips.DaggerCuts = flurry("DaggerCuts", 0.10, { 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80 }, 1.0, 0, 1.6, { "high", "mid", "low", "mid" })

-- Draw and sheathe.
Clips.DaggerEquip = { name = "DaggerEquip", priority = Action, keys = {
	K(0, {}, { base = CALM }),
	K(0.15, { RightShoulder = { 34, 0, -30 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 34, 0, 30 }, LeftElbow = { 80, 0, 0 }, Waist = { -6, 0, 0 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.3, { RightShoulder = { 62, 0, 84 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 62, 0, -84 }, LeftElbow = { 20, 0, 0 }, Waist = { -8, 0, 0 }, Neck = { 8, 0, 0 } }, { base = CALM, ease = "Cubic", dir = "Out" }),
	K(0.46, { RightShoulder = { 60, 0, 40 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 60, 0, -40 }, LeftElbow = { 70, 0, 0 }, Waist = { 4, 8, 0 } }, { base = CALM, ease = "Cubic", dir = "InOut" }),
	K(0.62, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }
Clips.DaggerUnequip = { name = "DaggerUnequip", priority = Action, keys = {
	K(0, {}),
	K(0.18, { RightShoulder = { 40, 0, -20 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 40, 0, 20 }, LeftElbow = { 80, 0, 0 } }, SOFT),
	K(0.4, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
} }

-- Stances (upper body only, Movement priority).
local function breathe(base, name, length)
	local mid = length / 2
	return { name = name, priority = Movement, loop = true, keys = {
		K(0, {}, { base = base, upper = true }),
		K(mid, { Waist = { base.Waist[1] + 2, base.Waist[2], 0 }, Neck = { base.Neck[1] - 1.5, base.Neck[2], 0 }, RightShoulder = { base.RightShoulder[1] + 3, base.RightShoulder[2], base.RightShoulder[3] + 2 }, LeftShoulder = { base.LeftShoulder[1] + 3, base.LeftShoulder[2], base.LeftShoulder[3] - 2 }, RightElbow = { base.RightElbow[1] + 5, 0, 0 }, LeftElbow = { base.LeftElbow[1] + 5, 0, 0 } }, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
		K(length, {}, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
	} }
end
Clips.DaggerIdle = breathe(CALM, "DaggerIdle", 3.0)
Clips.DaggerCombatIdle = breathe(READY, "DaggerCombatIdle", 2.0)

-- Dodges and reactions: the sword set's clips, re-based onto the dagger stance.
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
	Clips["Dagger" .. name] = rebase(Sword[name], "Dagger" .. name)
end

Clips.order = { "DaggerSlash", "DaggerSlashB", "DaggerCross", "DaggerFlurry", "DaggerPlunge", "DaggerBlink", "DaggerVeil", "DaggerDance", "DaggerShadowStrike", "DaggerCuts", "DaggerEquip", "DaggerUnequip", "DaggerIdle", "DaggerCombatIdle", "DaggerDodge", "DaggerDodgeForward", "DaggerDodgeLeft", "DaggerDodgeRight", "DaggerHitReactLight", "DaggerHitReactHeavy", "DaggerStagger" }

return Clips
