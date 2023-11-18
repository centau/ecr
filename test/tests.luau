local testkit = require("test/testkit")

local TEST, CASE, CHECK, FINISH = testkit.test()

local function CHECK_ERR<T...>(s: string, fn: (T...) -> (), ...: T...)
    local ok, err: string? = pcall(fn, ...)
    if CHECK(not ok, 2) then
        local i = string.find(err :: string, " ")
        assert(i)
        local msg = string.sub(err :: string, i+1)
        CHECK(msg == s, 2)
    end
end

type Map<T, U> = { [T]: U }
type Array<T> = { T }

local ecr = require "src/ecr"

local A, B, C, D = ecr.component(), ecr.component(), ecr.component(), ecr.component()
local E, F, G, H = ecr.component(), ecr.component(), ecr.component(), ecr.component(function() return true end)

local MAX_VER = 2^33-1

local function KEY(id: ecr.Entity): number
    local key = ecr.extract(id)
    return key
end

local function VER(id: ecr.Entity): number
    local _, ver = ecr.extract(id)
    return ver
end

local function CURRENT_VER(reg: ecr.Registry, id: ecr.Entity): number
    return (reg :: any):get_current_entity_version(id)
end
local function CREATE_ID(key: number, ver: number)
    return (ecr :: any).id(key, ver)
end

local function SET_ENTITY_VERSION(reg: ecr.Registry, key: number, ver: number)
    reg:release(reg:create(CREATE_ID(KEY(key), 1)))
    ;(reg :: any):set_entity_version(KEY(key), ver)
end

local function CREATE_DEPRECATED_ID(reg: ecr.Registry): ecr.Entity
    local id = reg:create()
    reg:release(id)
    SET_ENTITY_VERSION(reg, KEY(id), MAX_VER)
    id = reg:create()
    reg:release(id)
    return id
end

local function BULK_CREATE_IDS(reg: ecr.Registry, n: number): { ecr.Entity }
    local ids = table.create(n)
    for i = 1, n do
        ids[i] = reg:create()
    end
    return ids
end

--[[
local function INSPECT_IDS(reg)
    local pool = reg:storage(ecr.entity)
    local map = pool.map
    print "{"
    print(`  free: {pool.free}`)
    for i, data in map do
        if i == 0 then continue end
        local sign = math.sign(data) == -1 and "X" or " "
        local key, ver = ecr.extract(math.abs(data))
        print(`  [{i}] {sign} {key}:{ver}`)
    end
    print "}"
end
]]

local N = 1e3

TEST("registry:create()", function()
    do CASE "New ids unique"
        local reg = ecr.registry()

        local cache = {}

        for i = 1, N do
            local id = reg:create()
            CHECK(not cache[id])
            cache[id] = true
        end
    end

    do CASE "Reusing keys produce unique ids"
        local reg = ecr.registry()

        local cache = {}

        for i = 1, N do
            local id = reg:create()
            cache[id] = true
        end

        for id in cache do
            reg:release(id)
        end

        for i = 1, N do
            local id = reg:create() -- key reused
            CHECK(not cache[id])
            cache[id] = true
        end
    end

    do CASE "Create entity with specific id"
        do
            local sreg = ecr.registry()

            local ids = BULK_CREATE_IDS(sreg, N)

            -- mix array of ids
            local mixed = table.clone(ids)
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
                CHECK(reg:contains(ids[i]))
            end
        end

        local reg = ecr.registry()
        reg:create(CREATE_ID(3, 2))
        CHECK(reg:create() == CREATE_ID(1, 1))
        CHECK(reg:create() == CREATE_ID(2, 1)) 
        CHECK(reg:create() == CREATE_ID(4, 1))
    end

    do CASE "Create entity with previously used id"
        do
            local reg = ecr.registry()
            local id = reg:create()
            reg:release(id)
            reg:create(id)
            CHECK(reg:contains(id))
        end

        do
            local reg = ecr.registry()
            local id1, id2, id3 = reg:create(), reg:create(), reg:create()
            local id4 = reg:create()

            reg:release(id4)
            reg:release(id3)
            reg:release(id2)
            reg:release(id1)

            -- 1 -> 2 -> 3 -> 4
            reg:create(id4)
            -- 1 -> 2 -> 3
            reg:create(id2)
            -- 1 -> 3
            reg:create(id1)
            -- 3
            local id5 = reg:create(CREATE_ID(5, 1))
            reg:release(id5)
            -- 3 -> 5
            reg:create(id5)
            -- 3
            reg:create(id3)
            -- [empty]

            CHECK(reg:contains(id1))
            CHECK(reg:contains(id2))
            CHECK(reg:contains(id3))
            CHECK(reg:contains(id4))
            CHECK(reg:contains(id5))

            CHECK(KEY(id1) == 1)
            CHECK(KEY(id2) == 2)
            CHECK(KEY(id3) == 3)
            CHECK(KEY(id4) == 4)
            CHECK(KEY(id5) == 5)
        end
    end

    do CASE "Create entity with deprecated id"
        local reg = ecr.registry()
        local id = CREATE_DEPRECATED_ID(reg)
        reg:create(id)
        CHECK(reg:contains(id))
        CHECK(VER(id) == MAX_VER)
    end

    do CASE "Error if key is already in use"
        local sreg = ecr.registry()
        local id = sreg:create()

        local reg = ecr.registry()

        CHECK(id == reg:create())

        CHECK_ERR("key is already in use", function()
            reg:create(id)
        end)
    end

    do CASE "Error if null is used"
        local reg = ecr.registry()

        CHECK_ERR("malformed id", function()
            reg:create(ecr.null)
        end)
    end
end)

