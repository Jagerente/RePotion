local _, ns = ...

local Catalog = { types = {}, byKey = {}, byItem = {} }
ns.Catalog = Catalog

local PERCENT = 100
local NAME_DELAY = 0.2
local TYPE_DEFS = {
    { key = "health", pool = "health" },
    { key = "mana", pool = "mana" },
    { key = "freeAction", optIn = true },
}
local MANA = Enum.PowerType.Mana

local UnitHealthMax, UnitPowerMax = UnitHealthMax, UnitPowerMax

local function IsGraded(potions)
    for index = 2, #potions do
        if potions[index].amount ~= potions[1].amount then return true end
    end
    return false
end

for index, def in ipairs(TYPE_DEFS) do
    local key = def.key
    local potionType = {
        key = key,
        index = index,
        pool = def.pool,
        optIn = def.optIn,
        potions = ns.POTIONS[key],
        graded = IsGraded(ns.POTIONS[key]),
        floorKey = def.pool and key .. "Floor",
        stockKey = key .. "Stock",
    }
    for _, potion in ipairs(potionType.potions) do
        potion.type = potionType
        Catalog.byItem[potion.item] = potion
    end
    Catalog.types[index] = potionType
    Catalog.byKey[key] = potionType
end

local SETTING_TYPES = {}
for _, potionType in ipairs(Catalog.types) do
    if potionType.floorKey then SETTING_TYPES[potionType.floorKey] = potionType end
    SETTING_TYPES[potionType.stockKey] = potionType
end

function Catalog.TypeOfSetting(key)
    return SETTING_TYPES[key]
end

function Catalog.MaxPool(potionType)
    local value
    if potionType.pool == "health" then
        value = UnitHealthMax("player")
    elseif potionType.pool == "mana" then
        value = UnitPowerMax("player", MANA)
    end
    if value == nil or ns.IsSecret(value) then return nil end
    return value
end

function Catalog.HasPool(potionType)
    if potionType.pool ~= "mana" then return true end
    local max = Catalog.MaxPool(potionType)
    return max == nil or max > 0
end

function Catalog.IsEnabled(potionType)
    local choice = ns.charDB.types[potionType.key]
    if choice == nil then return not potionType.optIn and Catalog.HasPool(potionType) end
    return choice
end

function Catalog.IsActive(potionType)
    return Catalog.HasPool(potionType) and Catalog.IsEnabled(potionType)
end

function Catalog.SetEnabled(potionType, enabled)
    ns.charDB.types[potionType.key] = enabled
    ns.Fire("TYPES_CHANGED")
end

function Catalog.Floor(potionType)
    local max = Catalog.MaxPool(potionType)
    if not max then return 0 end
    return max * ns.db[potionType.floorKey] / PERCENT
end

function Catalog.IsUsable(potion, level)
    return potion.level <= level
end

function Catalog.StrongestUsable(potionType, level, marketOnly)
    local potions = potionType.potions
    for index = #potions, 1, -1 do
        local potion = potions[index]
        if Catalog.IsUsable(potion, level) and (potion.market or not marketOnly) then return potion end
    end
end

function Catalog.EffectiveFloor(potionType, level)
    local floor = Catalog.Floor(potionType)
    local top = Catalog.StrongestUsable(potionType, level)
    if top and top.amount < floor then return top.amount end
    return floor
end

function Catalog.IsOffered(potion, level, floor)
    return Catalog.IsUsable(potion, level) and potion.amount >= floor
end

function Catalog.Name(potion)
    return C_Item.GetItemNameByID(potion.item) or string.format(ns.L.ITEM_LOADING, potion.item)
end

function Catalog.Icon(potion)
    return C_Item.GetItemIconByID(potion.item)
end

function Catalog.Range(potion)
    if not potion.type.pool then return nil end
    if potion.low == potion.high then return tostring(potion.amount) end
    return string.format(ns.L.RANGE, potion.low, potion.high)
end

function Catalog.TypeName(potionType)
    return ns.L["TYPE_" .. potionType.key]
end

local function OnItemLoaded(item)
    if not Catalog.byItem[item] then return end
    ns.Schedule("names", NAME_DELAY, function() ns.Fire("NAMES_CHANGED") end)
end

ns.Listen("LOGIN", function()
    ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
    for item in pairs(Catalog.byItem) do
        C_Item.RequestLoadItemDataByID(item)
    end
end)
