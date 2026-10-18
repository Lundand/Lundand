--!strict
-- Who may use development commands outside Studio (DevCommandsService). Filled in at integration
-- (docs/INTEGRATION.md). Development commands are always available in Studio and never elsewhere
-- unless both the place and the user are listed here.
return table.freeze({
	developmentPlaceIds = table.freeze({}),
	allowedUserIds = table.freeze({}),
})
