--!strict
-- Windows opened from the world (L-42): crafting at a workshop and buying from an NPC vendor. They open through
-- a conversation and close when you walk away. Property, guild, cosmetic shop and Rift windows join here as
-- their services arrive (docs/specs/INTERFACES.md).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = require(Shared.Presentation.Ui)
local Content = require(Shared.Content)
local Pricing = require(Shared.Domain.Pricing)
local ItemPreview = require(Shared.Presentation.ItemPreview)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local WALK_AWAY = 20

local gui = Ui.screen("Stations")
local inventory: any = nil
local openedAt: Vector3? = nil

local function carried(itemId: string): number
	local total = 0
	for _, entry in ipairs((inventory and inventory.entries) or {}) do
		if entry.itemId == itemId then
			total += entry.count
		end
	end
	return total
end

-- An item's 3D model in a small square at the start of a row (asset pass). Returns the row to put the text in and how much
-- width the icon takes; without a model it returns the parent unchanged, so the text lays out as before.
local function withIcon(parent: Instance, itemId: string?, size: number): (Instance, number)
	if not ItemPreview.has(itemId) then
		return parent, 0
	end
	local row = Ui.row(parent)
	local box = Instance.new("Frame")
	box.BackgroundColor3 = Ui.colors.charcoal
	box.BackgroundTransparency = 0.2
	box.Size = UDim2.fromOffset(size, size)
	Ui.corner(box, 3)
	Ui.stroke(box, Ui.colors.line, 0.5)
	box.Parent = row
	ItemPreview.view(box, itemId, { layout = "tile" })
	return row, size + 10
end

local function fitBeside(label: TextLabel, offset: number)
	if offset > 0 then
		label.Size = UDim2.new(1, -offset, 0, 0)
	end
end

local function rememberPosition()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local part: any = root
	openedAt = part and part.Position
end

-- Crafting ----------------------------------------------------------------------------------------------
local _, craftBody = Ui.window(gui, "Crafting", "Workshop", 600, 600)
local craftView: any = nil

Ui.onRefresh("Crafting", function()
	Ui.clear(craftBody)
	if craftView == nil then
		return
	end
	-- UI v2 crafting: per recipe, the requirement against your level, what it makes, the materials, your rarity
	-- chances (equipment) and a gold Craft button when you can craft it.
	local RARITY_HEX = { Common = "#c8c8c8", Uncommon = "#6ebe78", Rare = "#5a96f0", Epic = "#aa64e6", Legendary = "#f0aa3c" }
	Ui.text(craftBody, string.format("<b>%s</b>      Fee %d gold      <font color='%s'>You have %d gold</font>", craftView.name, craftView.fee, Ui.hex.gold, (inventory and inventory.currencies.Gold) or 0), 15)
	for _, recipe in ipairs(craftView.recipes) do
		local section = Ui.section(craftBody, recipe.name)
		local your = tonumber(recipe.yourLevel)
		local met = your == nil or your >= recipe.minLevel
		Ui.text(section, string.format("%s  ·  needs level %d%s", recipe.profession, recipe.minLevel, if your then string.format("  ·  <font color='%s'>yours %d</font>", if met then Ui.hex.green else Ui.hex.red, your) else ""), 13, Ui.colors.muted)
		if recipe.output ~= nil then
			local source = Content.recipes[recipe.id]
			local into, offset = withIcon(section, source and source.output and source.output.itemId, 52)
			local makes = Ui.text(into, string.format("Makes  <b>%s</b>%s%s", recipe.output.name, if (recipe.output.amount or 1) > 1 then " ×" .. recipe.output.amount else "", if recipe.output.equipment and recipe.output.itemLevel then string.format("  ·  item level %d", recipe.output.itemLevel) else ""), 14, Ui.colors.text)
			fitBeside(makes, offset)
		end
		for _, input in ipairs(recipe.inputs) do
			local have = carried(input.itemId)
			local enough = have >= input.amount
			local into, offset = withIcon(section, input.itemId, 28)
			local line = Ui.text(into, string.format("<font color='%s'>%s</font>  %s  %d / %d", if enough then Ui.hex.green else Ui.hex.red, if enough then "✓" else "–", input.name, math.min(have, input.amount), input.amount), 14, if enough then Ui.colors.text else Ui.colors.muted)
			fitBeside(line, offset)
		end
		if recipe.chances ~= nil and #recipe.chances > 0 then
			local parts = {}
			for _, entry in ipairs(recipe.chances) do
				local percent = entry.chance * 100
				table.insert(parts, string.format("<font color='%s'>%s %s%%</font>", RARITY_HEX[entry.rarity] or Ui.hex.silver, entry.rarity, if percent < 1 then string.format("%.1f", percent) else string.format("%d", math.floor(percent + 0.5))))
			end
			Ui.text(section, "Rarity at your level:  " .. table.concat(parts, "  ·  "), 13, Ui.colors.muted)
		end
		if recipe.blocked ~= nil then
			Ui.text(section, recipe.blocked, 13, Ui.colors.red)
		end
		local recipeId = recipe.id
		local craft = Ui.button(section, "Craft", function()
			remotes.CraftRequest:FireServer(recipeId)
		end, 140)
		if recipe.blocked == nil then
			Ui.primary(craft)
		else
			craft.TextColor3 = Ui.colors.muted
		end
	end
end)

-- Vendor ------------------------------------------------------------------------------------------------
local ShopItems = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)
local _, shopBody = Ui.window(gui, "Vendor", "Shop", 520, 520)
local shopView: any = nil
local amounts: {[string]: number} = {}

