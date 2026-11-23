local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Market = ns.Market
local Catalog = ns.Catalog
local SidePanel = ns.SidePanel

local AuctionPanel = {}
ns.AuctionPanel = AuctionPanel

local CHOICE_HEIGHT, CHOICES_TOP = 24, 6
local MARK_WIDTH = 2
local CHOICE_INSET = 8
local PRICE_WIDTH, RANGE_WIDTH, COLUMN_GAP = 64, 70, 8
local SLIDE_TIME = 0.18
local SELECTED_FILL = { 0.243, 0.235, 0.220, 1 }
local CHOICE_HOVER = { 1, 1, 1, 0.05 }
local CLEAR = { 1, 1, 1, 0 }

local Money, ShortMoney = SidePanel.Money, SidePanel.ShortMoney
local HOSTS = { "AuctionHouseFrame" }

local panel

local function ShownPotion(entry)
    if entry.offer then return entry.offer.potion end
    return entry.offers[1] and entry.offers[1].potion
end

local function ShownItem(entry)
    local potion = ShownPotion(entry)
    return potion and potion.item
end

local function Stock(entry)
    local target = ns.Inventory.StockTarget(entry.type)
    if entry.mail > 0 then
        if entry.bank > 0 then return string.format(L.AH_HAVE_BANK_MAIL, entry.have, target, entry.bank, entry.mail) end
        return string.format(L.AH_HAVE_MAIL, entry.have, target, entry.mail)
    end
    if entry.bank > 0 then return string.format(L.AH_HAVE_BANK, entry.have, target, entry.bank) end
    return string.format(L.AH_HAVE, entry.have, target)
end

local function Detail(entry)
    local status = entry.status
    local offer = entry.offer
    if status == Market.SEARCHING then return L.AH_SEARCHING, C.muted end
    if status == Market.ENOUGH then return Stock(entry), C.muted end
    if status == Market.NONE then return L.AH_NONE, C.bad end
    if status == Market.POOR then return L.AH_POOR, C.bad end
    if status == Market.BUYING then return L.AH_BUYING, C.accent end
    if status == Market.CONFIRM then return L.AH_PRICE_UP, C.warn end
    if status == Market.RAISED then
        return string.format(L.AH_RAISED, Money(Market.SeenPrice(offer.item)), Money(offer.base)), C.warn
    end
    if offer.quantity < entry.need and offer.beyond then
        return string.format(L.AH_CHEAP_ONLY, offer.quantity, Money(offer.beyond)), C.warn
    end
    if offer.quantity < entry.need then return string.format(L.AH_PARTIAL, offer.quantity), C.warn end
    return Stock(entry), C.muted
end

local function LotSize(entry)
    local offer = entry.offer
    if not offer or offer.status ~= Market.READY then return entry.need end
    if offer.kind == "item" and offer.auctions[1] then return offer.auctions[1].quantity end
    return offer.quantity
end

local function ButtonText(entry, confirm)
    if confirm then return L.AH_CONFIRM end
    if entry.status == Market.ENOUGH then return L.AH_ENOUGH end
    return string.format(L.AH_BUY, LotSize(entry))
end

local function OnSale(offer)
    return offer ~= nil and offer.status == Market.READY
end

local function AddLine(text, color)
    GameTooltip:AddLine(text, color[1], color[2], color[3], true)
end

