--!strict
-- Property rules (L-28, L-54). Owned buildings are unique, visible to everyone and deliberately scarce; inn
-- rooms are the only instanced homes (L-29). Each player may own one home and one shop. Guild halls belong to
-- a guild, are bought from its treasury, and need the guild to reach a level. Prices are placeholders (O-10).
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	limitsPerPlayer = {
		House = 1, -- decided: one home per player
		Shop = 1, -- decided: one shop per player (L-54)
	},
	pricesByTier = { Noble = 250000, Modest = 25000, Market = 100000, Hall = 150000 }, -- placeholders (O-10)
	guildHall = { kind = "GuildHall", perGuild = 1 }, -- the guild level needed is in Config/Guilds
	reservationSeconds = 120,
	permissionModes = { Private = true, Friends = true, Public = true },
	maxAllowedVisitors = 50,
	-- Inn rooms (L-29). Placeholders until O-11.
	rental = { pricePerDay = 50, dayLengthSeconds = 86400, maxDays = 7, maxInvited = 10 },
})