local renderShop: () -> ()
renderShop = function()
	Ui.clear(shopBody)
	if shopView == nil then
		return
	end
	Ui.text(shopBody, string.format("<b>%s</b>      <font color='%s'>You have %d gold</font>", shopView.name, Ui.hex.gold, (inventory and inventory.currencies.Gold) or 0), 15)
	for _, offer in ipairs(shopView.stock) do
		local section = Ui.section(shopBody, offer.name)
		local itemDef = ShopItems.items[offer.itemId]
		local description = offer.description or (itemDef and itemDef.description)
		local owned = carried(offer.itemId)
		local into, offset = withIcon(section, offer.itemId, 56)
		if offset > 0 then
			-- beside the model: the description and what you own, as one block
			local lines = {}
			if description ~= nil then
				table.insert(lines, description)
			end
			if owned > 0 then
				table.insert(lines, string.format("You own %d", owned))
			end
			fitBeside(Ui.text(into, table.concat(lines, "\n"), 13, Ui.colors.muted), offset)
		else
			if description ~= nil then
				Ui.text(section, description, 13, Ui.colors.muted)
			end
			if owned > 0 then
				Ui.text(section, string.format("You own %d", owned), 12, Ui.colors.muted)
			end
		end
		local itemId = offer.itemId
		local amount = amounts[itemId] or 1
		local row = Ui.row(section)
		if offer.stackable then
			Ui.button(row, "-", function()
				amounts[itemId] = math.max(1, amount - 1)
				renderShop()
			end, 34)
			local count = Ui.text(row, tostring(amount), 15)
			count.AutomaticSize = Enum.AutomaticSize.None
			count.Size = UDim2.new(0, 30, 0, 26)
			count.TextXAlignment = Enum.TextXAlignment.Center
			Ui.button(row, "+", function()
				amounts[itemId] = math.min(10, amount + 1)
				renderShop()
			end, 34)
		end
		local cost = offer.price * amount
		local affordable = cost <= ((inventory and inventory.currencies.Gold) or 0)
		local price = Ui.text(row, if affordable then string.format("<font color='%s'>%d gold</font>", Ui.hex.gold, cost) else string.format("<font color='%s'>%d gold · not enough gold</font>", Ui.hex.red, cost), 15)
		price.AutomaticSize = Enum.AutomaticSize.None
		price.Size = UDim2.new(0, if affordable then 110 else 210, 0, 26)
		local buy = Ui.button(row, "Buy", function()
			remotes.VendorBuy:FireServer(shopView.id, itemId, amount)
		end, 90)
		if affordable then
			Ui.primary(buy)
		else
			buy.TextColor3 = Ui.colors.muted
		end
	end
	-- Vendors buy anything, cheaply; a player's buy order often pays more (L-53).
	local selling = Ui.section(shopBody, "Sell to this vendor")
	local entries = (inventory and inventory.entries) or {}
	if #entries == 0 then
		Ui.text(selling, "Nothing to sell.", 13, Ui.colors.muted)
	end
	for _, entry in ipairs(entries) do
		local def = Content.items[entry.itemId]
		if def ~= nil then
			local each = Pricing.vendorPays(def, Content.economy.vendorBuyBack)
			local row = Ui.row(selling)
			local hasIcon = ItemPreview.has(entry.itemId)
			if hasIcon then
				local box = Instance.new("Frame")
				box.BackgroundColor3 = Ui.colors.charcoal
				box.BackgroundTransparency = 0.2
				box.Size = UDim2.fromOffset(28, 28)
				Ui.corner(box, 3)
				box.Parent = row
				ItemPreview.view(box, entry.itemId, { layout = "tile" })
			end
			local label = Ui.text(row, string.format("%s  x%d   <font color='%s'>%d gold each</font>", entry.name, entry.count, Ui.hex.gold, each), 14)
			label.AutomaticSize = Enum.AutomaticSize.None
			label.Size = UDim2.new(0, if hasIcon then 205 else 300, 0, 26) -- with the icon, Sell 1 and Sell all still fit on one line
			local key, uid, total = entry.key, entry.uid, entry.count
			Ui.button(row, "Sell 1", function()
				remotes.VendorSell:FireServer(shopView.id, key, uid, 1)
			end, 70)
			if uid == nil and total > 1 then
				Ui.button(row, "Sell all", function()
					remotes.VendorSell:FireServer(shopView.id, key, nil, total)
				end, 80)
			end
		end
	end
end
Ui.onRefresh("Vendor", renderShop)

-- Property (L-28, L-54) ------------------------------------------------------------------------------
local _, propertyBody = Ui.window(gui, "Property", "Property", 480, 380)
local propertyView: any = nil
local confirming = false

