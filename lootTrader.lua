--[[ Init ]]--

LootTraderAddon = CreateFrame("Frame")
local LibDataBroker = LibStub("LibDataBroker-1.1");
local LibDBIcon = LibStub("LibDBIcon-1.0")
local SK = LootTraderAddon
SK:SetScript('OnEvent', function(self, event, ...) SK[event](self, ...); end)
SK:RegisterEvent("PLAYER_LOGIN")

--[[ Functions ]]--

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
            if item.assignedName then
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
    local assignedItems, prevSelectedItem = {}, SK.selectedItem

    -- saved assigned items
    for _,item in pairs(SK.items) do
        if item.assignedName then
            assignedItems[SK:invKey(item)] = item
        end
    end

    table.wipe(SK.items)

    SK.selectedItem = nil

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

                        local item = { itemId = itemId, link = link, icon = icon, time = time, itemName = itemName, bag = bag, slot = slot }

                        if assignedItems[SK:invKey(item)] and assignedItems[SK:invKey(item)].itemId == itemId then
                            item.assignedName = assignedItems[SK:invKey(item)].assignedName
                            item.assignedClass = assignedItems[SK:invKey(item)].assignedClass
                        end

                        if prevSelectedItem and prevSelectedItem.slot == slot and prevSelectedItem.bag == bag then
                            SK.selectedItem = item
                        end

                        table.insert(SK.items, item)
                    end
                end
            end
        end
    end

    if SK.selectedItem then
        SetPortraitToTexture(SK.mainFrame.portrait, SK.selectedItem.icon)
        SK.mainFrame.ItemLink:SetText(SK.selectedItem.link)
    else
        SetPortraitToTexture(SK.mainFrame.portrait, "Interface\\QuestFrame\\UI-QuestLog-BookIcon")
        SK.mainFrame.ItemLink:SetText(nil)
    end
end

function SK:SortItems()
    if SK.sortBy == "item" and SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return format("%s%s", i1.itemName, SK:invKey(i1)) > format("%s%s", i2.itemName, SK:invKey(i2)); end)
    elseif SK.sortBy == "item" and not SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return format("%s%s", i1.itemName, SK:invKey(i1)) < format("%s%s", i2.itemName, SK:invKey(i2)); end)
    elseif SK.sortBy == "player" and SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return format("%s%s", i1.assignedName or "", SK:invKey(i1)) > format("%s%s", i2.assignedName or "", SK:invKey(i2)); end)
    elseif SK.sortBy == "player" and not SK.sortReverse then
        table.sort(SK.items, function(i1,i2) return format("%s%s", i1.assignedName or "", SK:invKey(i1)) < format("%s%s", i2.assignedName or "", SK:invKey(i2)); end)
    elseif SK.sortReverse then -- default to time
        table.sort(SK.items, function(i1,i2) return format("%03u%s", i1.time, SK:invKey(i1)) > format("%03u%s", i2.time, SK:invKey(i2)); end)
    else -- default to time
        table.sort(SK.items, function(i1,i2) return format("%03u%s", i1.time, SK:invKey(i1)) < format("%03u%s", i2.time, SK:invKey(i2)); end)
    end
end

--[[ Events ]]--

function SK:PLAYER_LOGIN()
    SK.sortBy = "time"
    SK.sortReverse = false
    SK.visibleLines = 15 -- number of scroll items in XML
    SK.items = {}
    SK.itemHistory = {}
    SK.tradeCanceled = {}
    SK.debug = false
    LootTraderAddonSavedVariables = LootTraderAddonSavedVariables or {}
    SK.accountSettings = LootTraderAddonSavedVariables

    SK.mainFrame = CreateFrame("Frame", "LootTraderMainFrame", UIParent, "MainFrameTemplate")
    SK.dropMenuFrame = CreateFrame("Frame", "LootTraderDropMenuHelper", UIParent, "UIDropDownMenuTemplate")

    SK.scanTooltip = CreateFrame("GameTooltip")
    SK.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    SK.scanTooltip.left, SK.scanTooltip.right = {}, {}
    for i=1,60 do
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
    })

    LibDBIcon:Register("LootTrader", miniButton, SK.accountSettings);

    SK:RegisterEvent("TRADE_SHOW")
    SK:RegisterEvent("TRADE_ACCEPT_UPDATE")
    SK:RegisterEvent("TRADE_REQUEST_CANCEL")
    SK:RegisterEvent("TRADE_CLOSED")
    SK:RegisterEvent("BAG_UPDATE_DELAYED")

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

    local slotIndex = 1

    for _,item in pairs(SK.items) do
        if item.assignedName == SK.tradingPlayer and slotIndex < 7 then
            UseContainerItem(item.bag, item.slot)
            if GetTradePlayerItemLink(slotIndex) then
                slotIndex = slotIndex + 1
            else
                SK:Print("Problem trading item: "..item.link)
            end
        end
    end