TEST("registry:release()", function()
    local reg = ecr.registry()

    do CASE "Released entities invalid"
        local id = reg:create()
        reg:release(id)
        CHECK(not reg:contains(id))
    end

    do CASE "Release invalid id"
        local id = reg:create()
        reg:release(id)
        CHECK_ERR("invalid entity", function()
            reg:release(id)
        end)
    end

    do CASE "Release null id"
        CHECK_ERR("invalid entity", function()
            reg:release(ecr.null)
        end)
    end

    do CASE "Release deprecated id"
        local id = CREATE_DEPRECATED_ID(reg)
        CHECK_ERR("invalid entity", function()
            reg:release(id)
        end)
    end
end)

TEST("registry:contains()", function()
    local reg = ecr.registry()

    do
        local id = reg:create()

        do CASE "New entity valid"
            CHECK(reg:contains(id))
        end

        reg:release(id)

        do CASE "Released entity invalid"
            CHECK(not reg:contains(id))
        end

        local newid = reg:create()

        do CASE "Id with reused key valid"
            CHECK(reg:contains(newid))
        end

        do CASE "Released entity still invalid despite key reuse"
            CHECK(not reg:contains(id))
        end

        do CASE "Id that has not been created yet"
            local sreg = ecr.registry()
            for i = 1, 10 do sreg:create() end
            local id2 = sreg:create()
            CHECK(not reg:contains(id2))
        end
    end

    do CASE "Integer invalid"
        local id = reg:create()
        assert(KEY(id) == 2)
        CHECK(not reg:contains(2))
    end

    do CASE "Null entity invalid"
        CHECK(not reg:contains(ecr.null))
    end

    do CASE "Deprecated id invalid"
        local id = CREATE_DEPRECATED_ID(reg)
        CHECK(not reg:contains(id))
    end
end)

TEST("registry:version()", function()
    local reg = ecr.registry()

    do CASE "Get version"
        local id = reg:create()
        CHECK(VER(id) == 1)
    end

    do CASE "Version increments on reuse"
        local id_old = reg:create()
        CHECK(VER(id_old) == 1)
        reg:destroy(id_old)
        local id_new = reg:create()
        CHECK(VER(id_old) == 1)
        CHECK(VER(id_new) == 2)
    end

    do CASE "Version overflow"
        local reg2 = ecr.registry()
        
        reg2:release( reg2:create() ); -- ensure id internally exists

        SET_ENTITY_VERSION(reg2, 1, MAX_VER - 1)

        -- verify version was set to MAX-1 correctly
        local id = reg2:create()
        CHECK(VER(id) == MAX_VER - 1)
        CHECK(KEY(id) == 1)
        -- trigger version increment
        reg2:release(id)

        -- verify version is now MAX
        id = reg2:create()
        CHECK(VER(id) == MAX_VER)
        CHECK(KEY(id) == 1)

        -- id deprecated
        reg2:release(id)
        CHECK(VER(id) == MAX_VER)
        
        -- should produce a new key and not recycle as the previous key is at MAX version
        id = reg2:create()
        CHECK(VER(id) == 1)
        CHECK(KEY(id) == 2)
    end
end)

TEST("registry:current()", function()
    local reg = ecr.registry()
    local id_old = reg:create()
    reg:release(id_old)
    local id_new = reg:create()

    do CASE "Gets current version"
        CHECK(VER(id_old) == 1)
        CHECK(CURRENT_VER(reg, id_old) == 2)
    end

    do CASE "Version increments on release"
        reg:release(id_new)
        CHECK(CURRENT_VER(reg, id_new) == 3)
    end

    do CASE "Deprecated key"
        CHECK(CURRENT_VER(reg, CREATE_DEPRECATED_ID(reg)) == MAX_VER)
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

    do CASE "Attempt to add an already added component does nothing"
        local id = reg:create()
        reg:set(id, ADD_A, false)
        reg:add(id, ADD_A)
        CHECK(reg:get(id, ADD_A) == false)
    end

    do CASE "Add a component with no constructor errors"
        CHECK_ERR("no constructor defined for component (arg #1)", function()
            local id = reg:create()
            reg:add(id, B)
        end)
    end

    do CASE "Constructor returning nil errors"
        CHECK_ERR("component (arg #1) constructor did not return a value", function()
            local id = reg:create()
            reg:add(id, ADD_C)
        end)
    end

    do CASE "Add component to invalid id with unused key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:add(id, ADD_A)
        end)
    end

    do CASE "Add component to invalid id with used key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:create() -- reuse key
            reg:add(id, ADD_A)
        end)
    end

    do CASE "Add component to deprecated id"
        CHECK_ERR("invalid entity", function()
            local id = CREATE_DEPRECATED_ID(reg)
            reg:add(id, ADD_A)
        end)
    end

    do CASE "Add component to invalid id with used key that has component"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            local newid = reg:create() -- reuse key
            reg:add(newid, ADD_A)
            reg:add(id, A)
        end)
    end

    do CASE "Add component to null entity"
        CHECK_ERR("invalid entity", function()
            reg:add(ecr.null, ADD_A)
        end)
    end
end)

TEST("registry:set()", function()
    local reg = ecr.registry()

    do
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
            reg:remove(id, A)
            CHECK(reg:try_get(id, A) == nil)
            CHECK(not reg:has(id, A))
        end
    end

    do CASE "Add component to invalid id with unused key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:set(id, A, 1)
        end)
    end

    do CASE "Add component to invalid id with used key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:create() -- reuse key
            reg:set(id, A, 1)
        end)
    end

    do CASE "Add component to invalid id with used key that has component"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)

            local newid = reg:create() -- reuse key
            reg:set(newid, A, 0)

            reg:set(id, A, 1)
        end)
    end

    do CASE "Add component to null entity"
        CHECK_ERR("invalid entity", function()
            reg:set(ecr.null, A, true)
        end)
    end

    do CASE "Add component to deprecated id"
        CHECK_ERR("invalid entity", function()
            local id = CREATE_DEPRECATED_ID(reg)
            reg:set(id, A, 1)
        end)
    end

    do CASE "Change component of invalid entity with used key that has component"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            
            local newid = reg:create() -- reuse key
            reg:set(newid, A, 1)

            reg:set(id, A, 2)
        end)
    end

    do CASE "Attempt to set nil value"
        CHECK_ERR("cannot set nil value", function()
            local id = reg:create()
            reg:set(id, A, nil)
        end)
    end