local renderProperty: () -> ()
renderProperty = function()
	Ui.clear(propertyBody)
	local view = propertyView
	if view == nil then
		return
	end
	-- a readable name from the id ("Storefront01" -> "Storefront No. 1"), then kind and district
	local base, number = string.match(tostring(view.id), "^(.-)(%d+)$")
	local words = string.gsub(base or tostring(view.id), "(%l)(%u)", "%1 %2")
	local title = if number then string.format("%s No. %d", words, tonumber(number)) else words
	local heading = Ui.text(propertyBody, title, 22, Ui.colors.text)
	heading.FontFace = Ui.fonts.title
	Ui.text(propertyBody, string.format("%s  ·  %s", view.kind, view.district), 13, Ui.colors.muted)
	if not view.readable then
		Ui.text(propertyBody, "The deeds office can't be reached right now. Try again shortly.", 14, Ui.colors.red)
		return
	end
	if view.ownerName ~= nil then
		Ui.text(propertyBody, if view.isMine then "This is yours." else "Owned by " .. tostring(view.ownerName), 15, Ui.colors.silver)
		if view.isMine and not view.isShop and view.kind == "Home" then
			-- who may come inside (the server checks and shows others out)
			Ui.text(propertyBody, "Who may come in: " .. tostring(view.accessMode), 14, Ui.colors.muted)
			local row = Ui.row(propertyBody)
			local propertyId = view.id
			for _, mode in ipairs(view.accessModes or {}) do
				local label = if mode == "Private" then "Only me" elseif mode == "Friends" then "My friends" else "Anyone"
				local button = Ui.button(row, label, function()
					remotes.PropertyRequest:FireServer("SetAccess", propertyId, mode)
				end, 120)
				if mode == view.accessMode then
					Ui.markSelected(button)
				end
			end
		end
		if view.isShop then
			local shopId = view.id
			Ui.primary(Ui.button(propertyBody, view.isMine and "Open your shop counter" or "Visit the shop counter", function()
				remotes.ShopRequest:FireServer("Open", { shopId = shopId })
			end, 240))
		end
		return
	end
	local affordable = (view.gold or 0) >= (view.price or 0)
	Ui.text(propertyBody, string.format("For sale  <font color='%s'>%d gold</font>%s", if affordable then Ui.hex.gold else Ui.hex.red, view.price, if affordable then "" else "  ·  not enough gold"), 16)
	Ui.text(propertyBody, string.format("You have %d gold", view.gold), 13, Ui.colors.muted)
	if view.note ~= nil then
		Ui.text(propertyBody, view.note, 14, Ui.colors.muted)
		local offer = view.hallOffer
		if offer ~= nil and not offer.allowed then
			Ui.text(propertyBody, "For " .. tostring(offer.guildName) .. ": " .. tostring(offer.reason), 14, Ui.colors.red)
		elseif offer ~= nil and not confirming then
			Ui.primary(Ui.button(propertyBody, string.format("Buy for %s (%d gold from the treasury)", offer.guildName, offer.price), function()
				confirming = true
				renderProperty()
			end, 400))
		elseif offer ~= nil then
			Ui.text(propertyBody, string.format("Buy this hall for %s? %d gold leaves the guild treasury.", offer.guildName, offer.price), 14, Ui.colors.gold)
			local row = Ui.row(propertyBody)
			local propertyId = view.id
			Ui.primary(Ui.button(row, "Confirm purchase", function()
				confirming = false
				remotes.PropertyRequest:FireServer("BuyHall", propertyId)
			end, 170))
			Ui.button(row, "Cancel", function()
				confirming = false
				renderProperty()
			end, 100)
		end
		return
	end
	if not view.canBuy then
		Ui.text(propertyBody, "You can't buy this: " .. tostring(view.reason), 14, Ui.colors.red)
		return
	end
	if not affordable then
		-- nothing to confirm until the gold is there
		local blocked = Ui.button(propertyBody, string.format("Buy for %d gold", view.price), function() end, 220)
		blocked.TextColor3 = Ui.colors.muted
	elseif not confirming then
		Ui.primary(Ui.button(propertyBody, string.format("Buy for %d gold", view.price), function()
			confirming = true
			renderProperty()
		end, 220))
	else
		Ui.text(propertyBody, string.format("Buy this %s for %d gold? You'll have %d gold left.", string.lower(view.kind), view.price, view.gold - view.price), 14, Ui.colors.gold)
		local row = Ui.row(propertyBody)
		local propertyId = view.id
		Ui.primary(Ui.button(row, "Confirm purchase", function()
			confirming = false
			remotes.PropertyRequest:FireServer("Buy", propertyId)
		end, 170))
		Ui.button(row, "Cancel", function()
			confirming = false
			renderProperty()
		end, 100)
	end
end
Ui.onRefresh("Property", renderProperty)

-- Inn rooms (L-29) ---------------------------------------------------------------------------------------------------
local _, rentalBody = Ui.window(gui, "Rentals", "A room at the inn", 460, 330)
local rentalView: any = nil

local function duration(seconds: number): string
	local hours = math.floor(seconds / 3600)
	if hours >= 24 then
		return string.format("%d days %d hours", math.floor(hours / 24), hours % 24)
	end
	return string.format("%d hours %d minutes", hours, math.floor((seconds % 3600) / 60))
end

