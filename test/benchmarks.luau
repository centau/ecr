local testkit = require("test/testkit")
local BENCH, START = testkit.benchmark()

local function TITLE(name: string)
    print()
    print(testkit.color.white(name))
end

local ecr = require "src/ecr"

local function rtrue() return true :: any end
local A, B, C, D = ecr.component(rtrue), ecr.component(rtrue), ecr.component(rtrue), ecr.component(rtrue)
local E, F, G, H = ecr.component(), ecr.component(), ecr.component(), ecr.component()

local TA, TB, TC, TD = ecr.tag(), ecr.tag(), ecr.tag(), ecr.tag()

local function BULK_CREATE_IDS(reg: ecr.Registry, n: number): { ecr.Entity }
    local ids = table.create(n)
    for i = 1, n do
        ids[i] = reg:create()
    end
    return ids
end

local N = 2^16-2 -- 65,534

local function RESERVE(reg: ecr.Registry, ...)
    for _, ctype in { ... } do
        reg:storage(ctype):reserve(N) -- todo 8 bytes
    end
end

local function REG_INIT()
    local reg = ecr.registry()

    for _, ctype in { ecr.entity, A, B, C, D, E, F, G, H, TA, TB, TC, TD } do
        reg:storage(ctype):reserve(N/2)
    end

    return reg
end

do TITLE "entities"
    BENCH("create", function()
        local reg = REG_INIT()

        for i = 1, START(N) do
            reg:create()
        end
    end)

    BENCH("release", function()
        local reg = REG_INIT()

        local id = table.create(N)

        for i = 1, N do
            id[i] = reg:create()
        end

        for i = 1, START(N) do
            reg:release(id[i])
        end
    end)

    BENCH("create with id", function()
        local sreg = REG_INIT()
        
        local id = table.create(N)

        for i = 1, N do
            id[i] = sreg:create()
        end

        local reg = REG_INIT()

        for i = 1, START(N) do
            reg:create(id[i])
        end
    end)
end

do TITLE "add"
    local function setup()
        local reg = REG_INIT()

        local ids = table.create(N)
        for i = 1, N do
            ids[i] = reg:create()
        end
        return reg, ids
    end

    do
        local reg, ids = setup()

        BENCH("1 component", function()
            for i = 1, START(N) do
                reg:add(ids[i], A)
            end
        end)
    end

    do
        local reg, ids = setup()

        BENCH("2 components", function()
            for i = 1, START(N) do
                reg:add(ids[i], A, B)
            end
        end)
    end

    do
        local reg, ids = setup()

        BENCH("4 components", function()
            for i = 1, START(N) do
                reg:add(ids[i], A, B, C, D)
            end
        end)
    end

    do
        local reg, ids = setup()
        BENCH("1 tag", function()
            for i = 1, START(N) do
                reg:add(ids[i], TA)
            end
        end)
    end

    do
        local reg, ids = setup()
        BENCH("4 tags", function()
            for i = 1, START(N) do
                reg:add(ids[i], TA, TB, TC, TD)
            end
        end)
    end
end

do TITLE "set"
    local function setup()
        local reg = REG_INIT()
        RESERVE(reg, A, B, C, D)
        local ids = table.create(N)
        for i = 1, N do
            ids[i] = reg:create()
        end
        return reg, ids
    end

    do
        local reg, ids = setup()

        BENCH("add 1", function()
            for i = 1, START(N) do
                reg:set(ids[i], A, true)
            end
        end)

        BENCH("change 1", function()
            for i = 1, START(N) do
                reg:set(ids[i], A, true)
            end
        end)
    end

    do
        local reg, ids = setup()

        BENCH("add 2", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
            end
        end)

        BENCH("change 2", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
            end
        end)
    end

    do
        local reg, ids = setup()
        BENCH("add 4", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
                reg:set(e, C, true)
                reg:set(e, D, true)
            end
        end)

        BENCH("change 4", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
                reg:set(e, C, true)
                reg:set(e, D, true)
            end
        end)
    end
