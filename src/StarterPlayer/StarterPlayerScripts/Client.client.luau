--[[
	CORE HUNTERS — client entry point. Starts every client module in order.
]]

local StarterGui = game:GetService("StarterGui")

local State = require(script.State)
local Notify = require(script.Notify)
local Anim = require(script.Anim)
local FX = require(script.FX)
local World = require(script.World)
local Panels = require(script.Panels)
local HUD = require(script.HUD)
local Reveal = require(script.Reveal)
local Input = require(script.Input)

State.Init()
Notify.Init()
State.MessageHandler = function(message: string, ok: boolean)
	Notify.Toast(message, ok and "success" or "error")
end
Anim.Init()
FX.Init()
World.Init()
Panels.Init()
Notify.PanelOpener = Panels.Open
HUD.Init()
Reveal.Init()
Input.Init()

-- No tools in this game: hide the backpack bar. Health has its own bar in the HUD.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			break
		end
		task.wait(1)
	end
end)
