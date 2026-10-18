--!nonstrict
-- Builds the staff set into ReplicatedStorage.Shared.AnimationSequences: solves the two-handed grips on a preview rig,
-- then builds each clip. Run from the command bar / MCP:  require(game.ServerStorage.AnimationTools.BuildStaff).run()
-- (Studio caches required modules, so this loads fresh copies of the tool modules each time.)
local BuildStaff = {}

local function fresh(module)
	local copy = module:Clone()
	copy.Parent = module.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	assert(ok, result)
	return result
end

function BuildStaff.run(onlyNames)
	local tools = game.ServerStorage.AnimationTools
	local Builder = fresh(tools.Builder)
	local Clips = fresh(tools.StaffClips)
	local Models = require(game.ServerScriptService.Server.Tools.Models)
	local rig = Models.humanoid()
	rig.Name = "AnimBuildRig"
	rig.Parent = workspace
	rig:PivotTo(CFrame.new(0, 800, 0))
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	local animate = rig:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	Models.equipWeapon(rig, "Staff")
	rig:SetAttribute("GripOffset", CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(-135), 0, 0)) -- same grip as Models.equipWeapon
	local report = {}
	local folder = game.ReplicatedStorage.Shared.AnimationSequences
	for _, name in ipairs(Clips.order) do
		if onlyNames == nil or table.find(onlyNames, name) then
			local clip = Clips[name]
			if clip.twoHand then
				table.insert(report, Builder.solveTwoHand(clip, rig))
				if clip.loop then -- loops must end exactly where they began
					local first, last = clip.keys[1], clip.keys[#clip.keys]
					for _, joint in ipairs({ "RightShoulder", "LeftShoulder", "LeftElbow", "LeftWrist" }) do
						last.j[joint] = { table.unpack(first.j[joint]) }
					end
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

return BuildStaff
