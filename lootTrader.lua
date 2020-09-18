--[[ Init ]]--

LootTraderAddon = CreateFrame("Frame")
local LibDataBroker = LibStub("LibDataBroker-1.1");
local LibDBIcon = LibStub("LibDBIcon-1.0")
local SK = LootTraderAddon
SK:SetScript('OnEvent', function(self, event, ...) SK[event](self, ...); end)
SK:RegisterEvent("PLAYER_LOGIN")

--[[ Functions ]]--

function SK:Show()
    SK:ItemList_Update(true)
end

function SK:ItemList_Update(sort)
    if sort then
        SK:SortItems()
    end

    FauxScrollFrame_Update(SK.mainFrame.itemList, #SK.items, SK.visibleLines, 16) -- frame, total lines, visible lines, pixels per line
    local start = FauxScrollFrame_GetOffset(SK.mainFrame.itemList)

    for i=1,SK.visibleLines do
        if i > #SK.items then
            SK.mainFrame.entries[i]:Hide()
        else
            local item = SK.items[start+i]
            SK.mainFrame.entries[i].Col1:SetText(item.link)
            if item.assignedName and item.pickedUp then
                SK.mainFrame.entries[i].Col2:SetText("|cFF90EE90Traded to|r " .. RAID_CLASS_COLORS[item.assignedClass]:WrapTextInColorCode(item.assignedName))
            elseif item.assignedName then
                SK.mainFrame.entries[i].Col2:SetText(RAID_CLASS_COLORS[item.assignedClass]:WrapTextInColorCode(item.assignedName))
            else
                SK.mainFrame.entries[i].Col2:SetText("|cFFAAAAAAUnassigned|r")
            end
            SK.mainFrame.entries[i].Col3:SetText(item.time.."|cFFFFFF00m|r")
            SK.mainFrame.entries[i]:SetChecked(SK.selectedItem == item)
            SK.mainFrame.entries[i].item = item
            SK.mainFrame.entries[i]:Show()
        end
    end
end

function SK:ItemList_Reload()
    table.wipe(SK.items)

    SK.selectedItem = nil
    SetPortraitToTexture(SK.mainFrame.portrait, "Interface\\QuestFrame\\UI-QuestLog-BookIcon")
    SK.mainFrame.ItemLink:SetText(nil)

    for bag = 0, NUM_BAG_SLOTS do
        if GetContainerNumSlots(bag) then
            for slot = 1, GetContainerNumSlots(bag) do
                local icon, _, _, _, _, _, link, _, _, itemId = GetContainerItemInfo(bag, slot)

                if link then
                    SK:ScanToolTipSetBagItem(bag, slot)
                    local line = SK:ScanToolTipFindLine("You may trade this item with players that were also eligible", true, false)

                    if line then
                        local itemName = GetItemInfo(link)
                        local time = string.match(line, ".-(%d+) min") or 0
                        time = time + (string.match(line, ".-(%d+) hour") or 0)*60
                        table.insert(SK.items, { itemId = itemId, link = link, icon = icon, time = time, itemName = itemName })
                    end
                end
            end
        end
    end
end

function SK:SortItems()
    if SK.sortBy == "item" and SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return i1.itemName > i2.itemName; end)
    elseif SK.sortBy == "item" and not SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return i1.itemName < i2.itemName; end)
    elseif SK.sortReverse then -- default to time
        table.sort(SK.items, function(i1,i2) return i1.time > i2.time; end)
    else -- default to time
        table.sort(SK.items, function(i1,i2) return i1.time < i2.time; end)
    end
--[[
    elseif SK.sortBy == "player" and SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return (i1.assignedName or "") > (i2.assignedName or ""); end)
    elseif SK.sortBy == "player" and not SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return (i1.assignedName or "") < (i2.assignedName or ""); end)
]]--
end

--[[ Events ]]--

