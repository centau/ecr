local TEST, CASE, CHECK, FINISH = require("test/testkit").getUnitTestTools()

local ecr = require "src/ecr"

local A, B, C, D = ecr.component(), ecr.component(), ecr.component(), ecr.component()
local E, F, G, H = ecr.component(), ecr.component(), ecr.component(), ecr.component()

local function printt(t: {})
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
end

TEST("pool - basic tests", function()
    local pool = ecr.pool
    local p = pool.create()

    do CASE "Set new value"
        pool.set(p, 1, 1)
        CHECK(pool.has(p, 1))
        CHECK(pool.get(p, 1) == nil)
    end

    do CASE "Set existing value"
        pool.set(p, 1, 1, true)
        CHECK(pool.get(p, 1) == true)
    end

    do CASE "Get non-existing value"
        CHECK(not pool.has(p, 2))
        CHECK(pool.get(p, 2) == nil)
    end

    do CASE "Check size"
        CHECK(pool.size(p) == 1)
    end

    do CASE "Set then check another value"
        pool.set(p, 3, 3, true)
        CHECK(pool.has(p, 3))
        CHECK(not pool.has(p, 2))
        CHECK(pool.get(p, 3) == true)
        CHECK(pool.size(p) == 2)
    end

    do CASE "Clear then check size and old values were cleared"
        pool.clear(p)
        CHECK(pool.size(p) == 0)
        CHECK(not pool.has(p, 1))
        CHECK(pool.get(p, 1) == nil)
    end

    do CASE "Set old values again"
        pool.set(p, 1, 1, 1)
        pool.set(p, 2, 2, 2)
        pool.set(p, 3, 3, 3)
        CHECK(pool.get(p, 1) == 1)
        CHECK(pool.get(p, 2) == 2)
        CHECK(pool.get(p, 3) == 3)
    end

    do CASE "Remove value, confirm removal and check association"
        pool.remove(p, 1)
        CHECK(pool.get(p, 1) == nil)
        CHECK(not pool.has(p, 1))

        CHECK(pool.get(p, 2) == 2)
        CHECK(pool.get(p, 3) == 3)
    end

    do CASE "Remove last value, confirm removal and check association"
        pool.remove(p, 3)
        CHECK(pool.get(p, 2) == 2)
        CHECK(pool.get(p, 3) == nil)
        CHECK(not pool.has(p, 3))
    end
end)

TEST("registry:create()", function()
    local N = 1e3

    do CASE "New ids unique"
        local reg = ecr.registry()
        local cache = {}

        for i = 1, N do
            local e = reg:create()
            CHECK(not cache[e])
            cache[e] = true
        end
    end

    do CASE "Reused ids unique"
        local reg = ecr.registry()
        local cache = {}

        for i = 1, N do -- create entities
            local e = reg:create()
            cache[e] = true
        end

        for e in cache do -- release all entities
            reg:release(e)
        end

        for i = 1, N do -- reuse all ids
            local entity = reg:create()
            CHECK(not cache[entity])
            cache[entity] = true
        end
    end

    do CASE "tmp"
        local entities = {}

        local sreg = ecr.registry()

        local e1 = sreg:create()
        local e2 = sreg:create()
        local e3 = sreg:create()
        local e4 = sreg:create()

        local reg = ecr.registry()

        reg:create(e2)

        reg:create(e1)

        for i = 1, N do
            CHECK(reg:valid(e1))
            CHECK(reg:valid(e1))
            CHECK(reg:valid(e1))

        end
    end

    do CASE "Create entity with identifier"
        local entities = {}

        local sreg = ecr.registry()

        for i = 1, N do
            entities[i] = sreg:create()   
        end

        local reg = ecr.registry()

        local mixed = table.clone(entities)
        for i = 1, N do
            local a = math.random(1, N)
            local b = math.random(1, N)
            mixed[a], mixed[b] = mixed[b], mixed[a]
        end

        for i = 1, N do
            reg:create(mixed[i])
        end

        for i = 1, N do
            CHECK(reg:valid(entities[i]))
        end
    end

    do CASE "Error if identifier is already in use"
        local sreg = ecr.registry()
        local e1 = sreg:create()

        local reg = ecr.registry()
        reg:create()

        local ok = pcall(function()
            reg:create(e1)
        end)

        CHECK(not ok)
    end
end)

