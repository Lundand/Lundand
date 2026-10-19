--!strict
-- Property rules (L-28, L-54). Owned buildings are unique (one owner each) and visible to everyone; their
-- interiors are instanced. Inn rooms (L-29) can be rented by any number of players, each getting their own copy.
-- Each player may own one home and one shop. Guild halls belong to a guild, are bought from its treasury, and need
-- the guild to reach a level. Prices are placeholders (O-10).
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	limitsPerPlayer = {
		House = 1, -- decided: one home per player
		Shop = 1, -- decided: one shop per player (L-54)
	},
	pricesByTier = { Noble = 250000, Townhouse = 60000, Modest = 25000, Market = 100000, Hall = 150000, GuildHouse = 80000 }, -- placeholders (O-10)
	-- Where a building stands moves its price: the tier price times a factor between these two, by the spot's foot
	-- traffic (0 a quiet back lane far from the square, 1 on a main road by the square). Shops live off passers-by,
	-- so their spread is widest. Prices are rounded to priceStep.
	locationFactor = { Shop = { 0.5, 2.5 }, GuildHall = { 0.8, 1.6 }, House = { 0.85, 1.25 } },
	priceStep = 500,
	guildHall = { kind = "GuildHall", perGuild = 1 }, -- the guild level needed is in Config/Guilds
	reservationSeconds = 120,
	permissionModes = { Private = true, Friends = true, Public = true },
	maxAllowedVisitors = 50,
	-- Inn rooms (L-29). Placeholders until O-11.
	rental = { pricePerDay = 50, dayLengthSeconds = 86400, maxDays = 7, maxInvited = 10 },
})