local function renderRentals()
	Ui.clear(rentalBody)
	local view = rentalView
	if view == nil then
		return
	end
	local heading = Ui.text(rentalBody, tostring(view.innName), 22, Ui.colors.text)
	heading.FontFace = Ui.fonts.title
	Ui.text(rentalBody, string.format("A private room, %d by %d studs  ·  %d gold a day", view.room[1], view.room[2], view.pricePerDay), 14, Ui.colors.muted)
	Ui.text(rentalBody, string.format("You have %d gold", view.gold), 13, Ui.colors.muted)
	if view.activeInn ~= nil and view.activeInn ~= view.innId then
		Ui.text(rentalBody, string.format("You already rent a room at %s (%s left).", tostring(view.activeInnName), duration(view.secondsLeft)), 14, Ui.colors.red)
		return
	end
	if view.activeInn == view.innId then
		Ui.text(rentalBody, "Your room is yours for another " .. duration(view.secondsLeft) .. ".", 15, Ui.colors.silver)
		if view.atDoor then
			local innId = view.innId
			Ui.primary(Ui.button(rentalBody, "Go to my room", function()
				remotes.RentalRequest:FireServer("Enter", innId)
				Ui.close()
			end, 200))
		end
	end
	-- a stay can run at most maxDays ahead, counting the time already paid for
	local dayLength = view.dayLengthSeconds or 86400
	local paidFor = if view.activeInn == view.innId then view.secondsLeft else 0
	local options = {}
	for _, days in ipairs({ 1, 3, view.maxDays }) do
		if not table.find(options, days) and days * dayLength + paidFor <= view.maxDays * dayLength then
			table.insert(options, days)
		end
	end
	if #options == 0 then
		Ui.text(rentalBody, string.format("A stay can be paid at most %d days ahead.", view.maxDays), 13, Ui.colors.muted)
		return
	end
	local row = Ui.row(rentalBody)
	local innId = view.innId
	-- each payment is a new one: one click per view, until the server answers with a fresh one
	local clicked = false
	for _, days in ipairs(options) do
		local cost = days * view.pricePerDay
		local label = string.format("%s %d day%s (%d gold)", if view.activeInn == view.innId then "Stay" else "Rent", days, if days == 1 then "" else "s", cost)
		local button = Ui.button(row, label, function()
			if not clicked then
				clicked = true
				remotes.RentalRequest:FireServer("Rent", innId, days)
			end
		end, 140)
		if view.gold < cost then
			button.TextColor3 = Ui.colors.muted
		end
	end
end
Ui.onRefresh("Rentals", renderRentals)

-- Guild desk (L-30, L-48, L-54) -----------------------------------------------------------------------
local _, guildBody = Ui.window(gui, "GuildDesk", "Guild desk", 660, 660)
local guildView: any = nil
local guildTab = "Guilds"
local foundingConfirm = false
local draftName, draftEmblem, draftNewEmblem = "", "", ""
local pendingLeader: number? = nil
local draftDisband = ""

local function guildRequest(action: string, args: any?)
	remotes.GuildRequest:FireServer(action, args or {})
end

-- An emblem from a Roblox image ID, with the default shown when there is none or it can't be loaded.
local function emblem(parent: Instance, assetId: any, size: number)
	local holder = Instance.new("Frame")
	holder.BackgroundColor3 = Ui.colors.charcoal
	holder.Size = UDim2.new(0, size, 0, size)
	Ui.corner(holder)
	holder.Parent = parent
	local fallback = Ui.text(holder, "No emblem", 10, Ui.colors.muted)
	fallback.TextXAlignment = Enum.TextXAlignment.Center
	fallback.AutomaticSize = Enum.AutomaticSize.None
	fallback.Size = UDim2.new(1, 0, 1, 0)
	local id = tonumber(assetId)
	if id ~= nil and id > 0 then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.new(1, 0, 1, 0)
		image.Image = "rbxassetid://" .. tostring(id)
		image.Parent = holder
		fallback.Visible = false
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ image }, function(_: string, status: Enum.AssetFetchStatus)
					if status ~= Enum.AssetFetchStatus.Success then
						image:Destroy()
						fallback.Visible = true
					end
				end)
			end)
		end)
	end
end

local function inputBox(parent: Instance, placeholder: string, value: string, changed: (string) -> ()): TextBox
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Ui.colors.charcoal
	box.TextColor3 = Ui.colors.text
	box.PlaceholderText = placeholder
	box.Font = Enum.Font.Gotham
	box.TextSize = 15
	box.Text = value
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = UDim2.new(1, 0, 0, 30)
	Ui.corner(box)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		changed(box.Text)
	end)
	box.Parent = parent
	return box
end

local renderGuildDesk: () -> ()

