--!strict
-- Grants Robux developer products (L-24). A purchase is recorded in the save and acknowledged to Roblox
-- only after the save is confirmed; until then Roblox retries and the receipt record prevents a second
-- grant. No products are enabled yet (O-04).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Purchases = require(Server.Domain.Purchases)

local SAVE_TIMEOUT = 15

local MonetizationService = {}
local services: any = nil

function MonetizationService.init(allServices: any)
	services = allServices
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil or not services.PlayerDataService.isLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = services.PlayerDataService.getData(player)
	local catalogue = Purchases.catalogue(Content.products, Content.cosmetics)
	local context = { robuxSpent = receiptInfo.CurrencySpent, eventId = Content.riftEvents.activeEventId }
	local ok, result = Purchases.grant(data, receiptInfo.PurchaseId, receiptInfo.ProductId, catalogue, os.time(), context)
	if not ok then
		warn(string.format("[Monetization] purchase %s not granted: %s", tostring(receiptInfo.PurchaseId), tostring(result)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not services.PlayerDataService.saveAndWait(player, SAVE_TIMEOUT) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService
