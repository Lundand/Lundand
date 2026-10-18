--!strict
-- Runs every spec in Tests/Specs and returns the summary.
-- In Studio (for example through the MCP server's execute_luau): require(game.ServerStorage.Tests.RunAll)()
local TestKit = require(script.Parent.TestKit)

return function(log: ((string) -> ())?)
	local suites = {}
	for _, child in ipairs(script.Parent.Specs:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(suites, { name = child.Name, define = require(child) })
		end
	end
	table.sort(suites, function(a, b)
		return a.name < b.name
	end)
	return TestKit.run(suites, log)
end
