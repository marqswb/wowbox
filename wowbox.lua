--[[
	WowBox
	WoW Forever. Lists Waylaid Crates and Craftsman's Writs in your bags.
	Clicking one searches its items in Auctionator's shopping tab.
]]

local ADDON = ...

local ROW_WIDTH = 510

local crates = {}
local writs = {}
local rowPool = {}
local headerPool = {}
local view = "crates"
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
	if WowBoxDB.tab ~= "writs" and WowBoxDB.tab ~= "crates" then
		WowBoxDB.tab = "crates"
	end
	if WowBoxDB.sort ~= "price" then
		WowBoxDB.sort = "default"
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
	local counts = {}
	local icons = {}
	local links = {}
	local names = {}
	for _, bag in ipairs(BagList()) do
		local slots = SlotCount(bag)
		for slot = 1, slots do
			local link, itemName, icon, count, itemID = SlotInfo(bag, slot)
			local name = NameFrom(link, itemName)
			local kind = name and Classify(name)
			if kind then
				local key = name:lower()
				counts[key] = (counts[key] or 0) + (count or 1)
				names[key] = name
				if icon and not icons[key] then
					icons[key] = icon
				end
				if link and not links[key] then
					links[key] = link
				end
			end
		end
	end
	return counts, icons, links, names
end

local function SortEntries(list)
	table.sort(list, function(a, b)
		local aOwned = (a.count or 0) > 0
		local bOwned = (b.count or 0) > 0
		if aOwned ~= bOwned then
			return aOwned
		end
		return a.name < b.name
	end)
end

local function MakeEntry(kind, name, count, icon, link)
	return {
		kind = kind,
		name = name,
		count = count or 0,
		icon = icon,
		link = link,
		reagents = nil,
		searchName = nil,
	}
end

