local _, ns = ...

local Macros = {}
ns.Macros = Macros

local ICON = 134400
local TOOLTIP_LINE = "#showtooltip"
local NAMES = { health = "RePotion Health", mana = "RePotion Mana", freeAction = "RePotion Action" }
local CHARACTER, ACCOUNT = true, false

function Macros.Name(potionType)
    return NAMES[potionType.key]
end

local function Index(potionType)
    local index = GetMacroIndexByName(NAMES[potionType.key])
    if index and index > 0 then return index end
end

function Macros.Exists(potionType)
    return Index(potionType) ~= nil
end

local function Body(record)
    local text = record.active.text
    if not text then return TOOLTIP_LINE end
    return TOOLTIP_LINE .. "\n" .. text
end

local function Sync(record)
    local index = Index(record.type)
    if not index then return end
    local body = Body(record)
    if GetMacroBody(index) ~= body then EditMacro(index, nil, nil, body) end
end

local function SyncAll()
    if InCombatLockdown() then return end
    for _, record in pairs(ns.Picker.records) do
        Sync(record)
    end
end

local function HasRoom(perCharacter)
    local account, character = GetNumMacros()
    local limits = Constants.MacroConsts
    if perCharacter then return character < limits.MAX_CHARACTER_MACROS end
    return account < limits.MAX_ACCOUNT_MACROS
end

local function Create(record)
    local name, body = NAMES[record.type.key], Body(record)
    for _, perCharacter in ipairs({ CHARACTER, ACCOUNT }) do
        if HasRoom(perCharacter) then
            CreateMacro(name, ICON, body, perCharacter)
            return Index(record.type)
        end
    end
end

function Macros.Pickup(potionType)
    if InCombatLockdown() then
        ns.Print(ns.L.MACRO_COMBAT)
        return false
    end
    local record = ns.Picker.records[potionType.key]
    if Index(potionType) then Sync(record) end
    local index = Index(potionType) or Create(record)
    if not index then
        ns.Print(ns.L.MACRO_FULL)
        return false
    end
    PickupMacro(index)
    return true
end

ns.Listen("PICKS_APPLIED", SyncAll)
