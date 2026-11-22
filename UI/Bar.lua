local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Catalog = ns.Catalog
local Inventory = ns.Inventory
local Picker = ns.Picker

local Bar = { buttons = {} }
ns.Bar = Bar

local NAMES = {
    health = "RePotionHealth",
    mana = "RePotionMana",
    freeAction = "RePotionFreeAction",
}
local KEY_BUTTON, PANEL_BUTTON = "Button", "PanelButton"
local TIP_GLYPH_HEIGHT = 14
local TIP_GLYPH = UI.InlineGlyph(TIP_GLYPH_HEIGHT)
local TIP_GAP = " "
local PAD = 4
local HEADER_HEIGHT, HEADER_GAP = 14, 5
local HEADER_GLYPH_HEIGHT, HEADER_GLYPH_GAP = 11, 5
local BORDER = 1
local ICON_CROP = 0.08
local PRESS_INSET = 1
local LABEL_INSET = 3
local SCRIM_ALPHA = 0.85
local HOVER_ALPHA, HOVER_TIME = 0.14, 0.12
local EMPTY_ALPHA = 0.45
local SHOW_TIME = 0.18
local BACKGROUND = { 0.078, 0.076, 0.072 }
local PERCENT = 100
local ICON_BACK = { 0, 0, 0, 0.7 }
local STRATA = "MEDIUM"
local NO_ACTION = "none"
local SHOW, HIDE = "show", "hide"
local VISIBILITY_STATES = {
    always = SHOW,
    combat = "[combat] show; hide",
    never = HIDE,
}

local holder, bar, header, glyph, title
local buttons = Bar.buttons
local keyButtons = {}
local visible = {}
local barFade = {}
local driverState
local pendingLayout = false
local moving = false

function Bar.Binding(potionType)
    return "CLICK " .. NAMES[potionType.key] .. KEY_BUTTON .. ":LeftButton"
end

local function CountColor(potionType, kept)
    if kept == 0 then return C.bad end
    if kept < Inventory.StockTarget(potionType) then return C.warn end
    return C.text
end

local function AddLine(text, color)
    GameTooltip:AddLine(text, color[1], color[2], color[3], true)
end

local function AddRow(left, right, leftColor, rightColor)
    GameTooltip:AddDoubleLine(left, right, leftColor[1], leftColor[2], leftColor[3], rightColor[1], rightColor[2], rightColor[3])
end

local function AddGap()
    GameTooltip:AddLine(TIP_GAP)
end

local function Describe(potion)
    local range = Catalog.Range(potion)
    if not range then return Catalog.Name(potion) end
    return string.format(L.POTION_WITH_RANGE, Catalog.Name(potion), range)
end

local function AddHeader(potionType)
    AddGap()
    AddRow(TIP_GLYPH .. " " .. ns.TITLE, Catalog.TypeName(potionType), C.accent, C.muted)
end

local function AddStatusLines(record)
    local active = record.active
    if not active.main then
        AddLine(L.TIP_NONE, C.bad)
    elseif active.fallback then
        AddRow(L.TIP_FALLBACK, Catalog.Name(active.fallback), C.muted, C.text)
    end
    if InCombatLockdown() and record.text ~= active.text then AddLine(L.TIP_AFTER_COMBAT, C.warn) end
end

local function AddBagLines(record, grade)
    local owned = record.owned
    if #owned < 2 then return end
    for index = #owned, 1, -1 do
        local potion = owned[index]
        local color = Inventory.Counts(potion, grade) and C.text or C.muted
        AddRow(Describe(potion), string.format(L.COUNT, Inventory.Count(potion.item)), color, color)
    end
end

local function AddStockLines(record)
    local potionType = record.type
    local grade = Inventory.StockPotion(potionType)
    local have, bank = Inventory.StockCount(potionType, grade)
    AddGap()
    AddRow(L.TIP_STOCK, string.format(L.TIP_STOCK_VALUE, have, Inventory.StockTarget(potionType)), C.muted, CountColor(potionType, have))
    if bank > 0 then AddRow(L.TIP_IN_BANK, bank, C.muted, C.text) end
    if grade and potionType.graded then AddLine(string.format(L.TIP_STOCK_FROM, Catalog.Name(grade)), C.muted) end
    AddBagLines(record, grade)
