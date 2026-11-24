-- Pawn by Vger-Azjol-Nerub
-- www.vgermods.com
-- © 2006-2026 Travis Spomer.  This mod is released under the Creative Commons Attribution-NonCommercial-NoDerivs 3.0 license.
-- See Readme.md for more information.
--
-- Set upgrades window: lists items you own that are an upgrade for a scale's "Compare against" equipment set but aren't
-- in that set yet, wherever they are: in your bags, equipped (say, while you're wearing a different set), or in your
-- bank (as of the last time it was open).  When a new one turns up, it pops up and says so in chat (each can be turned
-- off in the window).  /pawn upgrades opens it any time.
------------------------------------------------------------

local MAX_ROWS = 12
local ROW_HEIGHT, ICON_SIZE, WIDTH, PADDING = 32, 24, 360, 10
local FIRST_SLOT, LAST_SLOT = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19
local L = {
	Title = "Pawn: set upgrades",
	None = "No set upgrades.",
	More = "...and %d more.",
	PopUp = "Pop up for new upgrades",
	Announce = "Announce new upgrades in chat",
	Announcement = "|cff8ec3e6Pawn:|r %s is an upgrade for your |cffffd100%s|r set.  (/pawn upgrades)",
	Hint = "Click to equip, then save the set.  Shift-click to link.",
	NoSets = "No scales compare against an equipment set.  Pick one with \"Compare against\" on Pawn's Compare tab.",
	Combat = "Can't change equipment in combat.",
	Equipped = "Equipped %s.  Save |cffffd100%s|r in the equipment manager to add it.",
}

local Upgrades = {} -- { { Link, SetID, SetName, Lines = { upgrade tooltip lines }, ReplacesSlot }, ... }
local Seen = {} -- [link .. ":" .. setID] = true for upgrades already found this session
local AnySetScales = false
local BankOpen = false
local OpenedByHand = false

------------------------------------------------------------
-- Finding upgrades
------------------------------------------------------------

local function GetNumSlots(Bag)
	if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(Bag) or 0 end
	return GetContainerNumSlots and GetContainerNumSlots(Bag) or 0
end

local function GetSlotLink(Bag, Slot)
	if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(Bag, Slot) end
	return GetContainerItemLink and GetContainerItemLink(Bag, Slot)
end

local function IsEquippable(Link)
	local Fn = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
	if not Fn then return true end
	return Fn(Link)
end

local function GetBagLinks(Bags, Links)
	for _, Bag in ipairs(Bags) do
		for Slot = 1, GetNumSlots(Bag) do
			local Link = GetSlotLink(Bag, Slot)
			if Link and IsEquippable(Link) then table.insert(Links, Link) end
		end
	end
	return Links
end

-- Returns every equippable item you have: equipped, in your bags, and in your bank as of the last time it was open.
local function GetAllItemLinks()
	local Links = {}
	for Slot = FIRST_SLOT, LAST_SLOT do
		local Link = GetInventoryItemLink("player", Slot)
		if Link then table.insert(Links, Link) end
	end
	local Bags = {}
	for Bag = 0, NUM_BAG_SLOTS or 4 do table.insert(Bags, Bag) end
	GetBagLinks(Bags, Links)

	-- The bank can only be read while it's open, so remember what's in it.
	if BankOpen then
		local BankBags = { BANK_CONTAINER or -1 }
		local First = (NUM_BAG_SLOTS or 4) + 1
		for Bag = First, First + (NUM_BANKBAGSLOTS or 7) - 1 do table.insert(BankBags, Bag) end
		PawnOptions.SetUpgradeBankLinks = GetBagLinks(BankBags, {})
	end
	for _, Link in ipairs(PawnOptions.SetUpgradeBankLinks or {}) do table.insert(Links, Link) end
	return Links
end

-- Returns { [ScaleName] = EquipmentSetID } for the visible scales that compare against an equipment set, or nil if
-- there aren't any or Pawn isn't ready yet.
local function GetSetScales()
	if not PawnCommon or not PawnCommon.Scales or not PawnPlayerFullName or not PawnOptions then return nil end
	local Scales
	for ScaleName, Scale in pairs(PawnCommon.Scales) do
		-- PawnIsItemAnUpgrade fails if a scale's per-character options aren't set up yet.
		if not (Scale.PerCharacterOptions and Scale.PerCharacterOptions[PawnPlayerFullName]) then return nil end
		local SetID = PawnIsScaleVisible(ScaleName) and PawnGetScaleComparisonSet(ScaleName)
		if SetID then
			Scales = Scales or {}
			Scales[ScaleName] = SetID
		end
	end
	return Scales
end

local function GetItemID(Link)
	return Link and tonumber(Link:match("item:(%d+)"))
end

-- Returns the slot an equipment set keeps an item in, or nil if the item isn't in the set.
local function GetSetSlotForItem(SetID, Link)
	local ItemIDs = C_EquipmentSet.GetItemIDs and C_EquipmentSet.GetItemIDs(SetID)
	local ItemID = GetItemID(Link)
	if not ItemIDs or not ItemID then return nil end
	for Slot = FIRST_SLOT, LAST_SLOT do
		if ItemIDs[Slot] == ItemID then return Slot end
	end
end

-- Rebuilds the list.  Returns true if it found an upgrade that wasn't there before.
local function ScanUpgrades()
	wipe(Upgrades)
	if not PawnEquipmentSetsAvailable() then AnySetScales = false return false end
	local SetScales = GetSetScales()
	AnySetScales = SetScales ~= nil
	if not SetScales then return false end

	local Checked = {}
	for _, Link in ipairs(GetAllItemLinks()) do
		if not Checked[Link] then
			Checked[Link] = true
			local Item = PawnGetItemData(Link)
			local Succeeded, UpgradeInfo, NeedsEnhancements
			if Item then
				local _
				Succeeded, UpgradeInfo, _, _, _, NeedsEnhancements = pcall(PawnIsItemAnUpgrade, Item)
			end
			if Succeeded and UpgradeInfo then
				-- One entry per set, with a line for each of that set's scales.  Scales that compare against equipped items
				-- are left out: Pawn's bag arrows and tooltips already cover those.
				local BySet = {}
				for _, Upgrade in ipairs(UpgradeInfo) do
					local SetID = SetScales[Upgrade.ScaleName]
					if SetID and not GetSetSlotForItem(SetID, Link) then
						local Entry = BySet[SetID]
						if not Entry then
							Entry = { Link = Link, SetID = SetID, SetName = C_EquipmentSet.GetEquipmentSetInfo(SetID) or "?", Lines = {},
								ReplacesSlot = GetSetSlotForItem(SetID, Upgrade.ExistingItemLink) }
							BySet[SetID] = Entry
							tinsert(Upgrades, Entry)
						end
						tinsert(Entry.Lines, PawnGetUpgradeTooltipLine(Upgrade, NeedsEnhancements))
					end
				end
			end
		end
	end
	sort(Upgrades, function(a, b)
		if a.SetName ~= b.SetName then return a.SetName < b.SetName end
		return a.Link < b.Link
	end)

	local FoundNew = false
	for _, Upgrade in ipairs(Upgrades) do
		local Key = Upgrade.Link .. ":" .. Upgrade.SetID
		if not Seen[Key] then
			Seen[Key] = true
			FoundNew = true
			if not PawnCommon.SetUpgradesNoChat then VgerCore.Message(format(L.Announcement, Upgrade.Link, Upgrade.SetName)) end
		end
	end
	return FoundNew
end

------------------------------------------------------------
-- Window
------------------------------------------------------------

local Frame = CreateFrame("Frame", "PawnSetUpgradesFrame", UIParent)
Frame:SetSize(WIDTH, 100)
Frame:SetFrameStrata("DIALOG")
Frame:SetClampedToScreen(true)
Frame:SetMovable(true)
Frame:EnableMouse(true)
Frame:RegisterForDrag("LeftButton")
Frame:Hide()
tinsert(UISpecialFrames, "PawnSetUpgradesFrame") -- Escape closes it

local Background = Frame:CreateTexture(nil, "BACKGROUND")
Background:SetAllPoints()
Background:SetColorTexture(0, 0, 0, 0.8)

local TitleText = Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
TitleText:SetPoint("TOPLEFT", PADDING, -PADDING)
TitleText:SetText(L.Title)

local CloseButton = CreateFrame("Button", nil, Frame, "UIPanelCloseButton")
CloseButton:SetPoint("TOPRIGHT", 2, 2)

local MessageText = Frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
MessageText:SetPoint("TOPLEFT", TitleText, "BOTTOMLEFT", 0, -8)
MessageText:SetWidth(WIDTH - PADDING * 2)
MessageText:SetJustifyH("LEFT")

local HintText = Frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
HintText:SetPoint("BOTTOMLEFT", PADDING, PADDING)
HintText:SetText(L.Hint)

local PopUpCheck = CreateFrame("CheckButton", nil, Frame, "UICheckButtonTemplate")
PopUpCheck:SetSize(20, 20)
PopUpCheck:SetPoint("BOTTOMLEFT", HintText, "TOPLEFT", -2, 2)
local PopUpLabel = PopUpCheck.Text or PopUpCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
PopUpLabel:ClearAllPoints()
PopUpLabel:SetPoint("LEFT", PopUpCheck, "RIGHT", 2, 0)
PopUpLabel:SetFontObject("GameFontHighlightSmall")
PopUpLabel:SetText(L.PopUp)
PopUpCheck:SetScript("OnClick", function(self) PawnCommon.SetUpgradesNoPopUp = not self:GetChecked() end)

local ChatCheck = CreateFrame("CheckButton", nil, Frame, "UICheckButtonTemplate")
ChatCheck:SetSize(20, 20)
ChatCheck:SetPoint("BOTTOMLEFT", PopUpCheck, "TOPLEFT", 0, 0)
local ChatLabel = ChatCheck.Text or ChatCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ChatLabel:ClearAllPoints()
ChatLabel:SetPoint("LEFT", ChatCheck, "RIGHT", 2, 0)
ChatLabel:SetFontObject("GameFontHighlightSmall")
ChatLabel:SetText(L.Announce)
ChatCheck:SetScript("OnClick", function(self) PawnCommon.SetUpgradesNoChat = not self:GetChecked() end)

local function EquipUpgrade(Upgrade)
	if InCombatLockdown() then VgerCore.Message(L.Combat) return end
	local Equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
	if not Equip then return end
	Equip(Upgrade.Link, Upgrade.ReplacesSlot)
	VgerCore.Message(format(L.Equipped, Upgrade.Link, Upgrade.SetName))
end

local Rows = {}
local function GetRow(Index)
	if Rows[Index] then return Rows[Index] end
	local Row = CreateFrame("Button", nil, Frame)
	Row:SetSize(WIDTH - PADDING * 2, ROW_HEIGHT)
	Row:SetPoint("TOPLEFT", TitleText, "BOTTOMLEFT", 0, -6 - (Index - 1) * ROW_HEIGHT)
	Row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local Highlight = Row:CreateTexture(nil, "HIGHLIGHT")
	Highlight:SetAllPoints()
	Highlight:SetColorTexture(1, 1, 1, 0.1)

	Row.Icon = Row:CreateTexture(nil, "ARTWORK")
	Row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
	Row.Icon:SetPoint("LEFT", 2, 0)

	Row.Name = Row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	Row.Name:SetPoint("TOPLEFT", Row.Icon, "TOPRIGHT", 6, 0)
	Row.Name:SetPoint("RIGHT", Row, "RIGHT", -100, 0)
	Row.Name:SetJustifyH("LEFT")
	Row.Name:SetWordWrap(false)

	Row.SetName = Row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	Row.SetName:SetPoint("TOPRIGHT", Row, "TOPRIGHT", -2, -3)
	Row.SetName:SetWidth(96)
	Row.SetName:SetJustifyH("RIGHT")
	Row.SetName:SetWordWrap(false)

	Row.Detail = Row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	Row.Detail:SetPoint("BOTTOMLEFT", Row.Icon, "BOTTOMRIGHT", 6, 0)
	Row.Detail:SetPoint("RIGHT", Row, "RIGHT", -2, 0)
	Row.Detail:SetJustifyH("LEFT")
	Row.Detail:SetWordWrap(false)

	Row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.Upgrade.Link)
		GameTooltip:Show()
	end)
	Row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Row:SetScript("OnClick", function(self)
		if IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
			ChatEdit_InsertLink(self.Upgrade.Link)
		else
			EquipUpgrade(self.Upgrade)
		end
	end)

	Rows[Index] = Row
	return Row
