--!strict
-- Who may be inside an owned property (L-28), kept separate from buying it: walking into a building never grants
-- ownership, and an unowned building can be looked round by anyone. InteriorService asks at the door of a home's
-- instanced interior, and again for everyone inside whenever the owner changes who may come in.
local PropertyOwnership = require(script.Parent.PropertyOwnership)

local PropertyAccess = {}

-- Must this visitor be shown out? Only owned properties are private; the owner's permissions decide the rest.
-- isFriend is nil while the friendship isn't known yet: then nobody is turned out on a Friends-only home.
function PropertyAccess.shouldEject(record: any, visitorUserId: number, isFriend: boolean?): boolean
	if record == nil or record.owner == nil then
		return false
	end
	local permissions = record.permissions or { mode = "Private", allowed = {} }
	if permissions.mode == "Friends" and isFriend == nil and record.owner.userId ~= visitorUserId then
		return false
	end
	return not PropertyOwnership.canEnter(record, visitorUserId, isFriend == true)
end

return PropertyAccess
