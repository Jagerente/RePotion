local _, ns = ...

local Catalog = ns.Catalog
local Inventory = ns.Inventory

local Picker = { records = {} }
ns.Picker = Picker

local UPDATE_DELAY = 0.1
local USE_LINE = "/use item:%d"

local records = Picker.records
local pending = false

for _, potionType in ipairs(Catalog.types) do
    records[potionType.key] = { type = potionType, owned = {}, active = {} }
end

local function Stronger(candidate, current)
    if not current then return true end
    if candidate.amount ~= current.amount then return candidate.amount > current.amount end
    return current.market and not candidate.market
end

local function Strongest(owned, skip)
    local best
    for _, potion in ipairs(owned) do
        if potion ~= skip and Stronger(potion, best) then best = potion end
    end
    return best
end

local function CollectOwned(record, level)
    local owned = record.owned
    wipe(owned)
    for _, potion in ipairs(record.type.potions) do
        if Catalog.IsUsable(potion, level) and Inventory.Count(potion.item) > 0 then owned[#owned + 1] = potion end
    end
    return owned
end

local function Fallback(record)
    local main = record.main
    if not main or Inventory.Count(main.item) ~= 1 then return nil end
    return Strongest(record.owned, main)
end

local function Body(main, fallback)
    if not main then return nil end
    local text = string.format(USE_LINE, main.item)
    if fallback then text = text .. "\n" .. string.format(USE_LINE, fallback.item) end
    return text
end

local function Compute(record, level)
    local potionType = record.type
    record.main = Strongest(CollectOwned(record, level))
    record.fallback = Fallback(record)
    record.placeholder = Catalog.StrongestUsable(potionType, level, true) or Catalog.StrongestUsable(potionType, level)
    record.text = Body(record.main or record.placeholder, record.fallback)
end

local function Activate(record)
    local active = record.active
    active.main, active.fallback = record.main, record.fallback
    active.placeholder, active.text = record.placeholder, record.text
end

function Picker.Shown(record)
    local active = record.active
    return active.main or active.placeholder
end

function Picker.Update()
    local level = UnitLevel("player")
    for _, record in pairs(records) do
        Compute(record, level)
    end
    if InCombatLockdown() then
        pending = true
    else
        pending = false
        for _, record in pairs(records) do
            Activate(record)
        end
        ns.Fire("PICKS_APPLIED")
    end
    ns.Fire("PICKS_CHANGED")
end

function Picker.UpdateSoon()
    ns.Schedule("picks", UPDATE_DELAY, Picker.Update)
end

for _, message in ipairs({ "INVENTORY_CHANGED", "TYPES_CHANGED" }) do
    ns.Listen(message, Picker.UpdateSoon)
end

ns.Listen("SETTING_CHANGED", function(key)
    if key == nil or Catalog.TypeOfSetting(key) then Picker.UpdateSoon() end
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("PLAYER_LEVEL_UP", Picker.UpdateSoon)
    ns.RegisterUnitEvent("UNIT_MAXHEALTH", "player", Picker.UpdateSoon)
    ns.RegisterUnitEvent("UNIT_MAXPOWER", "player", Picker.UpdateSoon)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pending then Picker.Update() end
    end)
    Picker.Update()
end)
