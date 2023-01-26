local TEST, CASE, CHECK, FINISH = require("test/testkit").getUnitTestTools()

--[[local function printt(t: {})
    if next(t) then
        print("{")
        for i, v in next, t do
            print(string.format(
                "    [%s]: %s",
                tostring(i),
                tostring(v)
            ))
        end
        print("}")
    else
        print("{}")
    end
end]]

local ecr = require "src/ecr"

local A, B, C, D = ecr.component(), ecr.component(), ecr.component(), ecr.component()
local E, F, G, H = ecr.component(), ecr.component(), ecr.component(), ecr.component(function() return true end)

TEST("registry:create()", function()
    local N = 1e3

    do CASE "New ids unique"
        local reg = ecr.registry()
        local cache = {}

        for i = 1, N do
            local id = reg:create()
            CHECK(not cache[id])
            cache[id] = true
        end
    end

    do CASE "Reused ids unique"
        local reg = ecr.registry()
        local cache = {}

        for i = 1, N do
            local e = reg:create()
            cache[e] = true
        end

        for e in cache do
            reg:release(e)
        end

        for i = 1, N do -- reuse all ids
            local id = reg:create()
            CHECK(not cache[id])
            cache[id] = true
        end
    end

    do CASE "Create entity with identifier"
        local entities = {}

        local sreg = ecr.registry()

        for i = 1, N do
            entities[i] = sreg:create()   
        end

         -- mix array of entities
         local mixed = table.clone(entities)
         for i = 1, N do
             local a = math.random(1, N)
             local b = math.random(1, N)
             mixed[a], mixed[b] = mixed[b], mixed[a]
         end

        local reg = ecr.registry()

        for i = 1, N do
            reg:create(mixed[i])
        end

        for i = 1, N do
            CHECK(reg:valid(entities[i]))
        end
    end

    do CASE "Error if identifier is already in use"
        local sreg = ecr.registry()
        local id = sreg:create()

        local reg = ecr.registry()
        reg:create()

        local ok = pcall(function()
            reg:create(id)
        end)

        CHECK(not ok)
    end

    do CASE "Error if `null` is used"
        local reg = ecr.registry()
        reg:create()

        local ok = pcall(function()
            reg:create(ecr.null)
        end)

        CHECK(not ok)
    end
end)

TEST("registry:release()", function()
    local reg = ecr.registry()

    do CASE "Released entities are no longer valid"
        local id = reg:create()
        reg:release(id)
        CHECK(not reg:valid(id))
    end
end)

TEST("registry:valid()", function()
    local reg = ecr.registry()

    local id = reg:create()

    do CASE "New entity valid"
        CHECK(reg:valid(id))
    end

    reg:release(id)

    do CASE "Released entity invalid"
        CHECK(not reg:valid(id))
    end

    do CASE "Reused entity key valid"
        id = reg:create()
        CHECK(reg:valid(id))
    end

    do CASE "Integer key invalid"
        CHECK(not reg:valid(1))
    end

    do CASE "Null entity invalid"
        CHECK(not reg:valid(ecr.null))
    end
end)

TEST("registry:version()", function()
    local reg = ecr.registry()

    do CASE "Gets correct version"
        local id = reg:create()
        CHECK(reg:version(id) == 1)
    end

    do CASE "Version increments on reuse"
        local id_old = reg:create()
        CHECK(reg:version(id_old) == 1)
        reg:destroy(id_old)
        local id_new = reg:create()
        CHECK(reg:version(id_old) == 1)
        CHECK(reg:version(id_new) == 2)
    end

    do CASE "Version overflow"
        local reg2 = ecr.registry()
        local MAX_VER = 2^33 - 1
        
        reg2:release( reg2:create() ); -- ensure id internally exists

        (reg2 :: any):setEntityVersion(1, MAX_VER)

        -- verify version was set to max correctly
        local id = reg2:create()
        CHECK(reg2:version(id) == MAX_VER)
        -- trigger version increment
        reg2:release(id)
        
        -- should overflow and reset back to 1
        id = reg2:create()
        CHECK(reg2:version(id) == 1)
    end
end)