end

local function AddHintLines()
    AddGap()
    AddRow(L.TIP_SHIFT_DRAG, L.TIP_TAKE_MACRO, C.muted, C.muted)
    if not ns.db.locked then AddRow(L.TIP_ALT_DRAG, L.TIP_MOVE, C.muted, C.muted) end
    AddRow(L.TIP_RIGHT_CLICK, L.TIP_SETTINGS, C.muted, C.muted)
end

local function ShowTooltip(button)
    local record = button.record
    local potion = Picker.Shown(record)
    GameTooltip:SetOwner(button, UI.VerticalAnchor(button))
    if potion then
        GameTooltip:SetItemByID(potion.item)
    else
        GameTooltip:SetText(Catalog.TypeName(button.type), C.text[1], C.text[2], C.text[3])
    end
    AddHeader(button.type)
    AddStatusLines(record)
    AddStockLines(record)
    AddHintLines()
    GameTooltip:Show()
end

local function PaintCooldown(button, potion)
    local start, duration = 0, 0
    if potion then start, duration = Inventory.Cooldown(potion.item) end
    if duration > 0 then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
end

local function PaintButton(button)
    local potion = Picker.Shown(button.record)
    local have = potion and Inventory.Count(potion.item) or 0
    local kept = Inventory.StockCount(button.type)
    button.icon:SetTexture(potion and Catalog.Icon(potion) or nil)
    button.icon:SetDesaturated(have == 0)
    button.art:SetAlpha(have == 0 and EMPTY_ALPHA or 1)
    button.count:SetShown(ns.db.showCounts)
    button.scrim:SetShown(ns.db.showCounts)
    button.count:SetText(kept > 0 and kept or have)
    button.count:SetTextColor(unpack(CountColor(button.type, kept)))
    PaintCooldown(button, potion)
end

local function Paint()
    for _, button in ipairs(visible) do
        PaintButton(button)
    end
end

local function PaintCooldowns()
    for _, button in ipairs(visible) do
        PaintCooldown(button, Picker.Shown(button.record))
    end
end

local function Highlight(button, on)
    UI.Tween(button.hover, on and HOVER_ALPHA or 0, HOVER_TIME, function(_, value) button.highlight:SetAlpha(value) end)
end

local function SavePosition()
    local point, _, _, x, y = holder:GetPoint(1)
    local position = ns.db.position
    position.point, position.x, position.y = point, x, y
end

function Bar.ResetPosition()
    local current, default = ns.db.position, ns.DEFAULTS.position
    current.point, current.x, current.y = default.point, default.x, default.y
    ns.Fire("SETTING_CHANGED", "position")
end

local function StartMoving()
    if ns.db.locked or InCombatLockdown() then return false end
    moving = true
    holder:Raise()
    holder:StartMoving()
end

local function StopMoving()
    if not moving then return end
    moving = false
    holder:StopMovingOrSizing()
    SavePosition()
end

local function OnDragStart(button)
    if not IsShiftKeyDown() or IsAltKeyDown() then return end
    GameTooltip:Hide()
    ns.Macros.Pickup(button.type)
end

local function StartAltMoving()
    if not IsAltKeyDown() then return false end
    GameTooltip:Hide()
    return StartMoving()
end

local function OnPostClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.Options.Toggle()
    elseif mouseButton == "MiddleButton" and not ns.db.locked and not InCombatLockdown() then
        Bar.ResetPosition()
    end
end

