--!nonstrict
-- Builds the bow set into ReplicatedStorage.Shared.AnimationSequences: solves where the right hand takes the string for every
-- key that has a draw, then builds each clip.  Run:  require(game.ServerStorage.AnimationTools.BuildBow).run()  (load a fresh copy
-- of this module first, since Studio caches required modules).
local BuildBow = {}

local function fresh(module)
	local copy = module:Clone()
	copy.Parent = module.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	assert(ok, result)
	return result
end

-- A preview rig holding a bow the way Models.equipWeapon gives it (left hand, string to the archer).
function BuildBow.makeRig(position)
	local Models = require(game.ServerScriptService.Server.Tools.Models)
	local rig = Models.humanoid()
	rig.Name = "AnimBuildRig"
	rig.Parent = workspace
	rig:PivotTo(CFrame.new(position or Vector3.new(0, 800, 0)))
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	local animate = rig:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	Models.equipWeapon(rig, "Bow")
	rig:SetAttribute("WeaponHand", "Left")
	rig:SetAttribute("GripOffset", CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(-90), math.rad(180), 0))
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	return rig
end

function BuildBow.run(onlyNames)
	local tools = game.ServerStorage.AnimationTools
	local Builder = fresh(tools.Builder)
	local Clips = fresh(tools.BowClips)
	local rig = BuildBow.makeRig()
	local report = {}
	local folder = game.ReplicatedStorage.Shared.AnimationSequences
	for _, name in ipairs(Clips.order) do
		if onlyNames == nil or table.find(onlyNames, name) then
			local clip = Clips[name]
			table.insert(report, Builder.solveDraw(clip, rig))
			if clip.loop then -- loops must end exactly where they began
				local first, last = clip.keys[1], clip.keys[#clip.keys]
				for _, joint in ipairs({ "RightShoulder", "RightElbow", "RightWrist" }) do
					last.j[joint] = { table.unpack(first.j[joint]) }
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

return BuildBow