local function ShowChoiceTooltip(choice)
    local offer = choice.offer
    GameTooltip:SetOwner(choice, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(offer.item)
    GameTooltip:AddLine(" ")
    if not Market.IsSettled(offer) then
        AddLine(L.AH_SEARCHING, C.muted)
    elseif not OnSale(offer) then
        AddLine(L.AH_NONE, C.bad)
    else
        AddLine(string.format(L.AH_PER_POTION, Money(offer.unitCost)), C.text)
        if offer.quantity > 0 then
            AddLine(string.format(L.AH_TIP_AVAILABLE, offer.quantity), C.muted)
            AddLine(string.format(L.AH_TIP_TOTAL, offer.quantity, Money(offer.cost)), C.muted)
        else
            AddLine(L.AH_TIP_ENOUGH, C.muted)
        end
        if offer.beyond then AddLine(string.format(L.AH_TIP_BEYOND, Money(offer.beyond)), C.warn) end
    end
    GameTooltip:Show()
end

local function CreateChoice(row, index)
    local choice = CreateFrame("Button", nil, row.choices)
    choice:SetHeight(CHOICE_HEIGHT)
    choice:SetPoint("LEFT")
    choice:SetPoint("RIGHT")
    local hover = choice:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    W.HoverFill(choice, hover, CLEAR, CHOICE_HOVER)
    choice.price = UI.Text(choice, T.label, C.text)
    choice.price:SetPoint("RIGHT", -CHOICE_INSET, 0)
    choice.price:SetWidth(PRICE_WIDTH)
    choice.price:SetJustifyH("RIGHT")
    choice.range = UI.Text(choice, T.label, C.muted)
    choice.range:SetPoint("RIGHT", choice.price, "LEFT", -COLUMN_GAP, 0)
    choice.range:SetWidth(RANGE_WIDTH)
    choice.range:SetJustifyH("RIGHT")
    choice.name = UI.Text(choice, T.label, C.text)
    choice.name:SetPoint("LEFT", CHOICE_INSET, 0)
    choice.name:SetPoint("RIGHT", choice.range, "LEFT", -COLUMN_GAP, 0)
    choice.name:SetJustifyH("LEFT")
    choice:SetScript("OnClick", function(self) Market.Pick(row.entry, self.offer.potion) end)
    choice:HookScript("OnEnter", ShowChoiceTooltip)
    choice:HookScript("OnLeave", W.HideHint)
    row.choiceButtons[index] = choice
    return choice
end

local function ChoicePrice(offer)
    if not Market.IsSettled(offer) then return "…", C.muted end
    if offer.status ~= Market.READY then return L.AH_NONE_SHORT, C.muted end
    return ShortMoney(offer.unitCost), Market.IsRaised(offer) and C.warn or C.text
end

local function PaintChoice(choice, offer, chosen, busy)
    choice.offer = offer
    choice.name:SetText(Catalog.Name(offer.potion))
    choice.name:SetTextColor(unpack(chosen and C.accent or C.text))
    choice.range:SetText(Catalog.Range(offer.potion))
    local text, color = ChoicePrice(offer)
    choice.price:SetText(text)
    choice.price:SetTextColor(unpack(color))
    local pending = not Market.IsSettled(offer)
    choice:SetEnabled(OnSale(offer) and not busy)
    choice:SetAlpha((OnSale(offer) or pending or chosen) and 1 or SidePanel.DISABLED_ALPHA)
    choice:Show()
end

local function MoveSelection(row, y, animate)
    local function Apply(_, value)
        row.selection:SetPoint("TOPLEFT", 0, -value)
        row.selection:SetPoint("TOPRIGHT", 0, -value)
    end
    if animate then
        UI.Tween(row.slide, y, SLIDE_TIME, Apply)
    else
        UI.SnapTween(row.slide, y, Apply)
    end
end

local function PaintChoices(row, fresh)
    local entry = row.entry
    local offers = entry.offers
    local count = #offers
    row.choices:SetShown(count > 1)
    if count < 2 then return 0 end
    local busy = entry.status == Market.BUYING or entry.status == Market.CONFIRM
    local selected
    for index, offer in ipairs(offers) do
        local choice = row.choiceButtons[index] or CreateChoice(row, index)
        choice:SetPoint("TOP", 0, -(index - 1) * CHOICE_HEIGHT)
        local chosen = entry.offer == offer
        if chosen then selected = index end
        PaintChoice(choice, offer, chosen, busy)
    end
    for index = count + 1, #row.choiceButtons do
        row.choiceButtons[index]:Hide()
    end
    row.choices:SetHeight(count * CHOICE_HEIGHT)
    local slide = row.selection:IsShown() and not fresh
    row.selection:SetShown(selected ~= nil)
    row.mark:SetShown(selected ~= nil)
    if selected then MoveSelection(row, (selected - 1) * CHOICE_HEIGHT, slide) end
    return CHOICES_TOP + count * CHOICE_HEIGHT
end

local function CreateChoices(row)
    local choices = CreateFrame("Frame", nil, row)
    choices:SetPoint("TOPLEFT", SidePanel.TEXT_INDENT, -(SidePanel.HEAD_HEIGHT + CHOICES_TOP))
    choices:SetPoint("TOPRIGHT", 0, -(SidePanel.HEAD_HEIGHT + CHOICES_TOP))
    SidePanel.AddBackground(choices, C.control)
    row.selection = choices:CreateTexture(nil, "BORDER")
    row.selection:SetColorTexture(unpack(SELECTED_FILL))
    row.selection:SetHeight(CHOICE_HEIGHT)
    row.selection:Hide()
    row.mark = choices:CreateTexture(nil, "ARTWORK")
    row.mark:SetColorTexture(unpack(C.accent))
    row.mark:SetPoint("TOPLEFT", row.selection)
    row.mark:SetPoint("BOTTOMLEFT", row.selection)
    row.mark:SetWidth(MARK_WIDTH)
    row.mark:Hide()
    row.choices = choices
    row.choiceButtons = {}
    row.slide = {}
end

local function CreateRow(owner)
    local row = SidePanel.NewRow(owner, Market.Buy, ShownItem)
    CreateChoices(row)
    return row
end

local function PaintRow(row, fresh)
    local entry = row.entry
    local potion = ShownPotion(entry)
    row.icon:SetTexture(potion and Catalog.Icon(potion) or nil)
    row.name:SetText(potion and Catalog.Name(potion) or Catalog.TypeName(entry.type))
    local text, color = Detail(entry)
    row.detail:SetText(text)
    row.detail:SetTextColor(unpack(color))

    local status = entry.status
    local quoted = status == Market.CONFIRM
    local confirm = quoted or status == Market.RAISED
    local priced = status == Market.READY or status == Market.POOR or confirm
    row.price:SetShown(priced)
    if priced then row.price:SetText(Money(quoted and entry.quotedTotal or entry.offer.nextCost)) end
    row.price:SetTextColor(unpack(confirm and C.warn or C.text))

    row.button.text:SetText(ButtonText(entry, confirm))
    row.button:SetStyle(confirm and "primary" or "default")
    SidePanel.SetEnabled(row.button, status == Market.READY or confirm)
    row:SetHeight(SidePanel.HEAD_HEIGHT + PaintChoices(row, fresh))
end

local function Paint()
    panel.subtitle:SetText(L.AH_SUBTITLE)
    panel:PaintRows(Market.entries, CreateRow, PaintRow)
    panel.footerText:SetText(string.format(L.AH_TOTAL, Money(Market.Total())))
    panel.footerText:SetShown(#Market.entries > 0)
end

local function Create()
    panel = SidePanel.Create("RePotionAuctionPanel", {
        title = "AH_TITLE",
        empty = "AH_EMPTY",
        refresh = Market.Refresh,
        toggle = { key = "countBank", label = "COUNT_BANK", desc = "COUNT_BANK_DESC" },
        hosts = HOSTS,
        slot = "auction",
        offset = { x = "auctionX", y = "auctionY" },
        settingsPage = "auction",
    })
end

function AuctionPanel.IsShown()
    return panel ~= nil and panel:IsShown()
end

ns.Listen("MARKET_SHOWN", function(open)
    if not open then
        if panel then panel:Hide() end
        return
    end
    if not panel then Create() end
    Paint()
    panel:Open()
end)

local function RepaintIfShown()
    if panel and panel:IsShown() then Paint() end
end

ns.Listen("MARKET_CHANGED", RepaintIfShown)
ns.Listen("LOCALE_CHANGED", RepaintIfShown)
ns.Listen("NAMES_CHANGED", RepaintIfShown)
