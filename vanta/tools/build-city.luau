--!nocheck
-- lune run tools/build-city.luau [--rbxm] — runs Server.Tools.CityBuilder offline and reports what it built.
-- With --rbxm, also writes build/City.rbxm (insert it into Studio to look around without running the game).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Harness = require("./harness")
Harness.loadSource("src")
local game = Harness.game
local CityBuilder = Harness.require(Harness.find("ServerScriptService.Server.Tools.CityBuilder"))
local city = CityBuilder.build()
local counts = {}
local total = 0
for _, d in city:GetDescendants() do
	counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
	total += 1
end
local list = {}
for name, n in counts do
	table.insert(list, { name, n })
end
table.sort(list, function(a, b)
	return a[2] > b[2]
end)
for _, item in list do
	print(string.format("%-20s %d", item[1], item[2]))
end
print("instances", total)
-- parts per top-level folder
for _, child in city:GetChildren() do
	local n = 0
	for _, d in child:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	print(string.format("  %-16s %6d parts", child.Name, n))
end
if table.find(process.args, "--rbxm") then
	fs.writeDir("build")
	fs.writeFile("build/City.rbxm", roblox.serializeModel({ city }))
	print("wrote build/City.rbxm")
end