end

function SK:TRADE_ACCEPT_UPDATE()
    table.wipe(SK.tradingItems)

    for i=1,6 do
        local link = GetTradePlayerItemLink(i)
        if link then
            local itemId = GetItemInfoInstant(link)

            for _,item in pairs(SK.items) do
                if item.itemId == itemId and item.assignedName == SK.tradingPlayer then
                    table.insert(SK.tradingItems, itemId)
                    break
                end
            end
        end
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
                table.insert(SK.itemHistory, { itemId = itemId, player = tradingPlayer, time = date("%Y-%m-%d %H:%M:%S") })
                SK:Print(select(2,GetItemInfo(itemId)) .. " traded to " .. tradingPlayer)
            end
        end
    end)
end

function SK:BAG_UPDATE_DELAYED()
    SK:ItemList_Reload()
    SK:ItemList_Update(true)
end

--[[ UI Actions / Events ]]--

function SK:MainFrame_Show()
    SK:ItemList_Reload()
    SK:ItemList_Update(true)
end

function SK:MainFrame_Hide()
end

function SK:SortColumn_Click(sortBy)
    if SK.sortBy == sortBy then
        SK.sortReverse = not SK.sortReverse
    else
        SK.sortReverse = false
        SK.sortBy = sortBy
    end
    SK:ItemList_Update(true)
end