local function renderMine(mine: any)
	local header = Ui.row(guildBody)
	emblem(header, mine.emblemAssetId, 48)
	local title = Ui.text(header, string.format("<b>%s</b>   Level %d   <font color='%s'>%s</font>", mine.name, mine.level, Ui.hex.muted, mine.nextLevelXp and string.format("%d / %d guild XP", mine.xp, mine.nextLevelXp) or "highest level"), 16)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Size = UDim2.new(0, 520, 0, 48)
	local permissions = mine.permissions
	local myRank = table.find(guildView.ranks, mine.myRank) or 99

	local members = Ui.section(guildBody, string.format("Members (%d)", #mine.members))
	for _, member in ipairs(mine.members) do
		local row = Ui.row(members)
		local label = Ui.text(row, string.format("%s   <font color='%s'>%s</font>", member.name, Ui.hex.silver, member.rank), 14)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(0, 300, 0, 26)
		local rankIndex = table.find(guildView.ranks, member.rank) or 99
		local userId = member.userId
		if rankIndex > myRank then
			if permissions.promote and rankIndex - 1 > myRank then
				Ui.button(row, "Promote", function()
					guildRequest("SetRank", { userId = userId, rank = guildView.ranks[rankIndex - 1] })
				end, 90)
			end
			if permissions.promote and rankIndex < #guildView.ranks then
				Ui.button(row, "Demote", function()
					guildRequest("SetRank", { userId = userId, rank = guildView.ranks[rankIndex + 1] })
				end, 90)
			end
			if permissions.kick then
				Ui.button(row, "Remove", function()
					guildRequest("Kick", { userId = userId })
				end, 90)
			end
			if mine.myRank == guildView.ranks[1] then
				Ui.button(row, pendingLeader == userId and "Confirm" or "Make leader", function()
					if pendingLeader == userId then
						pendingLeader = nil
						guildRequest("TransferLeadership", { userId = userId })
					else
						pendingLeader = userId
						renderGuildDesk()
					end
				end, 110)
			end
		end
	end
	if permissions.invite and #guildView.invitable > 0 then
		local invite = Ui.section(guildBody, "Invite players nearby")
		for _, candidate in ipairs(guildView.invitable) do
			local userId = candidate.userId
			Ui.button(invite, "Invite " .. candidate.name, function()
				guildRequest("Invite", { userId = userId })
			end, 260)
		end
	end

	local economy = Ui.section(guildBody, "Treasury and tax")
	Ui.text(economy, string.format("Guild tax: %d%% of members' quest gold.", mine.taxRate), 14)
	if permissions.setTax then
		local rates = Ui.row(economy)
		for _, rate in ipairs(guildView.taxRates) do
			local button = Ui.button(rates, string.format("%d%%", rate), function()
				guildRequest("SetTax", { rate = rate })
			end, 60)
			if rate == mine.taxRate then
				button.TextColor3 = Ui.colors.text
			end
		end
	end
	if mine.treasury ~= nil then
		Ui.text(economy, string.format("Treasury: <font color='%s'>%d gold</font>", Ui.hex.gold, mine.treasury), 15)
		for index = #mine.ledger, 1, -1 do
			local entry = mine.ledger[index]
			Ui.text(economy, string.format("%s  %+d  %s", entry.kind, entry.amount, tostring(entry.purpose or "")), 13, Ui.colors.muted)
		end
	end

	local hall = Ui.section(guildBody, "Hall and upgrades")
	local condition = mine.maintenance.condition
	Ui.text(hall, string.format("Hall upkeep: %d gold a week. Condition: %s.", mine.maintenance.weeklyCost, condition), 14, condition == "Neglected" and Ui.colors.red or Ui.colors.text)
	if condition == "Neglected" and permissions.spend then
		Ui.primary(Ui.button(hall, string.format("Restore the hall (%d gold)", mine.maintenance.weeklyCost), function()
			guildRequest("Restore")
		end, 260))
	end
	for _, upgrade in ipairs(mine.upgrades) do
		local row = Ui.row(hall)
		local label = Ui.text(row, string.format("%s   %d gold, guild level %d%s", upgrade.name, upgrade.cost, upgrade.requiredLevel, upgrade.requires and (", after " .. upgrade.requires) or ""), 14)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(0, 420, 0, 26)
		if upgrade.built then
			Ui.text(row, "Built", 14, Ui.colors.green).Size = UDim2.new(0, 80, 0, 26)
		elseif permissions.upgrade then
			local upgradeId = upgrade.id
			Ui.primary(Ui.button(row, "Build", function()
				guildRequest("BuyUpgrade", { upgradeId = upgradeId })
			end, 80))
		end
	end

	if permissions.emblem then
		local emblemSection = Ui.section(guildBody, "Emblem")
		Ui.text(emblemSection, "A Roblox image ID. If Roblox can't show the image, the default emblem appears.", 13, Ui.colors.muted)
		inputBox(emblemSection, "Image ID", draftNewEmblem, function(text: string)
			draftNewEmblem = text
		end)
		Ui.button(emblemSection, "Change emblem", function()
			guildRequest("SetEmblem", { assetId = draftNewEmblem })
		end, 160)
	end
	Ui.danger(Ui.button(guildBody, "Leave the guild", function()
		guildRequest("Leave")
	end, 180))
	if mine.myRank == guildView.ranks[1] then
		local ending = Ui.section(guildBody, "Disband the guild")
		Ui.text(ending, "This cannot be undone: the guild, its treasury, its level and its hall are gone for good. Type the guild's name to confirm.", 13, Ui.colors.red)
		inputBox(ending, mine.name, draftDisband, function(text: string)
			draftDisband = text
		end)
		Ui.danger(Ui.button(ending, "Disband forever", function()
			guildRequest("Disband", { confirmName = draftDisband })
		end, 180))
	end
end

local function renderFounding()
	local founding = guildView.founding
	local info = Ui.section(guildBody, "Found a guild")
	Ui.text(info, string.format("Founding costs <font color='%s'>%d gold</font> and needs character level %d. You are level %d with %d gold.", Ui.hex.gold, founding.cost, founding.minLevel, founding.level, founding.gold), 14)
	if not founding.canFound then
		Ui.text(info, tostring(founding.reason), 14, Ui.colors.red)
		return
	end
	inputBox(info, string.format("Guild name (%d to %d letters, digits and spaces)", founding.nameMin, founding.nameMax), draftName, function(text: string)
		draftName = text
	end)
	Ui.text(info, "Emblem: a Roblox image ID (optional). If Roblox can't show it, the default emblem appears.", 13, Ui.colors.muted)
	local preview = Ui.row(info)
	inputBox(preview, "Image ID", draftEmblem, function(text: string)
		draftEmblem = text
	end).Size = UDim2.new(0, 220, 0, 30)
	Ui.button(preview, "Preview", function()
		renderGuildDesk()
	end, 90)
	emblem(preview, draftEmblem, 48)
	if not foundingConfirm then
		Ui.primary(Ui.button(info, string.format("Found the guild for %d gold", founding.cost), function()
			foundingConfirm = true
			renderGuildDesk()
		end, 280))
	else
		Ui.text(info, string.format("Found \"%s\" for %d gold?", draftName, founding.cost), 14, Ui.colors.gold)
		local row = Ui.row(info)
		Ui.primary(Ui.button(row, "Confirm", function()
			foundingConfirm = false
			guildRequest("Found", { name = draftName, emblemAssetId = draftEmblem })
		end, 120))
		Ui.button(row, "Cancel", function()
			foundingConfirm = false
			renderGuildDesk()
		end, 100)
	end
end

renderGuildDesk = function()
	Ui.clear(guildBody)
	if guildView == nil then
		return
	end
	local tabs = Ui.row(guildBody)
	local available = { "Guilds" }
	if guildView.mine ~= nil then
		table.insert(available, "My guild")
	else
		table.insert(available, "Found a guild")
	end
	if guildView.invitation ~= nil then
		table.insert(available, "Invitation")
	end
	if table.find(available, guildTab) == nil then
		guildTab = available[1]
	end
	for _, tab in ipairs(available) do
		local button = Ui.button(tabs, tab, function()
			guildTab = tab
			renderGuildDesk()
		end, 140)
		if tab == guildTab then
			Ui.markSelected(button)
		end
		if tab == guildTab then
			button.TextColor3 = Ui.colors.text
			button.BackgroundColor3 = Ui.colors.charcoal
		end
	end
	if guildTab == "Guilds" then
		if #guildView.ranking == 0 then
			Ui.text(guildBody, "No guilds yet. Be the first.", 14, Ui.colors.muted)
		end
		for _, entry in ipairs(guildView.ranking) do
			local row = Ui.row(guildBody)
			emblem(row, entry.emblemAssetId, 36)
			local label = Ui.text(row, string.format("#%d  <b>%s</b>   Level %d   %d members   tax %d%%", entry.rank, entry.name, entry.level, entry.members, entry.taxRate or 0), 14)
			label.AutomaticSize = Enum.AutomaticSize.None
			label.Size = UDim2.new(0, 540, 0, 36)
		end
	elseif guildTab == "My guild" then
		renderMine(guildView.mine)
	elseif guildTab == "Found a guild" then
		renderFounding()
	else
		local invitation = guildView.invitation
		Ui.text(guildBody, string.format("%s invited you to join %s.", tostring(invitation.from), tostring(invitation.name)), 15)
		local row = Ui.row(guildBody)
		Ui.primary(Ui.button(row, "Accept", function()
			guildRequest("Accept")
		end, 120))
		Ui.button(row, "Decline", function()
			guildRequest("Decline")
		end, 120)
	end
end
Ui.onRefresh("GuildDesk", renderGuildDesk)
Ui.onClose("GuildDesk", function()
	foundingConfirm = false
end)

-- Shop counter (L-53 to L-55) -------------------------------------------------------------------------
local _, counterBody = Ui.window(gui, "ShopCounter", "Shop counter", 680, 660)
local counterView: any = nil
local drafts: {[string]: string} = {}

local function shopRequest(action: string, args: any?)
	remotes.ShopRequest:FireServer(action, args or {})
end

local function numberBox(parent: Instance, key: string, placeholder: string, width: number): TextBox
	local box = inputBox(parent, placeholder, drafts[key] or "", function(text: string)
		drafts[key] = text
	end)
	box.Size = UDim2.new(0, width, 0, 28)
	return box
end

local function sized(label: TextLabel, width: number)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(0, width, 0, 28)
end

local renderCounter: () -> ()
renderCounter = function()
	Ui.clear(counterBody)
	local view = counterView
	if view == nil then
		return
	end
	if view.unreachable then
		Ui.text(counterBody, "The shop's ledger can't be reached right now. Try again shortly.", 14, Ui.colors.red)
		return
	end
	local shopHeading = Ui.text(counterBody, string.format("%s's shop", tostring(view.ownerName)), 22, Ui.colors.text)
	shopHeading.FontFace = Ui.fonts.title
	Ui.text(counterBody, string.format("<font color='%s'>Royal market tax: %d%% of every sale</font>", Ui.hex.muted, view.taxPercent), 15)

	local sale = Ui.section(counterBody, "For sale")
	if #view.listings == 0 then
		Ui.text(sale, "Nothing listed.", 13, Ui.colors.muted)
	end
	for _, listing in ipairs(view.listings) do
		local row = Ui.row(sale)
		local detail = ""
		if listing.craftedBy ~= nil then
			detail = string.format("   <font color='%s'>crafted by %s%s</font>", Ui.hex.silver, tostring(listing.craftedBy), listing.quality and (", " .. tostring(listing.quality)) or "")
		end
		sized(Ui.text(row, string.format("%s  x%d   <font color='%s'>%d gold each</font>%s", listing.name, listing.count, Ui.hex.gold, listing.price, detail), 14, Ui.rarity[listing.rarity] or Ui.colors.text), 430)
		local listingId, price = listing.id, listing.price
		if view.isOwner then
			Ui.button(row, "Take back", function()
				shopRequest("Unlist", { listingId = listingId })
			end, 100)
		else
			local key = "buy:" .. listingId
			if not listing.unique then
				numberBox(row, key, "1", 50)
			end
			Ui.primary(Ui.button(row, "Buy", function()
				shopRequest("Buy", { listingId = listingId, quantity = tonumber(drafts[key] or "") or 1, price = price })
			end, 70))
		end
	end

	local buying = Ui.section(counterBody, "Buying")
	if #view.orders == 0 then
		Ui.text(buying, "No buy orders.", 13, Ui.colors.muted)
	end
	for _, order in ipairs(view.orders) do
		local row = Ui.row(buying)
		sized(Ui.text(row, string.format("%s   wants %d   <font color='%s'>%d gold each</font>", order.name, order.remaining, Ui.hex.gold, order.price), 14), 430)
		local orderId, itemId, price = order.id, order.itemId, order.price
		if view.isOwner then
			Ui.button(row, "Cancel", function()
				shopRequest("Cancel", { orderId = orderId })
			end, 90)
		else
			local have = carried(itemId)
			if have > 0 then
				local key = "sell:" .. orderId
				local most = math.min(have, order.remaining)
				numberBox(row, key, tostring(most), 50)
				Ui.primary(Ui.button(row, "Sell", function()
					shopRequest("Sell", { orderId = orderId, itemId = itemId, quantity = tonumber(drafts[key] or "") or most, price = price })
				end, 70))
			end
		end
	end
	if not view.isOwner then
		return
	end

	local earnings = Ui.section(counterBody, "Earnings")
	Ui.text(earnings, string.format("Waiting for you: <font color='%s'>%d gold</font> and %d kind(s) of goods bought.   Royal tax paid so far: %d gold.", Ui.hex.gold, view.balance or 0, view.collected or 0, view.taxPaid or 0), 14)
	Ui.primary(Ui.button(earnings, "Collect", function()
		shopRequest("Claim")
	end, 120))

	local listing = Ui.section(counterBody, "Put goods up for sale")
	for _, entry in ipairs((inventory and inventory.entries) or {}) do
		local row = Ui.row(listing)
		sized(Ui.text(row, string.format("%s  x%d", entry.name, entry.count), 14, Ui.rarity[entry.rarity] or Ui.colors.text), 260)
		local ref = entry.uid or entry.key
		local amountKey, priceKey = "amount:" .. ref, "price:" .. ref
		local stackKey, uid = entry.key, entry.uid
		if uid == nil then
			numberBox(row, amountKey, "amount", 80)
		end
		numberBox(row, priceKey, "gold each", 90)
		Ui.primary(Ui.button(row, "List", function()
			shopRequest("List", { stackKey = stackKey, uid = uid, amount = tonumber(drafts[amountKey] or "") or 1, price = tonumber(drafts[priceKey] or "") })
		end, 70))
	end

	local posting = Ui.section(counterBody, "Post a buy order")
	Ui.text(posting, "Choose what you want to buy. The order's full cost is set aside from your gold until it fills or you cancel it.", 13, Ui.colors.muted)
	local stackables = {}
	for id, def in pairs(Content.items) do
		if (def.maxStack or 1) > 1 then
			table.insert(stackables, { id = id, name = def.displayName })
		end
	end
	table.sort(stackables, function(a, b)
		return a.name < b.name
	end)
	for _, choice in ipairs(stackables) do
		local itemId = choice.id
		local button = Ui.button(posting, choice.name, function()
			drafts.orderItem = itemId
			renderCounter()
		end, 300)
		if drafts.orderItem == itemId then
			button.TextColor3 = Ui.colors.text
			button.BackgroundColor3 = Ui.colors.charcoal
		end
	end
	if drafts.orderItem ~= nil then
		local row = Ui.row(posting)
		numberBox(row, "orderQuantity", "how many", 100)
		numberBox(row, "orderPrice", "gold each", 100)
		Ui.primary(Ui.button(row, "Post order", function()
			shopRequest("Order", { itemId = drafts.orderItem, quantity = tonumber(drafts.orderQuantity or ""), price = tonumber(drafts.orderPrice or "") })
		end, 120))
	end
end
Ui.onRefresh("ShopCounter", renderCounter)

-- Rift contributions (L-36, L-47) -------------------------------------------------------------------------
local _, riftBody = Ui.window(gui, "RiftDonations", "Heart of Realms", 560, 560)
local riftView: any = nil
local riftChoice: any = nil

local renderRift: () -> ()
renderRift = function()
	Ui.clear(riftBody)
	local view = riftView
	if view == nil then
		return
	end
	local heading = Ui.text(riftBody, view.name, 22, Ui.colors.text)
	heading.FontFace = Ui.fonts.title
	Ui.text(riftBody, view.description, 14, Ui.colors.muted)
	local progress = Ui.bar(riftBody, view.fraction, Ui.colors.violet)
	progress.Size = UDim2.new(1, 0, 0, 14)
	local percent = Ui.text(progress, string.format("%d%%", math.floor(math.clamp(view.fraction, 0, 1) * 100 + 0.5)), 11, Ui.colors.text)
	percent.FontFace = Ui.fonts.labelBold
	percent.AutomaticSize = Enum.AutomaticSize.None
	percent.Size = UDim2.new(1, 0, 1, 0)
	percent.TextXAlignment = Enum.TextXAlignment.Center
	percent.ZIndex = 3
	Ui.text(riftBody, string.format("%d of %d Robux gathered across all of Lundand.   %d still needed.", view.total, view.target, view.remaining), 14)
	if view.status ~= "Collecting" then
		Ui.text(riftBody, view.status == "Open" and "The Rift is open to every adventurer." or "This Rift has closed.", 15, Ui.colors.gold)
		return
	end
	Ui.text(riftBody, "Contributions are voluntary and give no advantage in play. Everyone can enter the Rift once it opens.", 13, Ui.colors.muted)
	local amounts = Ui.section(riftBody, "Contribute")
	local tiersRow = Ui.row(amounts)
	for _, tier in ipairs(view.tiers) do
		local key, robux = tier.key, tier.robux
		local button = Ui.button(tiersRow, tier.available and string.format("%d Robux", robux) or string.format("%d Robux (not set up yet)", robux), function()
			if tier.available then
				riftChoice = { key = key, robux = robux }
				renderRift()
			end
		end, if tier.available then 130 else 230)
		if not tier.available then
			button.TextColor3 = Ui.colors.muted
		elseif riftChoice ~= nil and riftChoice.key == key then
			Ui.markSelected(button)
		end
	end
	if riftChoice ~= nil then
		local confirm = Ui.section(riftBody, "Confirm")
		Ui.text(confirm, string.format("Contribute %d Robux to %s? Roblox will ask you to confirm the purchase.", riftChoice.robux, view.name), 14, Ui.colors.gold)
		local row = Ui.row(confirm)
		local key = riftChoice.key
		Ui.primary(Ui.button(row, "Contribute", function()
			riftChoice = nil
			remotes.RiftRequest:FireServer("Donate", { product = key })
			renderRift()
		end, 140))
		Ui.button(row, "Cancel", function()
			riftChoice = nil
			renderRift()
		end, 100)
	end
end
Ui.onRefresh("RiftDonations", renderRift)
Ui.onClose("RiftDonations", function()
	riftChoice = nil
end)

-- Cosmetic shop (L-46) --------------------------------------------------------------------------------
local _, cosmeticBody = Ui.window(gui, "CosmeticShop", "Silk and Silver", 620, 620)
local cosmeticView: any = nil

Ui.onRefresh("CosmeticShop", function()
	Ui.clear(cosmeticBody)
	if cosmeticView == nil then
		return
	end
	Ui.text(cosmeticBody, "Looks only. Nothing here changes stats, drops or experience.", 13, Ui.colors.muted)
	local category, section = nil, nil
	for _, item in ipairs(cosmeticView.items) do
		if item.category ~= category or section == nil then
			category = item.category
			section = Ui.section(cosmeticBody, item.category)
		end
		local tag = ""
		if item.label == "LimitedTime" and item.endsAt ~= nil then
			tag = string.format("   <font color='%s'>Limited time, until %s</font>", Ui.hex.gold, os.date("%d %b %Y", item.endsAt))
		end
		Ui.text(section, string.format("<b>%s</b>%s", item.name, tag), 15)
		Ui.text(section, item.description, 13, Ui.colors.muted)
		local row = Ui.row(section)
		local cosmeticId, worn = item.id, cosmeticView.worn[item.wearKey] == item.id
		local status
		if item.owned then
			status = Ui.text(row, worn and "Owned, worn" or "Owned", 14, Ui.colors.green)
			Ui.button(row, worn and "Remove" or "Wear", function()
				remotes.CosmeticRequest:FireServer(worn and "Remove" or "Wear", cosmeticId)
			end, 100)
		elseif item.availability == "Available" then
			status = Ui.text(row, string.format("%d Robux", item.price), 14, Ui.colors.gold)
			Ui.primary(Ui.button(row, "Buy", function()
				remotes.CosmeticRequest:FireServer("Buy", cosmeticId)
			end, 100))
		else
			status = Ui.text(row, item.availability == "Upcoming" and "Coming soon" or "Not on sale yet", 14, Ui.colors.muted)
		end
		status.AutomaticSize = Enum.AutomaticSize.None
		status.Size = UDim2.new(0, 160, 0, 26)
	end
end)

remotes.OpenInterface.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "GuildDesk" and type(data) == "table" and data.focus ~= nil then
		guildTab = data.focus
	end
	if kind == "ShopCounter" and type(data) == "table" then
		counterView = data
		rememberPosition()
		if Ui.isOpen("ShopCounter") then
			Ui.refresh("ShopCounter")
		else
			Ui.open("ShopCounter")
		end
	elseif kind == "RiftDonations" and type(data) == "table" then
		riftView = data
		riftChoice = nil
		rememberPosition()
		Ui.open("RiftDonations")
	elseif kind == "GuildDesk" and type(data) == "table" then
		guildView = data
		rememberPosition()
		if Ui.isOpen("GuildDesk") then
			Ui.refresh("GuildDesk")
		else
			Ui.open("GuildDesk")
		end
	elseif kind == "Rentals" and type(data) == "table" then
		rentalView = data
		rememberPosition()
		if Ui.isOpen("Rentals") then
			Ui.refresh("Rentals")
		else
			Ui.open("Rentals")
		end
	elseif kind == "Property" and type(data) == "table" then
		propertyView = data
		confirming = false
		rememberPosition()
		if Ui.isOpen("Property") then
			Ui.refresh("Property")
		else
			Ui.open("Property")
		end
	elseif kind == "CosmeticShop" and type(data) == "table" then
		cosmeticView = data
		rememberPosition()
		if Ui.isOpen("CosmeticShop") then
			Ui.refresh("CosmeticShop")
		else
			Ui.open("CosmeticShop")
		end
	elseif kind == "Crafting" and type(data) == "table" then
		craftView = data
		rememberPosition()
		if Ui.isOpen("Crafting") then
			Ui.refresh("Crafting")
		else
			Ui.open("Crafting")
		end
	elseif kind == "Vendor" and type(data) == "table" then
		shopView = data
		amounts = {}
		rememberPosition()
		Ui.open("Vendor")
	end
end)

remotes.Snapshot.OnClientEvent:Connect(function(section: string, data: any)
	if section == "Inventory" then
		inventory = data
		Ui.refresh("Crafting")
		Ui.refresh("Vendor")
		Ui.refresh("ShopCounter")
	end
end)

-- Walking away from the workshop or the vendor closes their window.
RunService.Heartbeat:Connect(function()
	if openedAt == nil or not (Ui.isOpen("Crafting") or Ui.isOpen("Vendor") or Ui.isOpen("CosmeticShop") or Ui.isOpen("Property") or Ui.isOpen("Rentals") or Ui.isOpen("GuildDesk") or Ui.isOpen("ShopCounter") or Ui.isOpen("RiftDonations")) then
		return
	end
	local root: any = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and (root.Position - openedAt).Magnitude > WALK_AWAY then
		openedAt = nil
		Ui.close()
	end
end)
