local _, ns = ...

SLASH_REPOTION1 = "/potions"
SLASH_REPOTION2 = "/repotion"
SlashCmdList.REPOTION = function()
    ns.Options.Toggle()
end

function RePotion_OnAddonCompartmentClick()
    ns.Options.Toggle()
end