TEST("registry:current()", function()
    local reg = ecr.registry()
    local id_old = reg:create()
    reg:release(id_old)
    local id_new = reg:create()

    do CASE "Gets current version"
        CHECK(reg:version(id_old) == 1)
        CHECK(reg:current(id_old) == 2)
    end

    do CASE "Version increments on release"
        reg:release(id_new)
        CHECK(reg:current(id_new) == 3)
    end
end)

TEST("registry:add()", function()
    local reg = ecr.registry()

    local ADD_A = ecr.component(function() return true end)
    local ADD_B = ecr.component(function() return false end)
    local ADD_C = ecr.component(function() return nil end)

    do CASE "Add components"
        local id = reg:create()
        reg:add(id, ADD_A, ADD_B)
        CHECK(reg:has(id, ADD_A))
        CHECK(reg:has(id, ADD_B))
    end

    do CASE "Attempt to add an already-owned component errors"
        local ok = pcall(function()
            local id = reg:create()
            reg:set(id, ADD_A, true)
            reg:add(id, ADD_A)
        end)
        CHECK(not ok)
    end

    do CASE "Add a component with no default value specified errors"
        local ok = pcall(function()
            local id = reg:create()
            reg:add(id, B)
        end)
        CHECK(not ok)
    end

    do CASE "Add a component with no returned value errors"
        local ok = pcall(function()
            local id = reg:create()
            reg:add(id, ADD_C)
        end)
        CHECK(not ok)
    end
end)

TEST("registry:set()", function()
    local reg = ecr.registry()
    local id = reg:create()

    do CASE "Add component"
        reg:set(id, A, 1)
        CHECK(reg:get(id, A) == 1)
    end

    do CASE "Change component"
        reg:set(id, A, 2)
        CHECK(reg:get(id, A) == 2)
    end
    
    do CASE "Remove component"
        reg:set(id, A, nil)
        CHECK(reg:get(id, A) == nil)
        CHECK(not reg:has(id, A))
    end
end)

TEST("registry:get()", function()
    local reg = ecr.registry()
    local id = reg:create()

    do CASE "Get component"
        reg:set(id, A, 1)
        CHECK(reg:get(id, A) == 1)
    end

    do CASE "Get multiple components"
        reg:set(id, B, 2)
        reg:set(id, C, 3)
        reg:set(id, D, 4)
        reg:set(id, E, 5)

        ;(function(...)
            local argn = select("#", ...)
            CHECK(argn > 0)
            for i = 1, argn do
                CHECK(select(i, ...) == i)
            end
        end)(reg:get(id, A, B, C, D, E))
    end

    do CASE "Get nil component"
        reg:remove(id, A)
        CHECK(reg:get(id, A) == nil)
    end
end)

TEST("registry:has()", function()
    local reg = ecr.registry()
    local id = reg:create()

    do CASE "Has component"
        reg:set(id, A, true)
        CHECK(reg:has(id, A) == true)

        reg:set(id, B, true)
        CHECK(reg:has(id, A, B))
    end

    do CASE "Does not have component"
        reg:set(id, A, nil)
        CHECK(reg:has(id, A) == false)
        CHECK(reg:has(id, B, A) == false)
    end
end)

TEST("registry:patch()", function()
    local reg = ecr.registry()
    local id = reg:create()
    reg:set(id, A, 0)

    do CASE "Change component"
        reg:patch(id, A :: number, function(cur)
            CHECK(cur == 0)
            return cur + 1
        end)
        CHECK(reg:get(id, A) == 1)
    end
end)