TEST("registry:release()", function()
    local reg = ecr.registry()
    local e = reg:create()
    reg:release(e)

    do CASE "Released entities are no longer valid"
        CHECK(not reg:valid(e))
    end

    do CASE "Releases entity keys can be reused"
        local e2 = reg:create()
        CHECK(bit32.band(e, 0xF) == bit32.band(e2, 0xF))
    end
end)

TEST("registry:valid()", function()
    local reg = ecr.registry()

    local e = reg:create()

    do CASE "New entity valid"
        CHECK(reg:valid(e))
    end

    reg:release(e)

    do CASE "Released entity invalid"
        CHECK(not reg:valid(e))
    end

    do CASE "Reused entity key valid"
        e = reg:create()
        CHECK(reg:valid(e))
    end

    do CASE "Integer key invalid"
        CHECK(not reg:valid(1))
    end
end)

TEST("registry:version()", function()
    local reg = ecr.registry()

    do CASE "Gets correct version"
        local e = reg:create()
        CHECK(reg:version(e) == 1)
    end

    do CASE "Version increments on reuse"
        local e_old = reg:create()
        CHECK(reg:version(e_old) == 1)
        reg:destroy(e_old)
        local e_new = reg:create()
        CHECK(reg:version(e_old) == 1) -- check old still shows old version
        CHECK(reg:version(e_new) == 2)
    end

    do CASE "Version overflow"
        local reg2 = ecr.registry()
        local MAX_VER = 2^33 - 1
        
        reg2:release( reg2:create() ); -- ensure id exists

        (reg2 :: any):setEntityVersion(1, MAX_VER)

        -- verify version was set to max correctly
        local entity = reg2:create()
        CHECK(reg2:version(entity) == MAX_VER)
        -- trigger version increaes
        reg2:destroy(entity)
        
        -- should overflow and reset back to 1
        entity = reg2:create()
        CHECK(reg2:version(entity) == 1)
    end
end)

TEST("registry:current()", function()
    local reg = ecr.registry()
    local e_old = reg:create()
    reg:release(e_old)
    local e_new = reg:create()

    do CASE "Gets current version"
        CHECK(reg:version(e_old) == 1)
        CHECK(reg:current(e_old) == 2)
    end

    do CASE "Version increments on release"
        reg:release(e_new)
        CHECK(reg:current(e_new) == 3)
    end
end)

TEST("registry:add()", function()
    local reg = ecr.registry()

    local ADD_A = ecr.component(function() return true end)
    local ADD_B = ecr.component(function() return false end)
    local ADD_C = ecr.component(function() return nil end)

    do CASE "Add components"
        local e = reg:create()
        reg:add(e, ADD_A, ADD_B)
        CHECK(reg:has(e, ADD_A))
        CHECK(reg:has(e, ADD_B))
    end

    do CASE "Attempt to add an already-owned component errors"
        local ok = pcall(function()
            local e = reg:create()
            reg:set(e, ADD_A, true)
            reg:add(e, ADD_A)
        end)
        CHECK(not ok)
    end

    do CASE "Add a component with no default value specified errors"
        local ok = pcall(function()
            local e = reg:create()
            reg:add(e, A)
        end)
        CHECK(not ok)
    end

    do CASE "Add a component with no returned value errors"
        local ok = pcall(function()
            local e = reg:create()
            reg:add(e, ADD_C)
        end)
        CHECK(not ok)
    end
end)

TEST("registry:set()", function()
    local reg = ecr.registry()
    local e = reg:create()

    do CASE "Add component"
        reg:set(e, A, 1)
        CHECK(reg:get(e, A) == 1)
    end

    do CASE "Change component"
        reg:set(e, A, 2)
        CHECK(reg:get(e, A) == 2)
    end
    
    do CASE "Remove component"
        reg:set(e, A, nil)
        CHECK(reg:get(e, A) == nil)
        CHECK(not reg:has(e, A))
    end
end)

TEST("registry:get()", function()
    local reg = ecr.registry()
    local e = reg:create()

    do CASE "Get component"
        reg:set(e, A, true)
        CHECK(reg:get(e, A) == true)
    end

    do CASE "Get nil component"
        reg:remove(e, A)
        CHECK(reg:get(e, A) == nil)
    end
end)

TEST("registry:has()", function()
    local reg = ecr.registry()
    local e = reg:create()

    do CASE "Has component"
        reg:set(e, A, true)
        CHECK(reg:has(e, A) == true)

        reg:set(e, B, true)
        CHECK(reg:has(e, A, B))
    end

    do CASE "Does not have component"
        reg:set(e, A, nil)
        CHECK(reg:has(e, A) == false)
    end
end)