end

local function Refresh()
	local Shown = math.min(#Upgrades, MAX_ROWS)
	for Index = 1, Shown do
		local Row, Upgrade = GetRow(Index), Upgrades[Index]
		Row.Upgrade = Upgrade
		local ItemID = GetItemID(Upgrade.Link)
		Row.Icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ItemID)) or (GetItemIcon and GetItemIcon(ItemID)) or "Interface\\Icons\\INV_Misc_QuestionMark")
		Row.Name:SetText(Upgrade.Link)
		Row.SetName:SetText(Upgrade.SetName)
		Row.Detail:SetText(table.concat(Upgrade.Lines, "  "))
		Row:Show()
	end
	for Index = Shown + 1, #Rows do Rows[Index]:Hide() end

	local Message
	if #Upgrades > MAX_ROWS then
		Message = format(L.More, #Upgrades - MAX_ROWS)
	elseif #Upgrades == 0 then
		Message = AnySetScales and L.None or L.NoSets
	end
	MessageText:ClearAllPoints()
	if Message then
		MessageText:SetPoint("TOPLEFT", TitleText, "BOTTOMLEFT", 0, -8 - Shown * ROW_HEIGHT)
		MessageText:SetText(Message)
		MessageText:Show()
	else
		MessageText:Hide()
	end

	PopUpCheck:SetChecked(not PawnCommon.SetUpgradesNoPopUp)
	ChatCheck:SetChecked(not PawnCommon.SetUpgradesNoChat)
	local MessageHeight = Message and ((MessageText:GetStringHeight() or 12) + 8) or 0
	Frame:SetHeight(PADDING + 16 + 6 + Shown * ROW_HEIGHT + MessageHeight + 8 + 20 + 24 + 14 + PADDING)
end

local function RestorePosition()
	Frame:ClearAllPoints()
	local Position = PawnCommon.SetUpgradesWindow
	if Position and Position.Point then
		Frame:SetPoint(Position.Point, UIParent, Position.RelativePoint or Position.Point, Position.X or 0, Position.Y or 0)
	else
		Frame:SetPoint("RIGHT", UIParent, "RIGHT", -80, 80)
	end
end

Frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
Frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local Point, _, RelativePoint, X, Y = self:GetPoint()
	PawnCommon.SetUpgradesWindow = { Point = Point, RelativePoint = RelativePoint, X = X, Y = Y }
end)
Frame:SetScript("OnHide", function() OpenedByHand = false end)