TEST("registry:remove()", function()
    local reg = ecr.registry()
    local id = reg:create()
    reg:set(id, A, 1)
    reg:set(id, B, 1)
    reg:set(id, C, 1)

    local id2 = reg:create()
    reg:set(id2, A, 2)

    do CASE "Remove single component"
        reg:remove(id, A)
        CHECK(reg:has(id, A) == false)
        CHECK(reg:get(id2, A) == 2) -- check removal maintains associativity
    end

    do CASE "Remove multiple components"
        reg:remove(id, B, C)
        CHECK(reg:has(id, B) == false)
        CHECK(reg:has(id, C) == false)
    end
end)

TEST("registry:clear()", function()
    do
        local reg = ecr.registry()
        local id1 = reg:create()
        local id2 = reg:create()

        reg:set(id1, A, 1)
        reg:set(id2, A, 2)

        reg:set(id1, B, 1)
        reg:set(id2, B, 2)

        reg:set(id1, C, 1)
        reg:set(id2, C, 2)

        do CASE "Clear A"
            reg:clear(A)
            CHECK(reg:has(id1, A) == false)
            CHECK(reg:has(id2, A) == false)
        end

        do CASE "Clear B and C"
            reg:clear(B, C)
            CHECK(reg:has(id1, B) == false)
            CHECK(reg:has(id2, B) == false)
            CHECK(reg:has(id1, C) == false)
            CHECK(reg:has(id2, C) == false)
        end
    end

    do CASE "Clear entities"
        local N = 1e3
        local reg = ecr.registry()
        local ids = {}

        for i = 1, N do
            ids[i] = reg:create()
        end

        reg:clear()

        local ids2 = {}

        for i = 1, N do
            ids2[i] = reg:create()
        end

        -- check cleared ids were formatted properly by creating a new generation
        for i = 1, N do
            CHECK(reg:version(ids[i]) + 1 == reg:version(ids2[i]))
        end
    end
end)

TEST("registry:orphan()", function()
    local reg = ecr.registry()
    local id = reg:create()

    do CASE "New entity is an orphan"
        CHECK(reg:orphan(id))
    end

    reg:set(id, B, 1)

    do CASE "No longer orphan after assigning component"
        CHECK(not reg:orphan(id))
    end

    reg:set(id, B, nil)

    do CASE "Orphan after removing last component"
        CHECK(reg:orphan(id))
    end
end)

TEST("registry:destroy()", function()
    local reg = ecr.registry()
    local id = reg:create()

    reg:set(id, A, 1)
    reg:set(id, B, 1)

    reg:destroy(id)

    do CASE "Destroyed entity is released"
        CHECK(not reg:valid(id))
    end

    do CASE "Component was removed"
        -- warning: do not rely on this behavior
        CHECK(not reg:has(id, A))
        CHECK(not reg:has(id, B))
    end
end)

TEST("registry:size()", function()
    local reg = ecr.registry()

    do CASE "Initial registry size is 0"
        CHECK(reg:size() == 0)
    end

    local id = reg:create()

    do CASE "Size after entity creation"
        CHECK(reg:size() == 1)
    end

    reg:release(id)

    do CASE "Size after entity release"
        CHECK(reg:size() == 0)
    end

    for i = 1, 100 do reg:create() end

    do CASE "Mass creation"
        CHECK(reg:size() == 100)
    end

    reg:clear()

    do CASE "Size after clear"
        CHECK(reg:size() == 0)
    end

    reg:create(id)

    do CASE "Size after specific entity creation"
        CHECK(reg:size() == 1)
    end
end)

TEST("registry:entities()", function()
    local N = 1e3
    local reg = ecr.registry()

    local ids = {}
    for i = 1, N do
        ids[i] = reg:create()
    end

    -- destroy random entities
    for i = 1, N do
        if math.random() > 0.5 then
            reg:destroy(ids[i])
            ids[i] = nil
        end
    end

    do CASE "All entities are valid"
        local list = reg:entities()

        local cache = {}

        for _, entity in list do
            cache[entity] = true
        end

        for _, entity in ids do
            CHECK(cache[entity])
        end
    end
end)



