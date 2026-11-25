-- Pawn by Vger-Azjol-Nerub
-- www.vgermods.com
-- © 2006-2026 Travis Spomer.  This mod is released under the Creative Commons Attribution-NonCommercial-NoDerivs 3.0 license.
-- See Readme.md for more information.
--
-- Set upgrades window: lists items you own that are an upgrade for a scale's "Compare against" equipment set but aren't
-- in that set yet, wherever they are: in your bags, equipped (say, while you're wearing a different set), or in your
-- bank (as of the last time it was open).  It stays on screen, like a unit frame, and says so in chat when a new one
-- turns up.  Drag to move; right-click for options, including hiding it; /pawn upgrades hides and shows it.
------------------------------------------------------------

local MAX_ROWS = 12
local ROW_HEIGHT, ICON_SIZE, WIDTH, PADDING = 28, 22, 300, 6
local FIRST_SLOT, LAST_SLOT = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19
local L = {
	Title = "Set upgrades",
	TitleCount = "Set upgrades (%d)",
	None = "None",
	More = "...and %d more.",
	Announce = "Announce new upgrades in chat",
	Lock = "Lock position",
	Hide = "Hide (/pawn upgrades to show)",
	Hidden = "Set upgrades hidden.  Type /pawn upgrades to show them again.",
	ChatOn = "Set upgrade announcements on.",
	ChatOff = "Set upgrade announcements off.",
	Usage = "/pawn upgrades -- show or hide the set upgrades window\n/pawn upgrades lock | unlock | chat | reset",
	Announcement = "|cff8ec3e6Pawn:|r %s is an upgrade for your |cffffd100%s|r set.",
	Hint = "Click to equip, then save the set.  Shift-click to link.  Right-click for options.",
	NoSets = "No scales compare against an equipment set.  Pick one with \"Compare against\" on Pawn's Compare tab.",
	Combat = "Can't change equipment in combat.",
	Equipped = "Equipped %s.  Save |cffffd100%s|r in the equipment manager to add it.",
}

local Upgrades = {} -- { { Link, SetID, SetName, Lines = { upgrade tooltip lines }, ReplacesSlot }, ... }
local Seen = {} -- [link .. ":" .. setID] = true for upgrades already found this session
local AnySetScales = false
local BankOpen = false

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
Frame:SetSize(WIDTH, 60)
Frame:SetFrameStrata("MEDIUM")
Frame:SetClampedToScreen(true)
Frame:SetMovable(true)
Frame:EnableMouse(true)
Frame:RegisterForDrag("LeftButton")
Frame:Hide()

local Background = Frame:CreateTexture(nil, "BACKGROUND")
Background:SetAllPoints()
Background:SetColorTexture(0, 0, 0, 0.5)

local TitleText = Frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TitleText:SetPoint("TOPLEFT", PADDING, -PADDING)
TitleText:SetText(L.Title)

local MessageText = Frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
MessageText:SetWidth(WIDTH - PADDING * 2)
MessageText:SetJustifyH("LEFT")

local Locked = function() return PawnCommon.SetUpgradesLocked end

local function EquipUpgrade(Upgrade)
	if InCombatLockdown() then VgerCore.Message(L.Combat) return end
	local Equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
	if not Equip then return end
	Equip(Upgrade.Link, Upgrade.ReplacesSlot)
	VgerCore.Message(format(L.Equipped, Upgrade.Link, Upgrade.SetName))
end

local function SetHidden(Hidden)
	PawnCommon.SetUpgradesHidden = Hidden or nil
	PawnSetUpgradesUpdate()
end

-- The options menu, on right-click.
local function OpenOptionsMenu(Owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		VgerCore.Message(L.Usage)
		return
	end
	GameTooltip:Hide()
	MenuUtil.CreateContextMenu(Owner, function(_, Root)
		Root:CreateTitle(L.Title)
		Root:CreateCheckbox(L.Announce, function() return not PawnCommon.SetUpgradesNoChat end, function() PawnCommon.SetUpgradesNoChat = not PawnCommon.SetUpgradesNoChat or nil end)
		Root:CreateCheckbox(L.Lock, function() return PawnCommon.SetUpgradesLocked end, function() PawnCommon.SetUpgradesLocked = not PawnCommon.SetUpgradesLocked or nil end)
		Root:CreateButton(L.Hide, function() SetHidden(true) VgerCore.Message(L.Hidden) end)
	end)
end

Frame:SetScript("OnMouseUp", function(self, Button)
	if Button == "RightButton" then OpenOptionsMenu(self) end
end)

local Rows = {}
local function GetRow(Index)
	if Rows[Index] then return Rows[Index] end
	local Row = CreateFrame("Button", nil, Frame)
	Row:SetSize(WIDTH - PADDING * 2, ROW_HEIGHT)
	Row:SetPoint("TOPLEFT", TitleText, "BOTTOMLEFT", 0, -4 - (Index - 1) * ROW_HEIGHT)
	Row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	Row:RegisterForDrag("LeftButton")

	local Highlight = Row:CreateTexture(nil, "HIGHLIGHT")
	Highlight:SetAllPoints()
	Highlight:SetColorTexture(1, 1, 1, 0.1)

	Row.Icon = Row:CreateTexture(nil, "ARTWORK")
	Row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
	Row.Icon:SetPoint("LEFT", 2, 0)

	Row.Name = Row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	Row.Name:SetPoint("TOPLEFT", Row.Icon, "TOPRIGHT", 6, -1)
	Row.Name:SetPoint("RIGHT", Row, "RIGHT", -90, 0)
	Row.Name:SetJustifyH("LEFT")
	Row.Name:SetWordWrap(false)

	Row.SetName = Row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	Row.SetName:SetPoint("TOPRIGHT", Row, "TOPRIGHT", -2, -4)
	Row.SetName:SetWidth(86)
	Row.SetName:SetJustifyH("RIGHT")
	Row.SetName:SetWordWrap(false)

	Row.Detail = Row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	Row.Detail:SetPoint("BOTTOMLEFT", Row.Icon, "BOTTOMRIGHT", 6, 1)
	Row.Detail:SetPoint("RIGHT", Row, "RIGHT", -2, 0)
	Row.Detail:SetJustifyH("LEFT")
	Row.Detail:SetWordWrap(false)

	Row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.Upgrade.Link)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.Hint, 0.5, 0.8, 1)
		GameTooltip:Show()
	end)
	Row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Row:SetScript("OnClick", function(self, Button)
		if Button == "RightButton" then
			OpenOptionsMenu(self)
		elseif IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
			ChatEdit_InsertLink(self.Upgrade.Link)
		else
			EquipUpgrade(self.Upgrade)
		end
	end)
	-- Dragging a row moves the window.
	Row:SetScript("OnDragStart", function() Frame:GetScript("OnDragStart")(Frame) end)
	Row:SetScript("OnDragStop", function() Frame:GetScript("OnDragStop")(Frame) end)

	Rows[Index] = Row
	return Row