function SK:Item_Click(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        SK:AnnounceItem(self.item)
    elseif button == "LeftButton" then
        SK.selectedItem = self.item
        SetPortraitToTexture(SK.mainFrame.portrait, SK.selectedItem.icon)
        SK.mainFrame.ItemLink:SetText(SK.selectedItem.link)
    elseif button == "RightButton" then
        SK:AssignItem(self.item)
    end
    SK:ItemList_Update()
end

function SK:AssignItem_Click(self)
    if not SK.selectedItem then
        return SK:Print("No item selected")
    end

    SK:AssignItem(SK.selectedItem)
end

function SK:AnnounceOne_Click(self)
    if not SK.selectedItem then
        return SK:Print("No item selected")
    end

    SK:AnnounceItem(SK.selectedItem)
end

function SK:AnnounceAll_Click(self)
    if not UnitInRaid("player") then
        return SK:Print("You are not in a raid")
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

function SK:History_Click(self)
    -- build menu
    local menu = {
        { text = "Settings", isTitle = true, notCheckable = true },
        { text = "Whisper winner", keepShownOnClick = true, checked = SK.accountSettings.whisperAssignee, func = function()
            SK.accountSettings.whisperAssignee = not SK.accountSettings.whisperAssignee
        end },
        { text = "Announce winner in raid", keepShownOnClick = true, checked = SK.accountSettings.announceAssignee, func = function()
            SK.accountSettings.announceAssignee = not SK.accountSettings.announceAssignee
        end },
        { text = "Announce disenchant in raid", keepShownOnClick = true, checked = SK.accountSettings.announceDisenchant, func = function()
            SK.accountSettings.announceDisenchant = not SK.accountSettings.announceDisenchant
        end },
        { text = "Actions", isTitle = true, notCheckable = true },
        { text = "List item history", notCheckable = true, func = function()
            for _,h in pairs(SK.itemHistory) do
                SK:Print(select(2, GetItemInfo(h.itemId)) .. " - " .. h.player .. " - " .. h.time)
            end
        end }
    }

    local playersByClass = {}

    -- players in raid
    for i=1,MAX_RAID_MEMBERS do
        local name = UnitName('raid'..i)
        local classEnglish, class = UnitClass('raid'..i);

        if name then
            if not playersByClass[class] then playersByClass[class] = { classEnglish = classEnglish, players = {} }; end
            table.insert(playersByClass[class].players, name)
        end
    end

    local pickedPlayer = function(self, arg)
        SK.disenchanterName = arg.name
        SK.disenchanterClass = arg.class
        CloseDropDownMenus()
    end

    local deMenu = {}
    for class,data in pairs(playersByClass) do
        local subMenu = {}
        for _,name in pairs(data.players) do
            table.insert(subMenu, { text = RAID_CLASS_COLORS[class]:WrapTextInColorCode(name), notCheckable = true, arg1 = { name = name, class = class }, func = pickedPlayer })
        end

        table.insert(deMenu, { text = RAID_CLASS_COLORS[class]:WrapTextInColorCode(data.classEnglish), hasArrow = true, notCheckable = true, keepShownOnClick = true, menuList = subMenu })
    end
    table.insert(deMenu, { text = "|cFFAAAAAAUnassigned|r", notCheckable = true, arg1 = { name = nil, class = nil }, func = pickedPlayer })

    local disenchanter = SK.disenchanterName and RAID_CLASS_COLORS[SK.disenchanterClass]:WrapTextInColorCode(SK.disenchanterName) or "|cFFAAAAAAUnassigned|r"
    table.insert(menu, { text = "Disenchanter: "..disenchanter, hasArrow = true, notCheckable = true, keepShownOnClick = true, menuList = deMenu })
    table.insert(menu, { text = "Cancel", notCheckable = true })

    EasyMenu(menu, SK.dropMenuFrame, "cursor", 2, -2, "MENU");
end

--[[ Helper Functions ]]--

function SK:AssignItem(item)
    if not UnitInRaid("player") then
        return SK:Print("You are not in a raid")
    end

    local playersByClass = {}

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
        { text = "Assign "..item.link.." to", isTitle = true, notCheckable = true }
    }

    local pickedPlayer = function(self, arg)
        item.assignedName = arg.name
        item.assignedClass = arg.class
        CloseDropDownMenus()
        SK:ItemList_Update()

        if SK.accountSettings.announceDisenchant and arg.disenchant then
            SendChatMessage("Disenchanting "..item.link, "RAID")
        end

        if SK.accountSettings.whisperAssignee and not arg.disenchant then
            SendChatMessage("You won "..item.link..", trade me", "WHISPER", nil, item.assignedName)
        end

        if SK.accountSettings.announceAssignee and not arg.disenchant then
            SendChatMessage(arg.name.." won "..item.link..", trade me", "RAID")
        end
    end

    for class,data in pairs(playersByClass) do
        local subMenu = {}
        for _,name in pairs(data.players) do
            table.insert(subMenu, { text = RAID_CLASS_COLORS[class]:WrapTextInColorCode(name), notCheckable = true, arg1 = { name = name, class = class }, func = pickedPlayer })
        end

        table.insert(menu, { text = RAID_CLASS_COLORS[class]:WrapTextInColorCode(data.classEnglish), hasArrow = true, notCheckable = true, keepShownOnClick = true, menuList = subMenu })
    end

    if SK.disenchanterName then
        table.insert(menu, { text = "Disenchant: "..RAID_CLASS_COLORS[SK.disenchanterClass]:WrapTextInColorCode(SK.disenchanterName), notCheckable = true, arg1 = { name = SK.disenchanterName, class = SK.disenchanterClass, disenchant = true }, func = pickedPlayer })
    end

    table.insert(menu, { text = "Cancel", notCheckable = true })

    EasyMenu(menu, SK.dropMenuFrame, "cursor", 2, -2, "MENU");
end

function SK:AnnounceItem(item)
    if not UnitInRaid("player") then
        return SK:Print("You are not in a raid")
    end

    local channel = (UnitIsGroupAssistant("player") or UnitIsGroupLeader("player")) and "RAID_WARNING" or "RAID"
    SendChatMessage(item.link, channel);
end

function SK:ScanToolTipSetBagItem(bag, slot)
    SK.scanTooltip:SetBagItem(bag, slot)
end

function SK:ScanToolTipFindLine(needle, left, right)
    local str

    if SK.debug then
        return "You may trade this item with players that were also eligible to loot this item for the next "..math.random(0,1).." hour "..math.random(1,59).." min."
    end

    for i = 1,SK.scanTooltip:NumLines() do
        if left and SK.scanTooltip.left[i] then
            str = SK.scanTooltip.left[i]:GetText() or ""
            if str:match(needle) then return str; end
        end

        if right and SK.scanTooltip.right[i] then
            str = SK.scanTooltip.right[i]:GetText() or ""
            if str:match(needle) then return str; end
        end
    end
end

function SK:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99LootTrader|r: "..message)
end

function SK:invKey(item)
    return format("%02u%02u", item.bag, item.slot);
end
