local addonName = ...

WowBoxDB = WowBoxDB or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		WowBoxDB = WowBoxDB or {}
	end
end)

SLASH_WOWBOX1 = "/wowbox"
SLASH_WOWBOX2 = "/wb"
SlashCmdList.WOWBOX = function()
	print("|cffc9a227WowBox|r loaded.")
end
