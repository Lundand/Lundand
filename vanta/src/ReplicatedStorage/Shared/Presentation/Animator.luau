--!strict
-- Plays combat animations on any character, on the client (L-03, L-51). Each animation in Config/Animations plays as
-- a real animation track at Action priority, so it shows over walking and idling. Uploaded animations use their
-- assetId. Until an animation is uploaded, Studio plays it from its KeyframeSequence in Shared.AnimationSequences
-- (built from the same keyframes) through a temporary ID that only works in Studio; live servers need the upload.
local ContentProvider = game:GetService("ContentProvider")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent
local Animations = require(Shared.Config.Animations)
local Signal = require(Shared.Util.Signal)

local Animator = {}
-- Weapon-specific versions of shared clips (dodges and reactions end in the weapon's own stance, so the arms don't snap
-- to another weapon's guard). Resolved inside play/onMarker, so callers just ask for the plain name.
local VARIANTS: {[string]: {[string]: string}} = {
	Staff = {
		Dodge = "StaffDodge", DodgeForward = "StaffDodgeForward", DodgeLeft = "StaffDodgeLeft", DodgeRight = "StaffDodgeRight",
		HitReactLight = "StaffHitReactLight", HitReactHeavy = "StaffHitReactHeavy", Stagger = "StaffStagger",
	},
	Dagger = {
		Dodge = "DaggerDodge", DodgeForward = "DaggerDodgeForward", DodgeLeft = "DaggerDodgeLeft", DodgeRight = "DaggerDodgeRight",
		HitReactLight = "DaggerHitReactLight", HitReactHeavy = "DaggerHitReactHeavy", Stagger = "DaggerStagger",
	},
	Bow = {
		Dodge = "BowDodge", DodgeForward = "BowDodgeForward", DodgeLeft = "BowDodgeLeft", DodgeRight = "BowDodgeRight",
		HitReactLight = "BowHitReactLight", HitReactHeavy = "BowHitReactHeavy", Stagger = "BowStagger",
	},
	Mace = {
		Dodge = "MaceDodge", DodgeForward = "MaceDodgeForward", DodgeLeft = "MaceDodgeLeft", DodgeRight = "MaceDodgeRight",
		HitReactLight = "MaceHitReactLight", HitReactHeavy = "MaceHitReactHeavy", Stagger = "MaceStagger",
	},
	Spear = {
		Dodge = "SpearDodge", DodgeForward = "SpearDodgeForward", DodgeLeft = "SpearDodgeLeft", DodgeRight = "SpearDodgeRight",
		HitReactLight = "SpearHitReactLight", HitReactHeavy = "SpearHitReactHeavy", Stagger = "SpearStagger",
	},
	Greataxe = {
		Dodge = "AxeDodge", DodgeForward = "AxeDodgeForward", DodgeLeft = "AxeDodgeLeft", DodgeRight = "AxeDodgeRight",
		HitReactLight = "AxeHitReactLight", HitReactHeavy = "AxeHitReactHeavy", Stagger = "AxeStagger",
	},
	Fist = {
		Dodge = "FistDodge", DodgeForward = "FistDodgeForward", DodgeLeft = "FistDodgeLeft", DodgeRight = "FistDodgeRight",
		HitReactLight = "FistHitReactLight", HitReactHeavy = "FistHitReactHeavy", Stagger = "FistStagger",
	},
	Greatsword = {
		SwordCombo1 = "GreatswordCombo1", SwordCombo2 = "GreatswordCombo2", SwordCombo3 = "GreatswordCombo3", SwordHeavy = "GreatswordHeavy",
		SwordSweep = "GreatswordSweep", SwordParry = "GreatswordParry", SwordRiposte = "GreatswordRiposte",
		Dodge = "GreatswordDodge", DodgeForward = "GreatswordDodgeForward", DodgeLeft = "GreatswordDodgeLeft", DodgeRight = "GreatswordDodgeRight",
		HitReactLight = "GreatswordHitReactLight", HitReactHeavy = "GreatswordHitReactHeavy", Stagger = "GreatswordStagger",
	},
}

local function resolve(model: Model, animationId: string): string
	local weaponType = model:GetAttribute("WeaponType")
	local variants = if type(weaponType) == "string" then VARIANTS[weaponType] else nil
	local variant = variants and variants[animationId]
	if variant ~= nil and Animations[variant] ~= nil then
		return variant
	end
	return animationId
end
-- Fires (model, animationId) whenever an action clip starts, so presentation code can react (combat stance).
Animator.played = Signal.new()
local animationIds: {[string]: string} = {}
local tracks: {[Model]: {[string]: AnimationTrack}} = {}
local current: {[Model]: AnimationTrack} = {}
local stances: {[Model]: {id: string, track: AnimationTrack}} = {}
local rotation: {[Model]: number} = setmetatable({}, { __mode = "k" }) :: any

local function idFor(animationId: string): string?
	local known = animationIds[animationId]
	if known ~= nil then
		return known
	end
	local def = Animations[animationId]
	if def == nil then
		return nil
	end
	local id = nil
	if (def.assetId or 0) > 0 then
		id = "rbxassetid://" .. tostring(def.assetId)
	elseif RunService:IsStudio() then
		local folder = Shared:FindFirstChild("AnimationSequences")
		local sequence = folder and folder:FindFirstChild(animationId)
		if sequence ~= nil and sequence:IsA("KeyframeSequence") then
			local ok, result = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
			end)
			if ok then
				id = result
			end
		end
	end
	if id ~= nil then
		animationIds[animationId] = id
	end
	return id
