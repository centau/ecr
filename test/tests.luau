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

local TA, TB, TC, TD = ecr.tag(), ecr.tag(), ecr.tag(), ecr.tag()

local DEFER_ID_REUSE = ecr._test.defer_id_reuse
local MAX_VER = ecr._test.max_ver

local function KEY(id: ecr.entity): number
    local key = ecr.inspect(id)
    return key
end

local function VER(id: ecr.entity): number
    local _, ver = ecr.inspect(id)
    return ver
end

local function GET_KEY_VERSION(reg: ecr.Registry, key: number): number
    return ecr._test.get_key_version(reg:storage(ecr.entity) :: any, key)
end

local function CREATE_ID(key: number, ver: number)
    return ecr._test.create_id(key, ver)
end

local function SET_KEY_VERSION(reg: ecr.Registry, key: number, ver: number)
    reg:release(reg:create(CREATE_ID(key, 1))) -- ensure key exists
    ecr._test.set_key_version(reg:storage(ecr.entity) :: any, key, ver)
end

local function CREATE_DEPRECATED_ID(reg: ecr.Registry): ecr.entity
    local id = reg:create()
    reg:release(id)
    SET_KEY_VERSION(reg, KEY(id), MAX_VER)
    id = reg:create()
    reg:release(id)
    return id
end

local function BULK_CREATE_IDS(reg: ecr.Registry, n: number): { ecr.entity }
    local ids = table.create(n)
    for i = 1, n do
        ids[i] = reg:create()
    end
    return ids
end

local N = 1e3

TEST("registry:create()", function()
    do CASE "new ids unique"
        local reg = ecr.registry()
        local cache = {}

        for i = 1, N do
            local id = reg:create()
            CHECK(not cache[id])
            cache[id] = true
        end
    end

    do CASE "reusing keys produce unique ids"
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
            local id = reg:create()
            CHECK(not cache[id])
            cache[id] = true
        end
    end

    do CASE "use specific id"
        do -- copy ids from a server registry to a new registry in random order
            local sreg = ecr.registry()

            local ids = BULK_CREATE_IDS(sreg, N)

            -- randomize id array order
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

        do -- test internal linked list order
            local reg = ecr.registry()
            reg:create(CREATE_ID(3, 2))
            CHECK(reg:create() == CREATE_ID(1, 1))
            CHECK(reg:create() == CREATE_ID(2, 1)) 
            CHECK(reg:create() == CREATE_ID(4, 1))
        end
    end

    do CASE "reuse previously used id"
        do
            local reg = ecr.registry()
            local id = reg:create()
            reg:release(id)
            reg:create(id)
            CHECK(reg:contains(id))
        end

        do -- test internal linked list order and version tracking
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

    do CASE "reuse deprecated id"
        local reg = ecr.registry()
        local id = CREATE_DEPRECATED_ID(reg)
        reg:create(id)
        CHECK(reg:contains(id))
        CHECK(VER(id) == MAX_VER)
    end

    do CASE "error if key is already in use"
        local sreg = ecr.registry()
        local id = sreg:create()

        local reg = ecr.registry()

        CHECK(id == reg:create())

        CHECK_ERR("key already in use", function()
            reg:create(id)
        end)
    end

    do CASE "error if null is used"
        local reg = ecr.registry()

        CHECK_ERR("malformed id", function()
            reg:create(ecr.null)
        end)
    end

    do CASE "entity limit"
        -- 2 ids reserved: ctx and null
        local LIMIT = 2^16 - 2

        local reg = ecr.registry()

        for i = 1, LIMIT do
            reg:create()
        end

        CHECK(not reg:contains(ecr.null))

        CHECK_ERR("entity limit reached", function()
            reg:create()
        end)
    end
end)

TEST("registry:release()", function()
    local reg = ecr.registry()

    do CASE "released entities invalid"
        local id = reg:create()
        reg:release(id)
        CHECK(not reg:contains(id))
    end

    do CASE "release invalid id"
        local id = reg:create()
        reg:release(id)
        CHECK_ERR("invalid entity", function()
            reg:release(id)
        end)
    end

    do CASE "release null id"
        CHECK_ERR("invalid entity", function()
            reg:release(ecr.null)
        end)
    end

    do CASE "release deprecated id"
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

        do CASE "new entity valid"
            CHECK(reg:contains(id))
        end

        reg:release(id)

        do CASE "released entity invalid"
            CHECK(not reg:contains(id))
        end

        local newid = reg:create()

        do CASE "id with reused key valid"
            CHECK(reg:contains(newid))
        end

        do CASE "released entity still invalid despite key reuse"
            CHECK(not reg:contains(id))
        end

        do CASE "id that has not been created yet"
            local sreg = ecr.registry()
            for i = 1, 10 do sreg:create() end
            local id2 = sreg:create()
            CHECK(not reg:contains(id2))
        end
    end

    do CASE "integer invalid"
        local id = reg:create()
        assert(KEY(id) == 2)
        CHECK(not reg:contains(2))
    end

    do CASE "null entity invalid"
        CHECK(not reg:contains(ecr.null))
    end

    do CASE "deprecated id invalid"
        local id = CREATE_DEPRECATED_ID(reg)
        CHECK(not reg:contains(id))
    end
end)

TEST("registry:version()", function()
    local reg = ecr.registry()

    do CASE "get version"
        local id = reg:create()
        CHECK(VER(id) == 1)
    end

    do CASE "version increments on reuse"
        local id_old = reg:create()
        CHECK(VER(id_old) == 1)
        reg:destroy(id_old)
        local id_new = reg:create()
        CHECK(VER(id_old) == 1)
        CHECK(VER(id_new) == 2)
    end
end)

TEST("registry:current()", function()
    local reg = ecr.registry()
    local id_old = reg:create()
    reg:release(id_old)
    local id_new = reg:create()

    do CASE "get current version"
        CHECK(VER(id_old) == 1)
        CHECK(GET_KEY_VERSION(reg, KEY(id_old)) == 2)
    end

    do CASE "version increments on release"
        reg:release(id_new)
        CHECK(GET_KEY_VERSION(reg, KEY(id_new)) == 3)
    end
end)