end)

TEST("registry:get()", function()
    local reg = ecr.registry()

    do
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

            local values = { reg:get(id, A, B, C, D, E) }

            for i, value in values do
                CHECK(value == i)
            end
        end

        do CASE "Get nil component"
            reg:remove(id, A)
            CHECK_ERR("entity does not have component (arg #1)", function()
                reg:get(id, A)
            end)
        end
    end

    do CASE "Get component of invalid id"
        local id = reg:create()
        reg:release(id)
        CHECK_ERR("entity does not have component (arg #1)", function()
            reg:get(id, A)
        end)
    end

    do CASE "Get component of invalid id with used key that has component"
        local id = reg:create()
        reg:release(id)

        local newid = reg:create()
        reg:set(newid, A, 1)

        CHECK_ERR("invalid entity", function()
            reg:get(id, A)
        end)
    end
end)

TEST("registry:try_get()", function()
    local reg = ecr.registry()

    do CASE "Get nil component"
        local id = reg:create()
        reg:remove(id, A)
        CHECK(reg:try_get(id, A) == nil)
    end

    do CASE "Get component of invalid id"
        local id = reg:create()
        reg:release(id)
        CHECK(reg:try_get(id, A) == nil)
    end

    do CASE "Get component of invalid id with used key that has component"
        local id = reg:create()
        reg:release(id)

        local newid = reg:create()
        reg:set(newid, A, 1)

        CHECK(reg:try_get(id, A) == nil)
        --CHECK_ERR("invalid entity", function()
            --reg:try_get(id, A)
        --end)
    end
end)

TEST("registry:has()", function()
    local reg = ecr.registry()
    
    do
        local id = reg:create()

        do CASE "Has component"
            reg:set(id, A, true)
            CHECK(reg:has(id, A) == true)

            reg:set(id, B, true)
            CHECK(reg:has(id, A, B))
        end

        do CASE "Does not have component"
            reg:remove(id, A)
            CHECK(reg:has(id, A) == false)
            CHECK(reg:has(id, B, A) == false)
        end
    end

    do CASE "Invalid entity"
        local id = reg:create()
        reg:release(id)
        CHECK(reg:has(id, A) == false)
    end

    do CASE "Invalid entity with used key that has component"
        local id = reg:create()
        reg:release(id)

        local newid = reg:create()
        reg:set(newid, A, 1)

        CHECK(reg:has(id, A) == false)
    end
end)

TEST("registry:patch()", function()
    local reg = ecr.registry()

    do CASE "Change component"
        local id = reg:create()
        reg:set(id, A, 0)

        local ran = false
        reg:changing(A):connect(function()
            ran = true
        end)

        reg:patch(id, A :: number, function(v)
            CHECK(v == 0)
            return v + 1
        end)
        CHECK(reg:get(id, A) == 1)
        CHECK(ran)
    end

    do CASE "Patch returns nil"
        local id = reg:create()
        reg:set(id, A, true)
        
        CHECK_ERR("patcher cannot return nil", function()
            reg:patch(id, A :: number, function(v)
                return nil :: any
            end)
        end)
    end

    do CASE "Change non-existent component"
        local id = reg:create()
        
        CHECK_ERR("entity does not have component and no constructor for component (unknown)", function()
            reg:patch(id, A :: number, function(v)
                CHECK(false)
                return v + 1
            end)
        end)
    end

    do CASE "Change non-existent component with constructor"
        local id = reg:create()
        
        local ran = false
        reg:added(H):connect(function()
            ran = true
        end)
        
        reg:patch(id, H, function(v)
            CHECK(v == true)
            return not v
        end)

        CHECK(ran)
        CHECK(reg:get(id, H) == false)

        CHECK_ERR("patcher cannot return nil", function()
            reg:patch(id, H, function(v)
                return nil :: any
            end)
        end)
    end

    do CASE "Invalid id"
        local id = reg:create()
        reg:release(id)
        
        CHECK_ERR("invalid entity", function()
            reg:patch(id, A :: number, function(v)
                CHECK(false)
                return v + 1
            end)
        end)
    end

    do CASE "Invalid id that shares same key with id that has component"
        local id = reg:create()
        reg:release(id)

        local newid = reg:create()
        reg:set(newid, A, 1)
        
        CHECK_ERR("invalid entity", function()
            reg:patch(id, A :: number, function(v)
                CHECK(false)
                return v + 1
            end)
        end)
    end
end)