local function CreateArt(button)
    button.art = CreateFrame("Frame", nil, button)
    button.art:SetAllPoints()
    UI.Fill(button.art, ICON_BACK)
    button.icon = button.art:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetHideCountdownNumbers(true)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    button.highlight = UI.Fill(overlay, { 1, 1, 1, 1 }, "ARTWORK")
    button.highlight:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.highlight:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.highlight:SetAlpha(0)
    button.hover = {}

    button.scrim = overlay:CreateTexture(nil, "BACKGROUND")
    button.scrim:SetColorTexture(1, 1, 1, 1)
    button.scrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, SCRIM_ALPHA), CreateColor(0, 0, 0, 0))
    button.scrim:SetPoint("TOPLEFT", button, "LEFT", BORDER, 0)
    button.scrim:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.count = UI.BoldText(overlay, T.body, C.text)
    button.count:SetPoint("BOTTOMRIGHT", -LABEL_INSET, LABEL_INSET - 1)
end

local function SetPressed(button, pressed)
    local inset = BORDER + (pressed and PRESS_INSET or 0)
    button.icon:SetPoint("TOPLEFT", inset, -inset)
    button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
end

local function CreateKeyButton(potionType)
    local button = CreateFrame("Button", NAMES[potionType.key] .. KEY_BUTTON, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", Picker.records[potionType.key].active.text)
    keyButtons[potionType.key] = button
end

local function CreateButton(potionType)
    local button = CreateFrame("Button", NAMES[potionType.key] .. PANEL_BUTTON, bar, "SecureActionButtonTemplate")
    button.type = potionType
    button.record = Picker.records[potionType.key]
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type", "macro")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("*type2", NO_ACTION)
    button:SetAttribute("*type3", NO_ACTION)
    button:SetAttribute("alt-type1", NO_ACTION)
    button:SetAttribute("shift-type1", NO_ACTION)
    button:SetAttribute("macrotext", button.record.active.text)
    button:Hide()
    CreateArt(button)

    button:SetScript("PostClick", OnPostClick)
    button:SetScript("OnDragStart", OnDragStart)
    W.DragHandle(button, StartAltMoving, StopMoving)
    button:HookScript("OnEnter", function(self)
        Highlight(self, true)
        ShowTooltip(self)
    end)
    button:HookScript("OnLeave", function(self)
        Highlight(self, false)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    button:HookScript("OnMouseDown", function(self) SetPressed(self, true) end)
    button:HookScript("OnMouseUp", function(self) SetPressed(self, false) end)
    button:HookScript("OnHide", function(self) SetPressed(self, false) end)
    buttons[potionType.key] = button
    return button
end

local function OnHeaderMouseUp(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.Options.Toggle()
    elseif mouseButton == "MiddleButton" and not ns.db.locked and not InCombatLockdown() then
        Bar.ResetPosition()
    end
end

local function CreateHeader()
    header = CreateFrame("Frame", nil, bar)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:EnableMouse(true)
    Bar.header = header
    glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    glyph:SetPoint("LEFT")
    title = UI.BoldText(header, T.label, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    header:SetScript("OnEnter", function(self)
        W.ShowHint(self, ns.db.locked and "HEADER_LOCKED_DESC" or "HEADER_DESC")
    end)
    header:SetScript("OnLeave", W.HideHint)
    header:SetScript("OnMouseUp", OnHeaderMouseUp)
    W.DragHandle(header, function()
        if ns.db.locked or InCombatLockdown() then return false end
        StartMoving()
    end, StopMoving)
end

local function HeaderWidth()
    return glyph:GetWidth() + HEADER_GLYPH_GAP + math.ceil(title:GetStringWidth())
end

local function FadeBarIn()
    barFade.tweenValue = 0
    bar:SetAlpha(0)
    UI.Tween(barFade, 1, SHOW_TIME, function(_, value) bar:SetAlpha(value) end)
end

local function PaintBackground()
    bar.background:SetAlpha(ns.db.barBackground / PERCENT)
end

local function Create()
    holder = CreateFrame("Frame", "RePotionHolder", UIParent)
    holder:SetSize(1, 1)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:SetFrameStrata(STRATA)
    holder:SetToplevel(true)
    holder:HookScript("OnShow", FadeBarIn)

    bar = CreateFrame("Frame", "RePotionBar", holder)
    bar:SetPoint("TOPLEFT", holder, "CENTER")
    bar.background = UI.Fill(bar, BACKGROUND)
    PaintBackground()
    CreateHeader()
    for _, potionType in ipairs(Catalog.types) do
        CreateButton(potionType)
        CreateKeyButton(potionType)
    end
end

local function PlaceHolder()
    local position = ns.db.position
    holder:ClearAllPoints()
    holder:SetPoint(position.point, UIParent, position.point, position.x, position.y)
end

local function WantsButton(potionType)
    if not Catalog.IsActive(potionType) then return false end
    return ns.db.showEmpty or ns.TestMode.active or Picker.records[potionType.key].active.main ~= nil
end

local function Layout()
    wipe(visible)
    for _, potionType in ipairs(Catalog.types) do
        local button = buttons[potionType.key]
        if WantsButton(potionType) then
            visible[#visible + 1] = button
        else
            button:Hide()
        end
    end
    local size, gap = ns.db.iconSize, ns.db.spacing
    local horizontal = ns.db.layout == "HORIZONTAL"
    local showHeader = ns.db.showHeader
    header:SetShown(showHeader)
    title:SetText(L.HEADER)
    local top = showHeader and HEADER_HEIGHT + HEADER_GAP or 0
    for index, button in ipairs(visible) do
        local offset = (index - 1) * (size + gap)
        button:SetSize(size, size)
        button:ClearAllPoints()
        if horizontal then
            button:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + offset, -(PAD + top))
        else
            button:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -(PAD + top + offset))
        end
        button:Show()
    end
    local count = math.max(1, #visible)
    local along = count * size + (count - 1) * gap
    local width = horizontal and along or size
    local height = horizontal and size or along
    if showHeader then width = math.max(width, HeaderWidth()) end
    bar:SetSize(PAD * 2 + width, PAD * 2 + top + height)
end

local function WantedState()
    if not ns.db.enabled or #visible == 0 then return HIDE end
    if ns.TestMode.active or ns.Options.IsOpen() then return SHOW end
    return VISIBILITY_STATES[ns.db.visibility] or SHOW
end

local function ApplyVisibility()
    local state = WantedState()
    if state == driverState then return end
    driverState = state
    RegisterStateDriver(holder, "visibility", state)
end

function Bar.Refresh()
    if not holder then return end
    if InCombatLockdown() then
        pendingLayout = true
        Paint()
        return
    end
    pendingLayout = false
    Layout()
    ApplyVisibility()
    Paint()
end

function Bar.IsShown()
    return holder ~= nil and holder:IsShown()
end

local function ApplyTexts()
    if not holder or InCombatLockdown() then return end
    for key, button in pairs(buttons) do
        local text = Picker.records[key].active.text
        button:SetAttribute("macrotext", text)
        keyButtons[key]:SetAttribute("macrotext", text)
    end
end

ns.Listen("PICKS_APPLIED", ApplyTexts)
ns.Listen("PICKS_CHANGED", Bar.Refresh)
ns.Listen("INVENTORY_CHANGED", Paint)
ns.Listen("STOCK_CHANGED", Paint)
ns.Listen("TYPES_CHANGED", Bar.Refresh)
ns.Listen("TEST_MODE_CHANGED", Bar.Refresh)
ns.Listen("OPTIONS_SHOWN", Bar.Refresh)
ns.Listen("LOCALE_CHANGED", Bar.Refresh)
ns.Listen("SETTING_CHANGED", function(key)
    if not holder then return end
    if key == nil or key == "barBackground" then PaintBackground() end
    if (key == nil or key == "position") and not InCombatLockdown() then PlaceHolder() end
    Bar.Refresh()
end)

ns.Listen("LOGIN", function()
    Create()
    PlaceHolder()
    ns.RegisterEvent("BAG_UPDATE_COOLDOWN", PaintCooldowns)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        StopMoving()
        if pendingLayout then Bar.Refresh() end
    end)
    Bar.Refresh()
end)
