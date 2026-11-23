local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Catalog = ns.Catalog

local Options = {}
ns.Options = Options

local WIDTH, HEIGHT = 380, 560
local MARGIN = 14
local HEADER_HEIGHT, TABS_HEIGHT, BODY_GAP = 38, 26, 10
local HEADER_GLYPH_HEIGHT, HEADER_GLYPH_GAP = 16, 8
local SETTINGS_GLYPH_HEIGHT = 20
local TAB_PAD, MIN_TAB_PAD, TAB_GAP = 8, 4, 4
local PAGE_WIDTH = WIDTH - MARGIN * 2
local CONTENT_INSET = 8
local SECTION_GAP = 10
local SLIDER_GAP = 8
local PARAGRAPH_GAP = 4
local FLOOR_MAX = 60
local STOCK_MAX = 20
local TYPE_GAP = 14
local TYPE_HEAD_HEIGHT, TYPE_ICON_SIZE, TYPE_TEXT_GAP = 36, 30, 10
local FORM_INDENT = TYPE_ICON_SIZE + TYPE_TEXT_GAP
local FORM_ROW_HEIGHT, FORM_TOP_GAP, FORM_LABEL_GAP = 26, 4, 8
local FORM_SLIDER_WIDTH = 180
local ICON_BACK = { 0, 0, 0, 0.7 }
local ICON_CROP = 0.08
local LOCKED_SWITCH_ALPHA = 0.5
local ICON_SIZE_MIN, ICON_SIZE_MAX = 24, 64
local SPACING_MAX = 16
local RESET_CONFIRM_SECONDS = 3
local PANEL_OFFSET = 500
local PERCENT_MAX = 100

local window
local pages = {}
local tabButtons = {}
local tabPad = TAB_PAD
local currentPage
local previewStartedHere = false

local function Setting(key)
    return function() return ns.db[key] end, function(value) ns.Set(key, value) end
end