TEST("registry:patch()", function()
    local reg = ecr.registry()
    local e = reg:create()
    reg:set(e, A, 0)

    do CASE "Change component"
        reg:patch(e, A, function(cur)
            CHECK(cur == 0)
            return cur :: number + 1
        end)
        CHECK(reg:get(e, A) == 1)
    end
end)

TEST("registry:remove()", function()
    local reg = ecr.registry()
    local e = reg:create()
    reg:set(e, A, 1)
    reg:set(e, B, 1)
    reg:set(e, C, 1)

    local e2 = reg:create()
    reg:set(e2, A, 2)

    do CASE "Remove single component"
        reg:remove(e, A)
        CHECK(reg:has(e, A) == false)
        CHECK(reg:get(e2, A) == 2) -- check swap removal maintains associativity
    end

    do CASE "Remove multiple components"
        reg:remove(e, B, C)
        CHECK(reg:has(e, B) == false)
        CHECK(reg:has(e, C) == false)
    end
end)

TEST("registry:clear()", function()
    do
        local reg = ecr.registry()
        local e1 = reg:create()
        local e2 = reg:create()

        reg:set(e1, A, 1)
        reg:set(e2, A, 2)

        reg:set(e1, B, 1)
        reg:set(e2, B, 2)

        reg:set(e1, C, 1)
        reg:set(e2, C, 2)

        do CASE "Clear A"
            reg:clear(A)
            CHECK(reg:has(e1, A) == false)
            CHECK(reg:has(e2, A) == false)
        end

        do CASE "Clear B and C"
            reg:clear(B, C)
            CHECK(reg:has(e1, B) == false)
            CHECK(reg:has(e2, B) == false)
            CHECK(reg:has(e1, C) == false)
            CHECK(reg:has(e2, C) == false)
        end
    end

    do CASE "Clear entities"
        local N = 1e3
        local reg = ecr.registry()
        local entities = {}

        for i = 1, N do
            entities[i] = reg:create()
        end

        reg:clear()

        local entities2 = {}

        for i = 1, N do
            entities2[i] = reg:create()
        end

        for i = 1, N do
            CHECK(reg:version(entities[i]) + 1 == reg:version(entities2[i]))
        end
    end
end)

TEST("registry:orphan()", function()
    local reg = ecr.registry()
    local e = reg:create()

    do CASE "New entity is orphan"
        CHECK(reg:orphan(e))
    end

    reg:set(e, B, 1)

    do CASE "No longer orphan after assigning component"
        CHECK(not reg:orphan(e))
    end

    reg:set(e, B, nil)

    do CASE "Orphan after removing last component"
        CHECK(reg:orphan(e))
    end
end)

TEST("registry:destroy()", function()
    local reg = ecr.registry()
    local e = reg:create()

    reg:set(e, A, 1)
    reg:set(e, B, 1)

    reg:destroy(e)

    do CASE "Destroyed entity is released"
        CHECK(not reg:valid(e))
    end

    -- TODO: verify component was removed
end)

TEST("registry:size()", function()
    local reg = ecr.registry()

    do CASE "Initial registry size is 0"
        CHECK(reg:size() == 0)
    end

    local e = reg:create()

    do CASE "Size after entity creation"
        CHECK(reg:size() == 1)
    end

    reg:release(e)

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
end)

TEST("registry:entities()", function()
    local N = 1e3

    local reg = ecr.registry()

    local entities = {}

    for i = 1, N do
        entities[i] = reg:create()
    end

    for i = 1, N do
        if math.random() > 0.5 then
            reg:destroy(entities[i])
            entities[i] = nil
        end
    end

    do CASE "All entities are valid"
        local list = reg:entities()

        local map = {}

        for _, entity in list do
            map[entity] = true
        end

        for _, entity in entities do
            CHECK(map[entity])
        end
    end
end)