end

local function trackFor(model: Model, animationId: string): AnimationTrack?
	local cached = tracks[model] and tracks[model][animationId]
	if cached ~= nil then
		return cached
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local id = idFor(animationId)
	if humanoid == nil or id == nil then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or track == nil then
		return nil
	end
	-- Stance clips (loop = true) keep the Movement priority they were authored with, so walking legs play beneath them. A loop
	-- marked `action` (gathering) is a full action clip that simply repeats.
	local def = Animations[animationId]
	if def.loop == true then
		track.Looped = true
	end
	if def.loop ~= true or def.action == true then
		track.Priority = Enum.AnimationPriority.Action
	end
	if tracks[model] == nil then
		tracks[model] = {}
		model.AncestryChanged:Connect(function()
			if model.Parent == nil then
				tracks[model] = nil
				current[model] = nil
				stances[model] = nil
			end
		end)
	end
	tracks[model][animationId] = track
	return track
end

-- `windup`: for clips with a `hit` moment (spell casts), the clip is sped up or slowed so the release lands on it.
function Animator.play(model: Model, requestedId: string, windup: number?)
	local animationId = resolve(model, requestedId)
	local alternates = Animations[animationId].alternates
	if alternates ~= nil then
		local turn = ((rotation[model] or 0) % #alternates) + 1
		rotation[model] = turn
		animationId = alternates[turn]
	end
	local track = trackFor(model, animationId)
	if track == nil then
		return
	end
	local previous = current[model]
	if previous ~= nil and previous ~= track and previous.IsPlaying then
		previous:Stop(0.05)
	end
	local speed = 1
	local hit = Animations[animationId].hit
	if hit ~= nil and windup ~= nil then
		speed = math.clamp(hit / math.max(windup, 0.04), 0.6, 2.5)
	end
	track:Play(0.05, 1, speed)
	current[model] = track
	Animator.played:Fire(model, animationId)
end

-- Whether a character is still inside an action clip (not yet in its last stretch). Light hit reactions use this so
-- they don't cut off a swing.
function Animator.busy(model: Model): boolean
	local track = current[model]
	return track ~= nil and track.IsPlaying and track.TimePosition < track.Length * 0.85
end

-- Downloads every uploaded combat animation up front. Without this the first use of each clip arrives a few tenths of
-- a second late, so the first swing of a fight would miss its hit timing.
function Animator.preloadAll()
	local list = {}
	for _, def in pairs(Animations) do
		if (def.assetId or 0) > 0 then
			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. tostring(def.assetId)
			table.insert(list, animation)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	for _, animation in ipairs(list) do
		animation:Destroy()
	end
end

-- Whether a character is still playing a given clip (used to keep props, like a nocked arrow, in step with it).
function Animator.isPlaying(model: Model, animationId: string): boolean
	local byClip = tracks[model]
	local track = byClip and byClip[animationId]
	return track ~= nil and track.IsPlaying
end

-- Interrupts whatever action clip a character is playing (hit reactions, death).
function Animator.interrupt(model: Model, fade: number?)
	local track = current[model]
	if track ~= nil and track.IsPlaying then
		track:Stop(fade or 0.05)
	end
	current[model] = nil
end

-- Runs `callback` when an animation marker (for example "Hit") is reached on a clip's track, if the clip has one.
function Animator.onMarker(model: Model, animationId: string, markerName: string, callback: () -> ()): RBXScriptConnection?
	local track = trackFor(model, resolve(model, animationId))
	if track == nil then
		return nil
	end
	return track:GetMarkerReachedSignal(markerName):Connect(callback)
end

-- Holds a looping stance (relaxed or combat idle) on a character; nil removes it. Safe to call repeatedly.
function Animator.setStance(model: Model, animationId: string?)
	local held = stances[model]
	if held ~= nil and held.id == animationId then
		return
	end
	if held ~= nil then
		held.track:Stop(0.25)
		stances[model] = nil
	end
	if animationId == nil then
		return
	end
	local track = trackFor(model, animationId)
	if track == nil then
		return
	end
	track:Play(0.25)
	stances[model] = { id = animationId, track = track }
end

-- Hitstop: holds a character's current pose for a moment, so hits land with weight.
function Animator.freeze(model: Model, seconds: number)
	local track = current[model]
	if track ~= nil and track.IsPlaying then
		local speed = track.Speed
		track:AdjustSpeed(0)
		task.delay(seconds, function()
			if track.IsPlaying then
				track:AdjustSpeed(speed)
			end
		end)
	end
end

return Animator
