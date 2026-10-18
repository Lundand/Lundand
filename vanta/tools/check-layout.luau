--!nocheck
-- lune run tools/check-layout.luau — runs Server.Domain.LayoutRules on ServerData.CityLayout and lists problems.
local Harness = require("./harness")
Harness.loadSource("src")
local LayoutRules = Harness.require(Harness.find("ServerScriptService.Server.Domain.LayoutRules"))
local Layout = Harness.require(Harness.find("ServerStorage.ServerData.CityLayout"))
local Content = Harness.require(Harness.find("ReplicatedStorage.Shared.Content"))
local problems = LayoutRules.validate(Layout, Content.world, Content.npcs)
for _, problem in problems do
	print(problem)
end
print(#problems .. " problems")
Harness.exit(if #problems == 0 then 0 else 1)
