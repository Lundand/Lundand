--!strict
-- NPCs (L-40, L-42). In the world they are models tagged "Npc" with an NpcId attribute; players talk to
-- them through a contextual prompt that only shows nearby. Names are placeholders until the story is named.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	TheKing = { id = "TheKing", displayName = "King Halvard", title = "House Lundand", locationId = "ThroneRoom" },
	OldScholar = { id = "OldScholar", displayName = "Old Scholar", title = "Keeper of old songs", locationId = "HeartOfRealms" },
	GuildRegistrar = { id = "GuildRegistrar", displayName = "Guild Registrar", title = "Adventurers' Guild", locationId = "AdventurersGuild" },
	PartyClerk = { id = "PartyClerk", displayName = "Party Clerk", title = "Adventurers' Guild", locationId = "AdventurersGuild" },
	GuildSteward = { id = "GuildSteward", displayName = "Guild Steward", title = "Craftsmen's Guild", locationId = "CraftsmensGuild" },
	ForgeMaster = { id = "ForgeMaster", displayName = "Forge Master", title = "City Forge", locationId = "CityForge" },
	Apothecary = { id = "Apothecary", displayName = "Apothecary", title = "City Apothecary", locationId = "CityApothecary" },
	ChurchPriest = { id = "ChurchPriest", displayName = "Priest of the Summoning", title = "Church", locationId = "Church" },
	WearyStranger = { id = "WearyStranger", displayName = "Weary Stranger", title = "Church steps", locationId = "ChurchSteps" },
	Hunter = { id = "Hunter", displayName = "Hunter", title = "South gate", locationId = "SouthGate" },
	Clothier = { id = "Clothier", displayName = "Clothier", title = "Silk and Silver", locationId = "FineryStall" },
	-- An object, not a person: its prompt opens the contribution interface directly.
	HeartCrystal = { id = "HeartCrystal", displayName = "Heart of Realms", title = "", locationId = "HeartOfRealms", actionText = "Touch", opens = "OpenDonations" },
	Innkeeper = { id = "Innkeeper", displayName = "Innkeeper", title = "Square Inn", locationId = "SquareInn" },
})