end

do TITLE "patch"
    local function setup()
        local reg = REG_INIT()
        local ids = table.create(N)
        for i = 1, N do
            local e = reg:create()
            ids[i] = e
            reg:set(e, A, 0)
            reg:set(e, B, 0)
            reg:set(e, C, 0)
            reg:set(e, D, 0)
        end
        return reg, ids
    end
    
    local function patcher(v: number)
        return v + 1
    end
    
    do
        local reg, ids = setup()

        BENCH("patch 1", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:patch(e, A, patcher)
            end
        end)
    end
    
    do
        local reg, ids = setup()
        
        BENCH("patch 2", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:patch(e, A, patcher)
                reg:patch(e, B, patcher)
            end
        end)
    end
    
    do
        local reg, ids = setup()
        
        BENCH("patch 4", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:patch(e, A, patcher)
                reg:patch(e, B, patcher)
                reg:patch(e, C, patcher)
                reg:patch(e, D, patcher)
            end
        end)
    end
end

do TITLE "has"
    local reg = REG_INIT()
    local ids = table.create(N)

    for i = 1, N do
        ids[i] = reg:create()
        reg:set(ids[i], A, true)
        reg:set(ids[i], B, true)
        reg:set(ids[i], C, true)
        reg:set(ids[i], D, true)
    end

    BENCH("1 component", function()
        for i = 1, START(N) do
            reg:has(ids[i], A)
        end
    end)

    BENCH("2 components", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:has(e, A, B)
        end
    end)

    BENCH("4 components", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:has(e, A, B, C, D)
        end
    end)
end

do TITLE("get")
    local reg = REG_INIT()
    local ids = table.create(N)

    for i = 1, N do
        local e = reg:create()
        ids[i] = e
        reg:set(e, A, true)
        reg:set(e, B, true)
        reg:set(e, C, true)
        reg:set(e, D, true)

        reg:set(e, E, true)
        reg:set(e, F, true)
        reg:set(e, G, true)
        reg:set(e, H, true)
    end

    BENCH("1 component", function()
        for i = 1, START(N) do
            reg:get(ids[i], A)
        end
    end)

    BENCH("2 components", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:get(e, A, B)
        end
    end)

    BENCH("4 components", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:get(e, A, B, C, D)
        end
    end)

    BENCH("8 components", function()
        for i = 1, START(N) do
            reg:get(ids[i], A, B, C, D, E, F, G, H)
        end
    end)

    BENCH("try 1 component", function()
        for i = 1, START(N) do
            reg:try_get(ids[i], A)
        end
    end)
end

do TITLE("remove")
    local function setup()
        local reg = REG_INIT()
        local ids = table.create(N)
        for i = 1, N do
            local e = reg:create()
            ids[i] = e
            reg:set(e, A, true)
            reg:set(e, B, true)
            reg:set(e, C, true)
            reg:set(e, D, true)
            reg:set(e, E, true)
            reg:set(e, F, true)
            reg:set(e, G, true)
            reg:set(e, H, true)
        end
        return reg, ids
    end

    BENCH("1 unowned", function()
        local reg, ids = setup()

        for i = 1, N do
            reg:remove(ids[i], A)
        end

        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)

    BENCH("1 component", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)

    BENCH("2 components", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A, B)
        end
    end)

    BENCH("4 components", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A, B, C, D)
        end
    end)

    BENCH("8 components", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A, B, C, D, E, F, G, H)
        end
    end)
end

