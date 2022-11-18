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
        pool.set(p, 1)
        CHECK(pool.has(p, 1))
        CHECK(pool.get(p, 1) == nil)
    end

    do CASE "Set existing value"
        pool.set(p, 1, true)
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
        pool.set(p, 3, true)
        CHECK(pool.has(p, 3))
        CHECK(not pool.has(p, 2))
        CHECK(pool.get(p, 3) == true)
        CHECK(pool.size(p) == 2)
    end

    do CASE "Clear then check size and old values were cleared"
        pool.clear(p)
        CHECK(pool.size(p) == 0)
        CHECK(pool.has(p, 1) == false)
        CHECK(pool.get(p, 1) == nil)
    end

    do CASE "Set old values again"
        pool.set(p, 1, 1)
        pool.set(p, 2, 2)
        pool.set(p, 3, 3)
        CHECK(pool.get(p, 1) == 1)
        CHECK(pool.get(p, 2) == 2)
        CHECK(pool.get(p, 3) == 3)
    end

    do CASE "Remove value, confirm removal and check association"
        pool.remove(p, 1)
        CHECK(pool.get(p, 1) == nil)
        CHECK(pool.has(p, 1) == false)

        CHECK(pool.get(p, 2) == 2)
        CHECK(pool.get(p, 3) == 3)
    end

    do CASE "Remove last value, confirm removal and check association"
        pool.remove(p, 3)
        CHECK(pool.get(p, 2) == 2)
        CHECK(pool.get(p, 3) == nil)
        CHECK(pool.has(p, 3) == false)
    end
end)

TEST("registry:create()", function()
    local N = 1e3

    do CASE "New ids are unique"
        local reg = ecr.registry()
        local cache = {}

        for i = 1, N do
            local entity = reg:create()
            CHECK(not cache[entity])
            cache[entity] = true
        end
    end

    do CASE "Reused ids are unique"
        -- create N entities, destroy all then recreate N entities
        -- indexes will be reused, check if identifier remains unique
        local reg = ecr.registry(N)
        local cache = {}

        for i = 1, N do
            local entity = reg:create()
            cache[entity] = true
        end

        for entity in cache do
            reg:release(entity)
        end

        for i = 1, N do
            local entity = reg:create()
            CHECK(not cache[entity])
            cache[entity] = true
        end
    end

    do CASE "Version overflow"
    end
end)

TEST("registry:valid() and registry:release()", function()
    local reg = ecr.registry()

    local e1 = reg:create()
    local e2 = reg:create()

    reg:release(e1)

    CHECK(not reg:valid(e1))
    CHECK(reg:valid(e2))

    -- e3 will reuse e1's index
    -- check things function as expected
    local e3 = reg:create()
    CHECK(not reg:valid(e1))
    CHECK(reg:valid(e3))
end)

TEST("registry:version() and registry:current()", function()
    local reg = ecr.registry()

    local e1 = reg:create()
    local e2 = reg:create()
    reg:destroy(e1)
    local e3 = reg:create()

    CHECK(reg:version(e1) == 1)
    CHECK(reg:current(e1) == 2)
    CHECK(reg:version(e3) == 2)
    CHECK(reg:version(e2) == 1)
end)

TEST("registry:orphan()", function()
    local reg = ecr.registry()
    local e = reg:create()
    CHECK(reg:orphan(e))
    reg:set(e, A, true)
    CHECK(not reg:orphan(e))
    reg:remove(e, A)
    CHECK(reg:orphan(e))
end)

TEST("registry:has() and registry:set()", function()
    local reg = ecr.registry()

    local e1 = reg:create()
    local e2 = reg:create()

    do CASE "Set components"
        reg:set(e1, A, true)
        reg:set(e2, A, true)
        reg:set(e2, B, true)
    end

    do CASE "Has components"
        CHECK(reg:has(e1, A))
        CHECK(not reg:has(e1, B))
        CHECK(not reg:has(e1, A, B))

        CHECK(reg:has(e2, A))
        CHECK(reg:has(e2, B))
        CHECK(reg:has(e2, A, B))
        CHECK(not reg:has(e2, A, B, C))
    end
end)

