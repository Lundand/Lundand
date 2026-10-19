--!strict
-- Character appearance (L-38): only listed choices are accepted, and anything missing falls back to the first
-- option. Shared so the creation window and the server agree.
local AppearanceRules = {}

AppearanceRules.FIELDS = table.freeze({ gender = "genders", skinTone = "skinTones", hairStyle = "hairStyles", hairColor = "hairColors", face = "faces" })

local function find(list: {any}, id: any): any
	for _, option in ipairs(list) do
		if option.id == id then
			return option
		end
	end
	return nil
end

function AppearanceRules.default(config: any): any
	return {
		gender = config.genders[1].id,
		skinTone = config.skinTones[1].id,
		hairStyle = config.hairStyles[1].id,
		hairColor = config.hairColors[1].id,
		face = config.faces[1].id,
	}
end

-- A clean appearance from a choice sent by a client: every field must name a listed option.
function AppearanceRules.validate(choice: any, config: any): (boolean, any)
	if type(choice) ~= "table" then
		return false, "invalid appearance"
	end
	local result = {}
	for field, listName in pairs(AppearanceRules.FIELDS) do
		local option = find(config[listName], choice[field])
		if option == nil and choice[field] == nil then
			option = config[listName][1] -- left out (e.g. saved before the field existed): the default
		end
		if option == nil then
			return false, "unknown " .. field
		end
		result[field] = option.id
	end
	return true, result
end

-- What the server needs to dress the body: colours and asset IDs (0 means none yet).
function AppearanceRules.describe(appearance: any, config: any): any
	local chosen = AppearanceRules.default(config)
	for field, listName in pairs(AppearanceRules.FIELDS) do
		if appearance ~= nil and find(config[listName], appearance[field]) ~= nil then
			chosen[field] = appearance[field]
		end
	end
	return {
		skin = find(config.skinTones, chosen.skinTone).color,
		hairAssetId = find(config.hairStyles, chosen.hairStyle).assetId,
		hairColor = find(config.hairColors, chosen.hairColor).color,
		faceAssetId = find(config.faces, chosen.face).assetId,
		torso = config.clothing.torso,
		legs = config.clothing.legs,
	}
end

return AppearanceRules