TEST("registry:remove()", function()
    local reg = ecr.registry()

    do
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
    end

    do CASE "Remove component from invalid entity"
        local id = reg:create()
        reg:release(id)

        local ok = pcall(function()
            reg:remove(id, A)
        end)

        CHECK(ok)
    end

    do CASE "Remove component from invalid id that shares key with entity that has component"
        local id = reg:create()
        reg:release(id)

        local newid = reg:create()
        reg:set(newid, A, 1)

        --CHECK_ERR("invalid entity", function()
            --reg:remove(id, A)
        --end)

        reg:remove(id, A)

        CHECK(reg:has(newid, A))
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
        local reg = ecr.registry()
    
        -- deprecate key = 1
        CREATE_DEPRECATED_ID(reg)

        -- set key = 2 version to max
        SET_ENTITY_VERSION(reg, 2, MAX_VER)
        do
            local id = reg:create()
            assert(KEY(id) == 2)
            assert(VER(id) == MAX_VER)
        end

        local ids = BULK_CREATE_IDS(reg, N)

        reg:clear()

        local ids_after = BULK_CREATE_IDS(reg, N)

        CHECK(KEY(ids_after[1]) == 3) -- key = 1 should not be reused
        CHECK(KEY(ids_after[2]) == 4) -- key = 2 should now be deprecated

        for i = 1, N do
            CHECK(KEY(ids_after[i]) ~= 1)
            CHECK(KEY(ids_after[i]) ~= 2)
            CHECK(VER(ids[i]) + 1 == VER(ids_after[i]))
        end
    end

    do CASE "Clear with groups"
        local reg = ecr.registry()
        reg:group(A, B)

        local listener = { count = 0 } :: { id: number?, count: number }

        reg:removing(A):connect(function(id)
            listener.id = id
            listener.count += 1
        end)

        local eB = reg:handle():set(B, 2)
        local eAB = reg:handle():set(A, 1):set(B, 1)

        reg:clear(A)

        CHECK(#reg:storage(A).entities == 0)
        CHECK(listener.id == eAB.entity and listener.count == 1)

        eAB:set(A, 1) -- 1
        eB:set(A, 2) -- 2

        eAB:remove(A)

        CHECK(#reg:storage(A).entities == 1)
        CHECK(reg:storage(A).entities[1] == eB.entity)

    end
end)

TEST("registry:orphaned()", function()
    local reg = ecr.registry()
    local id = reg:create()

    do CASE "New entity is orphaned"
        CHECK(reg:orphaned(id))
    end

    reg:set(id, B, 1)

    do CASE "No longer orphaned after assigning component"
        CHECK(not reg:orphaned(id))
    end

    reg:remove(id, B)

    do CASE "Orphan after removing last component"
        CHECK(reg:orphaned(id))
    end

    reg:release(id) -- UB

    do CASE "Rejects invalid entity"
        CHECK_ERR("invalid entity", function()
            reg:orphaned(id)
        end)
    end
end)

TEST("registry:destroy()", function()
    local reg = ecr.registry()

    do CASE "Component was removed"
        local id = reg:create()

        reg:set(id, A, 1)
        reg:set(id, B, 1)

        reg:destroy(id)

         -- do not rely on this behavior
        CHECK(not reg:contains(id))
        CHECK(not reg:has(id, A))
        CHECK(not reg:has(id, B))
    end

    do CASE "Destroy invalid id"
        local id = reg:create()
        reg:release(id)

        CHECK_ERR("invalid entity", function()
            reg:destroy(id)
        end)
    end

    do CASE "Destroy deprecated id"
        local id = CREATE_DEPRECATED_ID(reg)

        CHECK_ERR("invalid entity", function()
            reg:destroy(id)
        end)
    end
end)

TEST("#registry", function()
    local reg = ecr.registry()

    do CASE "Initial registry size is 0"
        CHECK(#reg:view(ecr.entity) == 0)
    end

    local id = reg:create()

    do CASE "Size after entity creation"
        CHECK(#reg:view(ecr.entity) == 1)
    end

    reg:release(id)

    do CASE "Size after entity release"
        CHECK(#reg:view(ecr.entity) == 0)
    end

    for i = 1, 100 do reg:create() end

    do CASE "Mass creation"
        CHECK(#reg:view(ecr.entity) == 100)
    end

    reg:clear()

    do CASE "Size after clear"
        CHECK(#reg:view(ecr.entity) == 0)
    end

    reg:create(id)

    do CASE "Size after specific entity creation"
        CHECK(#reg:view(ecr.entity) == 1)
    end
end)

TEST("registry:__iter()", function()
    do
        local reg = ecr.registry()

        local ids = BULK_CREATE_IDS(reg, N)

        -- destroy random entities
        for i = 1, N do
            if math.random() > 0.5 then
                reg:destroy(ids[i])
                ids[i] = nil
            end
        end

        do CASE "All entities are valid"
            local cache = {}

            for entity in reg:view(ecr.entity) do
                cache[entity] = true
            end

            for _, entity in ids do
                CHECK(cache[entity])
            end
        end
    end

    do CASE "Deprecated id not returned"
        local reg = ecr.registry()
        CREATE_DEPRECATED_ID(reg) -- deprecate key1
        local id2 = reg:create() -- key2

        local ids = {}
        for id in reg:view(ecr.entity) do
            table.insert(ids, id)
        end

        local r_id = ids[1] -- should be key2

        CHECK(#ids == 1 and r_id == id2)
    end
end)

TEST("registry:view()", function()
    local function flip()
        return math.random() > 0.3
    end

    local function empty(t)
        return next(t) == nil
    end

    local function getids(view: ecr.View<...unknown>): { [ecr.Entity]: { unknown } }
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
    local notABs = {}

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
        if not has[A] and not has[B] then table.insert(notABs, id) end
    end

    do CASE "View size"
        CHECK(#reg:view(A) == #As)
        CHECK(#reg:view(B) == #Bs)
        CHECK(#reg:view(A, B, C) >= #ABCs)
        CHECK(#reg:view(A, B):exclude(C) >= #ABnotCs)
    end

    do CASE "View all entities with A"
        local viewed = getids(reg:view(A))
        CHECK(not empty(viewed))
        for _, id in As do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "View all entities with B"
        local viewed = getids(reg:view(B))
        CHECK(not empty(viewed))
        for _, id in Bs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "View all entities with ABC"
        local viewed = getids(reg:view(A, B, C))
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
        local viewed = getids(reg:view(A, B, C):use(C))
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
        local viewed = getids(reg:view(A, B):exclude(C))
        CHECK(not empty(viewed))
        for _, id in ABnotCs do 
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "View all entities without AB"
        local viewed = getids(reg:view(ecr.entity):exclude(A, B))
        CHECK(not empty(viewed))
        for _, id in notABs do 
            local v = viewed[id]
            if not CHECK(v) then continue end
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

    -- runcount, reg, entity, value
    local cc, ce, cv = 0, nil, nil

    local function fn(...)
        cc += 1
        ce, cv = ...
    end

    do 
        local con = reg:added(H):connect(fn)
        local id = reg:create()

        CASE "Adding triggers"
        reg:add(id, H)
        CHECK(cc == 1)
        CHECK(ce == id)
        CHECK(cv == true)

        CASE "Changing does not trigger"
        reg:set(id, H, false)
        CHECK(cc == 1)

        CASE "Removing then adding triggers"
        reg:remove(id, H)
        reg:set(id, H, true)
        CHECK(cc == 2)

        con:disconnect()

        CASE "Adding after disconnect does not trigger"
        reg:remove(id, H)
        reg:set(id, H, true)
        CHECK(cc == 2)
    end

    do CASE "Entity creation"
        reg:added(ecr.entity):connect(fn)

        local id = reg:create()

        CHECK(cc == 3)
        CHECK(ce == id)

        reg:release(id)
        reg:create(id)

        CHECK(cc == 4)
        CHECK(ce == id)
    end
end)

TEST("registry:changing()", function()
    local reg = ecr.registry()
    local id = reg:create()

    local cc, ce, cv, lv = 0, nil, nil, nil

    local function fn(...)
        cc += 1
        lv = reg:get(id, A) -- get current value
        ce, cv = ...
    end

    local con = reg:changing(A):connect(fn)

    CASE "Adding does not trigger"
    reg:set(id, A, true)
    CHECK(cc == 0)

    CASE "Changing triggers"
    reg:set(id, A, false)
    CHECK(cc == 1)
    CHECK(ce == id)
    CHECK(cv == false)
    CHECK(lv == true)

    reg:patch(id, A, function(v)
        return not v
    end)
    CHECK(cc == 2)
    CHECK(ce == id)
    CHECK(cv == true)
    CHECK(lv == false)

    CASE "Removing does not trigger"
    reg:remove(id, A)
    CHECK(cc == 2)

    con:disconnect()

    CASE "Changing after disconnect does not trigger"
    reg:set(id, A, true) -- add
    reg:set(id, A, false) -- change
    CHECK(cc == 2)

    con:reconnect()

    CASE "Changing after reconnect fires again"
    reg:set(id, A, true)
    CHECK(cc == 3)
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

        do CASE "Removing triggers"
            reg:set(id, A, true)
            reg:remove(id, A)
            CHECK(cc == 1)
            CHECK(ce == id)
            CHECK(cv == nil)
            CHECK(lv == true)

            reg:set(id, A, true)
            reg:remove(id, A)
            CHECK(cc == 2)
            CHECK(ce == id)
            CHECK(cv == nil)
            CHECK(lv == true)
        end

        do CASE "Removing via destroy"
            reg:set(id, A, false)
            reg:destroy(id)

            CHECK(cc == 3)
            CHECK(ce == id)
            CHECK(cv == nil)
            CHECK(lv == false)
        end

        con:disconnect()
     
        do CASE "Removing after disconnect does not trigger"
            reg:create(id)
            reg:set(id, A, true)
            reg:remove(id, A)
            CHECK(cc == 3)
        end
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

    do CASE "Entity destruction"
        local reg = ecr.registry()

        local cid
        reg:removing(ecr.entity):connect(function(id_)
            cid = id_
        end)

        local id1 = reg:create()
        local id2 = reg:create()
        reg:release(id1)

        CHECK(cid ~= nil)
        CHECK(cid == id1)

        reg:clear()

        CHECK(cid == id2)
    end
end)

TEST("registry:track()", function()
    local function flip()
        return math.random() > 0.3
    end

    local function empty(t)
        return next(t) == nil
    end

    local function cache_ids(observer: ecr.Observer<unknown>): { [ecr.Entity]: { unknown } }
        local cache = {}
    
        for id, a, b, c in observer do
            cache[id] = { a, b, c }
        end

        return cache
    end

    local reg = ecr.registry()
    local observerA = reg:track(A)
    local observerB = reg:track(B):persist()
    local observerABC = reg:track(A, B, C)
    local observerAnotC = reg:track(A):exclude(C):persist()

    local ids = {}
    local As = {}
    local Bs = {}
    local ABCs = {}
    local AnotCs = {}

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
        if has[A] and not has[C] then table.insert(AnotCs, id) end
    end

    do CASE "Observer size"
        CHECK(#observerA == #As)
        CHECK(#observerB == #Bs)
        CHECK(#observerABC >= #ABCs)
        CHECK(#observerAnotC >= #AnotCs)
    end

    do CASE "Initial components treated as changed"
        do
            local observer = reg:track(A)

            local cache = cache_ids(observer)
            CHECK(not empty(cache))

            for _, id in As do
                local v = cache[id]
                if not CHECK(v) then continue end
                CHECK(v[1] == id)
            end
        end
        do
            local observer = reg:track(A, B, C)
            local cache = cache_ids(observer)
            CHECK(not empty(cache))

            for _, id in ABCs do
                local v = cache[id]
                if not CHECK(v) then continue end
                CHECK(v[1] == id)
                CHECK(v[2] == id)
                CHECK(v[3] == id)
            end
        end
    end

    do CASE "A tracked"
        local cache = cache_ids(observerA)
        CHECK(not empty(cache))
        for _, id in As do
            local v = cache[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
        CHECK(#observerA == 0)
    end

    do CASE "AnotCs tracked"
        local cache = cache_ids(observerAnotC)
        CHECK(not empty(cache))
        for _, id in AnotCs do
            local v = cache[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
        CHECK(#observerAnotC > 0)
    end

    do CASE "ABCs tracked"
        local cache = cache_ids(observerABC)
        CHECK(not empty(cache))
        for _, id in ABCs do
            local v = cache[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == id)
        end
        CHECK(#observerA == 0)
    end

    --observerA:clear()

    do CASE "Changed components tracked after clear"
        CHECK(#observerA == 0)

        reg:set(As[1], A, As[1])

        local ran = false
        for id, v in observerA do
            ran = true
            CHECK(id == As[1])
            CHECK(v == id)
        end
        CHECK(ran)
    end

    do CASE "Changed components updated"
        for _, id in Bs do
            reg:patch(id, B :: number, function(cur)
                return cur + 1
            end)
        end

        for id, v in observerB do
            CHECK(v == id + 1)
        end

        CHECK(#observerB > 0)
    end

    do CASE "Removed components are not returned"
        local removed = {}

        for _, id in Bs do
            if flip() then
                reg:remove(id, B)
                removed[id] = true
            end
        end

        CHECK(not empty(removed))

        for id in observerB do
            CHECK(not removed[id])
        end
    end

    observerA:disconnect()

    do CASE "Changes not recorded if disconnected"
        local size = #observerA
        local id = reg:create()
        reg:set(id, A, 1)
        CHECK(#observerA == size)
    end

    observerA:reconnect():clear()

    do CASE "Changes recorded again after reconnect"
        local cache = {}
        for i = 1, 1e2 do
            local id = reg:create()
            reg:set(id, A, id)
            cache[id] = true
            table.insert(As, id)
        end

        for id, v in observerA do
            CHECK(cache[id])
            CHECK(v == id)
        end
    end

    observerA:clear()
    table.clear(As)

    do CASE "Observer returns up-to-date values despite being changed while disconnected"
        local observer = reg:track(A):clear():persist()
        local id1 = reg:create()
        local id2 = reg:create()
        local id3 = reg:create()

        reg:set(id1, A, 1)
        reg:set(id2, A, 2)
        reg:set(id3, A, 3)

        observer:disconnect()

        reg:remove(id1, A) -- remove id1
        reg:set(id2, A, -2) -- change id2

        local values = {}

        for id, v in observer do
            values[id] = v
        end

        CHECK(#observer == 2)
        CHECK(not values[id1])
        CHECK(values[id2] == -2)
        CHECK(values[id3] == 3)
    end

    do CASE "Observer garbage collection"
        local wref = setmetatable({}, { __mode = "v" })
        wref.observer = observerA
        wref.pool = (observerA :: any).pool
        observerA:disconnect()
        observerA = nil :: any

        if not game then -- check if running in roblox (collect is sandboxed)
            collectgarbage("collect" :: any)
            collectgarbage("collect" :: any)
            collectgarbage("collect" :: any)
            CHECK(not wref.observer)

            local id = reg:create()
            reg:set(id, A, 1)
            reg:remove(id, A) -- internal pool only cleared after event fired again

            collectgarbage("collect" :: any)
            collectgarbage("collect" :: any)
            collectgarbage("collect" :: any)
            CHECK(not wref.pool)
        end
    end

    do CASE "Track multiple"
        local observer = reg:track(A, B, C)
        observer:clear()

        local id1 = reg:create()
        reg:set(id1, C, true)

        local id2 = reg:create()
        reg:set(id2, A, true)

        local id3 = reg:create()
        reg:set(id3, A, 1)
        reg:set(id3, B, 2)
        reg:set(id3, C, 3)

        local runcount = 0
        for id, a, b, c in observer do
            runcount += 1
            CHECK(id == id3)
            CHECK(a == 1 and b == 2 and c == 3)
        end
        CHECK(runcount == 1)
    end
end)

TEST("registry:group()", function()
    local function flip() return math.random() > 0.3 end
    local function empty(t) return next(t) == nil end
    local function getids(group: ecr.Group<...unknown>): { [ecr.Entity]: { unknown } }
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
        local viewed = getids(groupAB)
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
        local viewed = getids(reg:group(A, B))
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
        local viewed = getids(reg:group(C, D, E))
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
        local viewed = getids(reg:group(F, G))
        CHECK(not empty(viewed))
        for _, id in FGs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == nil)
        end
    end

    do CASE "Removing components during group iteration"
        local cache = {}
        local removed = {}

        for id, a, b in reg:group(A, B) do
            CHECK(not cache[id]) -- ensure iterators arent invalidated
            cache[id] = { a, b }
            if flip() then
                removed[id] = true
                reg:remove(id, A)
            end
        end

        CHECK(#reg:group(A, B) > 0)

        for id, a, b in reg:group(A, B) do
            local v = cache[id]
            CHECK(v)
            CHECK(v[1] == a) -- check association is kept after remove
            CHECK(v[2] == b)
            cache[id] = nil
        end

        CHECK(not empty(cache))

        for id in cache do
            local v = removed[id]
            if not v then
                print(id, KEY(id))
            end
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
        reg:remove(id, A)
        CHECK(reg:try_get(id, A) == nil and reg:get(id, C) == 3)
    end

    do CASE "Using owned component for new group errors"
        CHECK_ERR(
            "cannot create group; component (arg #2) is not owned by the same group as previous args",
            function()
                reg:group(F, H)
            end
        )
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
            local id = reg2:create()
            reg2:set(id, A, id)
            reg2:set(id, B, id)
            reg2:set(id, C, id)
            reg2:set(id, D, id)
            reg2:set(id, E, id)
            ids2[i] = id
        end

        reg2:group(A, B, C, D, E)

        local viewed = getids(reg2:group(A, B, C, D, E))

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

    do CASE "Invalidation check"
        local Z, X = ecr.component(), ecr.component()

        reg:group(Z, X)

        local e1 = reg:handle()
        e1:set(Z, true)

        local e2 = reg:handle()
        e2:set(Z, true)

        CHECK_ERR("group reordered during iteration, iterator invalidaton occurred", function()
            for id in reg:view(Z) do
                reg:set(id, X, true)
            end
        end)

        CHECK(not e1:has(X)) -- confirm invalidation occured
    end
end)

TEST("registry:handle()", function()
    local reg = ecr.registry()

    do CASE "Call with nil"
        local e = reg:handle()

        CHECK(reg:contains(e.entity))

        e:set(A, 1)
        :set(B, 2)

        CHECK(e:has(A, B))
    end

    do CASE "Call with existing"
        local id = reg:create()
        local e = reg:handle(id)
        CHECK(e.entity == id)
    end

    do CASE "Caching"
        local e = reg:handle()
        local e2 = reg:handle(e.entity)
        CHECK(e == e2)

        local id = reg:create() 
        local e_b = reg:handle(id)
        local e_b2 = reg:handle(id)
        CHECK(e_b == e_b2)
    end

    do CASE "Garbage collection"
        local weak = setmetatable({}, { __mode = "v" })

        local id = reg:create()

        do
            weak.v = reg:handle(id)
        end

        (collectgarbage :: any)("collect")

        CHECK(weak.v == nil :: any)
    end
end)

TEST("registry:context()", function()
    local reg = ecr.registry()

    local ctx = reg:context()

    do CASE "Context valid"
        CHECK(reg:contains(ctx.entity))
    end

    ctx:set(A, 1):set(B, 2)

    do CASE "Components"
        CHECK(ctx:get(A) == 1)
        CHECK(ctx:get(B) == 2)
    end

    do CASE "Sizes"
        CHECK(#reg == 0)
        CHECK(#reg:view(A) == 1)
    end

    do CASE "Attempt to destroy"
        CHECK_ERR("cannot release id", function()
            ctx:destroy()
        end)
        CHECK_ERR("cannot release id", function()
            reg:release(ctx.entity)
        end)
    end

    reg:clear()

    do CASE "Clearing does not affect"
        CHECK(reg:contains(ctx.entity))
    end
end)

TEST("registry:storage()", function()
    local reg = ecr.registry()

    local id1 = reg:create()
    local id2 = reg:create()

    local a = reg:storage(A)

    do CASE "pool:set() |add|"
        a:set(id1, 1)
        a:set(id2, 2)
        CHECK(a.entities[1] == id1)
        CHECK(a.entities[2] == id2)
        CHECK(a.values[1] == 1)
        CHECK(a.values[2] == 2)
    end

    do CASE "pool:set() |change|"
        a:set(id1, 0)
        a:set(id2, 1)
        CHECK(a.values[1] == 0)
        CHECK(a.values[2] == 1)
    end

    do CASE "pool:get()"
        CHECK(a:get(id1) == 0)
        CHECK(a:get(id2) == 1)
    end

    do CASE "pool:has()"
        CHECK(a:has(id1))
        CHECK(a:has(id2))
    end

    do CASE "pool:remove()"
        a:remove(id1)
        CHECK(a.entities[1] == id2)
        CHECK(a.values[1] == 1)
        CHECK(a.entities[2] == nil)
        CHECK(a.values[2] == nil)
        CHECK(a:get(id2) == 1)

        a:remove(id2)
        CHECK(#a.map == 0)
        CHECK(#a.entities == 0)
        CHECK(#a.values == 0)
    end
end)

TEST("ecr.component()", function()
    do CASE "Components have unique ids"
        local cache = {}
        for i = 1, 1000 do
            local c = ecr.component()
            CHECK(cache[c] == nil)
            cache[c] = true
        end
    end
end)

TEST("ecr.queue()", function()
    do
        local queue = ecr.queue()

        do CASE "Iterate single value"
            for i = 1, 10 do
                queue:add(i)
            end

            CHECK(#queue == 10)

            local i = 0
            for v in queue do
                i += 1
                CHECK(v == i)
            end

            CHECK(#queue == 0)
            CHECK(i == 10)
        end

        do CASE "Iterate multiple values"
            for i = 1, 10 do
                (queue :: any):add(i+1, i+2, i+3)
            end

            CHECK(#queue == 10)

            local i = 0
            for a, b, c in queue do
                i += 1
                CHECK(a == i+1)
                CHECK(b == i+2)
                CHECK(c == i+3)
            end

            CHECK(#queue == 0)
            CHECK(i == 10)
        end
    end

    do CASE "Manual clear"
        local queue = ecr.queue()
        for i = 1, 10 do
            queue:add(i, i+1, i+2)
        end

        CHECK(#queue == 10)

        queue:clear()

        CHECK(#queue == 0)

        for _ in queue do
            CHECK(false)
        end
    end

    do CASE "Uneven values"
        local queue = ecr.queue()
        queue:add(1)
        ;(queue :: any):add(1, 2, nil)
        ;(queue :: any):add(1, nil, 3)

        local i = 0
        for a, b, c in queue do
            i += 1
            if i == 1 then CHECK(a == 1 and b == nil and c == nil)
            elseif i == 2 then CHECK(a == 1 and b == 2 and c == nil)
            elseif i == 3 then CHECK(a == 1 and b == nil and c == 3)
            else CHECK(false) end
        end
    end

    do CASE "Nil value first"
        local queue = ecr.queue()
        CHECK_ERR("first value cannot be nil", function()
            queue:add(nil, 1, 2, 3)
        end)
    end

    do CASE "Automatic signal connection"
        local listener: (...any) -> ()
        local signal = {
            connect = function(_, fn)
                listener = fn
            end
        }

        local queue = ecr.queue(signal)

        listener(1, 2, 3)

        CHECK(#queue == 1)
        for a, b, c in queue do
            CHECK(a == 1 and b == 2 and c == 3)
        end
    end
end)

TEST("ecr.name()", function()
    local cts = ecr.name ({
        A = ecr.component() :: number,
        B = ecr.component() :: string
    })

    local reg = ecr.registry()

    local id = reg:create()

    CHECK_ERR(`entity does not have component "A"`, function()
        reg:get(id, cts.A)
    end)

    CHECK_ERR(`no constructor defined for component "B"`, function()
        reg:add(id, cts.B)
    end)

end)

TEST("ecr.tag()", function()
    local TA, TB, TC, TD = ecr.tag(), ecr.tag(), ecr.tag(), ecr.tag()

    do CASE "Is tag"
        CHECK(ecr.is_tag(TA))
        CHECK(not ecr.is_tag(A))
    end

    local reg = ecr.registry()

    local e = reg:handle()

    do CASE "Add"
        local ran = false
        reg:added(TA):connect(function(id, v)
            ran = true
            CHECK(id == e.entity)
            CHECK(v == nil)
        end)

        e:add(TA)

        CHECK(e:has(TA))
        CHECK(e:get(TA) == nil)
        CHECK(ran)
    end

    do CASE "View"
        local i = 0
        for id, tag in reg:view(TA) do
            i += 1
            CHECK(i == 1)
            CHECK(tag == nil)
        end
    end

    -- multi-type views return values by unpacking a table
    -- the concern here is since tag values are nil, there is potential for
    -- undefined behavior with unpacking an array with holes
    -- we pre-allocate the arrays so the above should not be an issue
    do CASE "View unpack"
        e:add(TB, TC, TD)
        e:set(A, true)

        local ran = 0

        for id, ta, tb, tc, td, a in reg:view(TA, TB, TC, TD, A) do
            ran += 1
            CHECK(a == true)
        end

        for id, ta, tb, tc, td, a in reg:track(TA, TB, TC, TD, A) do
            ran += 1
            CHECK(a == true)
        end

        for id, ta, tb, tc, td, a in reg:group(TA, TB, TC, TD, A) do
            ran += 1
            CHECK(a == true)
        end

        CHECK(ran == 3)
    end

    do CASE "Remove"
        e:remove(TA)
        CHECK(not e:has(TA))
    end

    -- tags are implemented as normal components internally
    -- further testing should not be necessary
end)

TEST("Random usage test", function()
    --[[
        This test simulates modifying a registry through a sequence of systems
        by randomly creating, destroying, adding, updating, removing entities
        and their components.

        Each component value contains the id of the entity that owns it as well
        as a counter that is maintained separately from the registry.

        To check if the case passes we check if the two independent counters
        match up and that the id in the component corresponds to the entity that
        owns it.
    ]]

    local reg = ecr.registry()

    local function flip(p: number?)
        return math.random() > (p and (1 - p) or 0.5)
    end

    -- set of all ids in use
    local idcount = 0
    local ids = {} :: { [ecr.Entity]: true }

    -- array of all destroyed ids
    local frees = {} :: { ecr.Entity }

    -- map component to entity to value
    local incs = {} :: Map<unknown, Map<ecr.Entity, number>>

    local cts = {} :: Array<{ id: ecr.Entity, v: number }>

    for i = 1, 5 do
        local ctype = ecr.component()
        cts[i] = ctype :: any
        incs[ctype] = {}
    end

    local group1 = reg:group(cts[1], cts[3])
    local group2 = reg:group(cts[2], cts[4], cts[5])

    for i = 1, N do
        if flip(0.6) then
            local id = reg:create()
            ids[id] = true
            idcount += 1
        end

        do
            local id = table.remove(frees)
            if flip(0.2) and id then
                local ok = pcall(reg.create, reg, id)
                ids[id] = ok or nil :: any
                idcount += 1
            end
        end

        for _, ctype in cts do
            local inc = incs[ctype]

            for id in ids do
                -- add component
                if flip() and not inc[id] then
                    inc[id] = 0
                    --
                    if not reg:try_get(id, ctype) then
                        reg:set(id, ctype, { id = id, v = 0 })
                    end
                end

                -- increment component
                if flip() and inc[id] then
                    inc[id] += 1
                    --
                    reg:patch(id, ctype, function(old)
                        return { id = old.id, v = old.v + 1 }
                    end)
                end

                -- decrement component
                if flip(0.2) and inc[id] then
                    inc[id] -= 1
                    --
                    local old = reg:get(id, ctype)
                    reg:set(id, ctype, { id = old.id, v = old.v - 1 })
                end

                -- remove component
                if flip(0.1) and inc[id] then
                    inc[id] = nil
                    --
                    reg:remove(id, ctype)
                end
            end
        end

        for id in ids do
            -- destroy id
            if flip(0.005) then
                ids[id] = nil
                idcount -= 1
                table.insert(frees, id)
                for _, inc in incs do
                    inc[id] = nil
                end
                --
                reg:destroy(id)
            end
        end
    end

    local ran = 0

    for _, ctype in cts do
        local inc = incs[ctype]

        for id in ids do
            ran += 1
            local component = reg:try_get(id, ctype) :: any
            if inc[id] then
                CHECK(component)
                CHECK(inc[id] == component.v)  
                CHECK(component.id == id) 
            else
                CHECK(not component)
            end
        end
    end

    for id in reg:view(ecr.entity) do
        CHECK(ids[id])
    end

    CHECK(#group1 > 0 and #group2 > 0)
    CHECK(ran > 0)
    CHECK(idcount > 50)
    --testkit.print2(incs)
end)

local success = FINISH()
if not success then error(nil, 0) end