TEST("registry:get() and registry:set()", function()
    local reg = ecr.registry()
    local e = reg:create()
    reg:set(e, A, 1)
    reg:set(e, B, 2)
    reg:set(e, C, 3)

    do CASE "Get single component"
        CHECK(reg:get(e, A) == 1)
        CHECK(reg:get(e, B) == 2)
        CHECK(reg:get(e, C) == 3)
    end

    do CASE "Get multiple components"
        local a, b, c = reg:get(e, A, B, C)
        CHECK(a == 1)
        CHECK(b == 2 and c == 3)
    end

    do CASE "Change component and get"
        reg:set(e, A, 4)
        CHECK(reg:get(e, A) == 4)
    end
end)

TEST("registry:remove()", function()
    local reg = ecr.registry()

    local e1 = reg:create()
    local e2 = reg:create()

    reg:set(e1, A, 1)
    reg:set(e2, A, 2)

    do CASE "Remove component"
        reg:remove(e1, A)
        CHECK(reg:has(e1, A) == false)
        -- check removal does not break association (due to swap and pop)
        CHECK(reg:get(e2, A) == 2)
    end

    do CASE "Remove last component"
        reg:remove(e2, A)
        CHECK(not reg:has(e2, A))
    end
end)

TEST("registry:size() registry:clear()", function()
    local reg = ecr.registry()

    CHECK(reg:size() == 0)
    local e = reg:create()
    CHECK(reg:size() == 1)
    reg:destroy(e)
    CHECK(reg:size() == 0)

    local N = 1e3
    for i = 1, N do reg:create() end
    CHECK(reg:size() == N)
    reg:clear()
    CHECK(not reg:valid(e))
end)

TEST("registry:destroy()", function()
    
    local reg = ecr.registry()

    local e = reg:create()
    reg:set(e, A, 1)
    reg:set(e, B, 2)

    reg:destroy(e)

    CHECK(reg:get(e, A) == nil)
    CHECK(reg:get(e, B) == nil)
    CHECK(not reg:valid(e))
end)

TEST("registry:view()", function()
    local reg = ecr.registry()

    local N = 1e3

    local entities = {}
    local As = {}
    local Bs = {}
    local Cs = {}

    local ABCs = {}
    local ABs = {}
    local ABnotCs = {}

    local function flip() return math.random() > 0.3 end

    for i = 1, N do
        local e = reg:create()
        entities[i] = e
        local hasA, hasB, hasC = false, false, false
        if flip() then reg:set(e, A, e); hasA = true end
        if flip() then reg:set(e, B, e); hasB = true end
        if flip() then reg:set(e, C, e); hasC = true end

        if hasA then table.insert(As, e) end
        if hasB then table.insert(Bs, e) end
        if hasC then table.insert(Cs, e) end

        if hasA and hasB and hasC then table.insert(ABCs, e) end
        if hasA and hasB then table.insert(ABs, e) end
        if hasA and hasB and not hasC then table.insert(ABnotCs, e) end
    end
    
    do CASE "View all entities"
        local viewed = {}
        for entity in reg:view() do viewed[entity] = true end
        CHECK((next(viewed)))
        for _, entity in entities do CHECK(viewed[entity]) end
    end

    do CASE "View all entities for A"
        local viewed = {}
        for entity in reg:view(A) do viewed[entity] = true end
        CHECK((next(viewed)))
        for _, entity in As do CHECK(viewed[entity]) end
    end

    do CASE "View all entities for B"
        local viewed = {}
        for entity in reg:view(B) do viewed[entity] = true end
        CHECK((next(viewed)))
        for _, entity in Bs do CHECK(viewed[entity]) end
    end

    do CASE "View all entities for ABC"
        local viewed = {}
        for entity in reg:view(A, B, C) do viewed[entity] = true end
        CHECK((next(viewed)))
        for _, entity in ABCs do
            CHECK(viewed[entity])
            --CHECK(viewed[entity] == entity) -- check if entity and corresponding component matches
        end
    end

    do CASE "View all entities and values for ABC"
        local viewed = {}
        for entity, a, b, c in reg:view(A, B, C):each() do viewed[entity] = { a, b, c } end
        CHECK((next(viewed)))
        for _, entity in ABCs do
            CHECK(viewed[entity])
            CHECK(viewed[entity][1] == entity) -- check if entity and corresponding component matches
            CHECK(viewed[entity][2] == entity)
            CHECK(viewed[entity][3] == entity)
        end
    end

    do CASE "View all entities for AB and not C"
        local viewed = {}
        for entity in reg:view(A, B):exclude(C) do viewed[entity] = true end
        CHECK((next(viewed)))
        for _, entity in ABnotCs do 
            CHECK(viewed[entity])
        end
    end

    do CASE "Destroy keeps component association"
        for i = 1, 2e2 do
            local n = #ABs
            local toRemove = math.random(1, n)
            local entity = ABs[toRemove]
            ABs[toRemove] = ABs[n]
            ABs[n] = nil
            reg:destroy(entity)
        end

        local viewed = {}
        for entity, a, b in reg:view(A, B):each() do
            viewed[entity] = { a, b }   
        end
        CHECK((next(viewed)))
        for _, entity in ABs do
            CHECK(viewed[entity][1] == entity)
            CHECK(viewed[entity][2] == entity)
        end
    end

    do CASE "Component removal during view iteration"
        local visited = {}
        for entity in reg:view(A, B) do
            if flip() then
                reg:remove(entity, A)
            end
            visited[entity] = true
        end

        for _, entity in ABs do -- check that an entity isnt skipped
            CHECK(visited[entity])
        end
    end
end)