local function Track(page, widget)
    page.widgets[#page.widgets + 1] = widget
    return widget
end

local function AddToggle(page, key, label, desc)
    local get, set = Setting(key)
    return page.stack:Add(Track(page, W.Toggle(page.content, PAGE_WIDTH, { label = label, desc = desc, get = get, set = set })))
end

local function AddSlider(page, key, label, min, max, format, gap)
    local get, set = Setting(key)
    return page.stack:Add(Track(page, W.Slider(page.content, PAGE_WIDTH, {
        label = label, min = min, max = max, step = 1, get = get, set = set, format = format,
    })), gap or SLIDER_GAP)
end

local function AddSegmented(page, key, label, items, gap)
    local get, set = Setting(key)
    return page.stack:Add(Track(page, W.Segmented(page.content, PAGE_WIDTH, {
        label = label, count = #items, get = get, set = set,
        items = function()
            local list = {}
            for i, item in ipairs(items) do
                list[i] = { value = item.value, text = L[item.key] }
            end
            return list
        end,
    })), gap)
end

local function AddHeading(page, key)
    return page.stack:Add(W.Heading(page.content, PAGE_WIDTH, key), #page.stack.frames > 0 and SECTION_GAP or 0)
end

local function AddParagraph(page, key, gap)
    return page.stack:Add(W.Paragraph(page.content, PAGE_WIDTH, key), gap or PARAGRAPH_GAP)
end

local function AddLiveText(page, build, color, gap)
    local frame = CreateFrame("Frame", nil, page.content)
    frame:SetWidth(PAGE_WIDTH)
    local text = UI.Text(frame, T.label, color)
    text:SetPoint("TOPLEFT")
    text:SetWidth(PAGE_WIDTH)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    function frame:Refresh()
        text:SetText(build())
        self:SetHeight(math.floor(text:GetStringHeight() + 4))
    end
    frame:Refresh()
    page.stack:Add(Track(page, frame), gap)
    return frame
end

local function NewPage(id)
    local scroll = W.Scroll(window.body)
    scroll:SetAllPoints(window.body)
    scroll:Hide()
    local page = { id = id, scroll = scroll, content = scroll.content, widgets = {} }
    page.stack = W.Stack(page.content, CONTENT_INSET)
    pages[id] = page
    return page
end

local function RefreshPage(page, animate)
    for _, widget in ipairs(page.widgets) do
        widget:Refresh(animate)
    end
    if page.OnShow then page:OnShow() end
end

local function IsCurrent(page)
    return window and window:IsShown() and currentPage == page
end

local function FormatPercent(value)
    return string.format("%d%%", value)
end

local function ShowText(owner, text)
    if not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function ActivePotion(potionType)
    return ns.Picker.records[potionType.key].active.main
end

local function HeadPotion(potionType)
    return ns.Picker.Shown(ns.Picker.records[potionType.key]) or potionType.potions[#potionType.potions]
end

local function TypeStatus(potionType)
    if not Catalog.HasPool(potionType) then return L.NO_MANA, C.muted end
    local active = ActivePotion(potionType)
    if active then return Catalog.Name(active), C.muted end
    return L.NONE_IN_BAGS, C.bad
end

local function IsOpen(potionType)
    return Catalog.HasPool(potionType) and Catalog.IsEnabled(potionType)
end

local function StockHint(potionType)
    local grade = potionType.graded and ns.Inventory.StockPotion(potionType)
    return grade and string.format(L.TIP_STOCK_FROM, Catalog.Name(grade)) or nil
end

local function FloorHint(potionType)
    local floor = math.floor(Catalog.EffectiveFloor(potionType, UnitLevel("player")))
    return string.format(L["FLOOR_DESC_" .. potionType.key], floor)
end

local function CreateHead(block)
    local potionType = block.type
    local head = CreateFrame("Button", nil, block)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(TYPE_HEAD_HEIGHT)
    W.RowHover(head)
    local back = head:CreateTexture(nil, "ARTWORK")
    back:SetColorTexture(unpack(ICON_BACK))
    back:SetSize(TYPE_ICON_SIZE, TYPE_ICON_SIZE)
    back:SetPoint("LEFT")
    block.icon = head:CreateTexture(nil, "OVERLAY")
    block.icon:SetPoint("TOPLEFT", back, 1, -1)
    block.icon:SetPoint("BOTTOMRIGHT", back, -1, 1)
    block.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    block.switch = W.CreateSwitch(head)
    block.switch:SetPoint("RIGHT")
    block.name = UI.BoldText(head, T.body, C.text)
    block.name:SetPoint("TOPLEFT", back, "TOPRIGHT", TYPE_TEXT_GAP, 0)
    block.name:SetPoint("RIGHT", block.switch, "LEFT", -TYPE_TEXT_GAP, 0)
    block.name:SetJustifyH("LEFT")
    block.status = UI.Text(head, T.label, C.muted)
    block.status:SetPoint("BOTTOMLEFT", back, "BOTTOMRIGHT", TYPE_TEXT_GAP, 0)
    block.status:SetPoint("RIGHT", block.switch, "LEFT", -TYPE_TEXT_GAP, 0)
    block.status:SetJustifyH("LEFT")
    head:SetScript("OnClick", function()
        if not Catalog.HasPool(potionType) then return end
        Catalog.SetEnabled(potionType, not Catalog.IsEnabled(potionType))
    end)
    head:HookScript("OnEnter", function(self)
        W.SetSwitchHover(block.switch, Catalog.HasPool(potionType))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(HeadPotion(potionType).item)
        GameTooltip:Show()
    end)
    head:HookScript("OnLeave", function(self)
        W.SetSwitchHover(block.switch, false)
        W.HideHint(self)
    end)
end

local function PaintHead(block, animate)
    local potionType = block.type
    local open = IsOpen(potionType)
    block.icon:SetTexture(Catalog.Icon(HeadPotion(potionType)))
    block.icon:SetDesaturated(not open or ActivePotion(potionType) == nil)
    block.name:SetText(Catalog.TypeName(potionType))
    block.name:SetTextColor(unpack(open and C.text or C.muted))
    local status, color = TypeStatus(potionType)
    block.status:SetText(status)
    block.status:SetTextColor(unpack(open and color or C.muted))
    block.switch:SetAlpha(Catalog.HasPool(potionType) and 1 or LOCKED_SWITCH_ALPHA)
    W.SetSwitch(block.switch, open, animate)
end

local function AddFormRow(block, labelKey, hint)
    local row = CreateFrame("Frame", nil, block)
    row:SetSize(PAGE_WIDTH - FORM_INDENT, FORM_ROW_HEIGHT)
    row:EnableMouse(true)
    row.label = UI.Text(row, T.label, C.muted)
    row.label:SetPoint("LEFT")
    row.label:SetJustifyH("LEFT")
    W.Bind(row.label, labelKey)
    if hint then
        row:SetScript("OnEnter", function(self) ShowText(self, hint(block.type)) end)
        row:SetScript("OnLeave", W.HideHint)
    end
    block.rows[#block.rows + 1] = row
    return row
end

local function Attach(row, control)
    control:SetPoint("RIGHT")
    row.label:SetPoint("RIGHT", control, "LEFT", -FORM_LABEL_GAP, 0)
    row.control = control
    return control
end

local function AddSliderRow(block, labelKey, key, max, format, hint)
    local row = AddFormRow(block, labelKey, hint)
    local get, set = Setting(key)
    Attach(row, W.Slider(row, FORM_SLIDER_WIDTH, { min = 0, max = max, step = 1, get = get, set = set, format = format }))
end

local function AddKeyRow(block)
    local row = AddFormRow(block, "KEY_ROW")
    Attach(row, W.KeyBind(row, { desc = "KEY_DESC", binding = ns.Bar.Binding(block.type) }))
end

local function AddMacroRow(block)
    local row = AddFormRow(block, "MACRO_ROW")
    local button = W.Button(row, "MACRO_PICKUP", function() ns.Macros.Pickup(block.type) end, nil, W.KEY_BUTTON_WIDTH)
    button:HookScript("OnEnter", function(self) W.ShowHint(self, "MACRO_BUTTON_DESC") end)
    button:HookScript("OnLeave", W.HideHint)
    Attach(row, button)
end

local function LayoutBlock(block, animate)
    PaintHead(block, animate)
    local open = IsOpen(block.type)
    local y = TYPE_HEAD_HEIGHT
    for index, row in ipairs(block.rows) do
        row:SetShown(open)
        if open then
            y = y + (index == 1 and FORM_TOP_GAP or 0)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", FORM_INDENT, -y)
            if row.control.Refresh then row.control:Refresh() end
            y = y + FORM_ROW_HEIGHT
        end
    end
    block:SetHeight(y)
end

local function AddTypeBlock(page, potionType, gap)
    local block = CreateFrame("Frame", nil, page.content)
    block:SetWidth(PAGE_WIDTH)
    block.type = potionType
    block.rows = {}
    CreateHead(block)
    AddSliderRow(block, "STOCK_ROW", potionType.stockKey, STOCK_MAX, nil, StockHint)
    if potionType.floorKey then
        AddSliderRow(block, "FLOOR_ROW", potionType.floorKey, FLOOR_MAX, FormatPercent, FloorHint)
    end
    AddKeyRow(block)
    AddMacroRow(block)
    block.Refresh = LayoutBlock
    LayoutBlock(block, false)
    page.stack:Add(Track(page, block), gap)
end

local function BuildPotions()
    local page = NewPage("potions")
    for index, potionType in ipairs(Catalog.types) do
        AddTypeBlock(page, potionType, index > 1 and TYPE_GAP or 0)
    end

    local function RefreshIfVisible()
        if IsCurrent(page) then RefreshPage(page, true) end
    end
    ns.Listen("PICKS_CHANGED", RefreshIfVisible)
    ns.Listen("TYPES_CHANGED", RefreshIfVisible)
    ns.Listen("NAMES_CHANGED", RefreshIfVisible)
    ns.Listen("STOCK_CHANGED", RefreshIfVisible)
end

local AUTO = "auto"
local DOCK_SIDE_GAP, DOCK_TEXT_GAP = 10, 8
local DOCK_PAGES = { "auction", "bank" }

local DockPlacement = ns.SidePanel.Placement

local function DockTargets(slot)
    local items = {
        { value = AUTO, text = L.DOCK_AUTO },
        { value = ns.Dock.HOST, text = L["DOCK_HOST_" .. slot] },
    }
    for _, name in ipairs(ns.Dock:Family(slot)) do
        if name ~= ns.ADDON and ns.Dock:CanAttach(ns.ADDON, slot, name) then
            items[#items + 1] = { value = name, text = name }
        end
    end
    return items
end

local function DefaultSide(target)
    return target == ns.Dock.HOST and "RIGHT" or "BELOW"
end

local function SetDockTarget(slot, target)
    if target == AUTO then
        ns.SidePanel.SetPlacement(slot, nil)
        return
    end
    local placement = DockPlacement(slot)
    ns.SidePanel.SetPlacement(slot, target, placement and placement.side or DefaultSide(target))
end

local function SetDockSide(slot, side)
    local placement = DockPlacement(slot)
    if placement then ns.SidePanel.SetPlacement(slot, placement.target, side) end
end

local function DockStatus(slot)
    local parent, side, takenBy = ns.Dock:Place(ns.ADDON, slot)
    if not parent then return "" end
    local where = parent == ns.Dock.HOST and L["DOCK_OF_" .. slot] or parent
    local text = string.format(L["DOCK_NOW_" .. side], where)
    if takenBy then text = text .. "\n" .. string.format(L.DOCK_TAKEN, takenBy) end
    return text
end

local function DockSides()
    local list = {}
    for index, side in ipairs(ns.Dock.SIDES) do
        list[index] = { value = side, text = L["DOCK_SIDE_" .. side] }
    end
    return list
end

local function AddDockControls(page, slot)
    page.stack:Add(Track(page, W.Choices(page.content, PAGE_WIDTH, {
        label = "DOCK_TARGET",
        items = function() return DockTargets(slot) end,
        get = function()
            local placement = DockPlacement(slot)
            return placement and placement.target or AUTO
        end,
        set = function(target) SetDockTarget(slot, target) end,
    })))
    local sides = page.stack:Add(Track(page, W.Segmented(page.content, PAGE_WIDTH, {
        label = "DOCK_SIDE",
        count = #ns.Dock.SIDES,
        items = DockSides,
        get = function()
            local placement = DockPlacement(slot)
            return placement and placement.side
        end,
        set = function(side) SetDockSide(slot, side) end,
    })), DOCK_SIDE_GAP)
    local status = AddLiveText(page, function() return DockStatus(slot) end, C.text, DOCK_TEXT_GAP)
    local paintStatus = status.Refresh
    function status:Refresh()
        sides:SetShown(DockPlacement(slot) ~= nil)
        paintStatus(self)
    end
    status:Refresh()
end

ns.Dock:OnChange(function()
    for _, id in ipairs(DOCK_PAGES) do
        local page = pages[id]
        if page and IsCurrent(page) then RefreshPage(page, true) end
    end
end)

local function BuildAuction()
    local page = NewPage("auction")
    AddHeading(page, "SECTION_AUCTION")
    AddToggle(page, "auction", "AUCTION", "AUCTION_DESC")
    AddToggle(page, "countBank", "COUNT_BANK", "COUNT_BANK_DESC")
    AddParagraph(page, "BUY_EXPLAIN", 6)

    AddHeading(page, "SECTION_PRICES")
    AddSlider(page, "priceStep", "PRICE_STEP", 0, PERCENT_MAX, FormatPercent)
    AddParagraph(page, "PRICE_STEP_EXPLAIN", 6)

    AddHeading(page, "SECTION_PLACEMENT")
    AddDockControls(page, "auction")
    AddSlider(page, "auctionX", "OFFSET_X", -PANEL_OFFSET, PANEL_OFFSET)
    AddSlider(page, "auctionY", "OFFSET_Y", -PANEL_OFFSET, PANEL_OFFSET)
end

local function BuildBank()
    local page = NewPage("bank")
    AddHeading(page, "SECTION_BANK")
    AddToggle(page, "bank", "BANK", "BANK_DESC")
    AddToggle(page, "bankAuto", "BANK_AUTO", "BANK_AUTO_DESC")

    AddHeading(page, "SECTION_PLACEMENT")
    AddDockControls(page, "bank")
    AddSlider(page, "bankX", "OFFSET_X", -PANEL_OFFSET, PANEL_OFFSET)
    AddSlider(page, "bankY", "OFFSET_Y", -PANEL_OFFSET, PANEL_OFFSET)
end

local VISIBILITY_MODES = {
    { value = "always", key = "VISIBILITY_always" },
    { value = "combat", key = "VISIBILITY_combat" },
    { value = "never", key = "VISIBILITY_never" },
}

local LAYOUT_MODES = {
    { value = "HORIZONTAL", key = "LAYOUT_HORIZONTAL" },
    { value = "VERTICAL", key = "LAYOUT_VERTICAL" },
}

local function AddRecenterButton(page)
    local button = W.Button(page.content, "RECENTER", function() ns.Bar.ResetPosition() end)
    page.stack:Add(button, 12)
end

local function BuildPanel()
    local page = NewPage("panel")
    AddHeading(page, "SECTION_WHEN")
    AddSegmented(page, "visibility", "VISIBILITY", VISIBILITY_MODES)
    AddParagraph(page, "VISIBILITY_EXPLAIN", 6)
    AddToggle(page, "showEmpty", "SHOW_EMPTY", "SHOW_EMPTY_DESC")

    AddHeading(page, "SECTION_LOOK")
    AddSlider(page, "iconSize", "ICON_SIZE", ICON_SIZE_MIN, ICON_SIZE_MAX, nil, 4)
    AddSlider(page, "spacing", "SPACING", 0, SPACING_MAX)
    AddSegmented(page, "layout", "LAYOUT", LAYOUT_MODES, SLIDER_GAP)
    AddToggle(page, "showHeader", "SHOW_HEADER", "SHOW_HEADER_DESC")
    AddToggle(page, "showCounts", "SHOW_COUNTS", "SHOW_COUNTS_DESC")
    AddToggle(page, "locked", "LOCKED", "LOCKED_DESC")
    AddRecenterButton(page)

    AddHeading(page, "SECTION_BACKGROUND")
    AddSlider(page, "barBackground", "BAR_BACKGROUND", 0, PERCENT_MAX, FormatPercent, 4)
    AddSlider(page, "panelBackground", "PANEL_BACKGROUND", 0, PERCENT_MAX, FormatPercent)
end

local function AddResetButton(page)
    local button
    local function Disarm()
        button.armed = false
        button.text:SetText(L.RESET)
        button:Fit()
    end
    button = W.Button(page.content, "RESET", function(self)
        if self.armed then
            Disarm()
            ns.ResetSettings()
            return
        end
        self.armed = true
        self.text:SetText(L.RESET_CONFIRM)
        self:Fit()
        C_Timer.After(RESET_CONFIRM_SECONDS, function()
            if self.armed then Disarm() end
        end)
    end, "danger")
    page.stack:Add(button, 16)
end

local LANGUAGE_ITEMS = {}
for i, code in ipairs(ns.LANGUAGES) do
    LANGUAGE_ITEMS[i] = { value = code, key = "LANGUAGE_" .. code }
end

local function BuildGeneral()
    local page = NewPage("general")
    AddHeading(page, "SECTION_BEHAVIOR")
    AddToggle(page, "enabled", "ENABLE", "ENABLE_DESC")
    page.stack:Add(Track(page, W.Toggle(page.content, PAGE_WIDTH, {
        label = "MINIMAP_BUTTON",
        get = function() return not ns.db.minimap.hide end,
        set = ns.MinimapButton.SetShown,
    })))
    AddSegmented(page, "locale", "LANGUAGE", LANGUAGE_ITEMS, SECTION_GAP)
    AddResetButton(page)
end

local function BuildAbout()
    ns.About.Build(NewPage("about"), PAGE_WIDTH)
end

local DEFAULT_PAGE = "potions"
local TABS = {
    { id = "potions", key = "NAV_POTIONS", build = BuildPotions },
    { id = "panel", key = "NAV_PANEL", build = BuildPanel },
    { id = "auction", key = "NAV_AUCTION", build = BuildAuction },
    { id = "bank", key = "NAV_BANK", build = BuildBank },
    { id = "general", key = "NAV_GENERAL", build = BuildGeneral },
    { id = "about", key = "NAV_ABOUT", build = BuildAbout },
}

local function FindTab(id)
    for _, entry in ipairs(TABS) do
        if entry.id == id then return entry end
    end
end

local underline = { x = 0, width = 0, motion = {} }

local function SetUnderline(x, width)
    underline.x, underline.width = x, width
    window.tabUnderline:SetPoint("BOTTOMLEFT", window.tabBar, "BOTTOMLEFT", x, 0)
    window.tabUnderline:SetWidth(math.max(1, width))
end

local function MoveUnderline(button, animate)
    local toX, toWidth = button.offset + tabPad, button:GetWidth() - tabPad * 2
    if not animate then
        UI.SnapTween(underline.motion, 1, function() SetUnderline(toX, toWidth) end)
        return
    end
    local fromX, fromWidth = underline.x, underline.width
    underline.motion.tweenValue = 0
    UI.Tween(underline.motion, 1, 0.2, function(_, t)
        SetUnderline(UI.Lerp(fromX, toX, t), UI.Lerp(fromWidth, toWidth, t))
    end)
end

local function ShowPage(id, animate)
    if not FindTab(id) then id = DEFAULT_PAGE end
    local page = pages[id]
    if not page then
        FindTab(id).build()
        page = pages[id]
    end
    if currentPage and currentPage ~= page then
        currentPage.scroll:Hide()
    end
    currentPage = page
    RefreshPage(page)
    page.scroll:ScrollTo(0, false)
    if animate then
        UI.FadeIn(page.scroll, 0.14)
    else
        page.scroll:Show()
        page.scroll:SetAlpha(1)
    end
    for index, entry in ipairs(TABS) do
        local button = tabButtons[index]
        local selected = entry.id == id
        button.text:SetTextColor(unpack(selected and C.text or C.muted))
        if selected then MoveUnderline(button, animate) end
    end
    ns.db.lastPage = id
end

local function FitTabPad()
    local textWidth = 0
    for _, button in ipairs(tabButtons) do textWidth = textWidth + math.ceil(button.text:GetStringWidth()) end
    local spaces = #tabButtons - 1
    local spare = WIDTH - MARGIN * 2 - textWidth - spaces * TAB_GAP
    return math.max(MIN_TAB_PAD, math.min(TAB_PAD, math.floor(spare / (spaces * 2))))
end

local function LayoutTabs()
    tabPad = FitTabPad()
    local x = -tabPad
    for _, button in ipairs(tabButtons) do
        button:SetWidth(math.ceil(button.text:GetStringWidth()) + tabPad * 2)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", x, 0)
        button.offset = x
        x = x + button:GetWidth() + TAB_GAP
    end
    if currentPage then
        for index, entry in ipairs(TABS) do
            if entry.id == currentPage.id then MoveUnderline(tabButtons[index], false) end
        end
    end
end

local function CreateTabs()
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("TOPLEFT", MARGIN, -HEADER_HEIGHT)
    bar:SetPoint("TOPRIGHT", -MARGIN, -HEADER_HEIGHT)
    bar:SetHeight(TABS_HEIGHT)
    window.tabBar = bar
    local baseline = bar:CreateTexture(nil, "BACKGROUND")
    baseline:SetColorTexture(1, 1, 1, 0.05)
    baseline:SetHeight(1)
    baseline:SetPoint("BOTTOMLEFT")
    baseline:SetPoint("BOTTOMRIGHT")
    local line = bar:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(unpack(C.accent))
    line:SetHeight(2)
    window.tabUnderline = line

    for index, entry in ipairs(TABS) do
        local button = CreateFrame("Button", nil, bar)
        button:SetHeight(TABS_HEIGHT)
        button.text = UI.Text(button, T.body, C.muted)
        button.text:SetPoint("CENTER", 0, 1)
        W.Bind(button.text, entry.key)
        button:SetScript("OnClick", function() ShowPage(entry.id, true) end)
        button:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(C.text)) end)
        button:SetScript("OnLeave", function(self)
            if currentPage ~= pages[entry.id] then self.text:SetTextColor(unpack(C.muted)) end
        end)
        tabButtons[index] = button
    end
    LayoutTabs()
    W.AfterLocale(LayoutTabs)
end

local function CreatePreviewToggle(header)
    local toggle = CreateFrame("Button", nil, header)
    toggle:SetHeight(24)
    local switch = W.CreateSwitch(toggle)
    switch:SetPoint("RIGHT")
    local label = UI.Text(toggle, T.label, C.muted)
    label:SetPoint("RIGHT", switch, "LEFT", -8, 0)
    W.Bind(label, "PREVIEW")
    local function Fit() toggle:SetWidth(label:GetStringWidth() + 8 + 26) end
    Fit()
    W.OnLocale(Fit)
    toggle:SetScript("OnClick", function()
        previewStartedHere = not ns.TestMode.active
        ns.TestMode.Toggle()
    end)
    toggle:SetScript("OnEnter", function(self)
        label:SetTextColor(unpack(C.text))
        W.SetSwitchHover(switch, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.PREVIEW_DESC, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function()
        label:SetTextColor(unpack(C.muted))
        W.SetSwitchHover(switch, false)
        GameTooltip:Hide()
    end)
    ns.Listen("TEST_MODE_CHANGED", function(active) W.SetSwitch(switch, active, true) end)
    W.SetSwitch(switch, ns.TestMode.active, false)
    return toggle
end

local function CreateHeader()
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(true)
    W.DragHandle(header, function() window:StartMoving() end, function() window:StopMovingOrSizing() end)

    local glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    glyph:SetPoint("LEFT", MARGIN, -2)
    local title = UI.BoldText(header, T.title, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    title:SetText(ns.TITLE)
    local version = UI.Text(header, T.caption, C.faint)
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 0)
    version:SetText(ns.VERSION)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -MARGIN + 6, -2)
    local cross = UI.Text(close, 18, C.muted)
    cross:SetPoint("CENTER", 0, 1)
    cross:SetText("×")
    close:SetScript("OnClick", Options.Close)
    close:SetScript("OnEnter", function() cross:SetTextColor(unpack(C.text)) end)
    close:SetScript("OnLeave", function() cross:SetTextColor(unpack(C.muted)) end)

    local preview = CreatePreviewToggle(header)
    preview:SetPoint("RIGHT", close, "LEFT", -12, 0)
end

local function CreateAnimations()
    local open = window:CreateAnimationGroup()
    local fadeIn = open:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.16)
    fadeIn:SetSmoothing("OUT")
    local grow = open:CreateAnimation("Scale")
    grow:SetScaleFrom(0.97, 0.97)
    grow:SetScaleTo(1, 1)
    grow:SetDuration(0.18)
    grow:SetSmoothing("OUT")
    window.openAnimation = open

    local close = window:CreateAnimationGroup()
    local fadeOut = close:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.12)
    fadeOut:SetSmoothing("IN")
    close:SetScript("OnFinished", function() window:Hide() end)
    window.closeAnimation = close
end

local function CreateWindow()
    window = CreateFrame("Frame", "RePotionOptionsFrame", UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:Hide()
    UI.Fill(window, C.window)
    tinsert(UISpecialFrames, window:GetName())

    CreateHeader()
    CreateTabs()

    local body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", MARGIN - CONTENT_INSET, -HEADER_HEIGHT - TABS_HEIGHT - BODY_GAP)
    body:SetPoint("BOTTOMRIGHT", -MARGIN + CONTENT_INSET, MARGIN)
    window.body = body

    CreateAnimations()
    window:SetScript("OnHide", function()
        if previewStartedHere then
            ns.TestMode.Stop()
            previewStartedHere = false
        end
        ns.Fire("OPTIONS_SHOWN", false)
    end)
end

function Options.IsOpen()
    return window ~= nil and window:IsShown()
end

function Options.Open(pageId)
    if not window then CreateWindow() end
    window.closeAnimation:Stop()
    if not window:IsShown() then
        window:Show()
        window.openAnimation:Restart()
        ns.Fire("OPTIONS_SHOWN", true)
    end
    ShowPage(pageId or currentPage and currentPage.id or ns.db.lastPage or DEFAULT_PAGE, false)
end

function Options.Close()
    if not window or not window:IsShown() then return end
    window.openAnimation:Stop()
    window.closeAnimation:Restart()
end

function Options.Toggle(pageId)
    if window and window:IsShown() and (not pageId or currentPage == pages[pageId]) then
        Options.Close()
    else
        Options.Open(pageId)
    end
end

ns.Listen("SETTING_CHANGED", function()
    if window and window:IsShown() and currentPage then
        RefreshPage(currentPage, true)
    end
end)

local function RegisterSettingsCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    panel:Hide()
    local glyph = UI.AddonGlyph(panel, SETTINGS_GLYPH_HEIGHT)
    glyph:SetPoint("TOPLEFT", 16, -16)
    local title = UI.Text(panel, 20, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    title:SetText(ns.TITLE)
    local desc = UI.Text(panel, T.body, C.muted)
    desc:SetPoint("TOPLEFT", glyph, "BOTTOMLEFT", 0, -10)
    W.Bind(desc, "SETTINGS_DESC")
    local open = W.Button(panel, "SETTINGS_OPEN", function() Options.Open() end, "primary")
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    local category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
end

ns.Listen("LOGIN", RegisterSettingsCategory)
