local Mash = GSC.module('Mash')

---oo[ Freshness ]oo---

---o[ The picked-at time to stamp on something handed out now ]o---
function Mash.Stamp(now)
    local step = math.max(1, (Config.Freshness.StampMinutes or 30) * 60)
    return math.floor((now or os.time()) / step) * step
end

---o[ 0 (fresh) .. 1 (stale) ]o---
function Mash.Staleness(picked, now)
    local conf = Config.Freshness
    picked = tonumber(picked)
    if not conf.Enabled or not picked then return 0.0 end

    local minutes = math.max(0, (now or os.time()) - picked) / 60.0
    if minutes <= conf.FreshMinutes then return 0.0 end
    if minutes >= conf.StaleMinutes then return 1.0 end
    return (minutes - conf.FreshMinutes) / math.max(1, conf.StaleMinutes - conf.FreshMinutes)
end

---o[ Does any recipe count this item as going stale? ]o---
local perishable = nil -- [item] = true, built on first use

local function IsPerishable(itemName)
    if not perishable then
        perishable = {}
        for _, recipe in pairs(Config.Recipes) do
            for _, ing in ipairs(recipe.ingredients or {}) do
                if type(ing) == 'table' and ing.item and ing.perishable then perishable[ing.item] = true end
            end
        end
    end
    return perishable[itemName] == true
end

---o[ The metadata a freshly picked item is handed out with ]o---
function Mash.PickedMetadata(itemName)
    if not (Config.Freshness.Enabled and IsPerishable(itemName)) then return nil end

    return {
        picked = Mash.Stamp(),
        description = Config.Text.FreshPickedDescription,
    }
end

---oo[ Coconut Water In The Satchel ]oo---

---o[ Every coconut_water and filled_pot the player carries, freshest first ]o---
function Mash.CoconutStacks(src)
    local conf = Config.CoconutBucketConf
    local stacks, totalMl = {}, 0

    for _, item in ipairs(exports.vorp_inventory:getUserInventoryItems(src) or {}) do
        local isWaterItem = item.name == conf.CoconutWaterItem or item.name == conf.FilledPotItem
        local ml = isWaterItem and item.metadata and tonumber(item.metadata.ml) or 0
        if ml > 0 then
            stacks[#stacks + 1] = {
                id = item.id, name = item.name, count = item.count, ml = ml,
                metadata = item.metadata, picked = tonumber(item.metadata.picked),
            }
            totalMl = totalMl + ml * item.count
        end
    end

    table.sort(stacks, function(a, b) return (a.picked or math.huge) > (b.picked or math.huge) end)

    return stacks, totalMl
end

---o[ Take usageMl out of those stacks, in the same order Evaluate counted them ]o---
function Mash.UseCoconut(src, stacks, usageMl)
    local conf = Config.CoconutBucketConf
    local remaining = usageMl

    for _, stack in ipairs(stacks) do
        local isPot = stack.name == conf.FilledPotItem

        for _ = 1, stack.count do
            if remaining <= 0 then return end

            if stack.ml <= remaining then
                if exports.vorp_inventory:subItemById(src, stack.id, nil, nil, 1) and isPot then
                    exports.vorp_inventory:addItem(src, conf.RequiredPotItem, 1)
                end
                remaining = remaining - stack.ml
            else
                local leftMl = stack.ml - remaining
                local metadata = {}
                for k, v in pairs(stack.metadata) do metadata[k] = v end
                metadata.ml = leftMl
                metadata.label = string.format("Coconut Water (%dml)", leftMl)
                metadata.description = isPot
                    and string.format("A pot filled with %dml of fresh coconut water.", leftMl)
                    or string.format("%dml of fresh coconut water.", leftMl)

                exports.vorp_inventory:setItemMetadata(src, stack.id, metadata, 1)
                return
            end
        end
    end
end

---oo[ The Recipe Book: Which Recipes A Player Knows ]oo---

function Mash.Knows(src, recipeKey)
    local recipe = Config.Recipes[recipeKey]
    if not recipe then return false end
    if not recipe.recipeItem then return true end
    return (tonumber(exports.vorp_inventory:getItemCount(src, nil, recipe.recipeItem)) or 0) > 0
end