TEST("Removal during iterations", function()
    do CASE("Remove during view iteration")
        local reg = ecr.registry()
        local entities = {}
        for i = 1, 1e3 do
            entities[i] = reg:create()
            reg:set(entities[i], A, 1)
            reg:set(entities[i], B, 2)
            reg:set(entities[i], C, 3)
        end

        -- 1. all entities are iterated over
        -- 2. no entity is iterated twice
        local viewed = {}
        for entity, a in reg:view(A, B, C) do
            CHECK(not viewed[entity])
            viewed[entity] = true
            reg:remove(entity, A, B, C)
        end

        for _, entity in entities do
            CHECK(viewed[entity])
        end
    end
end)

TEST("registry:entities()", function()
    local N = 1e3

    local reg = ecr.registry(N)
    local cache = table.create(N)
    for i = 1, N do cache[i] = reg:create() end
    
    local entities = reg:entities()

    for i, entity in cache do
        CHECK(entity == entities[i])
    end
end)

TEST("registry:storage()", function()
    local reg = ecr.registry()

    local e1 = reg:create()
        reg:set(e1, A, 1)
    local e2 = reg:create()
        reg:set(e2, A, true)
        reg:set(e2, B, true)
    
    local a = reg:storage(A)
    CHECK(a.entities[1] == e1)
    CHECK(a.values[1] == 1)

    CHECK(a.entities[2] == e2)
    CHECK(a.values[2] == true)

    local b = reg:storage(B)
    CHECK(b.entities[1] == e2)
end)

