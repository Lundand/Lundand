--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local PlayerSchema = require(Server.Data.PlayerSchema)
local Migrations = require(Server.Data.Migrations)
local Content = require(Shared.Content)

return function(t)
	t.test("a new save is valid and independent from other new saves", function()
		local first = PlayerSchema.template()
		local problems, warnings = PlayerSchema.validate(first, Content)
		t.deepEqual(problems, {})
		t.deepEqual(warnings, {})
		local second = PlayerSchema.template()
		first.characters.main.currencies.Gold = 5
		t.equal(second.characters.main.currencies.Gold, 0)
	end)

	t.test("structural damage is a problem; unknown content is only a warning", function()
		local save = PlayerSchema.template()
		save.characters.main.level.xp = "lots"
		local problems = PlayerSchema.validate(save, Content)
		t.equal(#problems, 1)
		local other = PlayerSchema.template()
		other.characters.main.inventory.stacks.RetiredItem = { itemId = "RetiredItem", count = 3 }
		local otherProblems, warnings = PlayerSchema.validate(other, Content)
		t.deepEqual(otherProblems, {})
		t.equal(#warnings, 1)
	end)

	t.test("missing pieces and future versions are problems", function()
		local save = PlayerSchema.template()
		save.activeCharacterId = "ghost"
		save.account.receipts = nil
		t.equal(#PlayerSchema.validate(save, Content), 2)
		local future = PlayerSchema.template()
		future.schemaVersion = PlayerSchema.VERSION + 1
		t.equal(#PlayerSchema.validate(future, Content), 1)
	end)

	t.test("migrations run in order up to the target version", function()
		local steps = {
			[1] = function(data)
				data.added = 1
				return data
			end,
			[2] = function(data)
				data.added += 1
				return data
			end,
		}
		local ok, result = Migrations.run({ schemaVersion = 1 }, 3, steps)
		t.truthy(ok)
		t.equal(result.schemaVersion, 3)
		t.equal(result.added, 2)
	end)

	t.test("migration failures are reported, never half-applied silently", function()
		t.falsy(Migrations.run({ schemaVersion = 1 }, 2, {}), "missing step")
		local failing = {
			[1] = function()
				error("boom")
			end,
		}
		local ok, err = Migrations.run({ schemaVersion = 1 }, 2, failing)
		t.falsy(ok)
		t.truthy(string.find(err, "boom", 1, true))
		t.falsy(Migrations.run({ schemaVersion = 5 }, 2, {}), "newer than this server")
		t.falsy(Migrations.run({ schemaVersion = 1.5 }, 2, {}), "fractional version")
		t.truthy(Migrations.run(PlayerSchema.template(), PlayerSchema.VERSION))
	end)
end
