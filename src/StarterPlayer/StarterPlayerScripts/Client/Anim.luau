--[[
	Anim — procedural player animation, no uploaded animation assets needed.
	* A distinct attack for every weapon style (keyframes in Poses), started instantly by Anim.Swing,
	  with the weapon's "SwingTrail" trails switched on during the strike
	* Both hands on the carried Core: arm IK aimed at the Core part every frame, legs keep walking
	* R15 (Motor6D, or the AnimationConstraints of the Avatar Joint Upgrade) and R6. Poses are written to the
	  joints' Transform in PreSimulation — after the Animator, before physics — so C0 is never touched and the
	  default walk/idle animation keeps running underneath (arm poses fade it out, torso poses add to it)
	* Runs on every client for every player's character (Transform is local)
	* Mob animation lives in MobAnim (Anim.Lunge / Anim.Init forward to it)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MobAnim = require(script.Parent.MobAnim)
local Poses = require(script.Parent.Poses)

local Anim = {}

type JointState = { anim: CFrame, written: CFrame? }
type State = {
	character: Model,
	rig: Poses.Rig?,
	joints: Poses.Joints,
	jstate: { [Instance]: JointState },
	readAt: number,
	style: string,
	start: number,
	dur: number,
	alt: boolean,
	attacking: boolean,
	carry: number, -- 0..1 blend of the carry pose
	weapon: Instance?,
	trails: { Trail },
	trailOn: boolean,
}

local states: { [Model]: State } = {}
local camera = workspace.CurrentCamera
local ANIMATE_DISTANCE = 220
local CARRY_BLEND = 0.18 -- seconds to lift / lower the arms around the Core

-- Mobs (kept here so callers only need one module)
function Anim.Lunge(model: Instance)
	MobAnim.Lunge(model)
end

--------------------------------------------------------------------------------
-- Per-character state
--------------------------------------------------------------------------------
local function getState(character: Model): State
	local state = states[character]
	if not state then
		state = {
			character = character,
			rig = nil,
			joints = {},
			jstate = {},
			readAt = -math.huge,
			style = "sword",
			start = 0,
			dur = 0.3,
			alt = false,
			attacking = false,
			carry = 0,
			weapon = nil,
			trails = {},
			trailOn = false,
		}
		states[character] = state
	end
	return state
end

-- (Re)reads the joints when the rig changes (respawn, avatar loading, scaling) or every couple of seconds
local function refreshRig(state: State, now: number)
	local stale = now - state.readAt > 2
	if not stale then
		for _, joint in state.joints do
			if not joint.Parent then
				stale = true
				break
			end
		end
	end
	if not stale and (state.rig or now - state.readAt < 0.5) then
		return
	end
	state.readAt = now
	local rig, joints = Poses.Read(state.character)
	state.rig, state.joints = rig, joints
	if rig then
		rig.grip = Poses.Grip(state.character)
	end
end

local function setTrails(state: State, on: boolean)
	if state.trailOn == on then
		return
	end
	state.trailOn = on
	for _, trail in state.trails do
		if trail.Parent then
			trail.Enabled = on
		end
	end
end

-- Weapon grip (for two-handed poses) and swing trails, re-read when the weapon model changes
local function refreshWeapon(state: State)
	local weapon = state.character:FindFirstChild("EquippedWeapon")
	if weapon == state.weapon then
		return
	end
	setTrails(state, false)
	state.weapon = weapon
	state.trails = {}
	state.trailOn = false
	if state.rig then
		state.rig.grip = Poses.Grip(state.character)
	end
	if weapon then
		for _, d in weapon:GetDescendants() do
			if d:IsA("Trail") and d.Name == "SwingTrail" then
				table.insert(state.trails, d)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Writing joints
--------------------------------------------------------------------------------
-- The animation's own Transform this frame. If the Animator did not rewrite the joint (throttled, or no track
-- touches it) it still holds what we wrote last frame, so reuse the value we saw under it.
local function animOf(state: State, joint: Instance): CFrame
	local js = state.jstate[joint]
	local current: CFrame = (joint :: any).Transform
	if not js then
		js = { anim = current, written = nil }
		state.jstate[joint] = js
		return current
	end
	local written = js.written
	if not (written and current:FuzzyEq(written, 1e-5)) then
		js.anim = current
	end
	return js.anim
end

local function write(state: State, key: string, R: CFrame?, weight: number)
	local joint = state.joints[key]
	if not joint then
		return
	end
	local anim = animOf(state, joint)
	local js = state.jstate[joint]
	local target: any = joint -- Motor6D or AnimationConstraint: both have Transform
	if R and weight > 0 then
		local frames = Poses.Frames(joint)
		if frames then
			local t = Poses.JointTransform(key, frames.c0, R, anim, weight)
			target.Transform = t
			js.written = t
			return
		end
	end
	if js.written then
		target.Transform = anim -- hand the joint back to the animation
		js.written = nil
	end
end

local KEYS = { "root", "waist", "neck", "rs", "re", "rw", "ls", "le", "lw" }

local function release(state: State)
	for _, key in KEYS do
		write(state, key, nil, 0)
	end
	setTrails(state, false)
end

--------------------------------------------------------------------------------
-- Carrying
--------------------------------------------------------------------------------
local function carriedCore(character: Model): (BasePart?, number)
	local model = character:FindFirstChild("CarriedCore")
	if not model then
		return nil, 0
	end
	local core = (model :: Model).PrimaryPart or model:FindFirstChild("Core")
	if not core or not core:IsA("BasePart") then
		return nil, 0
	end
	local shell = model:FindFirstChild("Shell")
	if shell and shell:IsA("BasePart") then
		return core, math.min(shell.Size.X, shell.Size.Y, shell.Size.Z) / 2
	end
	return core, math.max(core.Size.X, core.Size.Y, core.Size.Z) * 0.7
end

local function carryPose(state: State, rig: Poses.Rig, root: BasePart, out: Poses.Out)
	local core, radius = carriedCore(state.character)
	if not core then
		-- the Core has not replicated yet: arms reach forward
		out.rs = Poses.Shoulder(math.rad(70), math.rad(12), 0, 0, true)
		out.ls = Poses.Shoulder(math.rad(70), math.rad(12), 0, 0, false)
		return
	end
	local center = root.CFrame:PointToObjectSpace(core.Position)
	local rootJoint, waistJoint = state.joints.root, state.joints.waist
	local rootT = if rootJoint then animOf(state, rootJoint) else CFrame.identity
	local waistT = if waistJoint then animOf(state, waistJoint) else CFrame.identity
	Poses.CarryPose(rig, center, radius, rootT, waistT, out)
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------
local function animate(state: State, now: number, dt: number)
	local character = state.character
	local root = character:FindFirstChild("HumanoidRootPart")
	refreshRig(state, now)
	local rig = state.rig
	if not rig or not root or not root:IsA("BasePart") then
		return
	end
	refreshWeapon(state)

	local carrying = character:GetAttribute("Carrying") == true
	local goal = carrying and 1 or 0
	state.carry = if state.carry < goal then math.min(goal, state.carry + dt / CARRY_BLEND) else math.max(goal, state.carry - dt / CARRY_BLEND)

	local out: Poses.Out = {}
	local weight = 0
	local trail = false
	if state.carry > 0 then
		state.attacking = false
		carryPose(state, rig, root, out)
		weight = state.carry
	elseif state.attacking then
		local p = (now - state.start) / state.dur
		if p >= 1 then
			state.attacking = false
		else
			weight = Poses.Attack(rig, state.style, p, state.alt, out)
			local window = Poses.Style(state.style).trail
			trail = window ~= nil and p >= window[1] and p <= window[2]
		end
	end
	setTrails(state, trail)
	for _, key in KEYS do
		write(state, key, (out :: any)[key], weight)
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------
--[[
	Starts the attack animation of `style` on a character (the local player's predicted swing or another
	player's). Returns the seconds until the weapon connects, until a shot leaves (ranged styles) and the whole
	swing's length, so FX can time slashes, sparks and projectiles to the motion.
]]
function Anim.Swing(character: Model, style: string): (number, number?, number)
	local cfg = Config.WeaponStyles[style]
	local dur, hit, release = Poses.Timing(style, cfg and cfg.rate or 1.5)
	local state = getState(character)
	local s = Poses.Style(style)
	state.alt = s.mirror == true and state.style == style and not state.alt
	state.style = style
	state.start = os.clock()
	state.dur = dur
	state.attacking = true
	return hit, release, dur
end

-- Whether the character's current swing is the mirrored one (daggers alternate hands)
function Anim.IsAlt(character: Model): boolean
	local state = states[character]
	return state ~= nil and state.alt
end

function Anim.Init()
	MobAnim.Init()
	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		local camPos = (workspace.CurrentCamera or camera).CFrame.Position
		local live: { [Model]: boolean } = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and character.Parent then
				live[character] = true
				local state = states[character]
				local root = character:FindFirstChild("HumanoidRootPart")
				local near = root and root:IsA("BasePart") and (root.Position - camPos).Magnitude < ANIMATE_DISTANCE
				if near and (state or character:GetAttribute("Carrying")) then
					animate(state or getState(character), now, dt)
				elseif state then
					release(state)
				end
			end
		end
		-- forget characters that despawned (their joints went with them)
		for character in states do
			if not live[character] then
				states[character] = nil
			end
		end
	end)
end

return Anim