do TITLE "clear"
    local function setup()
        local reg = REG_INIT()
        local ids = table.create(N)
        for i = 1, N do
            local e = reg:create()
            ids[i] = e
            reg:set(e, A, true)
            reg:set(e, B, true)
            reg:set(e, C, true)
            reg:set(e, D, true)
            reg:set(e, E, true)
            reg:set(e, F, true)
            reg:set(e, G, true)
            reg:set(e, H, true)
        end
        return reg, ids
    end

    BENCH("1 component", function()
        local reg = setup()

        START(N)
        reg:clear(A)
    end)

    BENCH("2 components", function()
        local reg = setup()

        START(N)
        reg:clear(A, B)
    end)

    BENCH("4 components", function()
        local reg = setup()

        START(N)
        reg:clear(A, B, C, D)
    end)

    BENCH("8 components", function()
        local reg = setup()

        START(N)
        reg:clear(A, B, C, D, E, F, G, H)
    end)

    BENCH("all entities (no components)", function()
        local reg = REG_INIT()
        for i = 1, N do reg:create() end

        START(N)
        reg:clear()
    end)

    BENCH("1 component (grouped)", function()
        local reg = setup()
        reg:group(A, B)

        START(N)
        reg:clear(A)
    end)
end

do TITLE("create view")
    local reg = REG_INIT()

    reg:view(A, B, C, D, E, F, G, H) -- register components

    BENCH("1 component", function()
        for i = 1, START(N) do
            reg:view(A)
        end
    end)

    BENCH("4 component", function()
        for i = 1, START(N) do
            reg:view(A, B, C, D)
        end
    end)
end

do
    local function viewBench(reg: ecr.Registry)
        local function getExactSize(view: ecr.View<...any>): number
            local i = 0
            for _ in view do
                i += 1
            end
            return i
        end

        BENCH("1 component", function()
            local view = reg:view(A)

            START(getExactSize(view))
            for entity, a in view do end
        end)

        BENCH("2 components", function()
            local view = reg:view(A, B)

            START(getExactSize(view))
            for entity, a, b in view do end
        end)

        BENCH("4 components", function()
            local view = reg:view(A, B, C, D)

            START(getExactSize(view))
            for entity, a, b, c, d in view do end
        end)

        BENCH("8 components", function()
            local view = reg:view(A, B, C, D, E, F, G, H)

            START(getExactSize(view))
            for entity, a, b, c, d, e, f, g, h in view do end
        end)
    end

    do TITLE("iter view (ordered)")
        local reg = REG_INIT()

        for i = 1, N do
            local entity = reg:create()
            reg:set(entity, A, true)
            reg:set(entity, B, true)
            reg:set(entity, C, true)
            reg:set(entity, D, true)
            reg:set(entity, E, true)
            reg:set(entity, F, true)
            reg:set(entity, G, true)
            reg:set(entity, H, true)
        end

        viewBench(reg)
    end

    do TITLE("iter view (random)")
        local reg = REG_INIT()

        local function flip() return math.random() > 0.5 end

        for i = 1, N do
            local entity = reg:create()
            if flip() then reg:set(entity, A, true) end
            if flip() then reg:set(entity, B, true) end
            if flip() then reg:set(entity, C, true) end
            if flip() then reg:set(entity, D, true) end
            if flip() then reg:set(entity, E, true) end
            if flip() then reg:set(entity, F, true) end
            if flip() then reg:set(entity, G, true) end
            if flip() then reg:set(entity, H, true) end
        end

        viewBench(reg)
    end

    do TITLE("iter view (random + common)")
        -- 7 components are randomly assigned to entities,
        -- any entities that receive all 7 will be tagged with an 8th component.
        -- This guarantees that when iterating over this 8th component, all
        -- entities iterated will also contain the other 7.

        local reg = REG_INIT()

        local function flip() return math.random() > 0.5 end

        for i = 1, N do
            local entity = reg:create()
            local b, c, d, e, f, g, h
            if flip() then b=true; reg:set(entity, B, true) end
            if flip() then c=true; reg:set(entity, C, true) end
            if flip() then d=true; reg:set(entity, D, true) end
            if flip() then e=true; reg:set(entity, E, true) end
            if flip() then f=true; reg:set(entity, F, true) end
            if flip() then g=true; reg:set(entity, G, true) end
            if flip() then h=true; reg:set(entity, H, true) end
            if b and c and d and e and f and g and h then reg:set(entity, A, true) end
        end

        viewBench(reg)
    end

    do TITLE("iter view (tags)")
        local reg = REG_INIT()

        for i = 1, N do
            local e = reg:handle()
            e:add(TA, TB, TC, TD)
        end

        BENCH("1 tag", function()
            START(N)
            for id, a in reg:view(TA) do end
        end)

        BENCH("4 tags", function()
            START(N)
            for id, a, b, c, d in reg:view(TA, TB, TC, TD) do end
        end)
    end
