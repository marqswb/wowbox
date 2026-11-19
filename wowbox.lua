--[[
	WowBox
	WoW Forever. Lists Waylaid Crates and Craftsman's Writs in your bags.
	Clicking one searches its items in Auctionator's shopping tab.
]]

local ADDON = ...

local ROW_WIDTH = 390

local crates = {}
local writs = {}
local rowPool = {}
local headerPool = {}
local scanQueued = false

local frame

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100WowBox|r: " .. msg)
end

local function Secret(value)
	if issecretvalue and issecretvalue(value) then
		return true
	end
	return false
end

local function Trim(text)
	if type(text) ~= "string" then
		return ""
	end
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function EnsureDB()
	if type(WowBoxDB) ~= "table" then
		WowBoxDB = {}
	end
	if WowBoxDB.autoOpen == nil then
		WowBoxDB.autoOpen = true
	end
end

local function NormalizeBullets(text)
	text = text:gsub("|n", "\n")
	text = text:gsub("\226\128\162", "-")
	text = text:gsub("\226\128\147", "-")
	text = text:gsub("\226\128\148", "-")
	text = text:gsub("\194\183", "-")
	text = text:gsub("•", "-")
	text = text:gsub("–", "-")
	text = text:gsub("—", "-")
	text = text:gsub("·", "-")
	text = text:gsub("×", "x")
	return text
end

