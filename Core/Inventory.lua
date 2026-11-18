local _, ns = ...

local Catalog = ns.Catalog
local GetItemCount = C_Item.GetItemCount

local Inventory = { bags = {}, total = {}, mail = {} }
ns.Inventory = Inventory

local bags, total, mail = Inventory.bags, Inventory.total, Inventory.mail

local function Arrived(item, grown)
    local waiting = mail[item]
    if not waiting or grown <= 0 then return end
    mail[item] = waiting > grown and waiting - grown or nil
end

local function Recount()
    local changed = false
    for item in pairs(Catalog.byItem) do
        local inBags = GetItemCount(item, false) or 0
        local everywhere = GetItemCount(item, true, false, false, true) or inBags
        if bags[item] ~= inBags or total[item] ~= everywhere then
            if total[item] then Arrived(item, everywhere - total[item]) end
            bags[item], total[item] = inBags, everywhere
            changed = true
        end
    end
    if changed then ns.Fire("INVENTORY_CHANGED") end
end
Inventory.Recount = Recount

function Inventory.Count(item)
    return bags[item] or 0
end

function Inventory.BankCount(item)
    return math.max(0, (total[item] or 0) - (bags[item] or 0))
end

function Inventory.TotalCount(item)
    return total[item] or 0
end

function Inventory.MailCount(item)
    return mail[item] or 0
end

function Inventory.AddBought(item, quantity, countBefore)
    local arrived = math.max(0, Inventory.TotalCount(item) - countBefore)
    local waiting = quantity - arrived
    if waiting <= 0 then return end
    mail[item] = Inventory.MailCount(item) + waiting
    ns.Fire("INVENTORY_CHANGED")
end

function Inventory.Cooldown(item)
    local start, duration = C_Container.GetItemCooldown(item)
    if ns.IsSecret(start) or ns.IsSecret(duration) then return 0, 0 end
    return start or 0, duration or 0
end

function Inventory.StockTarget(potionType)
    return ns.db[potionType.stockKey]
end

function Inventory.Choices(potionType, level, out)
    wipe(out)
    local floor = Catalog.EffectiveFloor(potionType, level)
    local potions = potionType.potions
    for index = #potions, 1, -1 do
        local potion = potions[index]
        if potion.market and Catalog.IsOffered(potion, level, floor) then out[#out + 1] = potion end
    end
    if #out == 0 then out[1] = Catalog.StrongestUsable(potionType, level, true) end
    return out
end

local choices = {}

function Inventory.StockPotion(potionType, level)
    Inventory.Choices(potionType, level or UnitLevel("player"), choices)
    local picked = ns.charDB.buyPicks[potionType.key]
    for _, potion in ipairs(choices) do
        if potion.item == picked then return potion end
    end
    return choices[1]
end

function Inventory.Counts(potion, grade)
    return grade ~= nil and potion.amount >= grade.amount
end

function Inventory.Counted(potionType, level, grade, out)
    wipe(out)
    local potions = potionType.potions
    for index = #potions, 1, -1 do
        local potion = potions[index]
        if Catalog.IsUsable(potion, level) and Inventory.Counts(potion, grade) then out[#out + 1] = potion end
    end
    return out
end

local counted = {}

function Inventory.StockCount(potionType, grade)
    local level = UnitLevel("player")
    grade = grade or Inventory.StockPotion(potionType, level)
    local inBags, inBank, inMail = 0, 0, 0
    for _, potion in ipairs(Inventory.Counted(potionType, level, grade, counted)) do
        inBags = inBags + Inventory.Count(potion.item)
        inBank = inBank + Inventory.BankCount(potion.item)
        inMail = inMail + Inventory.MailCount(potion.item)
    end
    return inBags, inBank, inMail
end

function Inventory.Stock(potionType, grade)
    local have, bank, inMail = Inventory.StockCount(potionType, grade)
    if not ns.db.countBank then bank = 0 end
    local need = Inventory.StockTarget(potionType) - have - bank - inMail
    return { have = have, bank = bank, mail = inMail, need = need }
end

function Inventory.GetShoppingList(out)
    wipe(out)
    local level = UnitLevel("player")
    for _, potionType in ipairs(Catalog.types) do
        if Catalog.IsActive(potionType) then
            local potions = Inventory.Choices(potionType, level, {})
            local stocks = {}
            for index, potion in ipairs(potions) do
                stocks[index] = Inventory.Stock(potionType, potion)
            end
            if stocks[1] and stocks[1].need > 0 then
                out[#out + 1] = { type = potionType, potions = potions, stocks = stocks }
            end
        end
    end
    return out
end

local MAIL_ATTACHMENTS = 16
local inbox = {}

local function CountInbox()
    wipe(inbox)
    for index = 1, GetInboxNumItems() do
        local _, _, _, _, _, cod, _, attachments = GetInboxHeaderInfo(index)
        if attachments and attachments > 0 and (cod or 0) == 0 then
            for slot = 1, MAIL_ATTACHMENTS do
                local _, item, _, count = GetInboxItem(index, slot)
                if item and total[item] then inbox[item] = (inbox[item] or 0) + count end
            end
        end
    end
end

local function OnInboxUpdate()
    Recount()
    CountInbox()
    local changed = false
    for item, count in pairs(inbox) do
        if count > Inventory.MailCount(item) then
            mail[item] = count
            changed = true
        end
    end
    if changed then ns.Fire("INVENTORY_CHANGED") end
end

ns.Listen("LOGIN", function()
    ns.RegisterEvent("BAG_UPDATE_DELAYED", Recount)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", Recount)
    ns.RegisterEvent("BANKFRAME_CLOSED", Recount)
    ns.RegisterEvent("MAIL_INBOX_UPDATE", OnInboxUpdate)
    Recount()
end)
