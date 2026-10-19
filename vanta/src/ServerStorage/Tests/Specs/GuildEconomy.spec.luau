--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local GuildRules = require(Server.Domain.GuildRules)
local GuildEconomy = require(Server.Domain.GuildEconomy)
local Content = require(Shared.Content)

local rules = Content.guilds

local function guild(): any
	local record = GuildRules.newRecord("g1", "Wardens", 1, "Leader", 0)
	record.members["2"] = { rank = "Officer", name = "Officer", joinedAt = 0 }
	record.members["3"] = { rank = "Member", name = "Member", joinedAt = 0 }
	return record
end

return function(t)
	t.test("tax never creates or destroys gold at any offered rate", function()
		for _, rate in ipairs(rules.taxRates) do
			for amount = 1, 1000 do
				local kept, tax = GuildEconomy.splitTax(amount, rate)
				if kept + tax ~= amount or tax ~= math.floor(amount * rate / 100) then
					t.equal(kept + tax, amount, "rate " .. rate .. ", amount " .. amount)
				end
			end
		end
		t.deepEqual({ GuildEconomy.splitTax(100, 5) }, { 95, 5 })
		t.deepEqual({ GuildEconomy.splitTax(1000, 5) }, { 950, 50 })
	end)

	t.test("only the leader sets the tax, and only to an offered rate", function()
		local record = guild()
		t.falsy(GuildEconomy.setTaxRate(record, 2, 5, rules))
		t.falsy(GuildEconomy.setTaxRate(record, 1, 7, rules))
		t.truthy(GuildEconomy.setTaxRate(record, 1, 5, rules))
		t.equal(record.taxRate, 5)
	end)

	t.test("treasury: tax credited once per delivery; spending needs permission and money, once", function()
		local record = guild()
		t.truthy(GuildEconomy.creditTax(record, "tax1", 5, 3, 10, rules))
		t.truthy(GuildEconomy.creditTax(record, "tax1", 5, 3, 11, rules), "retry")
		t.equal(record.treasury, 5)
		t.falsy(GuildEconomy.spend(record, 3, "s1", 3, "Feast", 12, rules), "members can't spend")
		t.falsy(GuildEconomy.spend(record, 1, "s2", 6, "Feast", 12, rules), "never below zero")
		t.truthy(GuildEconomy.spend(record, 1, "s3", 3, "Feast", 12, rules))
		t.truthy(GuildEconomy.spend(record, 1, "s3", 3, "Feast", 13, rules), "retry")
		t.equal(record.treasury, 2)
		local last = record.ledger[#record.ledger]
		t.equal(last.by, 1)
		t.equal(last.purpose, "Feast")
		t.equal(last.balance, 2)
	end)

	t.test("guild level comes from play, never from gold", function()
		local record = guild()
		t.falsy(GuildEconomy.addXp(record, "x0", 5000, "GoldDeposit", rules))
		t.truthy(GuildEconomy.addXp(record, "x1", 1000, "GuildQuest", rules))
		t.truthy(GuildEconomy.addXp(record, "x1", 1000, "GuildQuest", rules), "retry")
		t.equal(record.xp, 1000)
		t.equal(GuildEconomy.level(999, rules), 1)
		t.equal(GuildEconomy.level(1000, rules), 2)
		t.equal(GuildEconomy.level(10 ^ 9, rules), #rules.levelThresholds + 1, "the cap grows by appending thresholds")
	end)

	t.test("leaderboard: level, then XP, then the older guild", function()
		local ranked = GuildEconomy.rank({
			{ id = "b", level = 3, xp = 4000, createdAt = 5 },
			{ id = "a", level = 3, xp = 4000, createdAt = 9 },
			{ id = "c", level = 5, xp = 9000, createdAt = 1 },
			{ id = "d", level = 3, xp = 4500, createdAt = 1 },
		})
		t.deepEqual({ ranked[1].id, ranked[2].id, ranked[3].id, ranked[4].id }, { "c", "d", "b", "a" })
		t.equal(ranked[4].rank, 4)
		t.truthy(GuildEconomy.leaderboardScore(5, 9000) > GuildEconomy.leaderboardScore(3, 4500))
		t.truthy(GuildEconomy.leaderboardScore(3, 4500) > GuildEconomy.leaderboardScore(3, 4000))
	end)

	t.test("emblems: asset IDs only, by permission, with a cooldown, never touching progress", function()
		local record = guild()
		record.xp = 2600
		local now = 100000
		t.falsy(GuildEconomy.setEmblem(record, 2, 123, now, rules), "officers can't by default")
		t.falsy(GuildEconomy.setEmblem(record, 1, -5, now, rules))
		t.falsy(GuildEconomy.setEmblem(record, 1, 1.5, now, rules))
		t.falsy(GuildEconomy.setEmblem(record, 1, "rbxassetid://123", now, rules), "IDs, never URLs")
		t.truthy(GuildEconomy.setEmblem(record, 1, 123456789, now, rules))
		t.falsy(GuildEconomy.setEmblem(record, 1, 987, now + 60, rules), "cooldown")
		t.truthy(GuildEconomy.setEmblem(record, 1, 987, now + rules.emblem.changeCooldownSeconds, rules))
		t.equal(record.emblemAssetId, 987)
		t.equal(record.xp, 2600)
	end)

	t.test("maintenance: each week charged once, neglect without loss, restore, and a cap on missed weeks", function()
		local record = guild()
		record.treasury = 120
		local week = rules.maintenance.periodSeconds
		t.equal(GuildEconomy.settleMaintenance(record, 10 * week, rules).charged, 0, "first settlement starts the clock")
		t.equal(GuildEconomy.settleMaintenance(record, 10 * week + 100, rules).charged, 0, "same week")
		t.equal(GuildEconomy.settleMaintenance(record, 11 * week, rules).charged, 50)
		t.equal(GuildEconomy.settleMaintenance(record, 11 * week, rules).charged, 0, "never twice")
		local result = GuildEconomy.settleMaintenance(record, 13 * week, rules)
		t.equal(result.charged, 50)
		t.equal(result.condition, "Neglected")
		t.equal(record.treasury, 20)
		t.equal(GuildRules.memberCount(record), 3, "nobody leaves")
		t.equal(GuildEconomy.settleMaintenance(record, 14 * week, rules).charged, 0, "no debt builds up")
		t.falsy(GuildEconomy.restore(record, 1, 14 * week, rules), "not enough gold")
		record.treasury = 100
		t.falsy(GuildEconomy.restore(record, 3, 14 * week, rules), "members can't spend")
		t.truthy(GuildEconomy.restore(record, 1, 14 * week, rules))
		t.equal(record.maintenance.condition, "Maintained")
		t.equal(record.treasury, 50)
		record.treasury = 10000
		t.equal(GuildEconomy.settleMaintenance(record, 40 * week, rules).charged, 50 * rules.maintenance.maxCatchUpPeriods)
	end)

	t.test("upgrades: level, prerequisites, treasury, permission, and one charge per purchase", function()
		local record = guild()
		record.treasury = 5000
		t.falsy(GuildEconomy.buyUpgrade(record, 1, "Banners", "u1", 0, rules), "guild level 1")
		GuildEconomy.addXp(record, "x1", 9000, "GuildQuest", rules)
		t.falsy(GuildEconomy.buyUpgrade(record, 3, "Banners", "u1", 0, rules), "members can't")
		t.falsy(GuildEconomy.buyUpgrade(record, 1, "GreatHearth", "u2", 0, rules), "banners first")
		t.truthy(GuildEconomy.buyUpgrade(record, 2, "Banners", "u3", 0, rules))
		t.truthy(GuildEconomy.buyUpgrade(record, 2, "Banners", "u3", 0, rules), "retry")
		t.equal(record.treasury, 4500)
		t.falsy(GuildEconomy.buyUpgrade(record, 1, "Banners", "u4", 0, rules), "already built")
		record.treasury = 100
		t.falsy(GuildEconomy.buyUpgrade(record, 1, "GreatHearth", "u5", 0, rules), "not enough gold")
	end)

	t.test("founding a guild costs gold and needs an experienced founder", function()
		local account = { guild = {} }
		t.falsy(GuildRules.canCreate(account, rules.minLeaderLevel - 1, rules.creationCost, rules), "level too low")
		t.falsy(GuildRules.canCreate(account, rules.minLeaderLevel, rules.creationCost - 1, rules), "not enough gold")
		t.truthy(GuildRules.canCreate(account, rules.minLeaderLevel, rules.creationCost, rules))
		t.falsy(GuildRules.canCreate({ guild = { id = "g1" } }, 50, 10 ^ 9, rules), "already in a guild")
	end)

	t.test("a guild buys one hall from its treasury, from the required guild level", function()
		local record = guild()
		record.treasury = 200000
		t.falsy(GuildEconomy.buyHall(record, 1, "Hall01", 150000, "h1", 0, rules), "guild level too low")
		GuildEconomy.addXp(record, "x1", rules.levelThresholds[rules.hallRequiredLevel - 1], "GuildQuest", rules)
		t.equal(GuildEconomy.level(record.xp, rules), rules.hallRequiredLevel)
		t.falsy(GuildEconomy.buyHall(record, 2, "Hall01", 150000, "h2", 0, rules), "officers can't spend")
		t.truthy(GuildEconomy.buyHall(record, 1, "Hall01", 150000, "h3", 0, rules))
		t.truthy(GuildEconomy.buyHall(record, 1, "Hall01", 150000, "h3", 0, rules), "retry")
		t.equal(record.treasury, 50000, "charged once")
		t.falsy(GuildEconomy.buyHall(record, 1, "Hall02", 1, "h4", 0, rules), "one hall per guild")
	end)

	t.test("each rank sees what its permissions allow, and a founding in progress blocks joining", function()
		local record = guild()
		record.members["4"] = { rank = "Recruit", name = "Recruit", joinedAt = 0 }
		GuildEconomy.creditTax(record, "t1", 25, 3, 1, rules)
		local leader = GuildEconomy.summary(record, 1, rules)
		t.equal(leader.treasury, 25)
		t.equal(#leader.ledger, 1)
		t.deepEqual({ leader.members[1].rank, leader.members[4].rank }, { "Leader", "Recruit" })
		t.equal(leader.nextLevelXp, rules.levelThresholds[1])
		t.equal(#leader.upgrades, 3)
		local recruit = GuildEconomy.summary(record, 4, rules)
		t.equal(recruit.treasury, nil, "recruits don't see the treasury")
		t.equal(GuildEconomy.summary(record, 99, rules), nil, "outsiders see nothing")
		t.falsy(GuildRules.canJoin({ guild = { pendingFounding = { guildId = "g2" } } }))
	end)

	t.test("a hall taken before the purchase finished is refunded to the treasury", function()
		local record = guild()
		record.treasury = 200000
		GuildEconomy.addXp(record, "x1", rules.levelThresholds[rules.hallRequiredLevel - 1], "GuildQuest", rules)
		GuildEconomy.buyHall(record, 1, "GuildHall01", 150000, "h1", 0, rules)
		t.equal(record.treasury, 50000)
		GuildEconomy.refundHall(record, 150000, 1, rules)
		t.equal(record.treasury, 200000)
		t.equal(record.hallPropertyId, nil)
		t.equal(record.ledger[#record.ledger].kind, "HallRefund")
	end)
end