end

do TITLE("handle")
    local N2 = N/32

    local reg = REG_INIT()
    local ids = table.create(N2)

    for i = 1, N2 do
        ids[i] = reg:create()
    end

    BENCH("create new", function()
        for i = 1, START(N2) do
            reg:handle(ids[i])
        end
    end)

    -- cache to prevent gc when starting next benchmark
    local cache = table.create(N2)
    for i = 1, N2 do
        cache[i] = reg:handle(ids[i])
    end

    BENCH("create cached", function()
        for i = 1, START(N2) do
            reg:handle(ids[i])
        end
    end)
end

do TITLE "group"
    do
        local reg = REG_INIT()

        local group = reg:group(A, B)

        local ids = {}

        for i = 1, N do
            ids[i] = reg:create()
        end

        BENCH("add 2 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, 1)
                reg:set(e, B, 2)
            end
        end)

        BENCH("iter 2 components", function()
            START(N)
            for entity, a, b in group do end
        end)

        BENCH("remove 2 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:remove(e, A, B)
            end
        end)

        BENCH("add 1 component", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, 1)
            end
        end)
    end

    do
        local reg = REG_INIT()

        local group2 = reg:group(C, D, E, F)
        
        local ids = {}

        for i = 1, N do
            ids[i] = reg:create()
        end

        BENCH("add 4 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, C, 1)
                reg:set(e, D, 2)
                reg:set(e, E, 3)
                reg:set(e, F, 4)
            end
        end)

        BENCH("iter 4 components", function()
            START(N)
            for entity, a, b, c, d in group2 do end
        end)

        BENCH("remove 4 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:remove(e, C, D, E, F)
            end
        end)

        BENCH("add 1 component", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, C, 1)
            end
        end)
    end
end

do TITLE("destroy")
    BENCH("0 components", function()
        local reg = REG_INIT()
        local ids = table.create(N)

        for i = 1, N do
            ids[i] = reg:create()
        end

        for i = 1, START(N) do
            reg:destroy(ids[i])
        end
    end)

    BENCH("1 component", function()
        local reg = REG_INIT()
        local ids = table.create(N)

        for i = 1, N do
            local e = reg:create()
            reg:set(e, A, true)
            ids[i] = e
        end

        for i = 1, START(N) do
            reg:destroy(ids[i])
        end
    end)

    BENCH("2 components", function()
        local reg = REG_INIT()
        local ids = table.create(N)

        for i = 1, N do
            local e = reg:create()
            reg:set(e, A, true)
            reg:set(e, B, true)
            ids[i] = e
        end

        for i = 1, START(N) do
            reg:destroy(ids[i])
        end
    end)

    BENCH("4 components", function()
        local reg = REG_INIT()
        local ids = table.create(N)

        for i = 1, N do
            local e = reg:create()
            reg:set(e, A, true)
            reg:set(e, B, true)
            reg:set(e, C, true)
            reg:set(e, D, true)
            ids[i] = e
        end

        for i = 1, START(N) do
            reg:destroy(ids[i])
        end
    end)

    BENCH("0 components (8 registered)", function()
        local reg = REG_INIT()
        local ids = table.create(N)

        for i = 1, N - 1 do
            local e = reg:create()
            ids[i] = e
        end

        do -- register all components
            local e = reg:create()
            reg:set(e, A, true)
            reg:set(e, B, true)
            reg:set(e, C, true)
            reg:set(e, D, true)
            reg:set(e, E, true)
            reg:set(e, F, true)
            reg:set(e, G, true)
            reg:set(e, H, true)
        end

        for i = 1, START(N - 1) do
            reg:destroy(ids[i])
        end
    end)

    BENCH("0 components (128 registered)", function()
        local reg = REG_INIT()

        do
            local id = reg:create()
            for i = 1, 128  do
                local component = ecr.component()
                reg:set(id, component, true)
            end
        end

        local ids = table.create(N - 1)

        for i = 1, N - 1 do
            ids[i] = reg:create()
        end

        for i = 1, START(N - 1) do
            reg:destroy(ids[i])
        end
    end)

    BENCH("0 components (1024 registered)", function()
        local reg = REG_INIT()

        do
            local id = reg:create()
            for i = 1, 1024  do
                local component = ecr.component()
                reg:set(id, component, true)
            end
        end

        local ids = table.create(N)

        for i = 1, N/10 do
            ids[i] = reg:create()
        end

        for i = 1, START(N/10) do
            reg:destroy(ids[i])
        end
    end)
