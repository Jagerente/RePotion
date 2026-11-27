local _, ns = ...

local L = ns.L
local C = ns.UI.COLORS
local Market = ns.Market
local Catalog = ns.Catalog
local SidePanel = ns.SidePanel

local Money, ShortMoney, AddLine = SidePanel.Money, SidePanel.ShortMoney, SidePanel.AddLine
local HOSTS = { "AuctionHouseFrame" }
local PRICE_UNKNOWN = "—"
local ESTIMATE_FORMAT = "≈ %s"
local FIND_ALL_MIN_ROWS = 2

local panel

local function ShownPotion(entry)
    if entry.offer then return entry.offer.potion end
    return entry.offers[1] and entry.offers[1].potion
end

local function ShownItem(entry)
    local potion = ShownPotion(entry)
    return potion and potion.item
end

local function Detail(entry)
    local status = entry.status
    local offer = entry.offer
    if status == Market.SEARCHING then return L.AH_SEARCHING, C.muted end
    if status == Market.IDLE or status == Market.ENOUGH then return SidePanel.Stock(entry), C.muted end
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
    return SidePanel.Stock(entry), C.muted
end

local function LotSize(entry)
    local offer = entry.offer
    if not offer or offer.status ~= Market.READY then return entry.need end
    if offer.kind == "item" and offer.auctions[1] then return offer.auctions[1].quantity end
    return offer.quantity
end

local function ButtonText(entry, confirm)
    if entry.status == Market.IDLE then return L.AH_FIND_PRICE end
    if confirm then return L.AH_CONFIRM end
    if entry.status == Market.ENOUGH then return L.AH_ENOUGH end
    return string.format(L.AH_BUY, LotSize(entry))
end

local function OnSale(offer)
    return offer ~= nil and offer.status == Market.READY
end

local function ShowChoiceTooltip(choice)
    local offer = choice.offer
    GameTooltip:SetOwner(choice, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(offer.item)
    if offer.status == Market.IDLE then
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(" ")
    if not Market.IsSettled(offer) then
        AddLine(L.AH_SEARCHING, C.muted)
    elseif not OnSale(offer) then
        AddLine(L.AH_NONE, C.bad)
    else
        AddLine(string.format(L.AH_PER_ITEM, Money(offer.unitCost)), C.text)
        if offer.quantity > 0 then
            AddLine(string.format(L.AH_TIP_TOTAL, offer.quantity, Money(offer.cost)), C.muted)
        else
            AddLine(L.AH_TIP_ENOUGH, C.muted)
        end
        if offer.beyond then AddLine(string.format(L.AH_TIP_BEYOND, Money(offer.beyond)), C.warn) end
    end
    GameTooltip:Show()
end

local function ChoicePrice(offer)
    if offer.status == Market.IDLE then
        if offer.estimate then return string.format(ESTIMATE_FORMAT, ShortMoney(offer.estimate)), C.muted end
        return PRICE_UNKNOWN, C.muted
    end
    if not Market.IsSettled(offer) then return "…", C.muted end
    if offer.status ~= Market.READY then return L.AH_NONE_SHORT, C.muted end
    return ShortMoney(offer.unitCost), Market.IsRaised(offer) and C.warn or C.text
end

local function PaintChoice(choice, offer, chosen)
    local text, color = ChoicePrice(offer)
    choice.price:SetText(text)
    choice.price:SetTextColor(unpack(color))
    local available = Market.IsAvailable(offer)
    choice:SetEnabled(available and not Market.Busy(offer.entry))
    choice:SetAlpha((available or chosen) and 1 or SidePanel.DISABLED_ALPHA)
end

local function OnRowButton(entry)
    if entry.status == Market.IDLE then
        Market.FindPrices(entry)
    else
        Market.Buy(entry)
    end
end

local function CreateRow(owner)
    local row = SidePanel.NewRow(owner, OnRowButton, ShownItem)
    SidePanel.CreateChoices(row, Market.Pick, ShowChoiceTooltip)
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
    local estimate = Market.EstimatedCost(entry)
    row.price:SetShown(priced or estimate ~= nil)
    if priced then
        row.price:SetText(Money(quoted and entry.quotedTotal or entry.offer.nextCost))
        row.price:SetTextColor(unpack(confirm and C.warn or C.text))
    elseif estimate then
        row.price:SetText(string.format(ESTIMATE_FORMAT, ShortMoney(estimate)))
        row.price:SetTextColor(unpack(C.muted))
    end

    row.button.text:SetText(ButtonText(entry, confirm))
    row.button:SetStyle(confirm and "primary" or "default")
    SidePanel.SetEnabled(row.button, status == Market.IDLE or status == Market.READY or confirm)
    row:SetHeight(SidePanel.HEAD_HEIGHT + SidePanel.PaintChoices(row, fresh, PaintChoice))
end

local function Paint()
    panel.subtitle:SetText(L.AH_SUBTITLE)
    local waiting, known = Market.PriceCounts()
    local total, approximate = Market.Total()
    local offerAll = waiting >= FIND_ALL_MIN_ROWS
    local showTotal = known > 0 or approximate
    panel:SetFooterShown(offerAll or showTotal)
    panel:PaintRows(Market.entries, CreateRow, PaintRow)
    if approximate then
        panel.footerText:SetText(string.format(L.AH_ABOUT, ShortMoney(total)))
    else
        panel.footerText:SetText(string.format(L.AH_TOTAL, Money(total)))
    end
    panel.footerText:SetShown(showTotal)
    panel:SetAction(L.AH_FIND_PRICES, true)
    panel.action:SetShown(offerAll)
    panel.refresh:SetShown(known > 0)
end

local function Create()
    panel = SidePanel.Create("RePotionAuctionPanel", {
        title = "AH_TITLE",
        empty = "AH_EMPTY",
        refresh = Market.Refresh,
        onAction = function() Market.FindPrices() end,
        toggles = { { key = "countBank", label = "COUNT_BANK", desc = "COUNT_BANK_DESC" } },
        hosts = HOSTS,
        slot = "auction",
        offset = { x = "auctionX", y = "auctionY" },
        settingsPage = "auction",
    })
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
