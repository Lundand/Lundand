--!strict
-- Ordered save migrations. steps[n] upgrades a save from version n to n + 1 and returns it.
-- PlayerDataService runs them on a copy and only writes the result back when all of them succeed.
local Migrations = {}

Migrations.steps = {}

function Migrations.run(data: any, targetVersion: number, steps: any?): (boolean, any)
	local list = steps or Migrations.steps
	if type(data) ~= "table" or type(data.schemaVersion) ~= "number" or math.floor(data.schemaVersion) ~= data.schemaVersion then
		return false, "save has no valid schema version"
	end
	if data.schemaVersion > targetVersion then
		return false, "save is newer than this server"
	end
	local current = data
	while current.schemaVersion < targetVersion do
		local fromVersion = current.schemaVersion
		local step = list[fromVersion]
		if step == nil then
			return false, string.format("no migration from version %d", fromVersion)
		end
		local ok, result = pcall(step, current)
		if not ok then
			return false, string.format("migration from version %d failed: %s", fromVersion, tostring(result))
		end
		if type(result) ~= "table" then
			return false, string.format("migration from version %d returned no data", fromVersion)
		end
		result.schemaVersion = fromVersion + 1
		current = result
	end
	return true, current
end

return Migrations