TEST("registry:view()", function()
    local N = 1e3

    local reg = ecr.registry()

    local entities = {}
    local As = {}
    local Bs = {}
    local Cs = {}
    local ABCs = {}
    local ABs = {}
    local ABnotCs = {}

    local function flip() return math.random() > 0.3 end
    local function empty(t) return next(t) == nil end

    -- setup components
    -- each component value is the id of the entity it is assigned to
    for i = 1, N do
        local e = reg:create()
        entities[i] = e
        local hasA, hasB, hasC = false, false, false
        if flip() then reg:set(e, A, e); hasA = true; table.insert(As, e) end
        if flip() then reg:set(e, B, e); hasB = true; table.insert(Bs, e) end
        if flip() then reg:set(e, C, e); hasC = true; table.insert(Cs, e) end

        if hasA and hasB and hasC then table.insert(ABCs, e) end
        if hasA and hasB then table.insert(ABs, e) end
        if hasA and hasB and not hasC then table.insert(ABnotCs, e) end
    end

    do CASE "View all entities with A"
        local viewed = {}
        for entity, a in reg:view(A) do viewed[entity] = a end
        CHECK(not empty(viewed))
        for _, entity in As do CHECK(viewed[entity] == entity) end
    end

    do CASE "View all entities with B"
        local viewed = {}
        for entity, b in reg:view(B) do viewed[entity] = b end
        CHECK(not empty(viewed))
        for _, entity in Bs do CHECK(viewed[entity] == entity) end
    end

    do CASE "View all entities with AB"
        local viewed = {}
        for entity, a, b in reg:view(A, B) do viewed[entity] = { a, b } end
        CHECK(not empty(viewed))
        for _, entity in ABs do
            local v = viewed[entity]
            CHECK(v)
            if not v then continue end
            CHECK(v[1] == entity)
            CHECK(v[2] == entity)
        end
    end

    do CASE "View all entities with ABC"
        local viewed = {}
        for entity, a, b, c in reg:view(A, B, C) do viewed[entity] = { a, b, c } end
        CHECK(not empty(viewed))
        for _, entity in ABCs do
            local v = viewed[entity]
            CHECK(v)
            if not v then continue end
            CHECK(v[1] == entity)
            CHECK(v[2] == entity)
            CHECK(v[3] == entity)
        end
    end

    do CASE "View all entities with AB and not C"
        local viewed = {}
        for entity in reg:view(A, B):exclude(C) do viewed[entity] = entity end
        CHECK(not empty(viewed))
        for _, entity in ABnotCs do 
            CHECK(viewed[entity] == entity)
        end
    end

    do CASE "View all entities with BA and not C"
        local viewed = {}
        for entity, b in reg:view(B, A):exclude(C) do viewed[entity] = b end
        CHECK(not empty(viewed))
        for _, entity in ABnotCs do 
            CHECK(viewed[entity] == entity)
        end
    end

    do CASE "Component addition during view iteration"
        -- set of new entities
        local newcache = {}

        local viewed = {}
        for entity, c in reg:view(C) do
            -- check that newly added entities+components are not included in iterations
            CHECK(not newcache[entity])
            if flip() then -- create new entity+component
                local new = reg:create()
                reg:set(new, C, true)
                newcache[new] = true
            end
            viewed[entity] = c
        end
        CHECK(not empty(viewed))
        for _, entity in Cs do
            CHECK(viewed[entity])
            CHECK(viewed[entity] == entity)
        end
    end

    do CASE "Removes keeps component association"
        for i = 1, 2e2 do
            local n = #ABs
            local entity = table.remove(ABs, math.random(1, n))
            assert(entity)
            reg:destroy(entity)
        end

        local viewed = {}
        for entity, a, b in reg:view(A, B):each() do
            viewed[entity] = { a, b }   
        end
        CHECK(not empty(viewed))
        for _, entity in ABs do
            CHECK(viewed[entity][1] == entity)
            CHECK(viewed[entity][2] == entity)
        end
    end

    do CASE "Component removal during view iteration"
        local viewed = {}
        for entity in reg:view(A, B) do
            if flip() then
                reg:remove(entity, A)
            end
            viewed[entity] = true
        end
        CHECK(not empty(viewed))
        for _, entity in ABs do -- check that an entity isn't skipped
            CHECK(viewed[entity])
        end
    end
end)

TEST("registry:added()", function()
    local reg = ecr.registry()
    local e = reg:create()

    -- runcount, reg, entity, value
    local cc, ce, cv = 0, nil, nil

    local function fn(...)
        cc += 1
        ce, cv = ...
    end

    local con = reg:added(A):connect(fn)

    CASE "Adding triggers"
    reg:set(e, A, true)
    CHECK(cc == 1)
    CHECK(ce == e)
    CHECK(cv == true)

    CASE "Changing does not trigger"
    reg:set(e, A, false)
    CHECK(cc == 1)

    CASE "Removing then adding triggers"
    reg:set(e, A, nil)
    reg:set(e, A, true)
    CHECK(cc == 2)

    con:disconnect()

    CASE "Adding after disconnect does not trigger"
    reg:set(e, A, nil)
    reg:set(e, A, true)
    CHECK(cc == 2)
end)