TEST("registry:view()", function()
    local N = 1e3
    local function flip() return math.random() > 0.3 end
    local function empty(t) return next(t) == nil end
    local function viewids(view: ecr.View<...unknown>): { [ecr.Entity]: { unknown } }
        local cache = {}
    
        for id, a, b, c, d in view do
            cache[id] = { a, b, c, d }
        end

        return cache
    end

    local reg = ecr.registry()

    local ids = {}
    local As = {}
    local Bs = {}
    local Cs = {}
    local ABCs = {}
    local ABnotCs = {}

    for i = 1, N do
        local id = reg:create()
        ids[i] = id

        local has = {}
        for _, component in { A, B, C, D, E, F, G, H } do
            if flip() then
                reg:set(id, component, id)
                has[component] = true
            end
        end

        if has[A] then table.insert(As, id) end
        if has[B] then table.insert(Bs, id) end
        if has[C] then table.insert(Cs, id) end
        if has[A] and has[B] and has[C] then table.insert(ABCs, id) end
        if has[A] and has[B] and not has[C] then table.insert(ABnotCs, id) end
    end

    do CASE "View size"
        CHECK(#reg:view(A) == #As)
        CHECK(#reg:view(B) == #Bs)
        CHECK(#reg:view(A, B, C) >= #ABCs)
        CHECK(#reg:view(A, B):exclude(C) >= #ABnotCs)
    end

    do CASE "View all entities with A"
        local viewed = viewids(reg:view(A))
        CHECK(not empty(viewed))
        for _, id in As do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "View all entities with B"
        local viewed = viewids(reg:view(B))
        CHECK(not empty(viewed))
        for _, id in Bs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "View all entities with ABC"
        local viewed = viewids(reg:view(A, B, C))
        CHECK(not empty(viewed))
        for _, id in ABCs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == id)
        end
    end

    do CASE "View all entities with ABC using C"
        local viewed = viewids(reg:view(A, B, C):use(C))
        CHECK(not empty(viewed))
        for _, id in ABCs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == id)
        end
    end

    do CASE "View all entities with AB and not C"
        local viewed = viewids(reg:view(A, B):exclude(C))
        CHECK(not empty(viewed))
        for _, id in ABnotCs do 
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "Addition during view iteration"
        local cache = {}
        for id, c in reg:view(C) do
            -- check that newly added entities+components are not included in iterations
            CHECK(not cache[id])
            if flip() then -- create new entity+component
                local new = reg:create()
                reg:set(new, C, true)
                table.insert(Cs, id)
                cache[new] = true
            end
        end
    end

    do CASE "Component removal during view iteration"
        local viewed = {}
        for entity in reg:view(A) do
            if flip() then
                reg:remove(entity, A)
            end
            viewed[entity] = true
        end
        CHECK(not empty(viewed))
        for _, entity in As do -- check that an entity isn't skipped
            CHECK(viewed[entity])
        end
    end

    do CASE "Duplicate include errors"
        local ok = pcall(function()
            reg:view(A, B, A)
        end)
        CHECK(not ok)
    end

    do CASE "Exclude an include errors"
        local ok = pcall(function()
            reg:view(A, B):exclude(C, A)
        end)
        CHECK(not ok)
    end
end)

TEST("registry:added()", function()
    local reg = ecr.registry()
    local id = reg:create()

    -- runcount, reg, entity, value
    local cc, ce, cv = 0, nil, nil

    local function fn(...)
        cc += 1
        ce, cv = ...
    end

    local con = reg:added(H):connect(fn)

    CASE "Adding triggers"
    reg:add(id, H)
    CHECK(cc == 1)
    CHECK(ce == id)
    CHECK(cv == true)

    CASE "Changing does not trigger"
    reg:set(id, H, false)
    CHECK(cc == 1)

    CASE "Removing then adding triggers"
    reg:set(id, H, nil)
    reg:set(id, H, true)
    CHECK(cc == 2)

    con:disconnect()

    CASE "Adding after disconnect does not trigger"
    reg:set(id, H, nil)
    reg:set(id, H, true)
    CHECK(cc == 2)
end)

TEST("registry:changed()", function()
    local reg = ecr.registry()
    local id = reg:create()

    local cc, ce, cv = 0, nil, nil

    local function fn(...)
        cc += 1
        ce, cv = ...
    end

    local con = reg:changed(A):connect(fn)

    CASE "Adding does not trigger"
    reg:set(id, A, true)
    CHECK(cc == 0)

    CASE "Changing triggers"
    reg:set(id, A, false)
    CHECK(cc == 1)
    CHECK(ce == id)
    CHECK(cv == false)

    CASE "Removing does not trigger"
    reg:set(id, A, nil)
    CHECK(cc == 1)

    con:disconnect()

    CASE "Changing after disconnect does not trigger"
    reg:set(id, A, true) -- add
    reg:set(id, A, false) -- change
    CHECK(cc == 1)
end)

TEST("registry:removing()", function()
    do
        local reg = ecr.registry()
        local id = reg:create()

        local cc, ce, cv, lv = 0, nil, nil, nil

        local function fn(...)
            cc += 1
            lv = reg:get(id, A) -- get current value
            ce, cv = ...
        end

        local con = reg:removing(A):connect(fn)

        reg:set(id, A, true)

        CASE "Removing triggers"
        reg:set(id, A, nil)
        CHECK(cc == 1)
        CHECK(ce == id)
        CHECK(cv == nil)
        CHECK(lv == true)

        CASE "Removing via destroy"
        reg:set(id, A, false)
        reg:destroy(id)

        CHECK(cc == 2)
        CHECK(ce == id)
        CHECK(cv == nil)
        CHECK(lv == false)

        con:disconnect()

        CASE "Removing after disconnect does not trigger"
        reg:set(id, A, true)
        reg:set(id, A, nil)
        CHECK(cc == 2)
    end

    do CASE "Clearing components fires removing event"
        local reg = ecr.registry()

        local entities = {}

        for i = 1, 1e3 do
            entities[i] = reg:create()
            reg:set(entities[i], A, true)
        end

        local cache = {}

        reg:removing(A):connect(function(entity)
            cache[entity] = true
        end)

        reg:clear(A)

        for _, entity in entities do
            CHECK(cache[entity])
        end
    end
end)

TEST("registry:track()", function()
    local N = 1e3
    local function flip() return math.random() > 0.3 end
    local function empty(t) return next(t) == nil end
    local function viewids(observer: ecr.Observer<...unknown>): { [ecr.Entity]: { unknown } }
        local cache = {}
    
        for id, a, b, c, d in observer do
            cache[id] = { a, b, c, d }
        end

        return cache
    end

    local reg = ecr.registry()
    local changedA = reg:track(A)
    local changedB = reg:track(B)
    local changedABC = reg:track(A, B, C)
    local changedABnotC = reg:track(A, B):exclude(C)

    local ids = {}
    local As = {}
    local Bs = {}
    local ABCs = {}
    local ABnotCs = {}

    for i = 1, N do
        local id = reg:create()
        ids[i] = id

        local has = {}
        for _, component in { A, B, C, D, E, F, G, H } do
            if flip() then
                reg:set(id, component, id)
                has[component] = true
            end
        end

        if has[A] then table.insert(As, id) end
        if has[B] then table.insert(Bs, id) end
        if has[A] and has[B] and has[C] then table.insert(ABCs, id) end
        if has[A] and has[B] and not has[C] then table.insert(ABnotCs, id) end
    end

    do CASE "Observer size"
        CHECK(#changedA == #As)
        CHECK(#changedB == #Bs)
        CHECK(#changedABC >= #ABCs)
        CHECK(#changedABnotC >= #ABnotCs)
    end

    do CASE "Initial components treated as changed"
        local changed = reg:track(A)
        local viewed = viewids(changed)
        CHECK(not empty(viewed))

        for _, id in As do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "A tracked"
        local viewed = viewids(changedA)
        CHECK(not empty(viewed))
        for _, id in As do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "ABCs tracked"
        local viewed = viewids(changedABC)
        CHECK(not empty(viewed))
        for _, id in ABCs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == id)
            CHECK(v[4] == nil)
        end
    end

    do CASE "ABnotCs tracked"
        local viewed = viewids(changedABnotC)
        CHECK(not empty(viewed))
        for _, id in ABnotCs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == nil)
        end
    end

    do CASE "Changed components tracked after clear"
        changedABC:clear()

        CHECK(#changedABC == 0)

        reg:set(ABCs[1], A, true)

        local ran = false
        for id, v in changedABC do
            ran = true
            CHECK(id == ABCs[1])
            CHECK(v == true)
        end
        CHECK(ran)
    end

    do CASE "Removed components are not returned"
        local removed = {}

        for _, id in As do
            if flip() then
                reg:remove(id, A)
                removed[id] = true
            end
        end

        CHECK(not empty(removed))

        for id in changedA:each() do
            CHECK(not removed[id])
        end
    end

    do CASE "Changed components updated"
        for _, id in Bs do
            reg:patch(id, B :: number, function(cur)
                return cur + 1
            end)
        end

        for id, v in changedB:each() do
            CHECK(v == id + 1)
        end
    end

    do CASE "Clear observer"
        changedA:clear()
        CHECK(true)
        for _ in changedA:each() do CHECK(false) end
    end

    do CASE "Changes not recorded if disconnected"
        changedA:disconnect()
        local id = reg:create()
        reg:set(id, A, 1)
        changedA:reconnect()
        CHECK(#changedA == 0)
    end

    do CASE "Changes recorded again after reconnect"
        local cache = {}
        for i = 1, 1e2 do
            local id = reg:create()
            reg:set(id, A, i)
            cache[id] = i
        end

        for id, v in changedA do
            CHECK(cache[id] == v)
        end
    end

    do CASE "Valid entities still returned if removed during disconnect"
        changedA:clear()
        local id1 = reg:create()
        local id2 = reg:create()

        reg:set(id1, A, 1)
        reg:set(id2, A, 2)

        changedA:disconnect()

        reg:remove(id1, A)

        CHECK(#changedA == 1)
        for id in changedA do
            CHECK(id == id2)
        end

        changedA:reconnect()
    end

    do CASE "Observer garbage collection"
        local wref = setmetatable({}, { __mode = "v" })
        wref.observer = changedA
        wref.pool = (changedA :: any).includes[1]
        changedA:disconnect()
        changedA = nil :: any

        if not game then -- check if running in roblox (collect is sandboxed)
            collectgarbage("collect" :: any)
            CHECK(not wref.observer)

            local id = reg:create()
            reg:set(id, A, 1)
            reg:remove(id, A) -- internal pool only cleared after event fired again

            collectgarbage("collect" :: any)
            CHECK(not wref.pool)
        end
    end
end)

TEST("registry:group()", function()
    local N = 1e3
    local function flip() return math.random() > 0.3 end
    local function empty(t) return next(t) == nil end
    local function viewids(group: ecr.Group<...unknown>): { [ecr.Entity]: { unknown } }
        local cache = {}
    
        for id, a, b, c, d, e in group do
            cache[id] = { a, b, c, d, e }
        end

        return cache
    end

    local reg = ecr.registry()
    local groupAB = reg:group(A, B)
    reg:group(C, D, E)

    local ids = {}
    local Bs = {}
    local ABs = {}
    local CDEs = {}
    local FGs = {}

    for i = 1, N do
        local id = reg:create()
        ids[i] = id

        local has = {}
        for _, component in { A, B, C, D, E, F, G, H } do
            if flip() then
                reg:set(id, component, id)
                has[component] = true
            end
        end

        if has[B] then table.insert(Bs, id) end
        if has[A] and has[B] then table.insert(ABs, id) end
        if has[C] and has[D] and has[E] then table.insert(CDEs, id) end
        if has[F] and has[G] then table.insert(FGs, id) end
    end

    do CASE "Group size"
        CHECK(#reg:group(A, B) == #ABs)
        CHECK(#reg:group(C, D, E) == #CDEs)
    end

    do CASE "Group AB cached"
        local viewed = viewids(groupAB)
        CHECK(not empty(viewed))
        for _, id in ABs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == nil)
        end
    end

    do CASE "Group AB"
        local viewed = viewids(reg:group(A, B))
        CHECK(not empty(viewed))
        for _, id in ABs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == nil)
        end
    end

    do CASE "Group CDE"
        local viewed = viewids(reg:group(C, D, E))
        CHECK(not empty(viewed))
        for _, id in CDEs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == id)
            CHECK(v[4] == nil)
        end
    end

    do CASE "Late initialized group FG"
        CHECK(#reg:group(F, G) == #FGs)
        local viewed = viewids(reg:group(F, G))
        CHECK(not empty(viewed))
        for _, id in FGs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == nil)
        end
    end

    do CASE "Create group with already-owned components errors"
        CHECK(not pcall(function()
            reg:group(A, F)
        end))
        CHECK(not pcall(function()
            reg:group(F, H)
        end))
    end

    do CASE "Removing components during group iteration"
        local viewed = {}
        local removed = {}

        for id, a, b in reg:group(A, B) do
            CHECK(not viewed[id]) -- ensure iterators arent invalidated
            viewed[id] = { a, b }
            if flip() then
                removed[id] = true
                reg:remove(id, A)
            end
        end

        CHECK(#reg:group(A, B) > 0)

        for id, a, b in reg:group(A, B) do
            local v = viewed[id]
            CHECK(v)
            CHECK(v[1] == a) -- check association is kept after remove
            CHECK(v[2] == b)
            viewed[id] = nil
        end

        CHECK(not empty(viewed))
        for id in viewed do
            CHECK(removed[id]) -- check only removed ids are left
        end
    end

    do CASE "Clearing with groups"
        reg:clear(A)
        CHECK(#reg:group(A, B) == 0)
        reg:set(ABs[1], A, 1)
        CHECK(#reg:group(A, B) == 1)
    end

    do CASE "Removing owned component from entity not in group"
        local id = reg:create()
        reg:set(id, A, 1)
        reg:set(id, C, 3)
        reg:set(id, A, nil)
        CHECK(reg:get(id, A) == nil and reg:get(id, C) == 3)
    end

    do CASE "Using owned component for new group errors"
        local ok = pcall(function()
            reg:group(F, H)
        end)
        CHECK(not ok)
    end

    do CASE "Single component group errors"
        local ok = pcall(function()
            reg:group(H)
        end)
        CHECK(not ok)
    end

    do CASE "Group ABCDE"
        local reg2 = ecr.registry()
        local ids2 = {}
        for i = 1, 1e2 do
            local id = reg:create()
            reg2:set(id, A, id)
            reg2:set(id, B, id)
            reg2:set(id, C, id)
            reg2:set(id, D, id)
            reg2:set(id, E, id)
            ids2[i] = id
        end

        reg2:group(A, B, C, D, E)

        local viewed = viewids(reg2:group(A, B, C, D, E))

        CHECK(not empty(viewed))
        for _, id in ids2 do
            local v = viewed[id]
            if not CHECK(v) then break end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == id)
            CHECK(v[4] == id)
            CHECK(v[5] == id)
        end
    end
end)

TEST("ecr:component()", function()
    do CASE "Components have unique ids"
        local cache = {}
        for i = 1, 1000 do
            local c = ecr.component()
            CHECK(cache[c] == nil)
            cache[c] = true
        end
    end
end)

local success = FINISH()
if not success then error "Test failed" end
