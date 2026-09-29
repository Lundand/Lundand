--[[
	Poses — the pure math behind Anim: no services and no instances, so tests/anim runs it under the plain luau CLI.

	How a pose reaches the character
	* A joint (Motor6D, or the AnimationConstraint that replaces it on R15 avatars with the Avatar Joint Upgrade)
	  places Part1 = Part0 * C0 * Transform * C1:Inverse()   (AnimationConstraint: C0/C1 = Attachment0/1.CFrame)
	* A pose is a rotation R about the joint, in Part0's axes (torso axes for the shoulders). Anim applies it through
	  Transform only — Transform = (C0.Rotation⁻¹ * R * C0.Rotation) * animation — so C0 is never edited and nothing
	  can drift. Arm poses fade the walk/idle animation out (`Poses.Transform`'s `override`), torso poses add to it.

	Keyframe angles are degrees:
	* arms  {pitch, across, out, twist}: pitch raises the arm forward (180 = straight up), across swings it toward
	  the other side, out lifts it sideways, twist turns it about itself. The left arm is mirrored, so the same
	  numbers give the mirror-image motion.
	* elbow: bend (0 = straight, 90 = right angle, forward).
	* wrist {x, y, z}: rotation in the forearm's axes. A forward-held blade points along the hand's -Z, so x < 0
	  tips it down toward the line of the arm; upright weapons (bow, staff, scythe) point along the hand's +Y.
	* torso: lean (forward +), turn (to the left +), tilt; spin turns the whole body (Root) to the left.
]]

local Poses = {}

export type Frames = { c0: CFrame, c1: CFrame }
export type Arm = {
	right: boolean,
	sh: Frames,
	el: Frames?, -- R15 only
	wr: Frames?, -- R15 only
	size: Vector3, -- R15: hand size, R6: arm size
}
export type Rig = {
	r6: boolean,
	root: Frames?, -- R15 "Root" (HumanoidRootPart -> LowerTorso), R6 "RootJoint" (HumanoidRootPart -> Torso)
	waist: Frames?, -- R15 only (LowerTorso -> UpperTorso)
	neck: Frames?,
	right: Arm?,
	left: Arm?,
	grip: CFrame?, -- the weapon Handle in the right hand's (R6: right arm's) space
}
-- Rotations to apply, each in its joint's parent axes (nil = leave the joint to the animation)
export type Out = {
	root: CFrame?,
	waist: CFrame?,
	neck: CFrame?,
	rs: CFrame?,
	re: CFrame?,
	rw: CFrame?,
	ls: CFrame?,
	le: CFrame?,
	lw: CFrame?,
}

local ID = CFrame.new()
local X = Vector3.new(1, 0, 0)
local Y = Vector3.new(0, 1, 0)
local rad = math.rad
local EPS = 1e-6

local MIN_BEND = rad(6) -- elbow limits for the IK
local MAX_BEND = rad(150)
local MAX_WRIST = rad(80)

