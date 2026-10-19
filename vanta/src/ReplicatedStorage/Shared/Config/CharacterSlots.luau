--!strict
-- Character slots (L-45). One slot to start. Extra slots come from account-level unlocks, earned when any
-- character reaches a level. The unlock levels are undecided, so the list is empty; an entry looks like
-- { id = "Slot2", atLevel = 20 }. Slots are never sold (L-33).
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	baseSlots = 1,
	maxSlots = 4, -- placeholder
	unlocks = {},
	deletionConfirmSeconds = 120, -- how long a delete confirmation stays valid
	-- An awakened character can only be deleted this long after its awakening, so re-rolling the class
	-- costs real time (L-49). Placeholder: 7 days.
	deleteWaitSeconds = 604800,
})
