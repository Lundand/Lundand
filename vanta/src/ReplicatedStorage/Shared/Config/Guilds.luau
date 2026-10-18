--!strict
-- Player guild settings (L-30, L-48). Values are placeholders (O-12).
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	maxMembers = 50,
	nameMinLength = 3,
	nameMaxLength = 24,
	inviteSeconds = 86400,
	-- Founding a guild (L-54): enough gold that only committed players found one. Less than the cheapest home
	-- (25,000), but many hours at current quest and bounty rewards. The gold leaves the game. Placeholders to
	-- re-tune once gold per hour is measured in playtests.
	creationCost = 10000,
	minLeaderLevel = 10,
	hallRequiredLevel = 5, -- a guild can buy its one hall from this guild level (L-54)
	ranks = { "Leader", "Officer", "Member", "Recruit" }, -- highest first
	permissions = {
		Leader = { invite = true, kick = true, promote = true, viewTreasury = true, setTax = true, spend = true, upgrade = true, emblem = true },
		Officer = { invite = true, kick = true, promote = true, viewTreasury = true, upgrade = true },
		Member = { invite = true, viewTreasury = true },
		Recruit = {},
	},
	-- Tax on eligible gold rewards, in percent. The player keeps the rest; rounding favours the player.
	taxRates = { 0, 2, 5, 10 },
	taxableSources = { QuestReward = true },
	-- Emblems are Roblox image asset IDs; 0 shows the default emblem.
	emblem = { changeCooldownSeconds = 86400 },
	-- Guild level comes from guild XP earned through play, never from gold. XP needed for level 2, 3, ...;
	-- raise the cap by appending only.
	levelThresholds = { 1000, 2500, 5000, 9000, 15000, 24000, 36000, 52000, 72000 },
	xpSources = { GuildQuest = true, DungeonClear = true, BossKill = true, GuildChallenge = true },
	-- How the hall looks, by guild level.
	hallStages = {
		{ level = 1, stage = "Modest" },
		{ level = 4, stage = "Established" },
		{ level = 8, stage = "Grand" },
	},
	-- Weekly upkeep from the treasury, by hall stage. When the treasury is short the hall looks neglected and
	-- comfort features pause; levels, members and history are never lost. At most a few missed weeks are
	-- charged after a quiet spell.
	maintenance = { periodSeconds = 604800, costByStage = { 50, 150, 400 }, maxCatchUpPeriods = 4 },
	upgrades = {
		Banners = { id = "Banners", displayName = "Guild banners", cost = 500, requiredLevel = 2 },
		Storehouse = { id = "Storehouse", displayName = "Storehouse", cost = 1500, requiredLevel = 3 },
		GreatHearth = { id = "GreatHearth", displayName = "Great hearth", cost = 3000, requiredLevel = 5, requires = "Banners" },
	},
	ledgerSize = 100, -- treasury history kept in the guild record
	recentOperationsKept = 500, -- delivery IDs remembered so a retried delivery applies once
})