local function StripMarkup(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
	text = text:gsub("|r", "")
	text = text:gsub("|T.-|t", "")
	text = text:gsub("|A.-|a", "")
	text = text:gsub("|H.-|h", "")
	text = text:gsub("|h", "")
	return text
end

local function AcceptReagent(list, seen, qty, name)
	qty = tonumber(qty)
	name = Trim(name or "")
	name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	name = name:gsub("%s*[Rr]equires.*$", "")
	name = name:gsub("%s*[Uu]se:.*$", "")
	name = Trim(name):gsub("%.$", "")
	if not qty or qty < 1 or qty > 999 then
		return
	end
	if name == "" or #name > 80 or not name:find("%a") then
		return
	end
	local lower = name:lower()
	if lower:find("bundle", 1, true) or lower:find("following list", 1, true) then
		return
	end
	if lower:find("^fill the crate") or lower:find("^requires") or lower:find("^use") then
		return
	end
	if lower:find("^level%s+%d") or seen[lower] then
		return
	end
	seen[lower] = true
	list[#list + 1] = { qty = qty, name = name }
end

local function ParseReagents(lines)
	local list = {}
	local seen = {}
	local blob = NormalizeBullets(StripMarkup(table.concat(lines, "\n")))

	local function FromLine(line)
		local qty, name = line:match("^%s*%-%s*(%d+)%s*x?%s*(.+)$")
		if not qty then
			qty, name = line:match("^%s*(%d+)%s*x%s+(.+)$")
		end
		if not qty then
			qty, name = line:match("^%s*(%d+)%s+([^%d].+)$")
		end
		if qty then
			AcceptReagent(list, seen, qty, name)
		end
	end

	for line in blob:gmatch("[^\n]+") do
		FromLine(line)
	end
	if #list > 0 then
		return list
	end

	-- Tooltip sometimes keeps the whole list on one line.
	for qty, name in blob:gmatch("%-%s*(%d+)%s*x?%s*([^%-]+)") do
		AcceptReagent(list, seen, qty, name)
	end
	return list
end

local function Classify(name)
	local lower = name:lower()
	if lower:find("waylaid crate", 1, true) then
		return "crate"
	end
	if lower:find("craftsman", 1, true) and lower:find("writ", 1, true) then
		return "writ"
	end
	return nil
end

local function WritSearchName(name)
	local item = name:match(":%s*(.+)$")
	item = Trim(item or "")
	if item == "" then
		return nil
	end
	return item
end

local function QualityPrefix(link)
	local hex = type(link) == "string" and link:match("|c(%x%x%x%x%x%x%x%x)")
	if hex then
		return "|c" .. hex
	end
	return "|cffffffff"
end

local function BagList()
	local bags = {}
	local maxBag = NUM_BAG_SLOTS or 4
	for bag = 0, maxBag do
		bags[#bags + 1] = bag
	end
	if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
		local reagentBag = Enum.BagIndex.ReagentBag
		if type(reagentBag) == "number" and reagentBag > maxBag then
			bags[#bags + 1] = reagentBag
		end
	end
	return bags
end

local function SlotCount(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	if GetContainerNumSlots then
		return GetContainerNumSlots(bag) or 0
	end
	return 0
end

local function SlotInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if not info or Secret(info) then
			return nil
		end
		local link = info.hyperlink or info.itemLink
		if Secret(link) then
			link = nil
		end
		local itemName = info.itemName
		if Secret(itemName) then
			itemName = nil
		end
		local icon = info.iconFileID
		if Secret(icon) then
			icon = nil
		end
		local count = info.stackCount
		if Secret(count) or type(count) ~= "number" then
			count = 1
		end
		local itemID = info.itemID
		if Secret(itemID) then
			itemID = nil
		end
		return link, itemName, icon, count, itemID
	end
	if GetContainerItemLink then
		local link = GetContainerItemLink(bag, slot)
		if not link or Secret(link) then
			return nil
		end
		local icon, count = GetContainerItemInfo(bag, slot)
		if type(count) ~= "number" then
			count = 1
		end
		return link, nil, icon, count, nil
	end
	return nil
end

local function NameFrom(link, itemName)
	if type(itemName) == "string" and itemName ~= "" and not Secret(itemName) then
		return itemName
	end
	if type(link) == "string" then
		local name = link:match("%[(.-)%]")
		if name and name ~= "" then
			return name
		end
	end
	return nil
end

local tooltipScanner

local function Scanner()
	if tooltipScanner then
		return tooltipScanner
	end
	tooltipScanner = CreateFrame("GameTooltip", "WowBoxTooltipScanner", nil, "GameTooltipTemplate")
	tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")
	return tooltipScanner
end

local function AddLine(lines, text)
	if type(text) ~= "string" or text == "" or Secret(text) then
		return
	end
	lines[#lines + 1] = text
end

local function TooltipLines(bag, slot, link)
	local lines = {}
	if C_TooltipInfo then
		local info
		if bag and slot and C_TooltipInfo.GetBagItem then
			local ok, result = pcall(C_TooltipInfo.GetBagItem, bag, slot)
			if ok then
				info = result
			end
		end
		if (not info or not info.lines) and link and C_TooltipInfo.GetHyperlink then
			local ok, result = pcall(C_TooltipInfo.GetHyperlink, link)
			if ok then
				info = result
			end
		end
		if info and type(info.lines) == "table" then
			for i = 1, #info.lines do
				local line = info.lines[i]
				if type(line) == "table" then
					AddLine(lines, line.leftText)
					AddLine(lines, line.rightText)
				end
			end
		end
		if #lines > 0 then
			return lines
		end
	end

	local tip = Scanner()
	tip:ClearLines()
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	local shown = false
	if bag and slot and tip.SetBagItem then
		shown = pcall(tip.SetBagItem, tip, bag, slot)
	end
	if not shown and link and tip.SetHyperlink then
		shown = pcall(tip.SetHyperlink, tip, link)
	end
	if shown then
		local count = tip:NumLines() or 0
		for i = 1, count do
			local left = _G["WowBoxTooltipScannerTextLeft" .. i]
			local right = _G["WowBoxTooltipScannerTextRight" .. i]
			if left then
				AddLine(lines, left:GetText())
			end
			if right then
				AddLine(lines, right:GetText())
			end
		end
	end
	tip:Hide()
	return lines
end

local function FreshEntry(kind, name, link, icon, count, itemID)
	return {
		kind = kind,
		name = name,
		link = link,
		icon = icon,
		count = count or 1,
		itemID = itemID,
		bag = nil,
		slot = nil,
		reagents = nil,
		searchName = nil,
		lines = nil,
	}
end

local function ScanBags()
	local found = {}
	for _, bag in ipairs(BagList()) do
		local slots = SlotCount(bag)
		for slot = 1, slots do
			local link, itemName, icon, count, itemID = SlotInfo(bag, slot)
			local name = NameFrom(link, itemName)
			local kind = name and Classify(name)
			if kind then
				local key = itemID or name
				local entry = found[key]
				if not entry then
					entry = FreshEntry(kind, name, link, icon, 0, itemID)
					found[key] = entry
				end
				entry.count = entry.count + (count or 1)
				if not entry.bag then
					entry.bag = bag
					entry.slot = slot
					entry.link = entry.link or link
					entry.icon = entry.icon or icon
				end
			end
		end
	end

	crates = {}
	writs = {}
	for _, entry in pairs(found) do
		entry.lines = TooltipLines(entry.bag, entry.slot, entry.link)
		if entry.kind == "crate" then
			entry.reagents = ParseReagents(entry.lines)
			crates[#crates + 1] = entry
		else
			entry.searchName = WritSearchName(entry.name)
			writs[#writs + 1] = entry
		end
	end

	table.sort(crates, function(a, b) return a.name < b.name end)
	table.sort(writs, function(a, b) return a.name < b.name end)
end

local function TermsFor(entry)
	local terms = {}
	if entry.kind == "writ" then
		if entry.searchName then
			terms[1] = entry.searchName
		end
		return terms
	end
	local seen = {}
	for i = 1, #(entry.reagents or {}) do
		local name = entry.reagents[i].name
		local key = name:lower()
		if not seen[key] then
			seen[key] = true
			terms[#terms + 1] = name
		end
	end
	return terms
end

local function Sanitize(terms)
	local clean = {}
	local seen = {}
	for i = 1, #terms do
		local term = terms[i]
		if type(term) == "string" and not Secret(term) then
			term = term:gsub('"', ""):gsub(";", " ")
			term = Trim(term)
			local key = term:lower()
			if term ~= "" and not seen[key] then
				seen[key] = true
				clean[#clean + 1] = term
			end
		end
	end
	return clean
end

local function AuctionHouseOpen()
	if AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() then
		return "modern"
	end
	if AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() then
		return "classic"
	end
	return nil
end

local function SearchTerms(terms, label)
	terms = Sanitize(terms)
	if #terms == 0 then
		Print("Nothing to search" .. (label and (" for " .. label) or "") .. ".")
		return
	end

	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	local exact = api and api.MultiSearchExact
	local loose = api and api.MultiSearch
	local house = AuctionHouseOpen()

	if (exact or loose) and house == "modern" then
		local fn = exact or loose
		local ok, err = pcall(fn, ADDON, terms)
		if ok then
			Print("Shopping list: " .. table.concat(terms, ", "))
		else
			Print("Auctionator refused the search. " .. tostring(err))
		end
		return
	end

	if type(Atr_SearchAH) == "function" and house then
		local ok, err = pcall(Atr_SearchAH, "WowBox", terms)
		if ok then
			Print("Shopping list: " .. table.concat(terms, ", "))
		else
			Print("Auctionator refused the search. " .. tostring(err))
		end
		return
	end

	if not api and type(Atr_SearchAH) ~= "function" then
		Print("Auctionator is not loaded. Enable it, then click again.")
		return
	end
	Print("Open the auction house first, then click the row again.")
end

local function SearchEntry(entry)
	if not entry then
		return
	end
	local terms = TermsFor(entry)
	if entry.kind == "crate" and #terms == 0 then
		Print("Could not read what goes in " .. entry.name .. ". Hover it in your bags, then /wowbox debug.")
		return
	end
	SearchTerms(terms, entry.name)
end

local function HidePool(pool)
	for i = 1, #pool do
		pool[i]:Hide()
	end
end

local function TakeHeader(index)
	local header = headerPool[index]
	if header then
		return header
	end
	header = frame.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetJustifyH("LEFT")
	headerPool[index] = header
	return header
end

local function TakeRow(index)
	local row = rowPool[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, frame.content)
	row:RegisterForClicks("LeftButtonUp")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(28, 28)
	row.icon:SetPoint("TOPLEFT", 4, -4)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", 38, -4)
	row.name:SetPoint("RIGHT", row, "RIGHT", -36, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.count:SetPoint("TOPRIGHT", -6, -4)
	row.count:SetJustifyH("RIGHT")

	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.detail:SetPoint("TOPLEFT", 38, -20)
	row.detail:SetWidth(ROW_WIDTH - 48)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetJustifyV("TOP")
	if row.detail.SetSpacing then
		row.detail:SetSpacing(2)
	end

	row:SetScript("OnMouseWheel", function(_, delta)
		local scroll = frame.scroll
		if not scroll then
			return
		end
		local current = scroll:GetVerticalScroll()
		local maxScroll = scroll:GetVerticalScrollRange() or 0
		scroll:SetVerticalScroll(math.min(maxScroll, math.max(0, current - delta * 36)))
	end)

	row:SetScript("OnClick", function(self)
		SearchEntry(self.entry)
	end)
	row:SetScript("OnEnter", function(self)
		if not self.link then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
		if ok then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Click to search these in Auctionator.", 1, 0.82, 0)
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	rowPool[index] = row
	return row
end

local function DetailText(entry)
	if entry.kind == "writ" then
		if entry.searchName then
			return "Search  |cffffffff" .. entry.searchName .. "|r"
		end
		return "|cffff8080Could not read the writ item.|r"
	end
	local reagents = entry.reagents or {}
	if #reagents == 0 then
		return "|cffff8080Could not read the crate list. /wowbox debug|r"
	end
	local lines = {}
	for i = 1, #reagents do
		local reagent = reagents[i]
		lines[i] = string.format("|cffffffff%d|r  %s", reagent.qty, reagent.name)
	end
	return table.concat(lines, "\n")
end

local function PlaceHeader(index, text, y)
	local header = TakeHeader(index)
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, y)
	header:SetText(text)
	header:Show()
	return y - 20
end

local function PlaceRow(index, entry, y)
	local row = TakeRow(index)
	row.entry = entry
	row.link = entry.link
	row:SetSize(ROW_WIDTH, 40)
	row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	row.name:SetText(QualityPrefix(entry.link) .. entry.name .. "|r")
	row.count:SetText(entry.count > 1 and ("x" .. entry.count) or "")
	local detail = DetailText(entry)
	row.detail:SetText(detail)
	local reagentCount = 1
	for _ in detail:gmatch("\n") do
		reagentCount = reagentCount + 1
	end
	local height = math.max(40, 24 + reagentCount * 14)
	row:SetHeight(height)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
	row:Show()
	return y - height - 4
end

local function Render()
	if not frame then
		return
	end
	HidePool(rowPool)
	HidePool(headerPool)

	local y = -4
	local headerIndex = 0
	local rowIndex = 0

	local function Section(title, entries)
		headerIndex = headerIndex + 1
		y = PlaceHeader(headerIndex, title, y)
		if #entries == 0 then
			headerIndex = headerIndex + 1
			y = PlaceHeader(headerIndex, "|cffb0a890None in your bags.|r", y)
			return
		end
		for i = 1, #entries do
			rowIndex = rowIndex + 1
			y = PlaceRow(rowIndex, entries[i], y)
		end
		y = y - 8
	end

	Section("Waylaid Crates", crates)
	Section("Craftsman's Writs", writs)

	frame.content:SetSize(ROW_WIDTH, math.max(1, -y))
	local total = #crates + #writs
	frame.status:SetText(total == 0 and "Nothing in your bags." or (total .. " in your bags."))
end

local function Refresh()
	ScanBags()
	Render()
end

local function QueueScan()
	if scanQueued or not frame or not frame:IsShown() then
		return
	end
	scanQueued = true
	local function run()
		scanQueued = false
		if frame:IsShown() then
			Refresh()
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.2, run)
	else
		run()
	end
end

local function SavePosition()
	EnsureDB()
	local point, _, relative, x, y = frame:GetPoint(1)
	WowBoxDB.point = { point, relative, x, y }
end

local function RestorePosition()
	EnsureDB()
	frame:ClearAllPoints()
	local point = WowBoxDB.point
	if type(point) == "table" and type(point[1]) == "string" and type(point[3]) == "number" and type(point[4]) == "number" then
		frame:SetPoint(point[1], UIParent, point[2] or point[1], point[3], point[4])
	else
		frame:SetPoint("CENTER")
	end
end

local function BuildFrame()
	if frame then
		return
	end
	local created
	created, frame = pcall(CreateFrame, "Frame", "WowBoxFrame", UIParent, "BackdropTemplate")
	if not created then
		frame = CreateFrame("Frame", "WowBoxFrame", UIParent)
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.04, 0.03, 0.02, 0.94)
	else
		local backdropOk = pcall(frame.SetBackdrop, frame, {
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		if not backdropOk then
			local bg = frame:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			if bg.SetColorTexture then
				bg:SetColorTexture(0.04, 0.03, 0.02, 0.94)
			end
		end
	end

	frame:SetSize(440, 520)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:Hide()

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("WowBox")

	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 16, -38)
	hint:SetPoint("TOPRIGHT", -16, -38)
	hint:SetJustifyH("LEFT")
	hint:SetText("Click a crate to shop every fill option. Click a writ to shop the item it asks for.")

	local scroll = CreateFrame("ScrollFrame", "WowBoxScrollFrame", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -78)
	scroll:SetPoint("BOTTOMRIGHT", -32, 40)
	frame.scroll = scroll

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_WIDTH, 1)
	scroll:SetScrollChild(content)
	frame.content = content

	local function OnWheel(_, delta)
		local current = scroll:GetVerticalScroll()
		local maxScroll = scroll:GetVerticalScrollRange() or 0
		local nextScroll = math.min(maxScroll, math.max(0, current - delta * 36))
		scroll:SetVerticalScroll(nextScroll)
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", OnWheel)
	content:EnableMouseWheel(true)
	content:SetScript("OnMouseWheel", OnWheel)

	local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	refresh:SetSize(90, 22)
	refresh:SetPoint("BOTTOMLEFT", 14, 12)
	refresh:SetText("Refresh")
	refresh:SetScript("OnClick", Refresh)

	local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("LEFT", refresh, "RIGHT", 10, 0)
	status:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
	status:SetJustifyH("RIGHT")
	frame.status = status

	frame:SetScript("OnShow", function()
		RestorePosition()
		Refresh()
	end)

	RestorePosition()
end

local function ShowFrame()
	if not frame then
		BuildFrame()
	end
	frame:Show()
end

local function Toggle()
	if not frame then
		BuildFrame()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end

local function Debug()
	ScanBags()
	local entry = crates[1] or writs[1]
	if not entry then
		Print("No Waylaid Crate or Craftsman's Writ in your bags.")
		return
	end
	Print(entry.name .. " tooltip:")
	local lines = entry.lines or {}
	if #lines == 0 then
		Print("  (no tooltip lines)")
	end
	for i = 1, #lines do
		Print("  " .. i .. ": " .. lines[i])
	end
	if entry.kind == "crate" then
		local reagents = entry.reagents or {}
		if #reagents == 0 then
			Print("Parsed no reagents.")
		end
		for i = 1, #reagents do
			Print(string.format("  reagent %d x %s", reagents[i].qty, reagents[i].name))
		end
	else
		Print("Writ search: " .. tostring(entry.searchName))
	end
end

local function Command(msg)
	EnsureDB()
	msg = Trim(msg or ""):lower()
	if msg == "debug" then
		Debug()
	elseif msg == "auto" then
		WowBoxDB.autoOpen = not WowBoxDB.autoOpen
		Print(WowBoxDB.autoOpen and "Will open when you visit the auction house." or "Will not open with the auction house. Use /wowbox.")
	elseif msg == "refresh" then
		ShowFrame()
		Refresh()
	else
		Toggle()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		EnsureDB()
		BuildFrame()
	elseif event == "BAG_UPDATE" then
		QueueScan()
	elseif event == "AUCTION_HOUSE_SHOW" then
		EnsureDB()
		if WowBoxDB.autoOpen then
			ShowFrame()
		elseif frame and frame:IsShown() then
			Refresh()
		end
	end
end)

SLASH_WOWBOX1 = "/wowbox"
SLASH_WOWBOX2 = "/wb"
SlashCmdList.WOWBOX = Command