function SK:PLAYER_LOGIN()
    SK.sortBy = "time"
    SK.sortReverse = false
    SK.visibleLines = 15 -- number of scroll items in XML
    SK.items = {}
    SK.tradeCanceled = {}
    SK.debug = false
    LootTraderAddonSavedVariables = LootTraderAddonSavedVariables or {}

    SK.mainFrame = CreateFrame("Frame", "LootTraderMainFrame", UIParent, "MainFrameTemplate")
    SK.dropMenuFrame = CreateFrame("Frame", "LootTraderDropMenuHelper", UIParent, "UIDropDownMenuTemplate")

    SK.scanTooltip = CreateFrame("GameTooltip")
    SK.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    SK.scanTooltip.left, SK.scanTooltip.right = {}, {}
    for i=1,30 do
        SK.scanTooltip.left[i], SK.scanTooltip.right[i] = SK.scanTooltip:CreateFontString(), SK.scanTooltip:CreateFontString()
        SK.scanTooltip.left[i]:SetFontObject(GameFontNormal)
        SK.scanTooltip.right[i]:SetFontObject(GameFontNormal)
        SK.scanTooltip:AddFontStrings(SK.scanTooltip.left[i], SK.scanTooltip.right[i])
    end

    local miniButton = LibDataBroker:NewDataObject("LootTraderAddon", {
        type = "launcher",
        icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
        OnClick = function(self, event)
            if SK.mainFrame:IsShown() then
                SK.mainFrame:Hide()
            else
                SK.mainFrame:Show()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("LootTrader")
        end
    });

    LibDBIcon:Register("LootTrader", miniButton, LootTraderAddonSavedVariables);

    SK:RegisterEvent("TRADE_SHOW")
    SK:RegisterEvent("TRADE_ACCEPT_UPDATE")
    SK:RegisterEvent("TRADE_REQUEST_CANCEL")
    SK:RegisterEvent("TRADE_CLOSED")

    SLASH_LOOTTRADER1 = "/lt";
    SlashCmdList["LOOTTRADER"] = function(arg)
        if arg == "debug" then
            SK.debug = true
            SK:Print("Debugging enabled. /reload UI to disable")
        end
        SK.mainFrame:Show()
    end
end

function SK:TRADE_SHOW()
    SK.tradeTimer = nil
    SK.tradingPlayer = GetUnitName("NPC")
    SK.tradingItems = {} -- dont wipe
    SK.tradeCanceled[SK.tradingPlayer] = nil

    local slotsAvail = 6

    -- clear trading flag
    for _,item in pairs(SK.items) do item.trading = false;	end

    for bag = 0, NUM_BAG_SLOTS do
        if GetContainerNumSlots(bag) then
            for slot = 0, GetContainerNumSlots(bag) do
                local _, _, _, _, _, _, link, _, _, itemId = GetContainerItemInfo(bag, slot)

                for _,item in pairs(SK.items) do
                    if item.itemId == itemId and item.trading == false and item.assignedName == SK.tradingPlayer and slotsAvail > 0 then
                        SK:ScanToolTipSetBagItem(bag, slot)
                        if SK:ScanToolTipFindLine("You may trade this item with players that were also eligible", true, false) then
                            item.trading = true
                            slotsAvail = slotsAvail - 1
                            UseContainerItem(bag, slot)
                        end
                    end
                end
            end
        end
    end
end

function SK:TRADE_ACCEPT_UPDATE()
    table.wipe(SK.tradingItems)

    for i=1,6 do
        local link = GetTradePlayerItemLink(i)
        local itemId = link and GetItemInfoInstant(link)
        table.insert(SK.tradingItems, itemId)
    end
end

function SK:TRADE_REQUEST_CANCEL()
    SK.tradeCanceled[SK.tradingPlayer] = true
end

-- GG BLIZZZZZARD
function SK:TRADE_CLOSED()
    if SK.tradeTimer then return; end
    SK.tradeTimer = true

    -- bring SK into timer's scope
    -- save reference to current tradingItems and copy tradingPlayer in case another trade happens before timer exectues
    local SK, tradingItems, tradingPlayer = SK, SK.tradingItems, SK.tradingPlayer
    C_Timer.After(2, function()
        if not SK.tradeCanceled[tradingPlayer] then
            for _,itemId in pairs(tradingItems) do
                for _,item in pairs(SK.items) do
                    if item.itemId == itemId and item.assignedName == tradingPlayer then
                        item.pickedUp = true
                        SK:Print(item.link .. " traded to " .. RAID_CLASS_COLORS[item.assignedClass]:WrapTextInColorCode(tradingPlayer))
                        break
                    end
                end
            end
            SK:ItemList_Update()
        end
    end)
end

--[[ UI Actions ]]--

function SK:SortColumn_Click(sortBy)
    if SK.sortBy == sortBy then
        SK.sortReverse = not SK.sortReverse
    else
        SK.sortReverse = false
        SK.sortBy = sortBy
    end
    SK:ItemList_Update(true)
