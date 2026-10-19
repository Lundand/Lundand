--!nonstrict
-- Generic build step for a weapon set: makes a preview rig holding the weapon the way Models.equipWeapon gives it, solves any
-- IK keys (two-handed grips: clip.twoHand; bow draw: keys with `draw`), and builds every clip of the set into
-- ReplicatedStorage.Shared.AnimationSequences.
--   local BS = <fresh copy of this module>;  print(BS.run("MaceClips", "Mace", { shield = true }))
-- (Studio caches required modules, so load fresh copies of the tool modules each time.)
local BuildSet = {}

local function fresh(module)
	local copy = module:Clone()
	copy.Parent = module.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	assert(ok, result)
	return result
end
BuildSet.fresh = fresh

function BuildSet.makeRig(weaponType, position, withShield)
	local Models = fresh(game.ServerScriptService.Server.Tools.Models) -- (a fresh copy: Studio caches required modules)
	local rig = Models.humanoid()
	rig.Name = "AnimBuildRig"
	rig.Parent = workspace
	rig:PivotTo(CFrame.new(position or Vector3.new(0, 800, 0)))
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	local animate = rig:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	Models.equipWeapon(rig, weaponType)
	local grip = Models.grips[weaponType] or { cf = CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(-90), 0, 0) }
	rig:SetAttribute("GripOffset", grip.cf)
	rig:SetAttribute("WeaponHand", grip.hand or "Right")
	if withShield then
		Models.equipShield(rig)
		rig:SetAttribute("ShieldGrip", Models.shieldGrip)
	end
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	return rig
end

function BuildSet.run(setName, weaponType, options)
	options = options or {}
	local tools = game.ServerStorage.AnimationTools
	local Builder = fresh(tools.Builder)
	local Clips = fresh(tools[setName])
	local rig = BuildSet.makeRig(weaponType, nil, options.shield)
	local report = {}
	local folder = game.ReplicatedStorage.Shared.AnimationSequences
	for _, name in ipairs(Clips.order) do
		if options.only == nil or table.find(options.only, name) then
			local clip = Clips[name]
			local joints = nil
			if clip.twoHand then
				table.insert(report, Builder.solveTwoHand(clip, rig))
				joints = { "RightShoulder", "LeftShoulder", "LeftElbow", "LeftWrist" }
			elseif options.draw then
				table.insert(report, Builder.solveDraw(clip, rig))
				joints = { "RightShoulder", "RightElbow", "RightWrist" }
			end
			if joints ~= nil and clip.loop then -- loops must end exactly where they began
				local first, last = clip.keys[1], clip.keys[#clip.keys]
				for _, joint in ipairs(joints) do
					if first.j[joint] then last.j[joint] = { table.unpack(first.j[joint]) } end
				end
			end
			local old = folder:FindFirstChild(name)
			if old then old:Destroy() end
			Builder.build(clip).Parent = folder
		end
	end
	rig:Destroy()
	return table.concat(report, "\n")
end

-- Config lines for Config/Animations, read back from the built sequences.
function BuildSet.configLines(setName)
	local tools = game.ServerStorage.AnimationTools
	local Clips = fresh(tools[setName])
	local folder = game.ReplicatedStorage.Shared.AnimationSequences
	local lines = {}
	for _, name in ipairs(Clips.order) do
		local duration = 0
		for _, key in ipairs(folder[name]:GetKeyframes()) do duration = math.max(duration, key.Time) end
		local clip = Clips[name]
		local extra = (clip.hit and (", hit = " .. clip.hit) or "") .. (clip.loop and ", loop = true" or "") .. (clip.alternates and (", alternates = { \"" .. table.concat(clip.alternates, "\", \"") .. "\" }") or "")
		table.insert(lines, ("\t%s = { assetId = 0, duration = %s%s, keyframes = {} },"):format(name, tostring(math.floor(duration * 100 + 0.5) / 100), extra))
	end
	return table.concat(lines, "\n")
end

return BuildSet
