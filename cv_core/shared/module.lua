GSC = GSC or {}
GSC.modules = GSC.modules or {}

---o[ Fetch or create a namespace ]o---
function GSC.module(name)
    local existing = GSC.modules[name]
    if existing then return existing end

    local created = {}
    GSC.modules[name] = created
    GSC[name] = created

    return created
end

---o[ What is loaded ]o---
function GSC.moduleList()
    local names = {}
    for name in pairs(GSC.modules) do names[#names + 1] = name end
    table.sort(names)
    return names
end

---o[ Runtime check that everything registered ]o---
RegisterCommand('gscmodules', function()
    local names = GSC.moduleList()
    print(("^2[GSC]^7 %d modules loaded: %s"):format(#names, table.concat(names, ", ")))
end, false)