end

local function Refresh()
	TitleText:SetText(#Upgrades > 0 and format(L.TitleCount, #Upgrades) or L.Title)

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
		Message = L.None
	end
	MessageText:ClearAllPoints()
	local MessageHeight = 0
	if Message then
		MessageText:SetPoint("TOPLEFT", TitleText, "BOTTOMLEFT", 0, -4 - Shown * ROW_HEIGHT)
		MessageText:SetText(Message)
		MessageText:Show()
		MessageHeight = (MessageText:GetStringHeight() or 10) + 4
	else
		MessageText:Hide()
	end
	Frame:SetHeight(PADDING + 12 + 4 + Shown * ROW_HEIGHT + MessageHeight + PADDING)
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

Frame:SetScript("OnDragStart", function(self) if not Locked() then self:StartMoving() end end)
Frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local Point, _, RelativePoint, X, Y = self:GetPoint()
	PawnCommon.SetUpgradesWindow = { Point = Point, RelativePoint = RelativePoint, X = X, Y = Y }
end)

local Ready = false
local PositionRestored = false

-- Rescans and shows the window, unless it's been hidden or no scale compares against an equipment set.
function PawnSetUpgradesUpdate()
	if not Ready then return end
	ScanUpgrades()
	if PawnCommon.SetUpgradesHidden or not AnySetScales then
		Frame:Hide()
		return
	end
	if not PositionRestored then
		RestorePosition()
		PositionRestored = true
	end
	Refresh()
	Frame:Show()
end

local UpdateQueued = false
local function QueueUpdate(Delay)
	if UpdateQueued then return end
	UpdateQueued = true
	C_Timer.After(Delay or 0.3, function()
		UpdateQueued = false
		PawnSetUpgradesUpdate()
	end)
end

-- /pawn upgrades [ lock | unlock | chat | reset ]
function PawnSetUpgradesCommand(Command)
	Command = strlower(strtrim(Command or ""))
	if Command == "" then
		SetHidden(not PawnCommon.SetUpgradesHidden)
		if not PawnCommon.SetUpgradesHidden and not AnySetScales then VgerCore.Message(L.NoSets) end
	elseif Command == "lock" or Command == "unlock" then
		PawnCommon.SetUpgradesLocked = (Command == "lock") or nil
	elseif Command == "chat" then
		PawnCommon.SetUpgradesNoChat = not PawnCommon.SetUpgradesNoChat or nil
		VgerCore.Message(PawnCommon.SetUpgradesNoChat and L.ChatOff or L.ChatOn)
	elseif Command == "reset" then
		PawnCommon.SetUpgradesWindow = nil
		RestorePosition()
	else
		VgerCore.Message(L.Usage)
	end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------

local EventFrame = CreateFrame("Frame")
EventFrame:SetScript("OnEvent", function(self, Event)
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
	pcall(EventFrame.RegisterEvent, EventFrame, Event)
end

-- Pawn refreshes its bag arrows whenever scales or their equipment sets change, so recheck then too.
hooksecurefunc("PawnResetBags", function() QueueUpdate() end)
