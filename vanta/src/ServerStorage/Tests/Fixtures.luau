--!strict
-- Shared test setup: fresh saves and deterministic dependencies.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Content = require(ReplicatedStorage:WaitForChild("Shared").Content)
local PlayerSchema = require(ServerScriptService:WaitForChild("Server").Data.PlayerSchema)

local Fixtures = {}

local DomainDeps = require(game:GetService("ServerScriptService"):WaitForChild("Server").Domain.DomainDeps)

function Fixtures.deps(ownerUserId: number?)
	local counter = 0
	local clock = 1000
	-- Built exactly as the game builds them (DomainDeps), plus what only the class book and the tests add.
	local deps = DomainDeps.build(ownerUserId or 1, function(): string
		counter += 1
		return string.format("uid-%d-%d", ownerUserId or 1, counter)
	end, function(): number
		return clock
	end)
	deps.allowDevelopmentContent = true
	function deps.advance(seconds: number)
		clock += seconds
	end
	return deps
end

function Fixtures.profile()
	return PlayerSchema.template()
end

function Fixtures.character(profile: any)
	return profile.characters[profile.activeCharacterId]
end

return Fixtures