local function BuildEntries()
	local counts, icons, links, names = ScanBags()
	local seen = {}
	crates = {}
	writs = {}

	local data = WowBoxData
	if type(data) == "table" and type(data.crates) == "table" then
		for i = 1, #data.crates do
			local row = data.crates[i]
			local name = row[1]
			local key = name:lower()
			seen[key] = true
			local entry = MakeEntry("crate", name, counts[key], icons[key], links[key])
			entry.reagents = {}
			local bundles = row[2] or {}
			for j = 1, #bundles do
				entry.reagents[j] = { qty = bundles[j][1], name = bundles[j][2] }
			end
			crates[#crates + 1] = entry
		end
	end

	if type(data) == "table" and type(data.writs) == "table" then
		for i = 1, #data.writs do
			local item = data.writs[i]
			local rank
			if type(item) == "table" then
				rank = item[2]
				item = item[1]
			end
			local name = "Craftsman's Writ: " .. item
			local key = name:lower()
			seen[key] = true
			local entry = MakeEntry("writ", name, counts[key], icons[key], links[key])
			entry.searchName = item
			entry.rank = rank
			writs[#writs + 1] = entry
		end
	end

	for key, count in pairs(counts) do
		if not seen[key] then
			local name = names[key]
			local kind = Classify(name)
			if kind == "crate" then
				local entry = MakeEntry("crate", name, count, icons[key], links[key])
				entry.reagents = {}
				crates[#crates + 1] = entry
			elseif kind == "writ" then
				local entry = MakeEntry("writ", name, count, icons[key], links[key])
				entry.searchName = WritSearchName(name)
				writs[#writs + 1] = entry
			end
		end
	end

	LoadSavedPrices()
	ApplySort()
end

local function TermsFor(entry)
	local terms = {}
	local seen = {}
	local function add(name)
		if type(name) ~= "string" or Secret(name) then
			return
		end
		name = Trim(name)
		local key = name:lower()
		if key ~= "" and not seen[key] then
			seen[key] = true
			terms[#terms + 1] = name
		end
	end
	add(entry.name)
	if entry.kind == "writ" then
		add(entry.searchName)
		return terms
	end
	for i = 1, #(entry.reagents or {}) do
		add(entry.reagents[i].name)
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

local Render
local prices = {}
local pendingTerms = {}
local termNames = {}
local lastResults
local searchGen = 0
local priceListener

local function Money(copper)
	copper = math.floor(copper or 0)
	if copper <= 0 then
		return "|cff9a9080none|r"
	end
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local copperLeft = copper % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = gold .. "g"
	end
	if silver > 0 or gold > 0 then
		parts[#parts + 1] = silver .. "s"
	end
	parts[#parts + 1] = copperLeft .. "c"
	return table.concat(parts, " ")
end

local function CleanName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	name = Trim(name)
	if name == "" then
		return nil
	end
	return name
end

local function NameFromItemKey(itemKey)
	if type(itemKey) ~= "table" then
		return nil
	end
	if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
		local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey)
		if ok and type(info) == "table" then
			local name = CleanName(info.itemName)
			if name then
				return name
			end
		end
	end
	local itemID = itemKey.itemID or itemKey.itemId
	if itemID and C_Item and C_Item.GetItemNameByID then
		local ok, name = pcall(C_Item.GetItemNameByID, itemID)
		if ok then
			name = CleanName(name)
			if name then
				return name
			end
		end
	end
	if itemID and GetItemInfo then
		local name = CleanName(GetItemInfo(itemID))
		if name then
			return name
		end
	end
	return nil
end

local function NameFromResult(row)
	local name = CleanName(row.name) or CleanName(row.itemName)
	if name then
		return name
	end
	if type(row.itemLink) == "string" then
		name = CleanName(row.itemLink:match("%[(.-)%]"))
		if name then
			return name
		end
	end
	return NameFromItemKey(row.itemKey)
end

local function Ingest(results)
	if type(results) ~= "table" then
		return
	end
	local changed = false
	local function take(row)
		if type(row) ~= "table" then
			return
		end
		local price = row.minPrice
		if type(price) ~= "number" then
			price = row.price or row.buyoutPrice
		end
		if type(price) ~= "number" then
			return
		end
		if type(row.stackSize) == "number" and row.stackSize > 1 and row.buyoutPrice == price then
			price = math.floor(price / row.stackSize)
		end
		local name = NameFromResult(row)
		if not name or type(price) ~= "number" or price <= 0 then
			return
		end
		local key = name:lower()
		local prev = prices[key]
		if prev == nil or prev == false or price < prev then
			prices[key] = price
			pendingTerms[key] = nil
			changed = true
		end
	end
	if results[0] ~= nil then
		take(results[0])
	end
	for i = 1, #results do
		take(results[i])
	end
	if changed and frame and frame:IsShown() then
		Render()
	end
end

local function DatabasePrice(name)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	local db = Auctionator and Auctionator.Database
	if (not api and not db) or type(name) ~= "string" then
		return nil
	end
	local ids = WowBoxData and WowBoxData.ids
	local itemID = ids and ids[name:lower()]
	local link
	if not itemID and GetItemInfo then
		link = select(2, GetItemInfo(name))
		itemID = link and tonumber(link:match("item:(%d+)"))
	end
	if not itemID and C_Item and C_Item.GetItemInfo then
		local info = C_Item.GetItemInfo(name)
		if type(info) == "table" then
			link = info.itemLink or info.hyperlink
			itemID = info.itemID or (link and tonumber(link:match("item:(%d+)")))
		end
	end
	if itemID and db and db.GetPrice then
		local ok, price = pcall(db.GetPrice, db, tostring(itemID))
		if ok and type(price) == "number" and price > 0 then
			return price
		end
	end
	if itemID and api and api.GetAuctionPriceByItemID then
		local ok, price = pcall(api.GetAuctionPriceByItemID, "WowBox", itemID)
		if ok and type(price) == "number" and price > 0 then
			return price
		end
	end
	if link and api and api.GetAuctionPriceByItemLink then
		local ok, price = pcall(api.GetAuctionPriceByItemLink, "WowBox", link)
		if ok and type(price) == "number" and price > 0 then
			return price
		end
	end
	return nil
end

function LoadSavedPrices()
	local data = WowBoxData
	if type(data) ~= "table" then
		return
	end
	local function note(name)
		if type(name) ~= "string" then
			return
		end
		local key = name:lower()
		if type(prices[key]) == "number" and prices[key] > 0 then
			return
		end
		local price = DatabasePrice(name)
		if price then
			prices[key] = price
		end
	end
	local cratesData = data.crates or {}
	for i = 1, #cratesData do
		note(cratesData[i][1])
		local bundles = cratesData[i][2] or {}
		for j = 1, #bundles do
			note(bundles[j][2])
		end
	end
	local writsData = data.writs or {}
	for i = 1, #writsData do
		local item = writsData[i]
		if type(item) == "table" then
			item = item[1]
		end
		note(item)
		note("Craftsman's Writ: " .. item)
	end
end

function ApplySort()
	EnsureDB()
	local mode = WowBoxDB.sort
	local function unitPrice(name)
		if type(name) ~= "string" then
			return nil
		end
		local cached = prices[name:lower()]
		if type(cached) == "number" and cached > 0 then
			return cached
		end
		local db = DatabasePrice(name)
		if db then
			prices[name:lower()] = db
		end
		return db
	end
	local function cost(entry)
		local best
		if entry.kind == "writ" then
			best = unitPrice(entry.searchName)
		else
			local reagents = entry.reagents or {}
			for i = 1, #reagents do
				local unit = unitPrice(reagents[i].name)
				if unit then
					local total = unit * (reagents[i].qty or 1)
					if not best or total < best then
						best = total
					end
				end
			end
		end
		local own = unitPrice(entry.name)
		if best and own then
			return best + own
		end
		return best or own
	end
	local function cmp(a, b)
		if mode == "price" then
			local aPrice = cost(a)
			local bPrice = cost(b)
			if aPrice and bPrice and aPrice ~= bPrice then
				return aPrice < bPrice
			end
			if aPrice and not bPrice then
				return true
			end
			if bPrice and not aPrice then
				return false
			end
		else
			local aOwned = (a.count or 0) > 0
			local bOwned = (b.count or 0) > 0
			if aOwned ~= bOwned then
				return aOwned
			end
		end
		return a.name < b.name
	end
	table.sort(crates, cmp)
	table.sort(writs, cmp)
end

local function ShoppingRows()
	local list = _G.AuctionatorShoppingListFrame
	if not list and AuctionHouseFrame then
		list = AuctionHouseFrame.AuctionatorShoppingListFrame
	end
	local provider = list and (list.DataProvider or (list.ResultsListing and list.ResultsListing.dataProvider))
	if not provider and EnumerateFrames then
		local current = EnumerateFrames()
		while current do
			if current.ResultsListing and current.DataProvider and current.DataProvider.results then
				provider = current.DataProvider
				break
			end
			current = EnumerateFrames(current)
		end
	end
	if provider and type(provider.results) == "table" then
		return provider.results
	end
	return nil
end

local function RefreshPrices()
	local rows = ShoppingRows()
	if rows then
		pcall(Ingest, rows)
	elseif lastResults then
		pcall(Ingest, lastResults)
	end
	local changed = false
	for key, name in pairs(termNames) do
		if prices[key] == nil then
			local price = DatabasePrice(name)
			if price then
				prices[key] = price
				pendingTerms[key] = nil
				changed = true
			end
		end
	end
	if changed and frame and frame:IsShown() then
		Render()
	end
end

local function EnsurePriceListener()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.RegisterForDBUpdate and not dbHooked then
		local ok = pcall(api.RegisterForDBUpdate, "WowBox", function()
			LoadSavedPrices()
			if frame and frame:IsShown() then
				ApplySort()
				Render()
			end
		end)
		if ok then
			dbHooked = true
		end
	end
	if priceListener then
		return
	end
	local bus = Auctionator and Auctionator.EventBus
	local events = Auctionator and Auctionator.ShoppingLists and Auctionator.ShoppingLists.Events
	if not bus or not events or not events.ListSearchEnded then
		return
	end
	local listener = {}
	function listener:ReceiveEvent(eventName, results)
		if eventName ~= events.ListSearchEnded and eventName ~= events.ListSearchIncrementalUpdate then
			return
		end
		lastResults = results
		pcall(RefreshPrices)
	end
	local ok = pcall(bus.Register, bus, listener, {
		events.ListSearchEnded,
		events.ListSearchIncrementalUpdate,
	})
	if ok then
		priceListener = listener
	end
end

local function FinishPrices(gen)
	if gen ~= searchGen then
		return
	end
	pcall(RefreshPrices)
	local leftover = {}
	for key in pairs(pendingTerms) do
		leftover[#leftover + 1] = key
	end
	local changed = false
	for i = 1, #leftover do
		if prices[leftover[i]] == nil then
			prices[leftover[i]] = false
			changed = true
		end
	end
	pendingTerms = {}
	if changed and frame and frame:IsShown() then
		Render()
	end
end

local function BeginPriceSearch(terms)
	searchGen = searchGen + 1
	local gen = searchGen
	pendingTerms = {}
	termNames = {}
	lastResults = nil
	for i = 1, #terms do
		local key = terms[i]:lower()
		pendingTerms[key] = true
		termNames[key] = terms[i]
		prices[key] = nil
	end
	EnsurePriceListener()
	pcall(RefreshPrices)
	if frame and frame:IsShown() then
		Render()
	end
	if not C_Timer or not C_Timer.After then
		return
	end
	local function later(delay, finish)
		C_Timer.After(delay, function()
			if gen ~= searchGen then
				return
			end
			if finish then
				FinishPrices(gen)
			else
				pcall(RefreshPrices)
			end
		end)
	end
	later(0.4, false)
	later(1.2, false)
	later(2.5, false)
	later(4.5, false)
	later(6, true)
end

local function LineTotal(name, qty)
	if type(name) ~= "string" then
		return nil
	end
	local value = prices[name:lower()]
	if type(value) == "number" and value > 0 then
		return value * (qty or 1)
	end
	return nil
end

local function CheapestTotal(entry)
	local best
	if entry.kind == "writ" then
		best = LineTotal(entry.searchName, 1)
	else
		local reagents = entry.reagents or {}
		for i = 1, #reagents do
			local total = LineTotal(reagents[i].name, reagents[i].qty)
			if total and (not best or total < best) then
				best = total
			end
		end
	end
	local own = LineTotal(entry.name, 1)
	if best and own then
		return best + own
	end
	return best or own
end

local function PriceSuffix(name, qty)
	if type(name) ~= "string" then
		return ""
	end
	local key = name:lower()
	local value = prices[key]
	if value == nil then
		if pendingTerms[key] then
			return "   |cff9a9080...|r"
		end
		return ""
	end
	if value == false then
		return "   |cff9a9080none|r"
	end
	return "   " .. Money(value * (qty or 1))
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
			BeginPriceSearch(terms)
			Print("Shopping list: " .. table.concat(terms, ", "))
		else
			Print("Auctionator refused the search. " .. tostring(err))
		end
		return
	end

	if type(Atr_SearchAH) == "function" and house then
		local ok, err = pcall(Atr_SearchAH, "WowBox", terms)
		if ok then
			BeginPriceSearch(terms)
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
	row.detail:SetWordWrap(true)
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
			local writPrice = PriceSuffix(entry.name, 1)
			local text = string.format("|cffffffff1|r  %s%s", entry.searchName, PriceSuffix(entry.searchName, 1))
			if writPrice ~= "" then
				text = text .. "\nWrit" .. writPrice
			end
			local cheapest = CheapestTotal(entry)
			if cheapest then
				text = text .. "\n|cffffd100Total|r  " .. Money(cheapest)
			end
			return text
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
		lines[i] = string.format("|cffffffff%d|r  %s%s", reagent.qty, reagent.name, PriceSuffix(reagent.name, reagent.qty))
	end
	local cratePrice = PriceSuffix(entry.name, 1)
	if cratePrice ~= "" then
		lines[#lines + 1] = "Crate" .. cratePrice
	end
	local cheapest = CheapestTotal(entry)
	if cheapest then
		lines[#lines + 1] = "|cffffd100Total|r  " .. Money(cheapest)
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
	row.name:SetText(QualityPrefix(entry.link) .. entry.name .. "|r" .. (entry.rank and (" |cffc9b27c(" .. entry.rank .. ")|r") or ""))
	local owned = (entry.count or 0) > 0
	if owned then
		row.count:SetText("|cffffffffx" .. entry.count .. "|r")
		row.name:SetAlpha(1)
		row.detail:SetAlpha(1)
		row.icon:SetAlpha(1)
	else
		row.count:SetText("|cff8a8172x0|r")
		row.name:SetAlpha(0.72)
		row.detail:SetAlpha(0.72)
		row.icon:SetAlpha(0.45)
	end
	local detail = DetailText(entry)
	if row.detail.SetWordWrap then
		row.detail:SetWordWrap(true)
	end
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

function Render()
	if not frame then
		return
	end
	HidePool(rowPool)
	HidePool(headerPool)

	local y = -4
	local headerIndex = 0
	local rowIndex = 0
	local entries = view == "writs" and writs or crates

	if #entries == 0 then
		headerIndex = headerIndex + 1
		y = PlaceHeader(headerIndex, "|cffb0a890None listed.|r", y)
	else
		for i = 1, #entries do
			rowIndex = rowIndex + 1
			y = PlaceRow(rowIndex, entries[i], y)
		end
	end

	frame.content:SetSize(ROW_WIDTH, math.max(1, -y))
	local owned = 0
	for i = 1, #entries do
		if entries[i].count > 0 then
			owned = owned + 1
		end
	end
	frame.status:SetText(owned .. " in your bags. " .. #entries .. " total.")
end

local function ShowTab(which)
	if which ~= "writs" then
		which = "crates"
	end
	view = which
	EnsureDB()
	WowBoxDB.tab = which
	if frame and frame.cratesButton then
		if which == "crates" then
			frame.cratesButton:LockHighlight()
			frame.writsButton:UnlockHighlight()
		else
			frame.writsButton:LockHighlight()
			frame.cratesButton:UnlockHighlight()
		end
	end
	if frame and frame.scroll then
		frame.scroll:SetVerticalScroll(0)
	end
	if frame and frame:IsShown() then
		Render()
	end
end

local function Refresh()
	BuildEntries()
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
		bg:SetColorTexture(0.07, 0.06, 0.05, 1)
	else
		local backdropOk = pcall(frame.SetBackdrop, frame, {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = false,
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		if backdropOk and frame.SetBackdropColor then
			frame:SetBackdropColor(0.07, 0.06, 0.05, 1)
			if frame.SetBackdropBorderColor then
				frame:SetBackdropBorderColor(0.85, 0.7, 0.35, 1)
			end
		end
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetPoint("TOPLEFT", 8, -8)
		bg:SetPoint("BOTTOMRIGHT", -8, 8)
		bg:SetColorTexture(0.07, 0.06, 0.05, 1)
	end

	frame:SetSize(560, 560)
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

	local cratesButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	cratesButton:SetSize(120, 22)
	cratesButton:SetPoint("TOPLEFT", 16, -38)
	cratesButton:SetText("Crates")
	cratesButton:SetScript("OnClick", function()
		ShowTab("crates")
	end)
	frame.cratesButton = cratesButton

	local writsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	writsButton:SetSize(120, 22)
	writsButton:SetPoint("LEFT", cratesButton, "RIGHT", 8, 0)
	writsButton:SetText("Writs")
	writsButton:SetScript("OnClick", function()
		ShowTab("writs")
	end)
	frame.writsButton = writsButton

	local function ShowSort(mode)
		if mode ~= "price" then
			mode = "default"
		end
		EnsureDB()
		WowBoxDB.sort = mode
		if mode == "price" then
			frame.priceButton:LockHighlight()
			frame.defaultButton:UnlockHighlight()
		else
			frame.defaultButton:LockHighlight()
			frame.priceButton:UnlockHighlight()
		end
		ApplySort()
		if frame.scroll then
			frame.scroll:SetVerticalScroll(0)
		end
		if frame:IsShown() then
			Render()
		end
	end

	local priceButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	priceButton:SetSize(80, 22)
	priceButton:SetPoint("TOPRIGHT", -36, -38)
	priceButton:SetText("Price")
	priceButton:SetScript("OnClick", function()
		ShowSort("price")
	end)
	frame.priceButton = priceButton

	local defaultButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	defaultButton:SetSize(80, 22)
	defaultButton:SetPoint("RIGHT", priceButton, "LEFT", -8, 0)
	defaultButton:SetText("Default")
	defaultButton:SetScript("OnClick", function()
		ShowSort("default")
	end)
	frame.defaultButton = defaultButton
	ShowSort(WowBoxDB.sort)

	local scroll = CreateFrame("ScrollFrame", "WowBoxScrollFrame", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -68)
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
		EnsureDB()
		ShowTab(WowBoxDB.tab)
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
	BuildEntries()
	local entry = crates[1] or writs[1]
	if not entry then
		Print("The crate and writ catalog is empty.")
		return
	end
	local owned = 0
	for i = 1, #crates do
		if crates[i].count > 0 then
			owned = owned + 1
		end
	end
	for i = 1, #writs do
		if writs[i].count > 0 then
			owned = owned + 1
		end
	end
	Print(string.format("%d crates, %d writs, %d of them in your bags.", #crates, #writs, owned))
	Print(entry.name .. " x" .. entry.count)
	local terms = TermsFor(entry)
	Print("Search: " .. table.concat(terms, ", "))
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
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		EnsureDB()
		BuildFrame()
		ShowTab(WowBoxDB.tab)
		EnsurePriceListener()
	elseif event == "ADDON_LOADED" and arg1 == "Auctionator" then
		EnsurePriceListener()
		LoadSavedPrices()
		if frame and frame:IsShown() then
			Refresh()
		end
	elseif event == "BAG_UPDATE" then
		QueueScan()
	elseif event == "AUCTION_HOUSE_SHOW" then
		EnsureDB()
		if WowBoxDB.autoOpen then
			ShowFrame()
		elseif frame and frame:IsShown() then
			Refresh()
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if frame then
			frame:Hide()
		end
	end
end)

SLASH_WOWBOX1 = "/wowbox"
SLASH_WOWBOX2 = "/wb"
SlashCmdList.WOWBOX = Command
