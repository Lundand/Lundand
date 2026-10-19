--!strict
-- Kept so existing commands still work: the greybox has been replaced by the full city (Tools.CityBuilder).
--   require(game.ServerScriptService.Server.Tools.GreyboxBuilder).build()
local CityBuilder = require(script.Parent.CityBuilder)

local GreyboxBuilder = {}

function GreyboxBuilder.build(): Model
	return CityBuilder.build()
end

return GreyboxBuilder