---o[ Recipe cards: use one from the satchel to read its recipe ]o---
if (Config.RecipeBook or {}).CardsUsable ~= false then
    local cardRecipe = {}
    local keys = {}
    for key in pairs(Config.Recipes) do keys[#keys + 1] = key end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local item = Config.Recipes[key].recipeItem
        if item and not cardRecipe[item] then
            cardRecipe[item] = key
            exports.vorp_inventory:registerUsableItem(item, function(data)
                local src = data.source
                if not Shared.GetChar(src) then return end
                exports.vorp_inventory:closeInventory(src)
                TriggerClientEvent('gsc_kassippu:client:readRecipeCard', src, cardRecipe[item])
            end)
        end
    end
end

---o[ The tabs of this player's book, in order ]o---
function Mash.KnownRecipes(src, uid)
    local loaded = uid and GSC.Distillery.LoadedRecipe(uid)
    local known = {}

    for key in pairs(Config.Recipes) do
        if key == loaded or Mash.Knows(src, key) then known[#known + 1] = key end
    end

    table.sort(known, function(a, b)
        local ra, rb = Config.Recipes[a], Config.Recipes[b]
        if (ra.recipeItem == nil) ~= (rb.recipeItem == nil) then return ra.recipeItem == nil end
        if a == Config.DefaultRecipe or b == Config.DefaultRecipe then return a == Config.DefaultRecipe end
        return (ra.label or a) < (rb.label or b)
    end)

    return known
end

---oo[ Products ]oo---

---o[ A recipe's strength tier, by key ]o---
function Mash.Strength(recipeKey, key)
    local recipe = Config.Recipes[recipeKey]
    if not recipe or not key then return nil end

    for _, tier in ipairs(recipe.strengths or {}) do
        if tier.key == key then return tier end
    end
    return nil
end

---o[ "Strong Kassippu" - or just the recipe, with no strength ]o---
function Mash.ProductLabel(recipeKey, strengthKey)
    local recipe = Config.Recipes[recipeKey]
    local recipeLabel = recipe and recipe.label or tostring(recipeKey)
    local strength = Mash.Strength(recipeKey, strengthKey)

    if not strength or (recipe and recipe.secondRun) then return recipeLabel end
    return string.format(Config.Text.ProductLabel, strength.label or strength.key, recipeLabel)
end

---oo[ First-Run Spirit, For The Second Runs ]oo---

local GRADE_RANK = { NORMAL = 1, GOOD = 2, PERFECT = 3 }

local SpiritByItem = nil

local function SpiritLookup()
    if SpiritByItem then return SpiritByItem end
    SpiritByItem = {}

    local keys = {}
    for key, recipe in pairs(Config.Recipes) do
        if not recipe.secondRun then keys[#keys + 1] = key end
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local recipe = Config.Recipes[key]
        local qualities = {}
        for quality in pairs(recipe.rewards or {}) do qualities[#qualities + 1] = quality end
        table.sort(qualities, function(a, b) return (GRADE_RANK[a] or 0) > (GRADE_RANK[b] or 0) end)

        for _, quality in ipairs(qualities) do
            local reward = recipe.rewards[quality]
            if reward.item and not SpiritByItem[reward.item] then
                SpiritByItem[reward.item] = { recipe = key, quality = quality }
            end
        end
        for _, strength in ipairs(recipe.strengths or {}) do
            if strength.item and not SpiritByItem[strength.item] then
                SpiritByItem[strength.item] = { recipe = key, quality = "NORMAL" }
            end
        end
    end
    return SpiritByItem
end

---o[ Is this stack a bottle of first-run spirit, and of what? ]o---
local function SpiritOf(entry)
    local meta = entry.metadata or {}
    if meta.aged or meta.soured then return "aged" end

    local recipe = meta.recipe and Config.Recipes[meta.recipe]
    if recipe and not recipe.secondRun and meta.quality then
        return { recipe = meta.recipe, quality = meta.quality, tainted = meta.tainted == true }
    end

    local known = SpiritLookup()[tostring(entry.name or "")]
    if known then return { recipe = known.recipe, quality = known.quality, tainted = false } end
    return nil
end

---o[ A recipe's ingredients, by item name ]o---
local function RecipeIngredients(recipe)
    local list = {}
    for _, ing in ipairs(recipe.ingredients or {}) do
        if type(ing) == 'table' and ing.item then list[ing.item] = ing end
    end
    return list
end

local function BatchIngredient(recipe)
    for _, ing in ipairs(recipe.ingredients or {}) do
        if type(ing) == 'table' and ing.item and ing.batch then return ing end
    end
    return nil
end

local function BatchName(n)
    local names = Config.Text.BatchNames or {}
    return names[n] or (tostring(n) .. "x")
end

local function Capitalise(text)
    return (tostring(text):gsub("^%l", string.upper))
end

---oo[ The Evaluation ]oo---

---o[ Everything about the batch in this barrel ]o---
function Mash.Evaluate(recipeKey, stored, coconutStacks, now)
    local T = Config.Text
    local S = T.MashSlip or {}
    local conf = Config.Mash or {}
    local recipe = Config.Recipes[recipeKey]

    local result = {
        recipe = recipeKey, ok = false, problems = {}, warnings = {}, lines = {},
        title = S.Title, legend = S.Legend, fixTitle = S.FixTitle,
    }
    local problems = result.problems

    if not recipe then
        problems[1] = T.RecipeDataLost
        return result
    end

    ---o[ Tally the barrel against the recipe's own ingredients ]o---
    local listed = RecipeIngredients(recipe)
    local takesSpirit = (tonumber(recipe.spiritPerBatch) or 0) > 0
    local totals = { batch = 0, sugar = 0, fruit = 0, spirit = 0 }
    local counted = {} -- [item] = how many of it are in
    local staleSum, staleWeight = 0.0, 0
    local anything, refused = false, {}
    local spiritBonusSum, spiritRankSum = 0.0, 0

    for _, entry in pairs(stored or {}) do
        local name = tostring(entry.name or "")
        local count = tonumber(entry.count) or tonumber(entry.amount) or 0

        if count > 0 then
            anything = true
            local ing = listed[name]
            local spirit = (not ing and takesSpirit) and SpiritOf(entry) or nil
            local label = (ing and ing.label) or (entry.metadata and entry.metadata.label) or entry.label or name

            if ing then
                ---o[ One of the recipe's ingredients ]o---
                counted[name] = (counted[name] or 0) + count
                if ing.batch then totals.batch = totals.batch + count end
                totals.sugar = totals.sugar + count * (tonumber(ing.sugar) or 0)
                totals.fruit = totals.fruit + count * (tonumber(ing.flavour) or 0)

                if ing.perishable then
                    local meta = entry.metadata or {}
                    staleSum = staleSum + Mash.Staleness(meta.picked, now) * count
                    staleWeight = staleWeight + count
                end
            elseif spirit == "aged" then
                ---o[ A second run: an aged or turned bottle ]o---
                if not refused[name] then
                    refused[name] = true
                    problems[#problems + 1] = string.format(T.MashSpiritAged, label)
                end
            elseif spirit and spirit.recipe == recipe.spiritOf then
                ---o[ A second run: first-run spirit of the right kind ]o---
                local rank = GRADE_RANK[spirit.quality] or 1
                if rank < (GRADE_RANK[recipe.minGrade or "NORMAL"] or 1) then
                    if not refused[name .. spirit.quality] then
                        refused[name .. spirit.quality] = true
                        problems[#problems + 1] = string.format(T.MashSpiritTooRough, label)
                    end
                else
                    totals.spirit = totals.spirit + count
                    spiritRankSum = spiritRankSum + rank * count
                    spiritBonusSum = spiritBonusSum + ((recipe.spiritBonus or {})[spirit.quality] or 0) * count
                    if spirit.tainted then result.tainted = true end
                end
            elseif not refused[name] then
                ---o[ Not on the recipe's list ]o---
                refused[name] = true
                problems[#problems + 1] = string.format(T.MashNotForRecipe, label, recipe.label)
            end
        end
    end

    if not anything then
        problems[1] = T.MashEmpty
        return result
    end

    ---o[ The batch size ]o---
    local maxBatch = conf.MaxBatch or 3
    local batchIng = BatchIngredient(recipe)
    local batches = 1

    if batchIng then
        local batchLabel = batchIng.label or batchIng.item
        batches = totals.batch
        if batches < 1 then
            problems[#problems + 1] = string.format(T.MashNoWater, batchLabel)
        elseif batches > maxBatch then
            problems[#problems + 1] = string.format(T.MashTooMuchWater, batchLabel, maxBatch)
        end
    end

    local batch = math.max(1, math.min(maxBatch, batches))
    result.batch = batch

    ---o[ What every batch needs ]o---
    for _, ing in ipairs(recipe.ingredients or {}) do
        local needed = type(ing) == 'table' and ing.item and (tonumber(ing.amount) or 0) * batch or 0
        local have = needed > 0 and counted[ing.item] or 0
        if needed > 0 and not ing.batch and have < needed then
            problems[#problems + 1] = string.format(T.MashNeedMore, needed - have, ing.label or ing.item,
                BatchName(batch), needed)
        end
    end

    if takesSpirit then
        local needed = recipe.spiritPerBatch * batch
        if totals.spirit < needed then
            problems[#problems + 1] = string.format(T.MashNeedMore, needed - totals.spirit,
                recipe.spiritLabel or "bottles", BatchName(batch), needed)
        end
    end

    ---o[ Coconut water from the satchel ]o---
    local coconutMl = (tonumber(recipe.coconutMl) or 0) * batch
    result.coconutMl = coconutMl

    if coconutMl > 0 then
        local have, used, staleMl = 0, 0, 0.0

        for _, stack in ipairs(coconutStacks or {}) do
            for _ = 1, stack.count do
                have = have + stack.ml
                if used < coconutMl then
                    local take = math.min(stack.ml, coconutMl - used)
                    used = used + take
                    staleMl = staleMl + Mash.Staleness(stack.picked, now) * take
                end
            end
        end

        if have < coconutMl then
            problems[#problems + 1] = string.format(T.MashNeedCoconut, coconutMl, have)
        else
            staleSum = staleSum + (staleMl / coconutMl) * batch
            staleWeight = staleWeight + batch
        end

        totals.sugar = totals.sugar + (recipe.coconutSugar or 0) * batch
        result.lines[#result.lines + 1] = { S.Coconut, string.format("%d / %dml", math.min(have, coconutMl), coconutMl) }
    end

    ---o[ Sugar: the strength ]o---
    local strengths = recipe.strengths or {}
    local sugarPer = totals.sugar / batch
    local strength = nil

    for _, tier in ipairs(strengths) do
        if sugarPer >= (tier.sugar or 0) then
            strength = tier
            break
        end
    end

    if sugarPer < (recipe.minSugar or 0) or (not strength and #strengths > 0) then
        problems[#problems + 1] = string.format(T.MashNeedSugar, recipe.minSugar or 1)
        strength = nil
    end
    result.strength = strength and strength.key or nil

    ---o[ Fruit: the quality, until it clogs ]o---
    local fruitPer = totals.fruit / batch
    local fruitBonus = math.min(fruitPer, conf.FruitBest or 2) * (conf.FruitBonusPer or 0)
    local over = math.max(0, fruitPer - (conf.FruitMax or math.huge))

    result.clog = over * batch * (conf.ClogResidue or 0)
    if over > 0 then result.warnings[#result.warnings + 1] = T.MashTooMuchFruit end

    ---o[ Freshness ]o---
    local stale = staleWeight > 0 and (staleSum / staleWeight) or 0.0
    local stalePenalty = stale * (Config.Freshness.MaxPenalty or 0)

    local spiritBonus = totals.spirit > 0 and (spiritBonusSum / totals.spirit) or 0.0

    result.scoreMod = math.floor(fruitBonus - stalePenalty + spiritBonus + 0.5)
    result.fruit = fruitBonus
    result.stale = stale

    ---o[ What it makes ]o---
    result.product = Mash.ProductLabel(recipeKey, result.strength)

    local fewest, most = math.huge, 0
    for _, reward in pairs(recipe.rewards or {}) do
        local count = (reward.count or 1) * batch
        fewest, most = math.min(fewest, count), math.max(most, count)
    end
    if fewest == math.huge then fewest = 0 end
    result.bottlesMin, result.bottlesMax = fewest, most

    ---o[ The slip, in plain words ]o---
    local fruitText
    local bonusShown = math.floor(fruitBonus + 0.5)
    if fruitPer <= 0 then
        fruitText = S.FruitNone
    elseif over > 0 then
        fruitText = string.format(S.FruitTooMuch, bonusShown)
    elseif fruitPer >= (conf.FruitBest or 2) then
        fruitText = string.format(S.FruitBest, bonusShown)
    else
        fruitText = string.format(S.FruitSome, bonusShown)
    end

    table.insert(result.lines, 1, { S.Batch, string.format("%s (%dx)", Capitalise(BatchName(batch)), batch) })
    table.insert(result.lines, 2, { S.Strength, strength and (strength.label or strength.key) or "-" })
    local takesFruit = false
    for _, ing in pairs(listed) do
        if (tonumber(ing.flavour) or 0) > 0 then takesFruit = true end
    end
    if takesFruit then
        table.insert(result.lines, 3, { S.Fruit, fruitText })
    end
    if takesSpirit and totals.spirit > 0 then
        local average = spiritRankSum / totals.spirit
        local grade = average >= 2.75 and "PERFECT" or average >= 1.5 and "GOOD" or "NORMAL"
        local gradeLabel = (Config.Product.Qualities[grade] or {}).label or grade
        table.insert(result.lines, 3, { S.Spirit, string.format(S.SpiritText, totals.spirit, gradeLabel) })
    end

    if staleWeight > 0 then
        local freshText
        local penaltyShown = -math.floor(stalePenalty + 0.5)
        if stale < 0.05 then
            freshText = S.Fresh
        elseif stale < 0.6 then
            freshText = string.format(S.Aging, penaltyShown)
        else
            freshText = string.format(S.Stale, penaltyShown)
        end
        table.insert(result.lines, 4, { S.Freshness, freshText })
    end

    result.ok = #problems == 0
    result.outcomeLabel = S.Outcome
    result.outcome = string.format(S.OutcomeText, fewest, most, result.product)
    result.note = result.ok and S.OutcomeNote or nil
    result.readyText = S.Ready

    return result
end

---oo[ The Recipe Book's Live Preview ]oo---
local LastPreview = {} -- [src] = game timer of their last ask
local LastBookOpen = {}

RegisterServerEvent('gsc_kassippu:server:previewMix')
AddEventHandler('gsc_kassippu:server:previewMix', function(uid, recipeKey)
    local _source = source
    if type(uid) ~= 'string' or type(recipeKey) ~= 'string' or not Config.Recipes[recipeKey] then return end

    local pos = GSC.Distillery.Position(uid)
    if not pos or not Shared.GetChar(_source) then return end

    local now = GetGameTimer()
    if LastPreview[_source] and now - LastPreview[_source] < 400 then return end
    LastPreview[_source] = now

    if not GSC.BarrelCrew.Can(_source, uid, "ingredients") or not Mash.Knows(_source, recipeKey) then return end

    if #(GetEntityCoords(GetPlayerPed(_source)) - pos) > (Config.KasiyaBarrelKitConf.KasiyaBarrelDistance + 5.0) then
        return
    end

    GSC.Distillery.RegisterStash(uid)
    exports.vorp_inventory:getCustomInventoryItems(uid, function(stored)
        local stacks = (tonumber(Config.Recipes[recipeKey].coconutMl) or 0) > 0 and Mash.CoconutStacks(_source) or nil
        local result = Mash.Evaluate(recipeKey, stored, stacks, os.time())
        TriggerClientEvent('gsc_kassippu:client:mixPreview', _source, uid, recipeKey, result)
    end)
end)

---oo[ Opening The Recipe Book ]oo---
RegisterServerEvent('gsc_kassippu:server:openBook')
AddEventHandler('gsc_kassippu:server:openBook', function(uid)
    local _source = source
    if type(uid) ~= 'string' or not GSC.Distillery.Position(uid) or not Shared.GetChar(_source) then return end

    ---o[ Spam guard: every ask counts the recipe cards in the satchel ]o---
    local nowMs = GetGameTimer()
    if LastBookOpen[_source] and nowMs - LastBookOpen[_source] < 1000 then return end
    LastBookOpen[_source] = nowMs

    TriggerClientEvent('gsc_kassippu:client:openBook', _source, uid, Mash.KnownRecipes(_source, uid))
end)

AddEventHandler('playerDropped', function()
    LastPreview[source] = nil
    LastBookOpen[source] = nil
end)
