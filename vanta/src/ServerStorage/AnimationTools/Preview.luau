--!nonstrict
-- Edit-mode contact sheets: poses copies of the AnimPreview rig at chosen times of a clip, in a row.
local Preview = {}

local function fresh(module)
	local copy = module:Clone() -- clones skip the require cache, so edits to the clip data show up
	copy.Parent = module.Parent -- so `script.Parent` lookups inside the module still work
	local ok, result = pcall(require, copy)
	copy:Destroy()
	assert(ok, result)
	return result
end

function Preview.sheet(clipName, times, spacing, height, setName)
	local tools = game.ServerStorage.AnimationTools
	local B = fresh(tools.Builder)
	local Clips = fresh(tools[setName or "SwordClips"])
	local tpl = workspace.AnimPreview
	local old = workspace:FindFirstChild("AnimSheet")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "AnimSheet"
	folder.Parent = workspace
	local y = height or 100
	for i, t in ipairs(times) do
		local m = tpl:Clone()
		m.Parent = folder
		m:PivotTo(CFrame.new((i - 1) * (spacing or 5), y, 0))
		B.pose(m, B.sample(Clips[clipName], t))
	end
	return #times
end

return Preview