TEST("registry:add()", function()
    local ADD_A = ecr.component(function() return true end)
    local ADD_B = ecr.component(function() return false end)
    local ADD_C = ecr.component(function() return nil end)

    local reg = ecr.registry()

    do CASE "add components"
        local id = reg:create()
        reg:add(id, ADD_A, ADD_B)
        CHECK(reg:has(id, ADD_A))
        CHECK(reg:has(id, ADD_B))
    end

    do CASE "add an already added component does nothing"
        local id = reg:create()
        reg:set(id, ADD_A, false)
        reg:add(id, ADD_A)
        CHECK(reg:get(id, ADD_A) == false)
    end

    do CASE "add a component with no constructor errors"
        CHECK_ERR("no constructor defined for component (arg #1)", function()
            local id = reg:create()
            reg:add(id, B)
        end)
    end

    do CASE "constructor returning nil errors"
        CHECK_ERR("component (arg #1) constructor did not return a value", function()
            local id = reg:create()
            reg:add(id, ADD_C)
        end)
    end

    do CASE "add component to invalid id with unused key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:add(id, ADD_A)
        end)
    end

    do CASE "add component to invalid id with used key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:create() -- reuse key
            reg:add(id, ADD_A)
        end)
    end

    do CASE "add component to invalid id with used key with component"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            local newid = reg:create() -- reuse key
            reg:add(newid, ADD_A)
            reg:add(id, A)
        end)
    end

    do CASE "add component to null entity"
        CHECK_ERR("invalid entity", function()
            reg:add(ecr.null, ADD_A)
        end)
    end
end)

TEST("registry:set()", function()
    local reg = ecr.registry()

    do
        local id = reg:create()

        do CASE "add component"
            reg:set(id, A, 1)
            CHECK(reg:get(id, A) == 1)
        end

        do CASE "change component"
            reg:set(id, A, 2)
            CHECK(reg:get(id, A) == 2)
        end

        do CASE "remove component"
            reg:remove(id, A)
            CHECK(reg:try_get(id, A) == nil)
            CHECK(not reg:has(id, A))
        end
    end

    do CASE "add component to invalid id with unused key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:set(id, A, 1)
        end)
    end

    do CASE "add component to invalid id with used key"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            reg:create() -- reuse key
            reg:set(id, A, 1)
        end)
    end

    do CASE "add component to invalid id with used key that has component"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)

            local newid = reg:create() -- reuse key
            reg:set(newid, A, 0)

            reg:set(id, A, 1)
        end)
    end

    do CASE "add component to null entity"
        CHECK_ERR("invalid entity", function()
            reg:set(ecr.null, A, true)
        end)
    end

    do CASE "add component to deprecated id"
        CHECK_ERR("invalid entity", function()
            local id = CREATE_DEPRECATED_ID(reg)
            reg:set(id, A, 1)
        end)
    end

    do CASE "change component of invalid entity with used key with component"
        CHECK_ERR("invalid entity", function()
            local id = reg:create()
            reg:release(id)
            
            local newid = reg:create() -- reuse key
            reg:set(newid, A, 1)

            reg:set(id, A, 2)
        end)
    end

    do CASE "attempt to set nil value"
        CHECK_ERR("cannot set component value to nil", function()
            local id = reg:create()
            reg:set(id, A, nil)
        end)
    end

    do CASE "set tag"
        local id = reg:create()
        reg:set(id, TA, nil)
        CHECK(reg:has(id, TA))
    end
end)

TEST("registry:get()", function()
    local reg = ecr.registry()

    do
        local id = reg:create()

        do CASE "get component"
            reg:set(id, A, 1)
            CHECK(reg:get(id, A) == 1)
        end

        do CASE "get multiple components"
            reg:set(id, B, 2)
            reg:set(id, C, 3)
            reg:set(id, D, 4)

            local values = { reg:get(id, A, B, C, D) }

            for i, value in values do
                CHECK(value == i)
            end
        end

        do CASE "get nil component"
            reg:remove(id, A)
            CHECK_ERR("entity does not have component (arg #1)", function()
                reg:get(id, A)
            end)
        end
    end

    do CASE "get component of invalid id"
        local id = reg:create()
        reg:release(id)
        CHECK_ERR("entity does not have component (arg #1)", function()
            reg:get(id, A)
        end)
    end

    do CASE "get component of invalid id with used key that has component"
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

    do CASE "get nil component"
        local id = reg:create()
        reg:remove(id, A)
        CHECK(reg:try_get(id, A) == nil)
    end

    do CASE "get component of invalid id"
        local id = reg:create()
        reg:release(id)
        CHECK(reg:try_get(id, A) == nil)
    end

    do CASE "get component of invalid id with used key that has component"
        local id = reg:create()
        reg:release(id)

        local newid = reg:create()
        reg:set(newid, A, 1)

        CHECK(reg:try_get(id, A) == nil)
    end
end)

TEST("registry:has()", function()
    local reg = ecr.registry()
    
    do
        local id = reg:create()

        do CASE "has component"
            reg:set(id, A, true)
            CHECK(reg:has(id, A) == true)

            reg:set(id, B, true)
            CHECK(reg:has(id, A, B))
        end

        do CASE "does not have component"
            reg:remove(id, A)
            CHECK(reg:has(id, A) == false)
            CHECK(reg:has(id, B, A) == false)
        end
    end

    do CASE "invalid entity"
        local id = reg:create()
        reg:release(id)
        CHECK(reg:has(id, A) == false)
    end

    do CASE "invalid entity with used key that has component"
        local id = reg:create()
        reg:release(id)

        local newid = reg:create()
        reg:set(newid, A, 1)

        CHECK(reg:has(id, A) == false)
    end
end)

