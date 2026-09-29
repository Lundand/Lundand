--[[
	MobAnim — procedural mob animation, no uploaded animation assets needed.
	Idle breathing and looking around, walk / trot / hop / hover / skitter cycles that blend in with speed,
	per-archetype attacks (wind-up -> strike -> recover), jaws, tails, wings, capes, tentacles and pincers.
	Elites and bosses move heavier (slower cycles, bigger swings). Stunned mobs freeze in place.
	Joint names come from Models.Mob (server): see the rig contract at the top of Models.luau.
	Runs every frame for mobs within 170 studs of the camera: one C0 write per joint.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local MobAnim = {}

type Motor = { m: Motor6D, c0: CFrame }
type MobState = {
	model: Model,
	root: BasePart,
	motors: { [string]: Motor },
	arch: string,
	phase: number,
	lunge: number,
	seed: number,
	move: number,
	s: number,
	heavy: number,
}

local mobAnims: { [Model]: MobState } = {}
local camera = workspace.CurrentCamera
local ANG = CFrame.Angles
local CF = CFrame.new
local ARCH_SCALE = { biped = 2, quad = 2, blob = 3, floater = 2, bug = 2.4 } -- root.Size.X at scale 1

local function scanMotors(anim: MobState)
	for _, d in anim.model:GetDescendants() do
		if d:IsA("Motor6D") and not anim.motors[d.Name] then
			anim.motors[d.Name] = { m = d, c0 = d.C0 }
		end
	end
end

local function registerMob(model: Instance)
	if not model:IsA("Model") or mobAnims[model] then
		return
	end
	task.defer(function()
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not model.Parent then
			return
		end
		local arch = tostring(model:GetAttribute("Arch") or "biped")
		local tier = model:GetAttribute("Tier")
		local scale = tonumber(model:GetAttribute("Scale")) or root.Size.X / (ARCH_SCALE[arch] or 2)
		local anim: MobState = {
			model = model,
			root = root,
			motors = {},
			arch = arch,
			phase = math.random() * 6,
			lunge = -10,
			seed = math.random() * 10,
			move = 0,
			s = scale,
			heavy = tier == "boss" and 1.6 or (tier == "elite" and 1.2 or 1),
		}
		scanMotors(anim)
		mobAnims[model] = anim
	end)
end

local function set(anim: MobState, name: string, cf: CFrame)
	local motor = anim.motors[name]
	if motor then
		motor.m.C0 = motor.c0 * cf
	end
end

-- Attack curve: 0 -> -1 (wind-up) -> +1 (strike) -> 0; returns wind (0..1), hit (0..1), active
local function attackCurve(age: number, duration: number): (number, number, boolean)
	if age < 0 or age >= duration then
		return 0, 0, false
	end
	local p = age / duration
	local a
	if p < 0.35 then
		a = -math.sin(p / 0.35 * math.pi / 2)
	elseif p < 0.55 then
		a = -1 + 2 * (p - 0.35) / 0.2
	else
		a = math.cos((p - 0.55) / 0.45 * math.pi / 2)
	end
	return math.max(-a, 0), math.max(a, 0), true
end

local function animateBiped(anim: MobState, t: number, move: number, wind: number, hit: number, attacking: boolean)
	local s, ph, seed = anim.s, anim.phase, anim.seed
	local swing = math.sin(ph) * 0.62 * move
	local breathe = math.sin(t * 1.9 + seed) * (1 - move)
	-- legs: stride, plus a step into the strike
	set(anim, "LeftHip", ANG(swing + hit * 0.35, 0, 0))
	set(anim, "RightHip", ANG(-swing - hit * 0.3, 0, 0))
	-- arms: counter-swing and idle sway; the right arm raises the weapon and brings it down
	local sway = math.sin(t * 1.6 + seed) * 0.05 * (1 - move)
	set(anim, "LeftShoulder", ANG(-swing * 0.8 + sway + wind * 0.5 - hit * 0.3, 0, -0.06 - wind * 0.2))
	local rs = swing * 0.8 - sway
	if attacking then
		rs = wind * 2.9 + hit * 1.0
	end
	set(anim, "RightShoulder", ANG(rs, 0, 0.06 + wind * 0.15))
	-- torso: bob twice per stride, lean into the run, twist with the steps, breathe when idle
	local bob = math.abs(math.cos(ph)) * 0.1 * s * move + breathe * 0.03 * s
	local lean = -0.1 * move + wind * 0.22 - hit * 0.38
	local twist = math.sin(ph) * 0.1 * move - wind * 0.3 + hit * 0.35
	set(anim, "Waist", CF(0, bob, 0) * ANG(lean, twist, 0))
	-- head looks around when idle, steadies when running
	local look = math.sin(t * 0.7 + seed) * 0.28 * (1 - move * 0.7)
	set(anim, "Neck", ANG(math.sin(t * 1.3 + seed) * 0.06 - hit * 0.15 + wind * 0.1, look - twist * 0.5, 0))
	set(anim, "Jaw", ANG(-(wind * 0.5 + math.max(math.sin(t * 5 + seed), 0) * 0.05), 0, 0))
	set(anim, "Tail", ANG(-0.1 * move + math.sin(t * 2.6 + seed) * 0.12, math.sin(t * 2.2 + seed) * 0.4, 0))
	local flap = math.sin(t * (2.6 + move * 5) + seed)
	local spread = wind * 0.5
	set(anim, "LeftWing", ANG(0, flap * 0.35 + spread, flap * 0.22 + spread * 0.4))
	set(anim, "RightWing", ANG(0, -flap * 0.35 - spread, -flap * 0.22 - spread * 0.4))
	set(anim, "Cape", ANG(-(0.08 + move * 0.5 + math.sin(t * 4 + seed) * 0.05 * (0.4 + move)), 0, 0))
end

local function animateQuad(anim: MobState, t: number, move: number, wind: number, hit: number)
	local s, ph, seed = anim.s, anim.phase, anim.seed
	local swing = math.sin(ph) * 0.6 * move
	local shift = math.sin(t * 1.2 + seed) * 0.04 * (1 - move)
	-- diagonal pairs move together (trot); front legs reach and back legs push during the pounce
	set(anim, "LegFL", ANG(swing + shift + hit * 0.6 - wind * 0.2, 0, 0))
	set(anim, "LegBR", ANG(swing - shift - hit * 0.45 + wind * 0.25, 0, 0))
	set(anim, "LegFR", ANG(-swing + shift + hit * 0.6 - wind * 0.2, 0, 0))
	set(anim, "LegBL", ANG(-swing - shift - hit * 0.45 + wind * 0.25, 0, 0))
	local bob = math.abs(math.cos(ph)) * 0.09 * s * move + math.sin(t * 2 + seed) * 0.02 * s * (1 - move)
	local y = bob - wind * 0.16 * s + hit * 0.22 * s
	set(anim, "Body", CF(0, y, -hit * 0.55 * s) * ANG(math.sin(ph * 2) * 0.03 * move + wind * 0.1 - hit * 0.12, 0, 0))
	local look = math.sin(t * 0.6 + seed) * 0.3 * (1 - move * 0.8)
	set(anim, "Neck", ANG(math.sin(t * 1.1 + seed) * 0.06 - math.abs(math.sin(ph)) * 0.05 * move + wind * 0.25 - hit * 0.35, look, 0))
	set(anim, "Jaw", ANG(-(wind * 0.55 + hit * 0.1 + math.max(math.sin(t * 3 + seed), 0) * 0.04 * (1 - move)), 0, 0))
	local wag = math.sin(t * (7 - move * 3) + seed)
	set(anim, "TailJoint", ANG(-move * 0.25, wag * 0.4 * (1 - move * 0.5), 0))
	set(anim, "Tail2", ANG(-move * 0.1, math.sin(t * (7 - move * 3) + seed - 0.9) * 0.45, 0))
end

local function animateBlob(anim: MobState, t: number, move: number, wind: number, hit: number)
	local s, ph, seed = anim.s, anim.phase, anim.seed
	local hop = math.abs(math.sin(ph * 0.5))
	local y = hop * 0.8 * s * move + math.abs(math.sin(t * 2.5 + seed)) * 0.06 * s * (1 - move) - wind * 0.15 * s + hit * 0.6 * s
	local tilt = -hop * 0.12 * move + math.sin(t * 1.7 + seed) * 0.04 + wind * 0.15 - hit * 0.2
	set(anim, "Body", CF(0, y, -hit * 0.9 * s) * ANG(tilt, 0, math.sin(t * 2.1 + seed) * 0.05 * (1 - move)))
end

local function animateFloater(anim: MobState, t: number, move: number, wind: number, hit: number)
	local s, seed, heavy = anim.s, anim.seed, anim.heavy
	local hover = math.sin(t * 2 / heavy + seed) * 0.35 * s
	set(anim, "Body", CF(0, hover + wind * 0.2 * s, wind * 0.4 * s - hit * 1.2 * s) * ANG(-0.2 * move + wind * 0.25 - hit * 0.35, 0, math.sin(t * 1.3 + seed) * 0.05))
	set(anim, "Spin", ANG(0, t * (1.8 + move) / heavy + seed, 0))
	set(anim, "Tail", ANG(math.sin(t * 3 + seed) * 0.25 + move * 0.3, 0, math.sin(t * 2.2 + seed) * 0.2))
	for i = 1, 6 do
		set(anim, "Tent" .. i, ANG(math.sin(t * 2.4 + i * 1.1 + seed) * 0.28 - hit * 0.6, 0, math.cos(t * 2.1 + i * 1.7) * 0.25))
	end
	set(anim, "LeftArm", ANG(math.sin(t * 2 + seed) * 0.15 + wind * 2.0 + hit * 1.0, 0, -wind * 0.3))
	set(anim, "RightArm", ANG(math.sin(t * 2 + seed + 1) * 0.15 + wind * 2.0 + hit * 1.0, 0, wind * 0.3))
end

local function animateBug(anim: MobState, t: number, move: number, wind: number, hit: number)
	local s, ph, seed = anim.s, anim.phase, anim.seed
	-- tripod gait: legs 1, 4, 5 against 2, 3, 6; odd legs are on the left
	for i = 1, 6 do
		local group = (i == 1 or i == 4 or i == 5) and 0 or math.pi
		local side = i % 2 == 1 and -1 or 1
		local sweep = math.sin(ph * 1.4 + group) * 0.4 * move
		local lift = math.max(math.cos(ph * 1.4 + group), 0) * 0.3 * move
		set(anim, "Leg" .. i, ANG(0, sweep, side * lift))
	end
	set(anim, "Body", CF(0, math.abs(math.sin(ph * 1.4)) * 0.05 * s * move - wind * 0.08 * s, -hit * 0.35 * s))
	-- the tail curls back on the wind-up and stings forward over the head
	local sway = math.sin(t * 1.5 + seed) * 0.15
	set(anim, "TailJoint", ANG(wind * 0.3 - hit * 0.5 + math.sin(t * 2 + seed) * 0.04, sway, 0))
	set(anim, "Tail2", ANG(wind * 0.25 - hit * 0.45 + math.sin(t * 2 + seed + 0.6) * 0.05, 0, 0))
	set(anim, "Tail3", ANG(wind * 0.2 - hit * 0.4, 0, 0))
	local snap = math.max(math.sin(t * 2.3 + seed), 0) ^ 4 * 0.35
	set(anim, "ClawL", ANG(0, -snap - wind * 0.4 + hit * 0.3, 0))
	set(anim, "ClawR", ANG(0, snap + wind * 0.4 - hit * 0.3, 0))
end

local function animateMob(anim: MobState, dt: number, t: number, serverNow: number)
	local model = anim.model
	if (model:GetAttribute("StunnedUntil") or 0) > serverNow then
		return -- frozen in place while stunned
	end
	local vel = anim.root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local target = math.clamp(speed / 12, 0, 1.2)
	anim.move += (target - anim.move) * math.min(1, dt * 8)
	local move = anim.move
	-- bigger mobs take slower, longer strides
	anim.phase += dt * (3 + speed * 0.55) / math.sqrt(math.max(anim.s, 0.5))
	local wind, hit, attacking = attackCurve(t - anim.lunge, 0.42 * anim.heavy ^ 0.7)
	local arch = anim.arch
	if arch == "biped" then
		animateBiped(anim, t, move, wind, hit, attacking)
	elseif arch == "quad" then
		animateQuad(anim, t, move, wind, hit)
	elseif arch == "blob" then
		animateBlob(anim, t, move, wind, hit)
	elseif arch == "floater" then
		animateFloater(anim, t, move, wind, hit)
	elseif arch == "bug" then
		animateBug(anim, t, move, wind, hit)
	end
end

-- Called by FX when the server says a mob attacks
function MobAnim.Lunge(model: Instance)
	local anim = model:IsA("Model") and mobAnims[model]
	if anim then
		anim.lunge = os.clock()
	end
end

function MobAnim.Init()
	for _, model in CollectionService:GetTagged("Mob") do
		registerMob(model)
	end
	CollectionService:GetInstanceAddedSignal("Mob"):Connect(registerMob)
	CollectionService:GetInstanceRemovedSignal("Mob"):Connect(function(model)
		if model:IsA("Model") then
			mobAnims[model] = nil
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		local camPos = camera.CFrame.Position
		for model, anim in mobAnims do
			if not model.Parent then
				mobAnims[model] = nil
			elseif (anim.root.Position - camPos).Magnitude < 170 then
				if next(anim.motors) == nil then
					scanMotors(anim)
				end
				animateMob(anim, dt, t, serverNow)
			end
		end
	end)
end

return MobAnim