TEST("registry events", function()
    local reg = ecr.registry()

    do CASE "registry:added()"
        local e1 = reg:create()

        -- runcount, reg, entity, value
        local cc, cr, ce, cv = 0, nil, nil, nil

        local fn = function(...)
            cr, ce, cv = ...
            cc += 1
        end

        reg:added(A):connect(fn)

        reg:set(e1, A, true)
        CHECK(cc == 1)
        CHECK(cr == reg)
        CHECK(ce == e1)
        CHECK(cv == true)

        reg:set(e1, A, 2)
        CHECK(cc == 1)

        reg:changed(A):disconnect(fn)
        reg:set(e1, A, true)
        CHECK(cc == 1)
    end

    do CASE "registry:changed()"
        local e1 = reg:create()

        -- runcount, reg, entity, value
        local cc, cr, ce, cv = 0, nil, nil, nil

        local fn = function(...)
            cr, ce, cv = ...
            cc += 1
        end

        reg:set(e1, A, true)

        reg:changed(A):connect(fn)

        reg:set(e1, A, true)
        CHECK(cc == 1)
        CHECK(cr == reg)
        CHECK(ce == e1)
        CHECK(cv == true)

        reg:set(e1, A, 2)
        CHECK(cc == 2)
        CHECK(cr == reg)
        CHECK(ce == e1)
        CHECK(cv == 2)

        reg:changed(A):disconnect(fn)
        reg:set(e1, A, true)
        CHECK(cc == 2)
    end

    do CASE "registry:removing()"
        local e1 = reg:create()

        local cc, cr, ce = 0, nil, nil

        local fn = function(...)
            cr, ce = ...
            cc += 1
        end

        reg:set(e1, B, true)

        reg:removing(B):connect(fn)

        reg:remove(e1, B)
        CHECK(cc == 1)
        CHECK(cr == reg)
        CHECK(ce == e1)

        reg:set(e1, B, true)
        reg:destroy(e1)
        CHECK(cc == 2)
        CHECK(cr == reg)
        CHECK(ce == e1)

        local e2 = reg:create()
        reg:set(e2, B, true)
        reg:removing(B):disconnect(fn)
        reg:remove(e2, B)
        CHECK(cc == 2)
    end
end)

TEST("reg:track()", function()
    local function flip() return math.random() > 0.5 end

    local N = 1e2
    local reg = ecr.registry(N)

    local trackerA = reg:track(A)
    local trackerAB = reg:track(A, B)

    local entities = {}
    local As = {}
    local ABs = {}
    local AnotBs = {}
    for i = 1, N do
        local e = reg:create()
        entities[i] = e
    
        reg:set(e, A, i)
        table.insert(As, e)

        local hasB = flip()
        if hasB then
            reg:set(e, B, i)
            table.insert(ABs, e)
        else
            table.insert(AnotBs, e)
        end
    end

    do CASE "Initial data treated as changed"
        do
            local tracker = reg:track(A)
            local viewed = {}
            for entity, value in tracker:each() do
                viewed[entity] = value
            end

            CHECK((next(viewed)))

            for i, entity in As do
                CHECK(viewed[entity])
                CHECK(viewed[entity] == i)
            end
        end
        do
            local tracker = reg:track(A, B)
            local viewed = {}
            for entity, value in tracker:each() do
                viewed[entity] = value
            end

            CHECK((next(viewed)))

            for i, entity in ABs do
                CHECK(viewed[entity])
                CHECK(viewed[entity] == i)
            end
        end
    end

    do CASE "Clear tracker"
        trackerA:clear()
        for _ in trackerA:each() do
            CHECK(false) -- check this loop does not run
        end
        CHECK(true)
    end

    do CASE "Tracker tracks future changes"
       local changed = {}
       for _, entity in entities do
            if flip() then
                reg:set(entity, A, 0)
                changed[entity] = 0    
            end
       end

       local tracked = {}
       for entity, value in trackerA:each() do
            tracked[entity] = value
       end

       CHECK((next(tracked)))

       for entity, value in changed do
            CHECK(tracked[entity])
            CHECK(tracked[entity] == value)
       end
    end

    do CASE "Track A for entities with B"
        local viewed = {}

        for entity, a, b in trackerAB:each() do
            viewed[entity] = { a = entity, b = entity }
        end

        CHECK((next(viewed)))

        for _, entity in ABs do
            CHECK(viewed[entity])
            if not viewed[entity] then continue end
            CHECK(viewed[entity].a == entity)
            CHECK(viewed[entity].b == entity)
        end
    end

    do CASE "Track removal"
        trackerA:clear()

        local removed = {}

        for i = 1, N do
            if math.random() > 0.5 then continue end
            table.insert(removed, As[i])
            reg:remove(As[i], A)
        end

        local viewed = {}
        for entity in trackerA:each() do
            viewed[entity] = true
        end

        for _, rentity in removed do
            CHECK(viewed[rentity])
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