end

function SK:AddMember_Click()
    SK.addUserFrame:Show()
end

function SK:Item_Click(self)
    SK.selectedItem = self.item
    SK:ItemList_Update()

    SetPortraitToTexture(SK.mainFrame.portrait, SK.selectedItem.icon)
    SK.mainFrame.ItemLink:SetText(SK.selectedItem.link)
end

function SK:AssignItem_Click(self)
    local playersByClass = {}

    if not UnitInRaid("player") then
        return SK:Print("You are not in a raid")
    end

    if not SK.selectedItem then
        return SK:Print("No item selected")
    end

    -- players in raid
    for i=1,MAX_RAID_MEMBERS do
        local name = UnitName('raid'..i)
        local classEnglish, class = UnitClass('raid'..i);

        if name then
            if not playersByClass[class] then playersByClass[class] = { classEnglish = classEnglish, players = {} }; end
            table.insert(playersByClass[class].players, name)
        end
    end

    -- build menu
    local menu = {
        { text = "Assign item to player", isTitle = true, notCheckable = true }
    }

    local pickedPlayer = function(self, name, class)
        SK.selectedItem.assignedName = name
        SK.selectedItem.assignedClass = class
        SK.selectedItem.pickedUp = nil
        CloseDropDownMenus()
        SK:ItemList_Update()
    end

    for class,data in pairs(playersByClass) do
        local subMenu = {}
        for _,name in pairs(data.players) do
            table.insert(subMenu, { text = RAID_CLASS_COLORS[class]:WrapTextInColorCode(name), notCheckable = true, arg1 = name, arg2 = class, func = pickedPlayer })
        end

        table.insert(menu, { text = RAID_CLASS_COLORS[class]:WrapTextInColorCode(data.classEnglish), hasArrow = true, notCheckable = true, keepShownOnClick = true, menuList = subMenu })
    end

    table.insert(menu, { text = "Cancel", notCheckable = true })

    EasyMenu(menu, SK.dropMenuFrame, "cursor", 5, -5, "MENU");
end

function SK:AnnounceOne_Click(self)
    if not UnitInRaid("player") then
        return SK:Print("You are not in a raid")
    end

    if not SK.selectedItem then
        return SK:Print("No item selected")
    end

    local channel = (UnitIsGroupAssistant("player") or UnitIsGroupLeader("player")) and "RAID_WARNING" or "RAID"
    SendChatMessage("Now bidding on " .. SK.selectedItem.link, channel);
end

function SK:AnnounceAll_Click(self)
    if not UnitInRaid("player") then
        return SK:Print("You are not in a raid")
    end

    if not SK.selectedItem then
        return SK:Print("No item selected")
    end

    StaticPopupDialogs["LOOTTRADER_ANNOUNCE_CONFIRM"] = {
        text = "Announce " .. #SK.items .. " item(s) to raid chat?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            for _,item in pairs(SK.items) do
                SendChatMessage(item.link, "RAID");
            end
            StaticPopup_Hide("LOOTTRADER_ANNOUNCE_CONFIRM")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopup_Show("LOOTTRADER_ANNOUNCE_CONFIRM")
end

function SK:Reload_Click(self)
    StaticPopupDialogs["LOOTTRADER_RELOAD_CONFIRM"] = {
        text = "Reload items? All assigned items will be cleared!",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            SK:ItemList_Reload()
            SK:ItemList_Update(true)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopup_Show("LOOTTRADER_RELOAD_CONFIRM")
end

--[[ Helper Functions ]]--

function SK:ScanToolTipSetBagItem(bag, slot)
    SK.scanTooltip:SetBagItem(bag, slot)
end

function SK:ScanToolTipFindLine(needle, left, right)
    local str

    if SK.debug then
        return "You may trade this item with players that were also eligible to loot this item for the next "..math.random(0,1).." hour "..math.random(1,59).." min."
    end

    for i = 1,SK.scanTooltip:NumLines() do
        if left then
            str = SK.scanTooltip.left[i]:GetText() or ""
            if str:match(needle) then return str; end
        end

        if right then
            str = SK.scanTooltip.right[i]:GetText() or ""
            if str:match(needle) then return str; end
        end
    end
end

function SK:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99LootTrader|r: "..message)
end