--------------------------------------------------------------------------------
-- Rotation helpers (only CFrame.new / Angles / GetComponents / * / Inverse, so the test stand-ins suffice)
--------------------------------------------------------------------------------
local function fromAxes(x: Vector3, y: Vector3, z: Vector3): CFrame
	return CFrame.new(0, 0, 0, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
end

local function rot(cf: CFrame): CFrame
	local _, _, _, a, b, c, d, e, f, g, h, i = cf:GetComponents()
	return CFrame.new(0, 0, 0, a, b, c, d, e, f, g, h, i)
end
Poses.Rot = rot

local function toQuat(cf: CFrame): (number, number, number, number)
	local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cf:GetComponents()
	local tr = m00 + m11 + m22
	local w, x, y, z
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		w, x, y, z = 0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(math.max(1 + m00 - m11 - m22, EPS)) * 2
		w, x, y, z = (m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(math.max(1 + m11 - m00 - m22, EPS)) * 2
		w, x, y, z = (m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s
	else
		local s = math.sqrt(math.max(1 + m22 - m00 - m11, EPS)) * 2
		w, x, y, z = (m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s
	end
	local n = math.sqrt(w * w + x * x + y * y + z * z)
	if n < EPS then
		return 1, 0, 0, 0
	end
	if w < 0 then
		n = -n -- shortest arc
	end
	return w / n, x / n, y / n, z / n
end

local function fromQuat(w: number, x: number, y: number, z: number): CFrame
	return CFrame.new(
		0,
		0,
		0,
		1 - 2 * (y * y + z * z),
		2 * (x * y - z * w),
		2 * (x * z + y * w),
		2 * (x * y + z * w),
		1 - 2 * (x * x + z * z),
		2 * (y * z - x * w),
		2 * (x * z - y * w),
		2 * (y * z + x * w),
		1 - 2 * (x * x + y * y)
	)
end

-- Rotation of `angle` radians about the unit vector `axis`
local function axisAngle(axis: Vector3, angle: number): CFrame
	local s = math.sin(angle / 2)
	return fromQuat(math.cos(angle / 2), axis.X * s, axis.Y * s, axis.Z * s)
end

-- Rotation angle of a CFrame (0..pi) and its axis
local function angleOf(cf: CFrame): (number, Vector3)
	local w, x, y, z = toQuat(cf)
	local s = math.sqrt(x * x + y * y + z * z)
	if s < EPS then
		return 0, X
	end
	return 2 * math.atan2(s, w), Vector3.new(x / s, y / s, z / s)
end
Poses.AngleOf = angleOf

-- `k` of the way from identity to cf (rotation along the shortest arc, position linearly)
function Poses.Scale(cf: CFrame, k: number): CFrame
	local p = cf.Position * k
	if k >= 1 then
		return CFrame.new(p) * rot(cf)
	elseif k <= 0 then
		return CFrame.new(p)
	end
	local angle, axis = angleOf(cf)
	return CFrame.new(p) * axisAngle(axis, angle * k)
end

-- Minimal rotation turning direction a into direction b
local function fromTo(a: Vector3, b: Vector3): CFrame
	if a.Magnitude < EPS or b.Magnitude < EPS then
		return ID
	end
	a, b = a.Unit, b.Unit
	local c = a:Cross(b)
	local s = c.Magnitude
	local d = a:Dot(b)
	if s < 1e-7 then
		if d > 0 then
			return ID
		end
		local perp = a:Cross(math.abs(a.X) < 0.9 and X or Y).Unit
		return axisAngle(perp, math.pi)
	end
	return axisAngle(c / s, math.atan2(s, d))
end
Poses.FromTo = fromTo

-- Orthonormal basis whose first axis is a and whose second axis leans toward b (nil if b is parallel to a)
local function basis(a: Vector3, b: Vector3): CFrame?
	local x = a.Unit
	local y = b - x * b:Dot(x)
	if y.Magnitude < 1e-5 then
		return nil
	end
	y = y.Unit
	return fromAxes(x, y, x:Cross(y))
end

-- Rotation taking direction a to A while turning b (as seen around a) toward B (as seen around A)
local function align(a: Vector3, b: Vector3, A: Vector3, B: Vector3): CFrame
	if a.Magnitude < EPS or A.Magnitude < EPS then
		return ID
	end
	local f0 = basis(a, b)
	local f1 = basis(A, B)
	if not f0 or not f1 then
		return fromTo(a, A)
	end
	return f1 * f0:Inverse()
end

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function perp(v: Vector3, axis: Vector3, fallback: Vector3): Vector3
	local p = v - axis * v:Dot(axis)
	if p.Magnitude < 1e-4 then
		p = fallback - axis * fallback:Dot(axis)
		if p.Magnitude < 1e-4 then
			p = axis:Cross(math.abs(axis.X) < 0.9 and X or Y)
		end
	end
	return p.Unit
end

--------------------------------------------------------------------------------
-- Joints
--------------------------------------------------------------------------------
-- The Transform that shows rotation R (Part0 axes, about the joint) on top of the animation's Transform.
-- override = 1 replaces the animation, 0 keeps it underneath.
function Poses.Transform(c0: CFrame, R: CFrame, anim: CFrame, override: number): CFrame
	local r0 = rot(c0)
	local base = override > 0 and Poses.Scale(anim, 1 - override) or anim
	return r0:Inverse() * R * r0 * base
end

-- Arm joints replace the walk/idle animation (fully at weight 1); torso, neck and root poses add to it
local OVERRIDE = { rs = true, re = true, rw = true, ls = true, le = true, lw = true }
function Poses.JointTransform(key: string, c0: CFrame, R: CFrame, anim: CFrame, weight: number): CFrame
	return Poses.Transform(c0, weight < 1 and Poses.Scale(R, weight) or R, anim, OVERRIDE[key] and weight or 0)
end

--------------------------------------------------------------------------------
-- Reading a character (joint names are the same for Motor6Ds and upgraded AnimationConstraints)
--------------------------------------------------------------------------------
export type Joints = { [string]: Instance }

local R15_JOINTS = {
	root = { "LowerTorso", "Root" },
	waist = { "UpperTorso", "Waist" },
	neck = { "Head", "Neck" },
	rs = { "RightUpperArm", "RightShoulder" },
	re = { "RightLowerArm", "RightElbow" },
	rw = { "RightHand", "RightWrist" },
	ls = { "LeftUpperArm", "LeftShoulder" },
	le = { "LeftLowerArm", "LeftElbow" },
	lw = { "LeftHand", "LeftWrist" },
}
local R6_JOINTS = {
	root = { "HumanoidRootPart", "RootJoint" },
	neck = { "Torso", "Neck" },
	rs = { "Torso", "Right Shoulder" },
	ls = { "Torso", "Left Shoulder" },
}

-- A Motor6D, or the AnimationConstraint that replaces it on upgraded R15 avatars
function Poses.IsJoint(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint"))
end

-- C0/C1 of a joint (an AnimationConstraint's are its attachments' CFrames)
function Poses.Frames(joint: Instance): Frames?
	if joint:IsA("Motor6D") then
		local m = joint :: Motor6D
		return { c0 = m.C0, c1 = m.C1 }
	elseif joint:IsA("AnimationConstraint") then
		local a0, a1 = (joint :: AnimationConstraint).Attachment0, (joint :: AnimationConstraint).Attachment1
		if a0 and a1 then
			return { c0 = a0.CFrame, c1 = a1.CFrame }
		end
	end
	return nil
end

-- The joints and rest frames of a character (Rig is nil when there are no arms to pose)
function Poses.Read(character: Model): (Rig?, Joints)
	local r6 = character:FindFirstChild("UpperTorso") == nil
	local joints: Joints = {}
	local frames: { [string]: Frames } = {}
	local names: { [string]: { string } } = if r6 then R6_JOINTS else R15_JOINTS
	for key, where in names do
		local part = character:FindFirstChild(where[1])
		local joint = part and part:FindFirstChild(where[2])
		local f = joint and Poses.IsJoint(joint) and Poses.Frames(joint)
		if joint and f then
			joints[key] = joint
			frames[key] = f
		end
	end
	local function arm(right: boolean): Arm?
		local sh = frames[right and "rs" or "ls"]
		if not sh then
			return nil
		end
		if r6 then
			local limb = character:FindFirstChild(right and "Right Arm" or "Left Arm")
			if not limb or not limb:IsA("BasePart") then
				return nil
			end
			return { right = right, sh = sh, size = limb.Size }
		end
		local el, wr = frames[right and "re" or "le"], frames[right and "rw" or "lw"]
		local hand = character:FindFirstChild(right and "RightHand" or "LeftHand")
		if not el or not wr or not hand or not hand:IsA("BasePart") then
			return nil
		end
		return { right = right, sh = sh, el = el, wr = wr, size = hand.Size }
	end
	local right, left = arm(true), arm(false)
	if not right and not left then
		return nil, joints
	end
	local rig: Rig = { r6 = r6, root = frames.root, waist = frames.waist, neck = frames.neck, right = right, left = left }
	return rig, joints
end

-- The equipped weapon's Handle in the space of the hand (R6: arm) holding it, from its "WeaponGrip" weld
function Poses.Grip(character: Model): CFrame?
	local weapon = character:FindFirstChild("EquippedWeapon")
	local handle = weapon and weapon:FindFirstChild("Handle")
	local weld = handle and handle:FindFirstChild("WeaponGrip")
	if weld and weld:IsA("Weld") then
		return weld.C0 * weld.C1:Inverse()
	end
	return nil
end

-- Part1 in Part0's space for a joint showing rotation R (and animation transform `anim`)
function Poses.Place(f: Frames, R: CFrame, anim: CFrame?): CFrame
	local r0 = rot(f.c0)
	return f.c0 * (r0:Inverse() * R * r0) * (anim or ID) * f.c1:Inverse()
end

function Poses.Shoulder(pitch: number, across: number, out: number, twist: number, right: boolean): CFrame
	local s = right and 1 or -1
	return CFrame.Angles(0, s * across, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, s * out) * CFrame.Angles(0, s * twist, 0)
end

function Poses.Elbow(bend: number): CFrame
	return CFrame.Angles(bend, 0, 0)
end

function Poses.Wrist(x: number, y: number, z: number, right: boolean): CFrame
	local s = right and 1 or -1
	return CFrame.Angles(x, s * y, s * z)
end

function Poses.Torso(lean: number, turn: number, tilt: number): CFrame
	return CFrame.Angles(0, turn, 0) * CFrame.Angles(-lean, 0, 0) * CFrame.Angles(0, 0, tilt)
end

-- Upper arm, lower arm and hand CFrames (shoulder-parent space) for the given joint rotations
function Poses.ArmFK(arm: Arm, rs: CFrame, re: CFrame?, rw: CFrame?): (CFrame, CFrame?, CFrame?)
	local upper = Poses.Place(arm.sh, rs)
	local el, wr = arm.el, arm.wr
	if not el or not wr then
		return upper, nil, nil
	end
	local lower = upper * Poses.Place(el, re or ID)
	return upper, lower, lower * Poses.Place(wr, rw or ID)
end

-- The part that holds the weapon (R15 hand, R6 arm) in shoulder-parent space
local function holder(arm: Arm, rs: CFrame, re: CFrame?, rw: CFrame?): CFrame
	local upper, _, hand = Poses.ArmFK(arm, rs, re, rw)
	return hand or upper
end
Poses.Holder = holder

--------------------------------------------------------------------------------
-- Inverse kinematics
--------------------------------------------------------------------------------
-- Elbow angle about hinge k making |u + rot(k, angle) * v| = d, nearest a natural bend
local function hingeAngle(u: Vector3, v: Vector3, k: Vector3, d: number): number
	local vPar = k * v:Dot(k)
	local vPerp = v - vPar
	local P = u:Dot(vPerp)
	local Q = u:Dot(k:Cross(vPerp))
	local c = (d * d - u:Dot(u) - v:Dot(v)) / 2 - u:Dot(vPar)
	local M = math.sqrt(P * P + Q * Q)
	if M < EPS then
		return rad(60)
	end
	local phi = math.atan2(Q, P)
	local a = math.acos(clamp(c / M, -1, 1))
	local best, bestErr = MIN_BEND, math.huge
	for _, t in { phi + a, phi - a } do
		t = (t + math.pi) % (2 * math.pi) - math.pi
		local tc = clamp(t, MIN_BEND, MAX_BEND)
		local err = math.abs(tc - t) * 4 + math.abs(tc - rad(70)) * 0.01
		if err < bestErr then
			best, bestErr = tc, err
		end
	end
	return best
end

-- Distance range the hand can reach from the shoulder joint (R15)
local function reachRange(arm: Arm, effector: Vector3): (number, number)
	local sh, el, wr = arm.sh, arm.el :: Frames, arm.wr :: Frames
	local u = el.c0.Position - sh.c1.Position
	local lowerToEffector = Poses.Place(wr, ID) * effector
	local v = rot(el.c0) * rot(el.c1):Inverse() * (lowerToEffector - el.c1.Position)
	local function dist(t: number): number
		return (u + axisAngle(X, t) * v).Magnitude
	end
	local lo, hi = math.huge, 0
	for i = 0, 12 do
		local d = dist(MIN_BEND + (MAX_BEND - MIN_BEND) * i / 12)
		lo, hi = math.min(lo, d), math.max(hi, d)
	end
	return lo, hi
end

--[[
	R15 arm reaching so the hand part lands on `hand` (a CFrame in the shoulder parent's space).
	`out` is where the outside of the arm should face; it decides where the elbow goes (the elbow
	ends up on the side of `out` turned 90° down around the reach direction). Returns shoulder, elbow
	and wrist rotations; the wrist twist is limited, so extreme hand orientations are only approached.
]]
function Poses.ReachR15(arm: Arm, hand: CFrame, out: Vector3): (CFrame, CFrame, CFrame)
	local sh, el, wr = arm.sh, arm.el :: Frames, arm.wr :: Frames
	local pS = sh.c0.Position
	local As = rot(sh.c0) * rot(sh.c1):Inverse()
	local Ae = rot(el.c0) * rot(el.c1):Inverse()
	local Aw = rot(wr.c0) * rot(wr.c1):Inverse()
	local u = el.c0.Position - sh.c1.Position -- shoulder -> elbow (upper arm axes)
	local v = Ae * (wr.c0.Position - el.c1.Position) -- elbow -> wrist (upper arm axes, straight elbow)
	local wrist = hand * wr.c1.Position
	local toW = wrist - pS
	local theta = hingeAngle(u, v, X, toW.Magnitude)
	local re = axisAngle(X, theta)
	local chain = As * (u + re * v)
	if toW.Magnitude < 1e-4 then
		toW = chain
	end
	local outside = As * (arm.right and X or -X)
	local target = perp(out, toW.Unit, arm.right and X or -X)
	local rs = align(chain, outside, toW, target)
	local lower = rs * As * re * Ae
	local rw = lower:Inverse() * rot(hand) * Aw:Inverse()
	local angle, axis = angleOf(rw)
	if angle > MAX_WRIST then
		rw = axisAngle(axis, MAX_WRIST)
	end
	return rs, re, rw
end

-- R6 arm (one piece) pointing its end at `point`, its outside turned toward `out`
function Poses.ReachR6(arm: Arm, point: Vector3, out: Vector3): CFrame
	local sh = arm.sh
	local restTip = (rot(sh.c0) * sh.c1:Inverse()) * Vector3.new(0, -arm.size.Y / 2, 0)
	local outside = rot(sh.c0) * rot(sh.c1):Inverse() * (arm.right and X or -X)
	local to = point - sh.c0.Position
	if to.Magnitude < 1e-4 then
		return ID
	end
	return align(restTip, outside, to, perp(out, to.Unit, arm.right and X or -X))
end

-- Length from the R6 shoulder joint to the end of the arm
local function r6Length(arm: Arm): number
	return ((rot(arm.sh.c0) * arm.sh.c1:Inverse()) * Vector3.new(0, -arm.size.Y / 2, 0)).Magnitude
end

--[[
	Direction from a sphere's center (c, radius r) to the point on it nearest `pref` whose distance from p lies
	within [lo, hi]. Distance grows monotonically with the angle from the point facing p, so this is closed-form.
]]
function Poses.ContactDir(c: Vector3, r: number, p: Vector3, pref: Vector3, lo: number, hi: number): Vector3
	local toP = p - c
	local D = toP.Magnitude
	if D < 1e-4 or r < 1e-4 then
		return pref.Unit
	end
	local near = toP / D
	pref = pref.Unit
	local cosPref = clamp(pref:Dot(near), -1, 1)
	local function angleFor(dist: number): number
		return math.acos(clamp((D * D + r * r - dist * dist) / (2 * r * D), -1, 1))
	end
	local phi = clamp(math.acos(cosPref), angleFor(lo), angleFor(math.max(hi, lo)))
	local side = perp(pref, near, Vector3.new(0, -1, 0))
	return near * math.cos(phi) + side * math.sin(phi)
end

--------------------------------------------------------------------------------
-- Carrying a Core: both hands on the lower sides of the shell
--------------------------------------------------------------------------------
Poses.Carry = {
	below = rad(20), -- contact point below the ball's equator
	back = rad(32), -- and turned back from the side toward the body
	lean = rad(5), -- torso leans back a little under the weight
	elbowOut = 0.1, -- how far the elbows flare out (0 = tucked in)
}

local function carryArm(arm: Arm, center: Vector3, radius: number): (CFrame, CFrame?, CFrame?)
	local cfg = Poses.Carry
	local s = arm.right and 1 or -1
	local pS = arm.sh.c0.Position
	local pref = Vector3.new(s * math.cos(cfg.below) * math.cos(cfg.back), -math.sin(cfg.below), math.cos(cfg.below) * math.sin(cfg.back))
	local half = arm.size.X / 2
	local shell = radius + half -- where the hand's center sits when its palm touches the shell
	if not arm.el or not arm.wr then
		local len = r6Length(arm)
		local n = Poses.ContactDir(center, shell, pS, pref, len, len)
		return Poses.ReachR6(arm, center + n * shell, n), nil, nil
	end
	local lo, hi = reachRange(arm, Vector3.zero)
	local n = Poses.ContactDir(center, shell, pS, pref, lo * 1.05, hi * 0.96)
	local handPos = center + n * shell
	-- palm (-X on the right hand, +X on the left) flat on the shell, fingers pointing away from the shoulder
	local xAxis = n * s
	local yAxis = perp(pS - handPos, xAxis, Y)
	local hand = CFrame.new(handPos) * fromAxes(xAxis, yAxis, xAxis:Cross(yAxis))
	local out = (n + Vector3.new(0, cfg.elbowOut, 0) + Vector3.new(s * cfg.elbowOut, 0, 0))
	return Poses.ReachR15(arm, hand, out)
end

-- Where the upper body (UpperTorso / R6 Torso) is in HumanoidRootPart space, given this frame's transforms
function Poses.TorsoInRoot(rig: Rig, rootT: CFrame, waistT: CFrame): CFrame
	local root = rig.root
	local cf = root and root.c0 * rootT * root.c1:Inverse() or ID
	local waist = rig.waist
	if waist then
		cf *= waist.c0 * waistT * waist.c1:Inverse()
	end
	return cf
end

--[[
	Pose for holding a ball at `center` (HumanoidRootPart space, radius `radius`).
	rootT / waistT are this frame's animation transforms of the Root and Waist joints (the legs keep walking,
	so the torso bobs and the hands must follow). Fills `out` (rotations) and returns it.
]]
function Poses.CarryPose(rig: Rig, center: Vector3, radius: number, rootT: CFrame, waistT: CFrame, out: Out): Out
	local lean = Poses.Torso(-Poses.Carry.lean, 0, 0)
	local waistNow = waistT
	if rig.waist then
		out.waist = lean
		waistNow = Poses.Transform(rig.waist.c0, lean, waistT, 0)
	end
	local torso = Poses.TorsoInRoot(rig, rootT, waistNow)
	local c = torso:Inverse() * center
	if rig.right then
		out.rs, out.re, out.rw = carryArm(rig.right, c, radius)
	end
	if rig.left then
		out.ls, out.le, out.lw = carryArm(rig.left, c, radius)
	end
	return out
end

--------------------------------------------------------------------------------
-- Attacks
--------------------------------------------------------------------------------
-- Channel layout of a sampled frame (radians)
local C = {
	rs = 1, -- 1..4 pitch, across, out, twist
	re = 5,
	rw = 6, -- 6..8
	ls = 9, -- 9..12
	le = 13,
	lw = 14, -- 14..16
	lean = 17,
	turn = 18,
	tilt = 19,
	spin = 20,
}
local N = 20
Poses.Channels = C

export type Key = {
	t: number,
	ease: string?,
	rs: { number }?,
	re: number?,
	rw: { number }?,
	ls: { number }?,
	le: number?,
	lw: { number }?,
	lean: number?,
	turn: number?,
	tilt: number?,
	spin: number?,
}
export type Style = {
	time: number, -- preferred length (s); always fits inside one attack (1 / rate)
	hit: number, -- fraction of the length when the weapon connects (slash, sparks, shake)
	release: number?, -- ranged: when the shot leaves
	trail: { number }?, -- {on, off} fractions: SwingTrail window
	twoHand: number?, -- the left hand grips the weapon this far along the Handle's +Y (studs)
	mirror: boolean?, -- every other attack is the mirror image (daggers: left, right, left...)
	keys: { Key },
	frames: { { number } }?, -- keys converted to radian channel arrays (built on first use)
}

-- stylua: ignore start
Poses.Styles = {
	-- diagonal chop from over the right shoulder down to the left hip, with follow-through
	sword = {
		time = 0.42, hit = 0.34, trail = { 0.1, 0.62 },
		keys = {
			{ t = 0, rs = { 150, -15, 30, 0 }, re = 40, rw = { -50, 0, 0 }, ls = { 25, 15, 10, 0 }, le = 40, lean = -4, turn = -22 },
			{ t = 0.12, ease = "out", rs = { 162, -20, 36, 0 }, re = 45, rw = { -45, 0, 0 }, ls = { 35, 20, 12, 0 }, le = 50, lean = -8, turn = -30 },
			{ t = 0.34, ease = "out", rs = { 80, 38, 8, 0 }, re = 8, rw = { -55, 0, 0 }, ls = { -25, 0, 18, 0 }, le = 25, lean = 12, turn = 26 },
			{ t = 0.6, rs = { 38, 58, 5, 0 }, re = 22, rw = { -45, 0, 0 }, ls = { -35, 0, 22, 0 }, le = 30, lean = 14, turn = 34 },
			{ t = 1, rs = { 20, 20, 8, 0 }, re = 30, rw = { -10, 0, 0 }, ls = { 0, 0, 6, 0 }, le = 15, lean = 3, turn = 6 },
		},
	},
	-- fast flat slash right-to-left, the forearm rolling over through the cut
	katana = {
		time = 0.3, hit = 0.36, trail = { 0.08, 0.62 },
		keys = {
			{ t = 0, rs = { 80, -55, 10, -20 }, re = 85, rw = { 0, -35, 0 }, ls = { 40, 30, 5, 0 }, le = 60, turn = -28 },
			{ t = 0.1, ease = "out", rs = { 85, -65, 12, -25 }, re = 95, rw = { 0, -45, 0 }, ls = { 45, 35, 5, 0 }, le = 65, turn = -34 },
			{ t = 0.36, ease = "out", rs = { 88, 45, 5, 30 }, re = 5, rw = { -80, 0, 0 }, ls = { -20, 0, 20, 0 }, le = 25, turn = 30, lean = 6 },
			{ t = 0.62, rs = { 82, 85, 5, 40 }, re = 18, rw = { -75, 10, 0 }, ls = { -30, 0, 25, 0 }, le = 30, turn = 40, lean = 8 },
			{ t = 1, rs = { 35, 30, 8, 10 }, re = 30, rw = { -20, 0, 0 }, ls = { 0, 0, 6, 0 }, le = 15, turn = 8 },
		},
	},
	-- both hands overhead, full-body slam into the ground in front
	greatsword = {
		time = 0.8, hit = 0.42, trail = { 0.16, 0.56 }, twoHand = -0.55,
		keys = {
			{ t = 0, rs = { 150, 10, 5, 0 }, re = 35, rw = { -60, 0, 0 }, lean = -8 },
			{ t = 0.2, ease = "out", rs = { 170, 12, 5, 0 }, re = 35, rw = { -70, 0, 0 }, lean = -14, turn = -6 },
			{ t = 0.42, ease = "in", rs = { 55, 18, 0, 0 }, re = 5, rw = { -75, 0, 0 }, lean = 24, turn = 4 },
			{ t = 0.66, rs = { 45, 18, 0, 0 }, re = 10, rw = { -78, 0, 0 }, lean = 26, turn = 4 },
			{ t = 1, rs = { 30, 12, 5, 0 }, re = 25, rw = { -15, 0, 0 }, lean = 6 },
		},
	},
	-- one full turn of the body to the left, the scythe held out wide at chest height
	scythe = {
		time = 0.62, hit = 0.5, trail = { 0.14, 0.86 },
		keys = {
			{ t = 0, rs = { 70, -40, 40, 0 }, re = 20, rw = { -60, 0, -75 }, ls = { 60, 30, 5, 0 }, le = 60, turn = -25 },
			{ t = 0.12, ease = "out", rs = { 75, -50, 45, 0 }, re = 15, rw = { -65, 0, -75 }, ls = { 65, 35, 5, 0 }, le = 60, turn = -32 },
			{ t = 0.5, ease = "inout", rs = { 80, -10, 55, 0 }, re = 10, rw = { -70, 0, -75 }, ls = { -10, 0, 40, 0 }, le = 20, turn = 5, spin = 200 },
			{ t = 0.86, ease = "out", rs = { 70, 20, 40, 0 }, re = 15, rw = { -65, 0, -70 }, ls = { 10, 0, 30, 0 }, le = 30, turn = 15, spin = 360 },
			{ t = 1, rs = { 40, 10, 20, 0 }, re = 25, rw = { -40, 0, -20 }, ls = { 0, 0, 8, 0 }, le = 15, spin = 360 },
		},
	},
	-- quick stab, alternating hands
	daggers = {
		time = 0.26, hit = 0.34, trail = { 0.1, 0.6 }, mirror = true,
		keys = {
			{ t = 0, rs = { 55, -10, 15, 0 }, re = 100, rw = { -30, 0, 0 }, ls = { 60, 15, 5, 0 }, le = 70, turn = -10 },
			{ t = 0.12, ease = "out", rs = { 50, -12, 18, 0 }, re = 115, rw = { -35, 0, 0 }, ls = { 65, 15, 5, 0 }, le = 80, turn = -14 },
			{ t = 0.34, ease = "out", rs = { 90, 12, 2, 0 }, re = 2, rw = { -90, 0, 0 }, ls = { 30, 5, 10, 0 }, le = 95, turn = 18, lean = 8 },
			{ t = 0.6, rs = { 85, 10, 4, 0 }, re = 10, rw = { -85, 0, 0 }, ls = { 32, 5, 10, 0 }, le = 90, turn = 16, lean = 7 },
			{ t = 1, rs = { 45, 5, 10, 0 }, re = 60, rw = { -40, 0, 0 }, ls = { 20, 5, 8, 0 }, le = 50, turn = 4 },
		},
	},
	-- pull back, then drive the point forward with a lunge
	spear = {
		time = 0.45, hit = 0.36, trail = { 0.14, 0.6 }, twoHand = 1.6,
		keys = {
			{ t = 0, rs = { -10, -10, 12, 0 }, re = 100, rw = { -90, 0, 0 }, lean = -4, turn = -18 },
			{ t = 0.16, ease = "out", rs = { -22, -12, 15, 0 }, re = 112, rw = { -90, 0, 0 }, lean = -8, turn = -24 },
			{ t = 0.36, ease = "out", rs = { 88, 10, 5, 0 }, re = 5, rw = { -88, 0, 0 }, lean = 18, turn = 20 },
			{ t = 0.6, rs = { 86, 10, 5, 0 }, re = 8, rw = { -88, 0, 0 }, lean = 16, turn = 18 },
			{ t = 1, rs = { 40, 0, 12, 0 }, re = 50, rw = { -60, 0, 0 }, lean = 3 },
		},
	},
	-- lifted high over the right shoulder, then brought down in a crushing overhead smash
	hammer = {
		time = 0.9, hit = 0.46, trail = { 0.2, 0.56 }, twoHand = 1.25,
		keys = {
			{ t = 0, rs = { 140, -10, 25, 0 }, re = 40, rw = { -55, 0, 0 }, lean = -6, turn = -12 },
			{ t = 0.25, ease = "out", rs = { 170, -8, 20, 0 }, re = 40, rw = { -75, 0, 0 }, lean = -16, turn = -14, tilt = 6 },
			{ t = 0.46, ease = "in", rs = { 45, 12, 0, 0 }, re = 5, rw = { -55, 0, 0 }, lean = 30, turn = 6 },
			{ t = 0.72, rs = { 40, 12, 0, 0 }, re = 8, rw = { -55, 0, 0 }, lean = 30, turn = 6 },
			{ t = 1, rs = { 28, 8, 5, 0 }, re = 25, rw = { -15, 0, 0 }, lean = 8 },
		},
	},
	-- bow in the right hand, turned side-on; the left hand draws the string to the chin and lets go
	bow = {
		time = 0.5, hit = 0.55, release = 0.55,
		keys = {
			{ t = 0, rs = { 80, 0, 0, 0 }, re = 10, rw = { -90, 0, 0 }, ls = { 80, 55, 0, 0 }, le = 20, lw = { 0, 0, 0 }, turn = 45 },
			{ t = 0.12, ease = "out", rs = { 88, 5, 0, 0 }, re = 5, rw = { -90, 0, 0 }, ls = { 88, 45, 0, 0 }, le = 25, turn = 55 },
			{ t = 0.52, ease = "inout", rs = { 90, 5, 0, 0 }, re = 5, rw = { -90, 0, 0 }, ls = { 85, 0, 20, 0 }, le = 140, turn = 60 },
			{ t = 0.6, ease = "out", rs = { 92, 5, 0, 0 }, re = 5, rw = { -90, 0, 0 }, ls = { 70, -20, 45, 0 }, le = 90, turn = 58 },
			{ t = 1, rs = { 45, 0, 5, 0 }, re = 20, rw = { -40, 0, 0 }, ls = { 15, 0, 10, 0 }, le = 20, turn = 12 },
		},
	},
	-- staff raised overhead, then thrust forward to cast
	staff = {
		time = 0.55, hit = 0.45, release = 0.42, trail = { 0.2, 0.5 },
		keys = {
			{ t = 0, rs = { -10, 0, 15, 0 }, re = 60, rw = { -20, 0, 0 }, ls = { 40, 20, 10, 0 }, le = 60, lean = -4 },
			{ t = 0.2, ease = "out", rs = { -25, 0, 18, 0 }, re = 70, rw = { -10, 0, 0 }, ls = { 50, 25, 12, 0 }, le = 70, lean = -10 },
			{ t = 0.42, ease = "out", rs = { 100, 5, 5, 0 }, re = 5, rw = { -130, 0, 0 }, ls = { 60, 15, 20, 0 }, le = 20, lean = 12, turn = 10 },
			{ t = 0.62, rs = { 92, 5, 5, 0 }, re = 8, rw = { -120, 0, 0 }, ls = { 40, 10, 20, 0 }, le = 25, lean = 10, turn = 8 },
			{ t = 1, rs = { 30, 0, 8, 0 }, re = 25, rw = { -40, 0, 0 }, ls = { 10, 0, 8, 0 }, le = 15 },
		},
	},
}
-- stylua: ignore end

local function toFrame(k: Key): { number }
	local f = table.create(N, 0)
	local function arm(base: number, a: { number }?, bend: number?, w: { number }?)
		if a then
			for i = 1, 4 do
				f[base + i - 1] = rad(a[i] or 0)
			end
		end
		f[base + 4] = rad(bend or 0)
		if w then
			for i = 1, 3 do
				f[base + 4 + i] = rad(w[i] or 0)
			end
		end
	end
	arm(C.rs, k.rs, k.re, k.rw)
	arm(C.ls, k.ls, k.le, k.lw)
	f[C.lean] = rad(k.lean or 0)
	f[C.turn] = rad(k.turn or 0)
	f[C.tilt] = rad(k.tilt or 0)
	f[C.spin] = rad(k.spin or 0)
	return f
end

local function ease(kind: string?, a: number): number
	if kind == "out" then
		return 1 - (1 - a) * (1 - a) * (1 - a)
	elseif kind == "in" then
		return a * a * a
	elseif kind == "inout" then
		return a < 0.5 and 4 * a * a * a or 1 - (-2 * a + 2) ^ 3 / 2
	end
	return a * a * (3 - 2 * a) -- smoothstep
end

function Poses.Style(name: string): Style
	return Poses.Styles[name] or Poses.Styles.sword
end

-- Seconds: whole attack, weapon connects, shot leaves (ranged)
function Poses.Timing(name: string, rate: number): (number, number, number?)
	local style = Poses.Style(name)
	local dur = math.min(style.time, 0.92 / math.max(rate, 0.1))
	return dur, dur * style.hit, style.release and dur * style.release or nil
end

-- How much the attack pose replaces the walk/idle animation at fraction p (instant start, fades at the end)
function Poses.Weight(p: number): number
	if p <= 0 or p >= 1 then
		return 0
	elseif p > 0.72 then
		local a = (1 - p) / 0.28
		return a * a * (3 - 2 * a)
	end
	return 1
end

local sampled = table.create(N, 0)
-- Channels (radians) of a style at fraction p (0..1). `alt` mirrors styles that alternate hands.
function Poses.Sample(name: string, p: number, alt: boolean?): { number }
	local style = Poses.Style(name)
	local frames = style.frames
	if not frames then
		frames = {}
		for i, k in style.keys do
			frames[i] = toFrame(k)
		end
		style.frames = frames
	end
	local keys = style.keys
	local i = 1
	while i < #keys and keys[i + 1].t < p do
		i += 1
	end
	local a, b = frames[i], frames[math.min(i + 1, #keys)]
	local t0, t1 = keys[i].t, keys[math.min(i + 1, #keys)].t
	local w = t1 > t0 and ease(keys[math.min(i + 1, #keys)].ease, clamp((p - t0) / (t1 - t0), 0, 1)) or 0
	for c = 1, N do
		sampled[c] = a[c] + (b[c] - a[c]) * w
	end
	if alt and style.mirror then
		for c = 0, 7 do
			sampled[C.rs + c], sampled[C.ls + c] = sampled[C.ls + c], sampled[C.rs + c]
		end
		sampled[C.turn], sampled[C.tilt], sampled[C.spin] = -sampled[C.turn], -sampled[C.tilt], -sampled[C.spin]
	end
	return sampled
end

-- Keyframe arm rotations for one side, adapted to the rig (R6 arms follow where the R15 hand would be)
local STD_UPPER = Vector3.new(0.5, -0.75, 0)
local STD_LOWER = Vector3.new(0, -0.9, 0)
local function keyArm(arm: Arm, f: { number }, base: number, grip: CFrame?): (CFrame, CFrame?, CFrame?)
	local right = arm.right
	local rs = Poses.Shoulder(f[base], f[base + 1], f[base + 2], f[base + 3], right)
	local re = Poses.Elbow(f[base + 4])
	local rw = Poses.Wrist(f[base + 5], f[base + 6], f[base + 7], right)
	if arm.el and arm.wr then
		return rs, re, rw
	end
	-- R6 (no elbow): turn the arm like the R15 hand, so the weapon points exactly the same way, then twist it
	-- about the weapon's axis until the arm points as close as it can to where the R15 hand would be
	local s = right and 1 or -1
	local tip = rs * (Vector3.new(s * STD_UPPER.X, STD_UPPER.Y, 0) + re * STD_LOWER)
	local q = rs * re * rw
	local blade = q * (grip and rot(grip) * Y or Vector3.new(0, 0, -1))
	local restTip = (rot(arm.sh.c0) * arm.sh.c1:Inverse()) * Vector3.new(0, -arm.size.Y / 2, 0)
	local now = q * restTip
	local a = now - blade * now:Dot(blade)
	local b = tip - blade * tip:Dot(blade)
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then
		return q, nil, nil
	end
	return axisAngle(blade, math.atan2(blade:Dot(a:Cross(b)), a:Dot(b))) * q, nil, nil
end

--[[
	Attack pose at fraction p of the swing. Fills `out` with rotations and returns the weight
	(how much the pose replaces the animation on the arms).
]]
function Poses.Attack(rig: Rig, name: string, p: number, alt: boolean?, out: Out): number
	local f = Poses.Sample(name, p, alt)
	local style = Poses.Style(name)
	local torso = Poses.Torso(f[C.lean], f[C.turn], f[C.tilt])
	local spin = CFrame.Angles(0, f[C.spin], 0)
	if rig.r6 then
		-- no waist on R6: turn and lean the whole body a bit less
		out.root = spin * Poses.Torso(f[C.lean] * 0.45, f[C.turn] * 0.7, f[C.tilt] * 0.5)
	else
		out.root = spin
		out.waist = torso
	end
	out.neck = CFrame.Angles(0, -f[C.turn] * 0.45, 0) * CFrame.Angles(f[C.lean] * 0.35, 0, 0)
	local right, left = rig.right, rig.left
	if right then
		out.rs, out.re, out.rw = keyArm(right, f, C.rs, rig.grip)
	end
	if left then
		out.ls, out.le, out.lw = keyArm(left, f, C.ls, rig.grip)
	end
	-- two-handed weapons: the left hand grabs the handle wherever the right hand swung it
	local grip = rig.grip
	if style.twoHand and grip and right and left and out.rs and not (alt and style.mirror) then
		local held = holder(right, out.rs, out.re, out.rw) * grip
		local point = held * Vector3.new(0, style.twoHand, 0)
		if left.el and left.wr then
			-- the left hand wraps the handle: its grip face on the shaft, fingers around it like the right hand's
			local grab = CFrame.new(point) * rot(held) * rot(grip):Inverse()
			local hand = grab * CFrame.new(0, left.size.Y / 2, 0)
			out.ls, out.le, out.lw = Poses.ReachR15(left, hand, Vector3.new(-1, -0.6, 0.3))
		else
			out.ls = Poses.ReachR6(left, point, Vector3.new(-1, -0.6, 0.3))
		end
	end
	return Poses.Weight(p)
end

return Poses
