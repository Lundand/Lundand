--!strict
-- Character creation (L-38): skin tone, hair style, hair colour and face from the listed choices. Each choice shows
-- on your character straight away; "Begin" keeps them. Shown once, for a new character.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Content)
local Ui = require(Shared.Presentation.Ui)
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local gui = Ui.screen("Creation")
local _, body = Ui.window(gui, "Creation", "Your character", 560, 600)
local choice: any = nil

local SECTIONS = {
	{ field = "gender", list = "genders", title = "Gender" },
	{ field = "skinTone", list = "skinTones", title = "Skin tone" },
	{ field = "hairStyle", list = "hairStyles", title = "Hair" },
	{ field = "hairColor", list = "hairColors", title = "Hair colour" },
	{ field = "face", list = "faces", title = "Face" },
}

local function send(final: boolean)
	remotes.CharacterRequest:FireServer("SetAppearance", { appearance = choice, final = final })
end

local render: () -> ()
render = function()
	Ui.clear(body)
	if choice == nil then
		return
	end
	Ui.text(body, "Shape how you look. This never changes your strength; it's yours to choose.", 14, Ui.colors.muted)
	for _, section in ipairs(SECTIONS) do
		local group = Ui.section(body, section.title)
		local row = Ui.row(group)
		for _, option in ipairs(Content.appearance[section.list]) do
			local field, id = section.field, option.id
			local button = Ui.button(row, option.displayName or "", function()
				choice[field] = id
				send(false)
				render()
			end, option.color and 44 or 110)
			if option.color ~= nil then
				button.BackgroundColor3 = Color3.fromRGB(option.color[1], option.color[2], option.color[3])
			end
			if choice[field] == id then
				Ui.markSelected(button)
			end
		end
	end
	Ui.primary(Ui.button(body, "Begin", function()
		send(true)
		Ui.close()
	end, 160))
end
Ui.onRefresh("Creation", render)

remotes.OpenInterface.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "CharacterCreation" and type(data) == "table" then
		choice = table.clone(data.current)
		Ui.open("Creation")
	end
end)