end

-- do TITLE("Direct storage")
--     local reg = REG_INIT()
--     local a = reg:storage(A)
--     a:reserve(N)

--     local ids = BULK_CREATE_IDS(reg, N)

--     BENCH("Add component", function()
--         for i = 1, START(N) do
--             a:set(ids[i], i)
--         end
--     end)

--     BENCH("Change component", function()
--         for i = 1, START(N) do
--             a:set(ids[i], i)
--         end
--     end)

--     BENCH("Get component", function()
--         for i = 1, START(N) do
--             a:get(ids[i])
--         end
--     end)

--     BENCH("Has component", function()
--         for i = 1, START(N) do
--             a:has(ids[i])
--         end
--     end)

--     BENCH("Remove component", function()
--         for i = 1, START(N) do
--             a:remove(ids[i])
--         end
--     end)
-- end

do TITLE("contains")
    BENCH("", function()
        local reg = REG_INIT()
        local ids = table.create(N)
        for i = 1, N do
            ids[i] = reg:create()
        end

        START(N)

        for i = 1, N do
            reg:contains(ids[i])   
        end
    end)
end

do TITLE "signal"
    local reg = REG_INIT()
    local ids = table.create(N)

    for i = 1, N do
        ids[i] = reg:create()
    end

    BENCH("added", function()
        reg:added(A):connect(function() end)

        for i = 1, START(N) do
            reg:set(ids[i], A, true)
        end
    end)

    BENCH("changed", function()
        reg:changed(A):connect(function() end)

        for i = 1, START(N) do
            reg:set(ids[i], A, false)
        end
    end)


    BENCH("removing", function()
        reg:removing(A):connect(function() end)

        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)
end

do TITLE "observer"
    local reg = REG_INIT()
    local observer = reg:track(A)

    local ids = table.create(N)
    for i = 1, N do
        ids[i] = reg:create()
    end

    BENCH("add", function()
        for i = 1, START(N) do
            reg:set(ids[i], A, true)
        end
    end)

    BENCH("change", function()
        for i = 1, START(N) do
            reg:set(ids[i], A, false)
        end
    end)

    BENCH("iterate", function()
        START(N)
        for id, v in observer do end
    end)

    BENCH("remove", function()
        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)

    BENCH("clear", function()
        START(N)
        observer:clear()
    end)
end

do TITLE "queue"
    do
        local q = ecr.queue()

        BENCH("add 1", function()
            for i = 1, START(N) do
                q:add(i)
            end
        end)

        BENCH("iter 1", function()
            START(N)
            for i in q do end
        end)
    end

    do
        local q = ecr.queue()

        BENCH("add 4", function()
            for i = 1, START(N) do
                q:add(i, i, i, i)
            end
        end)

        BENCH("iter 4", function()
            START(N)
            for a, b, c, d in q do end
        end)
    end