TEST("registry:changed()", function()
    local reg = ecr.registry()
    local e = reg:create()

    local cc, ce, cv = 0, nil, nil

    local function fn(...)
        cc += 1
        ce, cv = ...
    end

    local con = reg:changed(A):connect(fn)

    CASE "Adding does not trigger"
    reg:set(e, A, true)
    CHECK(cc == 0)

    CASE "Changing triggers"
    reg:set(e, A, false)
    CHECK(cc == 1)
    CHECK(ce == e)
    CHECK(cv == false)

    CASE "Removing does not trigger"
    reg:set(e, A, nil)
    CHECK(cc == 1)

    con:disconnect()

    CASE "Changing after disconnect does not trigger"
    reg:set(e, A, true) -- add
    reg:set(e, A, false) -- change
    CHECK(cc == 1)
end)

TEST("registry:removing()", function()
    do
        local reg = ecr.registry()
        local e = reg:create()

        local cc, ce, cv, lv = 0, nil, nil, nil

        local function fn(...)
            cc += 1
            lv = reg:get(e, A) -- get current value
            ce, cv = ...
        end

        local con = reg:removing(A):connect(fn)

        reg:set(e, A, true)

        CASE "Removing triggers"
        reg:set(e, A, nil)
        CHECK(cc == 1)
        CHECK(ce == e)
        CHECK(cv == nil)
        CHECK(lv == true)

        con:disconnect()

        CASE "Removing after disconnect does not trigger"
        reg:set(e, A, true) -- add
        reg:set(e, A, nil) -- remove
        CHECK(cc == 1)
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

    local reg = ecr.registry()

    local changedA = reg:track(A)
    local changedABC = reg:track(A, B, C)

    local As = {}
    local ABCs = {}
    local AincBexcCs = {}

    local function flip() return math.random() > 0.3 end

    for i = 1, N do
        local e = reg:create()
  
        local hasA, hasB, hasC = false, false, false
        if flip() then reg:set(e, C, e); hasC = true end
        if flip() then reg:set(e, B, e); hasB = true end
        if flip() then reg:set(e, A, e); hasA = true end

        if hasA then table.insert(As, e) end
        if hasA and hasB and hasC then table.insert(ABCs, e) end
        if hasA and hasB and not hasC then table.insert(AincBexcCs, e) end
    end

    do CASE "Initial components treated as changed"
        local changed = reg:track(A)

        local viewed = {}

        for entity, value in changed:each() do
            viewed[entity] = value
        end

        CHECK((next(viewed)))

        for _, entity in As do
            CHECK(viewed[entity])
        end
    end

    do CASE "A tracked"
        local viewed = {}

        for entity, value in changedA:each() do
            viewed[entity] = value
        end

        CHECK((next(viewed)))

        for _, entity in As do
            CHECK(viewed[entity])
        end
    end

    do CASE "ABCs tracked"
        local viewed = {}

        for entity, value in changedABC:each() do
            viewed[entity] = value
        end

        CHECK((next(viewed)))

        for _, entity in ABCs do
            CHECK(viewed[entity])
        end
    end

    do CASE "Changed components tracked after clear"
        changedABC:clear()
        reg:set(ABCs[1], A, true)

        local ran = false
        for entity, value in changedABC:each() do
            ran = true
            CHECK(entity == ABCs[1])
            CHECK(value == true)
        end
        CHECK(ran)
    end

    do CASE "Removed components are not returned"
        local removed = {}

        for _, entity in As do
            if flip() then
                reg:remove(entity, A)
                removed[entity] = true
            end
        end

        CHECK((next(removed)))

        for entity in changedA:each() do
            CHECK(not removed[entity])
        end
    end

    do CASE "Clear observer"
        changedA:clear()

        CHECK(true)
        for _ in changedA:each() do CHECK(false) end
    end
end)

TEST("registry:sort()", function()
    local N = 1e1
    local reg = ecr.registry()

    do
        local entities = {}
        for i = 1, N do
            entities[i] = reg:create()
        end

        for _ = 1, N do -- add components in random order
            local n = #entities
            local i = math.random(1, n)

            reg:set(entities[i], A, bit32.band(entities[i], 0xFFFFF))

            entities[i] = entities[n]
            entities[n] = nil
        end
    end

    reg:sort(A)

    for i, entity in reg:storage(A).entities do
        CHECK(i == bit32.band(entity, 0xFFFFF))
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
