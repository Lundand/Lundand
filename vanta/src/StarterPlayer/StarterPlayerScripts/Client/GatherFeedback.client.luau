--!strict
-- Gathering animations (animation pass): while a player holds a gathering prompt, the server sets the GatherNode attribute on
-- their character; every client then shows that character mining, chopping or harvesting, with the tool in hand and sparks,
-- wood chips or torn leaves at each strike. Presentation only: what a node gives, and whether the gather succeeds, is decided
-- by GatheringService as before.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animator = require(Shared.Presentation.Animator)
local ToolProps = require(Shared.Presentation.ToolProps)

type Kind = { clip: string, tool: string?, color: Color3, material: Enum.Material?, amount: number }
local WOOD: Kind = { clip = "GatherChop", tool = "Hatchet", color = Color3.fromRGB(196, 156, 108), amount = 7 }
local ROCK: Kind = { clip = "GatherMine", tool = "Pickaxe", color = Color3.fromRGB(255, 214, 140), amount = 9 }
local LEAF: Kind = { clip = "GatherHarvest", tool = nil, color = Color3.fromRGB(110, 190, 100), amount = 6 }
local KINDS: { [string]: Kind } = {
	OakTree = WOOD,
	CopperVein = ROCK, IronVein = ROCK, SilverVein = ROCK,
	HealingHerbPatch = LEAF, CaveMushroomCluster = LEAF,
}
-- Where each tool sits in the hand (the same grip the weapon models use).
local TOOL_GRIP = CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(-135), 0, 0)

type State = { clip: string, prop: Model?, hidden: { [BasePart]: number }, marker: RBXScriptConnection?, moving: RBXScriptConnection }
local states: { [Model]: State } = {}

local function burst(character: Model, kind: Kind)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local low = kind == LEAF
	local at = root.Position + root.CFrame.LookVector * (if low then 2.2 else 3.2) + Vector3.new(0, if low then -1.6 else 0.4, 0)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = at
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(kind.color)
	emitter.LightEmission = if kind == ROCK then 1 else 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(8, 16)
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Enabled = false
	emitter.Parent = attachment
	anchor.Parent = workspace
	emitter:Emit(kind.amount)
	Debris:AddItem(anchor, 1)
end

local function stop(character: Model)
	local state = states[character]
	if state == nil then
		return
	end
	states[character] = nil
	state.moving:Disconnect()
	if state.marker ~= nil then
		state.marker:Disconnect()
	end
	Animator.interrupt(character, 0.15)
	if state.prop ~= nil then
		state.prop:Destroy()
	end
	for part, original in pairs(state.hidden) do
		if part.Parent ~= nil then
			part.Transparency = original
		end
	end
end

local function start(character: Model, nodeType: string)
	if states[character] ~= nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local hand = character:FindFirstChild("RightHand")
	if humanoid == nil or root == nil or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end
	local kind = KINDS[nodeType] or LEAF
	-- the weapon in hand makes way for the tool
	local hidden: { [BasePart]: number } = {}
	if kind.tool ~= nil then
		for _, name in ipairs({ "Weapon", "OffhandWeapon" }) do
			local held = character:FindFirstChild(name)
			if held ~= nil then
				for _, part in ipairs(held:GetDescendants()) do
					if part:IsA("BasePart") then
						hidden[part] = part.Transparency -- (the camera resets LocalTransparencyModifier, so the weapon is hidden by its own property)
						part.Transparency = 1
					end
				end
			end
		end
	end
	local prop: Model? = nil
	if kind.tool ~= nil and hand ~= nil and hand:IsA("BasePart") then
		local toolItem = character:GetAttribute("GatherToolItem")
		prop = ToolProps.build(kind.tool, if type(toolItem) == "string" then toolItem else nil)
		if prop ~= nil and prop.PrimaryPart ~= nil then
			prop.Name = "GatherTool"
			prop:PivotTo(hand.CFrame * TOOL_GRIP)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = prop.PrimaryPart
			weld.Parent = prop.PrimaryPart
			prop.Parent = character
		end
	end
	-- walking away (or dying) ends the animation; holding the prompt again restarts it
	local moving = RunService.Heartbeat:Connect(function()
		if root.AssemblyLinearVelocity.Magnitude > 6 or humanoid.Health <= 0 or character.Parent == nil then
			stop(character)
		end
	end)
	states[character] = { clip = kind.clip, prop = prop, hidden = hidden, marker = nil, moving = moving }
	Animator.play(character, kind.clip)
	local state = states[character]
	if state ~= nil then
		state.marker = Animator.onMarker(character, kind.clip, "Hit", function()
			burst(character, kind)
		end)
	end
end

local function refresh(character: Model)
	local value = character:GetAttribute("GatherNode")
	if type(value) == "string" then
		start(character, value)
	else
		stop(character)
	end
end

local function watchCharacter(character: Model)
	character:GetAttributeChangedSignal("GatherNode"):Connect(function()
		refresh(character)
	end)
	character.AncestryChanged:Connect(function()
		if character.Parent == nil then
			stop(character)
		end
	end)
	refresh(character)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character ~= nil then
		task.spawn(watchCharacter, player.Character)
	end
end
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