local Ready = false
local function Update()
	if not Ready then return end
	local FoundNew = ScanUpgrades()
	if FoundNew and not PawnCommon.SetUpgradesNoPopUp and not Frame:IsShown() then
		RestorePosition()
		Frame:Show()
	elseif #Upgrades == 0 and Frame:IsShown() and not OpenedByHand then
		-- It popped up by itself and there's nothing left to show.
		Frame:Hide()
	end
	if Frame:IsShown() then Refresh() end
end

local UpdateQueued = false
local function QueueUpdate(Delay)
	if UpdateQueued then return end
	UpdateQueued = true
	C_Timer.After(Delay or 0.3, function()
		UpdateQueued = false
		Update()
	end)
end

-- Shows or hides the window.  (/pawn upgrades)
function PawnSetUpgradesToggle()
	if Frame:IsShown() then Frame:Hide() return end
	if not Ready then return end
	ScanUpgrades()
	RestorePosition()
	Frame:Show()
	OpenedByHand = true
	Refresh()
end

------------------------------------------------------------
-- Events
------------------------------------------------------------

Frame:SetScript("OnEvent", function(self, Event)
	if Event == "PLAYER_ENTERING_WORLD" then
		-- Pawn sets up its scales on login; give it a moment.
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		C_Timer.After(3, function() Ready = true QueueUpdate() end)
		return
	elseif Event == "BANKFRAME_OPENED" then
		BankOpen = true
	elseif Event == "BANKFRAME_CLOSED" then
		BankOpen = false
	end
	-- Item data arrives in bursts, so wait a little longer for it.
	QueueUpdate(Event == "GET_ITEM_INFO_RECEIVED" and 1 or 0.3)
end)

for _, Event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED",
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
	pcall(Frame.RegisterEvent, Frame, Event)
end

-- Pawn refreshes its bag arrows whenever scales or their equipment sets change, so recheck then too.
hooksecurefunc("PawnResetBags", function() QueueUpdate() end)