TEST("registry:insert()", function()
    local ARRAY = ecr.component() :: {number}
    local reg = ecr.registry()
    local id = reg:create()
    
    do CASE "insert adds array if no value"
        reg:insert(id, ARRAY, 1)

        CHECK(reg:has(id, ARRAY))
        CHECK(type(reg:get(id, ARRAY)) == "table")
        CHECK(reg:get(id, ARRAY)[1] == 1)
    end

    do CASE "insert adds values to the end"
        reg:insert(id, ARRAY, 2)

        CHECK(reg:has(id, ARRAY))
        CHECK(type(reg:get(id, ARRAY)) == "table")
        CHECK(reg:get(id, ARRAY)[1] == 1)
        CHECK(reg:get(id, ARRAY)[2] == 2)
    end

end)

TEST("registry:patch()", function()
    local reg = ecr.registry()

    do CASE "change component"
        local id = reg:create()
        reg:set(id, A, 0)

        local ran = false
        reg:on_change(A):connect(function()
            ran = true
        end)

        reg:patch(id, A :: number, function(v)
            CHECK(v == 0)
            return v + 1
        end)
        CHECK(reg:get(id, A) == 1)
        CHECK(ran)
    end

    do CASE "patch returns nil"
        local id = reg:create()
        reg:set(id, A, true)
        
        CHECK_ERR("function cannot return nil", function()
            reg:patch(id, A :: number, function(v)
                return nil :: any
            end)
        end)
    end

    do CASE "change non-existent component"
        local id = reg:create()

        CHECK_ERR("entity does not have component and no constructor for component (unknown)", function()
            reg:patch(id, A :: number, function(v)
                CHECK(false)
                return v + 1
            end)
        end)
    end

    do CASE "add non-existent component without constructor"
        local id = reg:create()
        
        local ran = false
        reg:on_add(H):connect(function()
            ran = true
        end)
        
        reg:patch(id, H)

        CHECK(ran)
        CHECK(reg:get(id, H) == true)
    end

    do CASE "change non-existent component with constructor"
        local id = reg:create()
        
        local ran = false
        reg:on_add(H):connect(function()
            ran = true
        end)
        
        reg:patch(id, H, function(v)
            CHECK(v == true)
            return not v
        end)

        CHECK(ran)
        CHECK(reg:get(id, H) == false)

        CHECK_ERR("function cannot return nil", function()
            reg:patch(id, H, function(v)
                return nil :: any
            end)
        end)
    end

    do CASE "invalid id"
        local id = reg:create()
        reg:release(id)
        
        CHECK_ERR("invalid entity", function()
            reg:patch(id, A :: number, function(v)
                CHECK(false)
                return v + 1
            end)
        end)
    end

    do CASE "invalid id that shares same key with id that has component"
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

        do CASE "remove single component"
            reg:remove(id, A)
            CHECK(reg:has(id, A) == false)
            CHECK(reg:get(id2, A) == 2) -- check removal maintains associativity
        end

        do CASE "remove multiple components"
            reg:remove(id, B, C)
            CHECK(reg:has(id, B) == false)
            CHECK(reg:has(id, C) == false)
        end
    end

    do CASE "remove component from invalid entity"
        local id = reg:create()
        reg:release(id)

        local ok = pcall(function()
            reg:remove(id, A)
        end)

        CHECK(ok)
    end

    do CASE "remove component from invalid id that shares key with entity that has component"
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

TEST("registry:find()", function()
    local reg = ecr.registry()

    local ids = BULK_CREATE_IDS(reg, 5)

    for i, id in ids do
        reg:set(id, A, i)
        reg:set(id, TA)
    end

    CHECK(reg:find(A, 1) == ids[1])
    CHECK(reg:find(A, 3) == ids[3])
    CHECK(reg:find(A, 5) == ids[5])

    CHECK(reg:find(A, 6) == nil)
    reg:clear(A) 
    CHECK(reg:find(A, 1) == nil)

    CHECK(reg:find(TA) == ids[1])
    reg:clear(TA)
    CHECK(reg:find(TA) == nil)
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

        do CASE "clear A"
            reg:clear(A)
            CHECK(reg:has(id1, A) == false)
            CHECK(reg:has(id2, A) == false)
        end

        do CASE "clear B and C"
            reg:clear(B, C)
            CHECK(reg:has(id1, B) == false)
            CHECK(reg:has(id2, B) == false)
            CHECK(reg:has(id1, C) == false)
            CHECK(reg:has(id2, C) == false)
        end
    end

    do CASE "clear entities"
        local reg = ecr.registry()
    
        -- deprecate key = 1
        assert(KEY(CREATE_DEPRECATED_ID(reg)) == 1)

        -- set key = 2 version to max
        SET_KEY_VERSION(reg, 2, MAX_VER)
        do
            local id = reg:create()
            assert(KEY(id) == 2)
            assert(VER(id) == MAX_VER)
        end

        local ids = table.create(N)
        for i = 1, N do
            ids[i] = reg:create()
            if i == N/2 then
                reg:release(ids[i])
                ids[i] = reg:create()
            end
        end

        reg:clear()

        local ids_after = BULK_CREATE_IDS(reg, N)

        if DEFER_ID_REUSE then
            CHECK(KEY(ids_after[1]) == 3) -- key = 1 should not be reused
            CHECK(KEY(ids_after[2]) == 4) -- key = 2 should now be deprecated

            for i = 1, N do
                CHECK(KEY(ids_after[i]) ~= 1)
                CHECK(KEY(ids_after[i]) ~= 2)
                CHECK(VER(ids[i]) + 1 == VER(ids_after[i]))
            end
        else
            for i = 1, N do
                if i == 1 then
                    assert(ids[i] == CREATE_ID(1, 1))
                    CHECK(ids_after[i] == CREATE_ID(2, 1))
                elseif i == 2 then
                    assert(ids[i] == CREATE_ID(3, 1))
                    CHECK(ids_after[i] == CREATE_ID(1, 2))
                else
                    CHECK(VER(ids[i - 1]) + 1 == VER(ids_after[i]))
                end
            end
        end
    end

    do CASE "clear with groups"
        local reg = ecr.registry()
        reg:group(A, B)

        local listener = { count = 0 } :: { id: number?, count: number }

        reg:on_remove(A):connect(function(id)
            listener.id = id
            listener.count += 1
        end)

        local eB = reg:handle():set(B, 2)
        local eAB = reg:handle():set(A, 1):set(B, 1)

        reg:clear(A)

        CHECK(reg:storage(A).size == 0)
        CHECK(listener.id == eAB.entity and listener.count == 1)

        eAB:set(A, 1) -- 1
        eB:set(A, 2) -- 2

        eAB:remove(A)

        CHECK(reg:storage(A).size == 1)
        local pool = reg:storage(A)
        local entities = ecr.buffer_to_array(pool.entities, pool.size)
        CHECK(entities[1] == eB.entity)
    end
end)

TEST("registry:has_none()", function()
    local reg = ecr.registry()
    local id = reg:create()

    do CASE "new entity is has none"
        CHECK(reg:has_none(id))
    end

    reg:set(id, B, 1)

    do CASE "no longer has none after assigning component"
        CHECK(not reg:has_none(id))
    end

    reg:remove(id, B)

    do CASE "has none after removing last component"
        CHECK(reg:has_none(id))
    end

    reg:release(id) -- UB

    do CASE "rejects invalid entity"
        CHECK_ERR("invalid entity", function()
            reg:has_none(id)
        end)
    end
end)

TEST("registry:destroy()", function()
    local reg = ecr.registry()

    do CASE "component was removed"
        local id = reg:create()

        reg:set(id, A, 1)
        reg:set(id, B, 1)

        reg:destroy(id)

         -- do not rely on this behavior
        CHECK(not reg:contains(id))
        CHECK(not reg:has(id, A))
        CHECK(not reg:has(id, B))
    end

    do CASE "destroy invalid id"
        local id = reg:create()
        reg:release(id)

        CHECK_ERR("invalid entity", function()
            reg:destroy(id)
        end)
    end

    do CASE "destroy deprecated id"
        local id = CREATE_DEPRECATED_ID(reg)

        CHECK_ERR("invalid entity", function()
            reg:destroy(id)
        end)
    end
end)

TEST("#registry", function()
    local reg = ecr.registry()

    do CASE "initial registry size is 0"
        CHECK(#reg:view(ecr.entity) == 0)
    end

    local id = reg:create()

    do CASE "size after entity creation"
        CHECK(#reg:view(ecr.entity) == 1)
    end

    reg:release(id)

    do CASE "size after entity release"
        CHECK(#reg:view(ecr.entity) == 0)
    end

    for i = 1, 100 do reg:create() end

    do CASE "mass creation"
        CHECK(#reg:view(ecr.entity) == 100)
    end

    reg:clear()

    do CASE "size after clear"
        CHECK(#reg:view(ecr.entity) == 0)
    end

    reg:create(id)

    do CASE "size after specific entity creation"
        CHECK(#reg:view(ecr.entity) == 1)
    end

    do CASE "size after context entity creation"
        reg:context()
        CHECK(#reg:view(ecr.entity) == 2)
    end
end)

TEST("registry:view(ecr.entity)", function()
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

        do CASE "all entities are valid"
            local cache = {}

            for entity in reg:view(ecr.entity) do
                cache[entity] = true
            end

            for _, entity in ids do
                CHECK(cache[entity])
            end
        end
    end

    do CASE "deprecated id not returned"
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

    local function getids(view: ecr.View<...unknown>): { [ecr.entity]: { unknown } }
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
    local ABs = {}
    local ABCs = {}
    local AnotCs = {}
    local ABnotCs = {}
    local AnotBCs = {}
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
        if has[A] and not has[C] then table.insert(AnotCs, id) end
        if has[A] and has[B] then table.insert(ABs, id) end
        if has[A] and has[B] and has[C] then table.insert(ABCs, id) end
        if has[A] and has[B] and not has[C] then table.insert(ABnotCs, id) end
        if has[A] and not has[B] and not has[C] then table.insert(AnotBCs, id) end
        if not has[A] and not has[B] then table.insert(notABs, id) end
    end

    do CASE "view size"
        CHECK(#reg:view(A) == #As)
        CHECK(#reg:view(B) == #Bs)
        CHECK(#reg:view(A, B, C) >= #ABCs)
        CHECK(#reg:view(A, B):exclude(C) >= #ABnotCs)
    end

    do CASE "view all entities with A"
        local viewed = getids(reg:view(A))
        CHECK(not empty(viewed))
        for _, id in As do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "view all entities with B"
        local viewed = getids(reg:view(B))
        CHECK(not empty(viewed))
        for _, id in Bs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
    end

    do CASE "view all entities with AB"
        local viewed = getids(reg:view(A, B))
        CHECK(not empty(viewed))
        for _, id in ABs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
        end
    end

    do CASE "view all entities with ABC"
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

    -- do CASE "view all entities with ABC using C"
    --     local viewed = getids(reg:view(A, B, C):use(C))
    --     CHECK(not empty(viewed))
    --     for _, id in ABCs do
    --         local v = viewed[id]
    --         if not CHECK(v) then continue end
    --         CHECK(v[1] == id)
    --         CHECK(v[2] == id)
    --         CHECK(v[3] == id)
    --     end
    -- end

    do CASE "view all entities with A and not C"
        local viewed = getids(reg:view(A):exclude(C))
        CHECK(not empty(viewed))
        for _, id in AnotCs do 
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
        for id in viewed do
            CHECK(not reg:has(id, C))
        end
    end

    do CASE "view all entities with AB and not C"
        local viewed = getids(reg:view(A, B):exclude(C))
        CHECK(not empty(viewed))
        for _, id in ABnotCs do 
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
        for id in viewed do
            CHECK(not reg:has(id, C))
        end
    end

    do CASE "view all entities with A and not BC"

        local viewed = getids(reg:view(A):exclude(B, C))
        CHECK(not empty(viewed))
        for _, id in AnotBCs do
            local v = viewed[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
        for id in viewed do
            CHECK(not reg:has(id, B))
            CHECK(not reg:has(id, C))
        end
    end

    do CASE "view all entities without AB"
        local viewed = getids(reg:view(ecr.entity):exclude(A, B))
        CHECK(not empty(viewed))
        for _, id in notABs do 
            local v = viewed[id]
            if not CHECK(v) then continue end
        end
        for id in viewed do
            CHECK(not reg:has(id, A))
            CHECK(not reg:has(id, B))
        end
    end

    do CASE "addition during view iteration"
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

    do CASE "component removal during view iteration"
        local viewed = {}
        for id in reg:view(A) do
            if flip() then
                reg:remove(id, A)
                table.remove(As, table.find(As, id))
            end
            viewed[id] = true
        end
        CHECK(not empty(viewed))
        for _, entity in As do -- check that an entity isn't skipped due to reordering interally
            CHECK(viewed[entity])
        end
    end

    -- do CASE "duplicate include errors"
    --     local ok = pcall(function()
    --         reg:view(A, B, A)
    --     end)
    --     CHECK(not ok)
    -- end

    do CASE "exclude an include errors"
        local ok = pcall(function()
            reg:view(A, B):exclude(C, A)
        end)
        CHECK(not ok)
    end

    do CASE "view patch single"
        local expected_values = {}

        for id, v in reg:view(A) do
            expected_values[id] = v + 1
        end

        reg:view(A :: number):patch(function(v) return v + 1 end)

        for id, v in reg:view(A) do
            CHECK(v == expected_values[id])
        end
    end

    do CASE "view patch double"
        local expected_values = {}

        for id, a, b in reg:view(A, B) do
            expected_values[id] = { a + 1, b + 2 }
        end

        reg:view(A :: number, B :: number):patch(function(a, b) return a + 1, b + 2 end)

        for id, a, b in reg:view(A, B) do
            CHECK(a == expected_values[id][1])
            CHECK(b == expected_values[id][2])
        end
    end

    do CASE "view patch double (reverse query order)"
        local expected_values = {}

        for id, a, b in reg:view(B, A) do
            expected_values[id] = { a + 1, b + 2 }
        end

        reg:view(B :: number, A :: number):patch(function(a, b) return a + 1, b + 2 end)

        for id, a, b in reg:view(B, A) do
            CHECK(a == expected_values[id][1])
            CHECK(b == expected_values[id][2])
        end
    end

    do CASE "view patch multi"
        local expected_values = {}

        for id, a, b, c in reg:view(A, B, C) do
            expected_values[id] = { a + 1, b + 2, c + 3 }
        end

        reg:view(A :: number, B :: number, C :: number):patch(function(a, b, c)
            return a + 1, b + 2, c + 3
        end)

        for id, a, b, c in reg:view(A, B, C) do
            CHECK(a == expected_values[id][1])
            CHECK(b == expected_values[id][2])
            CHECK(c == expected_values[id][3])
        end
    end
end)

TEST("registry:on_add()", function()
    local reg = ecr.registry()

    -- runcount, reg, entity, value
    local cc, ce, cv = 0, nil, nil

    local function fn(...)
        cc += 1
        ce, cv = ...
    end

    do 
        local con = reg:on_add(H):connect(fn)
        local id = reg:create()

        CASE "adding triggers"
        reg:add(id, H)
        CHECK(cc == 1)
        CHECK(ce == id)
        CHECK(cv == true)

        CASE "changing does not trigger"
        reg:set(id, H, false)
        CHECK(cc == 1)

        CASE "removing then adding triggers"
        reg:remove(id, H)
        reg:set(id, H, true)
        CHECK(cc == 2)

        con:disconnect()

        CASE "adding after disconnect does not trigger"
        reg:remove(id, H)
        reg:set(id, H, true)
        CHECK(cc == 2)
    end

    do CASE "entity creation"
        reg:on_add(ecr.entity):connect(fn)

        local id = reg:create()

        CHECK(cc == 3)
        CHECK(ce == id)

        reg:release(id)
        reg:create(id)

        CHECK(cc == 4)
        CHECK(ce == id)
    end
end)

TEST("registry:on_change()", function()
    local reg = ecr.registry()
    local id = reg:create()

    local cc, ce, cv, ov = 0, nil, nil, nil

    local function fn(...)
        cc += 1
        ce, cv = ...
        ov = reg:get(..., A)
    end

    local con = reg:on_change(A):connect(fn)

    CASE "adding does not trigger"
    reg:set(id, A, true)
    CHECK(cc == 0)

    CASE "changing triggers"
    reg:set(id, A, false)
    CHECK(cc == 1)
    CHECK(ce == id)
    CHECK(cv == false)
    CHECK(ov == true)

    reg:patch(id, A, function(v)
        return not v
    end)
    CHECK(cc == 2)
    CHECK(ce == id)
    CHECK(cv == true)

    CASE "removing does not trigger"
    reg:remove(id, A)
    CHECK(cc == 2)

    con:disconnect()

    CASE "changing after disconnect does not trigger"
    reg:set(id, A, true) -- add
    reg:set(id, A, false) -- change
    CHECK(cc == 2)

    con:reconnect()

    CASE "changing after reconnect fires again"
    reg:set(id, A, true)
    CHECK(cc == 3)
end)

TEST("registry:on_remove()", function()
    do
        local reg = ecr.registry()
        local id = reg:create()

        local cc, ce, cv, lv = 0, nil, nil, nil

        local function fn(...)
            cc += 1
            lv = reg:get(id, A) -- get current value
            ce, cv = ...
        end

        local con = reg:on_remove(A):connect(fn)

        do CASE "removing triggers"
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

        do CASE "removing via destroy"
            reg:set(id, A, false)
            reg:destroy(id)

            CHECK(cc == 3)
            CHECK(ce == id)
            CHECK(cv == nil)
            CHECK(lv == false)
        end

        con:disconnect()
     
        do CASE "removing after disconnect does not trigger"
            reg:create(id)
            reg:set(id, A, true)
            reg:remove(id, A)
            CHECK(cc == 3)
        end
    end

    do CASE "clearing components fires removing event"
        local reg = ecr.registry()

        local entities = {}

        for i = 1, 1e3 do
            entities[i] = reg:create()
            reg:set(entities[i], A, true)
        end

        local cache = {}

        reg:on_remove(A):connect(function(entity)
            cache[entity] = true
        end)

        reg:clear(A)

        for _, entity in entities do
            CHECK(cache[entity])
        end
    end

    do CASE "entity destruction"
        local reg = ecr.registry()

        local cid
        reg:on_remove(ecr.entity):connect(function(id_)
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

TEST("signals", function()
    local reg = ecr.registry()

    do CASE "firing after disconnecting"
        local run = false
        local dont_run = true
        local a = reg:on_add(A):connect(function() run = true end) -- idx 1
        local b = reg:on_add(A):connect(function() dont_run = false end) -- idx 2
        -- {A, B}
        a:disconnect()
        -- {B}
        a:reconnect()
        -- {B, A}
        local _c = reg:on_add(A):connect(function() end) -- idx 3
        -- {B, A, C}
        b:disconnect()
        -- should be {A, C}, not {B, C}
        reg:handle():set(A, true)
        CHECK(run)
        CHECK(dont_run)
    end
    
end)

TEST("registry:track()", function()
    local function flip()
        return math.random() > 0.3
    end

    local function empty(t)
        return next(t) == nil
    end

    local function cache_ids(observer: ecr.Observer<unknown>): { [ecr.entity]: { unknown } }
        local cache = {}
        for id, a, b, c in observer do
            cache[id] = { a, b, c }
        end
        return cache
    end

    local function persist_cache_ids(observer: ecr.Observer<unknown>): { [ecr.entity]: { unknown } }
        local cache = {}
        for id, a, b, c in observer:iter() :: any do
            cache[id] = { a, b, c }
        end
        return cache
    end

    local reg = ecr.registry()
    local observerA = reg:track(A)
    local observerB = reg:track(B)
    local observerABC = reg:track(A, B, C)
    local observerAnotC = reg:track(A):exclude(C)

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

    do CASE "observer size"
        CHECK(#observerA == #As)
        CHECK(#observerB == #Bs)
        CHECK(#observerABC >= #ABCs)
        CHECK(#observerAnotC >= #AnotCs)
    end

    -- do CASE "initial components treated as changed"
    --     do
    --         local observer = reg:track(A)

    --         local cache = cache_ids(observer)
    --         CHECK(not empty(cache))

    --         for _, id in As do
    --             local v = cache[id]
    --             if not CHECK(v) then continue end
    --             CHECK(v[1] == id)
    --         end
    --     end
    --     do
    --         local observer = reg:track(A, B, C)
    --         local cache = cache_ids(observer)
    --         CHECK(not empty(cache))

    --         for _, id in ABCs do
    --             local v = cache[id]
    --             if not CHECK(v) then continue end
    --             CHECK(v[1] == id)
    --             CHECK(v[2] == id)
    --             CHECK(v[3] == id)
    --         end
    --     end
    -- end

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

    do CASE "AnotC tracked"
        local cache = persist_cache_ids(observerAnotC)
        CHECK(not empty(cache))
        for _, id in AnotCs do
            local v = cache[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
        end
        CHECK(#observerAnotC > 0)
    end

    do CASE "ABC tracked"
        local cache = cache_ids(observerABC)
        CHECK(not empty(cache))
        for _, id in ABCs do
            local v = cache[id]
            if not CHECK(v) then continue end
            CHECK(v[1] == id)
            CHECK(v[2] == id)
            CHECK(v[3] == id)
        end
        CHECK(#observerABC == 0)
    end

    observerA:clear()

    do CASE "changed components tracked after clear"
        CHECK(#observerA == 0)

        reg:set(As[1], A, As[1])

        local ran = false
        for id, v in observerA do
            ran = true
            CHECK(id == As[1])
            CHECK(v == id)
        end
        CHECK(ran)
        CHECK(#observerA == 0)
    end

    do CASE "changed components updated"
        for _, id in Bs do
            reg:patch(id, B :: number, function(cur)
                return cur + 1
            end)
        end

        for id, v in observerB:iter() do
            CHECK(v == id + 1)
        end

        CHECK(#observerB > 0)
    end

    do CASE "removed components are not returned"
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

    do CASE "changes not recorded if disconnected"
        local size = #observerA
        local id = reg:create()
        reg:set(id, A, 1)
        CHECK(#observerA == size)
    end

    observerA:reconnect():clear()

    do CASE "changes recorded again after reconnect"
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

    -- do CASE "observer returns up-to-date values despite being changed while disconnected"
    --     local observer = reg:track(A):clear()
    --     local id1 = reg:create()
    --     local id2 = reg:create()
    --     local id3 = reg:create()

    --     reg:set(id1, A, 1)
    --     reg:set(id2, A, 2)
    --     reg:set(id3, A, 3)

    --     observer:disconnect()

    --     reg:remove(id1, A) -- remove id1
    --     reg:set(id2, A, -2) -- change id2

    --     local values = {}

    --     for id, v in observer do
    --         values[id] = v
    --     end

    --     CHECK(#observer == 2)
    --     CHECK(not values[id1])
    --     CHECK(values[id2] == -2)
    --     CHECK(values[id3] == 3)
    -- end

    do CASE "disconnect non-empty observer"
        local observer = reg:track(A)

        reg:handle():set(A, true)

        CHECK_ERR("attempt to disconnect a non-empty observer", function()
            observer:disconnect()
        end)

        observer:clear():disconnect()
    end

    do CASE "observer garbage collection"
        local wref = setmetatable({}, { __mode = "v" })
        wref.observer = observerA
        wref.pool = (observerA :: any).pool
        observerA:clear():disconnect()
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

    do CASE "track multiple"
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
    local function getids(group: ecr.Group<...unknown>): { [ecr.entity]: { unknown } }
        local cache = {}
    
        for id, a, b, c, d, e in group do
            cache[id] = { a, b, c, d, e }
        end

        return cache
    end

    local Z, X = ecr.component(), ecr.component()

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

    do CASE "group size"
        CHECK(#reg:group(A, B) == #ABs)
        CHECK(#reg:group(C, D, E) == #CDEs)
    end

    do CASE "group AB cached"
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

    do CASE "group AB"
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

    do CASE "group CDE"
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

    do CASE "late initialized group FG"
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

    do CASE "removing components during group iteration"
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

    do CASE "clearing with groups"
        reg:clear(A)
        CHECK(#reg:group(A, B) == 0)
        reg:set(ABs[1], A, 1)
        CHECK(#reg:group(A, B) == 1)
    end

    do CASE "removing owned component from entity not in group"
        local id = reg:create()
        reg:set(id, A, 1)
        reg:set(id, C, 3)
        reg:remove(id, A)
        CHECK(reg:try_get(id, A) == nil and reg:get(id, C) == 3)
    end

    do CASE "using owned component for new group errors"
        CHECK_ERR(
            "cannot create group; component (arg #2) is not owned by the same group as previous args",
            function()
                reg:group(F, H)
            end
        )
    end

    do CASE "single component group errors"
        local ok = pcall(function()
            reg:group(H)
        end)
        CHECK(not ok)
    end

    do CASE "group ABCDE"
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

    do CASE "invalidation check"
        reg:group(Z, X)

        local e1 = reg:handle()
        e1:set(Z, true)

        local e2 = reg:handle()
        e2:set(Z, true)

        CHECK_ERR("group reordered during iteration", function()
            for id in reg:view(Z) do
                reg:set(id, X, true)
            end
        end)

        CHECK(not e1:has(X)) -- confirm invalidation occured
    end
end)

TEST("registry:handle()", function()
    local reg = ecr.registry()

    do CASE "call with nil"
        local e = reg:handle()

        CHECK(reg:contains(e.entity))

        e:set(A, 1)
        :set(B, 2)

        CHECK(e:has(A, B))
    end

    do CASE "call with existing"
        local id = reg:create()
        local e = reg:handle(id)
        CHECK(e.entity == id)
    end

    do CASE "caching"
        local e = reg:handle()
        local e2 = reg:handle(e.entity)
        CHECK(e == e2)

        local id = reg:create() 
        local e_b = reg:handle(id)
        local e_b2 = reg:handle(id)
        CHECK(e_b == e_b2)
    end

    do CASE "garbage collection"
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

    do CASE "initially invalid"
        CHECK(not reg:contains(ecr.context))
        CHECK(#reg:view(ecr.entity) == 0)
    end

    local ctx = reg:context()

    do CASE "valid"
        CHECK(reg:contains(ctx.entity))
    end

    ctx:set(A, 1):set(B, 2)

    do CASE "components"
        CHECK(ctx:get(A) == 1)
        CHECK(ctx:get(B) == 2)
    end

    do CASE "sizes"
        CHECK(#reg:view(ecr.entity) == 1)
        CHECK(#reg:view(A) == 1)
    end

    do CASE "destroy"
        ctx:destroy()
        CHECK(not reg:contains(ctx.entity))
        reg:context()
        CHECK(not ctx:has(A) and not ctx:has(B))
    end

    reg:clear()

    do CASE "clearing affects"
        CHECK(not reg:contains(ctx.entity))
    end
end)

TEST("registry:storage()", function()
    do CASE "get storage"
        local reg = ecr.registry()

        local ids = BULK_CREATE_IDS(reg, N)

        for i = 1, N do
            reg:set(ids[i], A, i)
        end

        local pool = reg:storage(A)

        local entities = ecr.buffer_to_array(pool.entities, pool.size)

        for i, id in entities do
            CHECK(ids[i] == id)
            CHECK(pool.values[i] == i)
        end
    end

    do CASE "get all storages"
        local reg = ecr.registry()

        local pool_A = reg:storage(A)
        local pool_B = reg:storage(B)

        local cache = {}

        for ctype, pool in reg:storage() do
            cache[ctype] = pool
        end

        CHECK(cache[A] == pool_A)
        CHECK(cache[B] == pool_B)
    end
end)

TEST("ecr.component()", function()
    do CASE "components have unique ids"
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

        do CASE "iterate single value"
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

        do CASE "iterate multiple values"
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
    
    do CASE "new iter does not clear"
        local queue = ecr.queue()
        queue:add(1)
        for _ in queue:iter() do end
        CHECK(#queue == 1)
    end

    do CASE "manual clear"
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

    do CASE "uneven values"
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

    do CASE "nil value first"
        local queue = ecr.queue()
        CHECK_ERR("first argument cannot be nil", function()
            queue:add(nil, 1, 2, 3)
        end)
    end

    do CASE "automatic signal connection"
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
    local cts = ecr.name {
        A = ecr.component() :: number,
        B = ecr.component() :: string
    }

    local reg = ecr.registry()

    local id = reg:create()

    CHECK_ERR(`entity does not have component "A"`, function()
        reg:get(id, cts.A)
    end)

    CHECK_ERR(`no constructor defined for component "B"`, function()
        reg:add(id, cts.B)
    end)

    CHECK(ecr.name(cts.A) == "A")
end)

TEST("ecr.tag()", function()
    do CASE "is tag"
        CHECK(ecr.is_tag(TA))
        CHECK(not ecr.is_tag(A))
    end

    local reg = ecr.registry()

    local observer = reg:track(TA, TB, TC, TD, A)

    local e = reg:handle()

    do CASE "add"
        local ran = false
        reg:on_add(TA):connect(function(id, v)
            ran = true
            CHECK(id == e.entity)
            CHECK(v == nil)
        end)

        e:add(TA)

        CHECK(e:has(TA))
        CHECK(e:get(TA) == nil)
        CHECK(ran)
    end

    do CASE "view"
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
    do CASE "view unpack"
        e:add(TB, TC, TD)
        e:set(A, true)

        local ran = 0

        for id, ta, tb, tc, td, a in reg:view(TA, TB, TC, TD, A) do
            ran += 1
            CHECK(a == true)
        end

        for id, ta, tb, tc, td, a in observer do
            ran += 1
            CHECK(a == true)
        end

        for id, ta, tb, tc, td, a in reg:group(TA, TB, TC, TD, A) do
            ran += 1
            CHECK(a == true)
        end

        CHECK(ran == 3)
    end

    do CASE "remove"
        e:remove(TA)
        CHECK(not e:has(TA))
    end

    -- tags are implemented as normal components internally
    -- further testing should not be necessary
end)

TEST("buffer helpers", function()
    local reg = ecr.registry()

    local ids = BULK_CREATE_IDS(reg, 10)
    local buf = buffer.create(10 * ecr.id_size)

    do CASE "array to buffer"
        ecr.array_to_buffer(ids, 10, buf)
        CHECK(true)
    end

    do CASE "buffer to array"
        local arr = table.create(10)
        ecr.buffer_to_array(buf, 10, arr)
        for i = 1, 10 do
            CHECK(arr[i] == ids[i])
        end
    end

    do CASE "buffer to buffer"
        buffer.fill(buf, 0, 0)
        local pool = reg:storage(ecr.entity)
        ecr.buffer_to_buffer(pool.entities, pool.size, buf)
        local arr = ecr.buffer_to_array(buf, pool.size)
        for i = 1, 10 do
            CHECK(arr[i] == ids[i])
        end
    end
end)

if DEFER_ID_REUSE then

TEST("deferred id reuse", function()
    do CASE "version overflow"
        local reg2 = ecr.registry()
        
        reg2:release( reg2:create() ); -- ensure id internally exists

        SET_KEY_VERSION(reg2, 1, MAX_VER - 1)

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

    do CASE "deprecated key"
        local reg = ecr.registry()
        CHECK(GET_KEY_VERSION(reg, KEY(CREATE_DEPRECATED_ID(reg))) == 0)
    end

    do CASE "add component to deprecated id"
        local reg = ecr.registry()
    
        CHECK_ERR("invalid entity", function()
            local id = CREATE_DEPRECATED_ID(reg)
            reg:add(id, A)
        end)
    end

    do CASE "add component to deprecated id"
        local reg = ecr.registry()

        CHECK_ERR("invalid entity", function()
            local id = CREATE_DEPRECATED_ID(reg)
            reg:set(id, A, 1)
        end)
    end

    do CASE "reuse"
        local reg = ecr.registry()

        local ids = table.create(ecr._test.max_creatable)

        for i = 1, ecr._test.max_creatable do
            ids[i] = reg:create(CREATE_ID(i, MAX_VER))
        end

        for i = 1, ecr._test.max_creatable do
            reg:release(ids[i])
        end

        local id = reg:create()
        CHECK(KEY(id) == 1)
        CHECK(VER(id) == 1)
    end
end)

else

TEST("immediate id reuse", function()
    do CASE "reuse 1"
        local reg = ecr.registry()

        for i = 1, MAX_VER do
            reg:release(reg:create())
        end

        local id = reg:create()
        CHECK(KEY(id) == 1)
        CHECK(VER(id) == 1)
    end

    do CASE "clear"
        local reg = ecr.registry()
        local ids = BULK_CREATE_IDS(reg, ecr._test.max_creatable)

        local chosen = ecr._test.max_creatable // 2
        local chosen_key = KEY(ids[chosen])

        reg:release(ids[chosen])
        SET_KEY_VERSION(reg, KEY(ids[chosen]), ecr._test.max_ver)
        CHECK(reg:create() == ecr._test.create_id(chosen_key, ecr._test.max_ver))

        reg:clear()

        local ids_new = BULK_CREATE_IDS(reg, ecr._test.max_creatable)

        for i = 1, ecr._test.max_creatable do
            local id = ids[i]
            local id_new = ids_new[i]

            if KEY(id_new) == chosen_key then
                CHECK(VER(id_new) == VER(id))
            else
                CHECK(VER(id) + 1 == VER(id_new))
            end
        end
    end
end)

end

TEST("random test", function()
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

    -- map component to entity to value
    local incs = {} :: Map<unknown, Map<ecr.entity, number>>

    local cts = {} :: Array<{ id: ecr.entity, v: number }>

    for i = 1, 5 do
        local ctype = ecr.component()
        cts[i] = ctype :: any
        incs[ctype] = {}
    end

    local reg = ecr.registry()

    local function flip(p: number?)
        return math.random() > (p and (1 - p) or 0.5)
    end

    -- set of all ids in use
    local idcount = 0
    local ids = {} :: { [ecr.entity]: true }

    -- array of all destroyed ids
    local frees = {} :: { ecr.entity }


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

            do -- test iterators
                local ctype2
                local ctype3

                repeat
                    ctype2 = cts[math.random(1, #cts)]
                until ctype2 ~= ctype

                if flip(0.3) then
                    repeat
                        ctype3 = cts[math.random(1, #cts)]
                    until ctype3 ~= ctype2 and ctype3 ~= ctype
                end
        
                if ctype3 then
                    for _ in reg:view(ctype, ctype2, ctype3) do end
                else
                    for _ in reg:view(ctype, ctype2) do end
                end
            end

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
end)

local success = FINISH()
if not success then error(nil, 0) end
