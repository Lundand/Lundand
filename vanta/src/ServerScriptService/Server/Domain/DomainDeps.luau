--!strict
-- The dependencies domain rules receive. The game and the tests both build them here, so they can't drift apart
-- (a field missing only in the game once broke the starter chest in Studio while every test passed).
local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)

local DomainDeps = {}

function DomainDeps.build(ownerUserId: number?, newUid: () -> string, now: () -> number): any
	return {
		items = Content.items,
		currencies = Content.currencies,
		classes = Content.classes,
		disciplines = Content.disciplines,
		progressionConfig = Content.progression,
		ownerUserId = ownerUserId,
		newUid = newUid,
		now = now,
	}
end

return DomainDeps