end

do TITLE "buffer"
    local reg = ecr.registry()

    local ids = BULK_CREATE_IDS(reg, N)
    local buf = buffer.create(N * ecr.id_size)

    BENCH("array to buffer", function()
        ecr.copy_array_to_buffer(ids, buf, START(N))
    end)

    BENCH("iter buffer", function()
        for i, id in ecr.bnext, buf, START(N) do
        end
    end)

    local arr = table.create(N)

    BENCH("buffer to array", function()
        ecr.copy_buffer_to_array(buf, arr, START(N))
    end)
end

local PN = 2^12

do TITLE(`practical test ({PN} entities)`)
    local world = REG_INIT()

    local Position = ecr.component() :: number
    local Velocity = ecr.component() :: number
    local Health = ecr.component() :: number

    local Dead = ecr.tag()

    world:group(Position, Velocity)

    local function init()
        for i = 1, 2^12 do -- ~4k
            local id = world:create()
            world:set(id, Position, i)
            world:set(id, Velocity, i)
            world:set(id, Health, 0)
        end
    end

    do -- pre-alloc
        init()

        for id in world:view(ecr.entity) do
            world:add(id, Dead)
        end

        world:clear()
    end

    BENCH("create entities with 3 components", function()
       init()
    end)

    BENCH("update positions", function()
        for id, pos, vel in world:group(Position, Velocity) do
            world:set(id, Position, pos + vel*1/60)
        end
    end)

    BENCH("raw update positions", function()
        local n = #world:group(Position, Velocity)
        local positions  = world:storage(Position).values
        local velocities = world:storage(Velocity).values
        
        for i = 1, n do
            positions[i] = positions[i] + velocities[i] * 1/60
        end
            
    end)

    BENCH("add tags", function()
        for id, health in world:view(Health) do
            if health <= 0 then
                world:add(id, Dead)
            end
        end
    end)

    BENCH("destroy", function()
        for id in world:view(Dead) do
            world:destroy(id)
        end
    end)
end

-- attempt to repeat the same test above but with regular OOP instead of ECS
-- this is just curiosity to see how ECS really fares against OOP in Luau
do TITLE "Practical test OOP"
    local world = {}

    local cache = {}

    type Obj = {
        Position: number,
        Velocity: number,
        Health: number,
        Dead: boolean
    }

    local function create(i)
        return {
            Position = i,
            Velocity = i,
            Health = 0,
            -- dummy fields
            A = 0,
            B = 0,
            C = 0,
            D = 0
        }
    end

    local tmp = {}
    do
        for i = 1, 2^14 do
            tmp[i] = create(i)
        end

        for i = 1, 2^14 do
            if math.random() > 0.7 then
                tmp[i] = nil
            end
        end
        collectgarbage("collect")
    end

    local permutation = {}

    -- luaus table allocator is really good and allocates tables in linear
    -- pages in memory, causing sequential access to tables to hit cache.
    -- i dont think this would occur in complex real games unless you
    -- specifically design for it so attempt to randomize here to try
    -- eliminate cache hits (this reduces performance by around ~5x)
    do
        for i = 1, 2^12 do
            cache[i] =  i
        end

        for i = 1, 2^14 do
            permutation[i] = cache[math.random(1, #cache)]
        end
    end

    BENCH("Create ~4k entities with 3 components", function()
        for i = 1, 2^12 do
            local idx = permutation[i]
            world[idx] = create(i)
        end
    end)

    BENCH("Update position ~4k entities", function()
        for _, obj in world do
            obj.Position = obj.Position + obj.Velocity * 1/60
        end
    end)

    BENCH("Add tag ~4k entities", function()
        for _, obj in world do
            if obj.Health <= 0 then
                obj.Dead = true
            end
        end
    end)

    BENCH("Destroy ~4k entities", function()
        table.clear(world)
        collectgarbage("collect" :: any) -- this probably isnt a fair test
    end)
end
