local BENCH, START, STOP, ITER = require "test/testkit/bench" ()

local ecr = require "src/ecr"

local A, B, C, D = ecr.component(), ecr.component(), ecr.component(), ecr.component()
local E, F, G, H = ecr.component(), ecr.component(), ecr.component(), ecr.component()

----------------------------------------
-- Entity creation
----------------------------------------

print("Entity creation and release")

BENCH("Entity creation", function()
    local N = 1e6
    local reg = ecr.registry(N)

    START(N)

    for i = 1, N do
        reg:create()
    end
end)

BENCH("Entity creation (no pre-allocation)", function()
    local N = 1e6
    local reg = ecr.registry()

    START(N)

    for i = 1, N do
        reg:create()
    end
end)

BENCH("Entity release", function()
    local N = 1e6
    local reg = ecr.registry(N)

    local id = table.create(N)

    for i = 1, N do
        id[i] = reg:create()
    end

    START(N)

    for i = 1, N do
        reg:release(id[i])
    end
end)

----------------------------------------
-- Setting components
----------------------------------------

print("Setting components")

do
    local N = 1e6

    local function setup()
        local reg = ecr.registry(N)
        local ids = table.create(N)
        for i = 1, N do
            ids[i] = reg:create()
        end
        return reg, ids
    end

    do
        local reg, ids = setup()
        BENCH("Set 1 new component", function()
            for i = 1, START(N) do
                reg:set(ids[i], A, true)
            end
        end)

        BENCH("Set 1 component", function()
            for i = 1, START(N) do
                reg:set(ids[i], A, true)
            end
        end)
    end

    do
        local reg, ids = setup()
        BENCH("Set 2 new components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
            end
        end)

        BENCH("Set 2 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
            end
        end)
    end

    do
        local reg, ids = setup()
        BENCH("Set 4 new components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
                reg:set(e, C, true)
                reg:set(e, D, true)
            end
        end)

        BENCH("Set 4 components", function()
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

----------------------------------------
-- Has components
----------------------------------------

print("Has components")

do
    local N = 1e6

    local reg = ecr.registry(N)
    local ids = table.create(N)

    for i = 1, N do
        ids[i] = reg:create()
        reg:set(ids[i], A, true)
        reg:set(ids[i], B, true)
        reg:set(ids[i], C, true)
        reg:set(ids[i], D, true)
    end

    BENCH("Has 1 component", function()
        for i = 1, START(N) do
            reg:has(ids[i], A)
        end
    end)

    BENCH("Has 2 component", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:has(e, A)
            reg:has(e, B)
        end
    end)

    BENCH("Has 4 component", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:has(e, A)
            reg:has(e, B)
            reg:has(e, C)
            reg:has(e, D)
        end
    end)
end

----------------------------------------
-- Getting components
----------------------------------------

print("Getting components")

do
    local N = 1e6

    local reg = ecr.registry(N)
    local ids = table.create(N)

    for i = 1, N do
        ids[i] = reg:create()
        reg:set(ids[i], A, true)
        reg:set(ids[i], B, true)
        reg:set(ids[i], C, true)
        reg:set(ids[i], D, true)
    end

    BENCH("Get 1 component", function()
        for i = 1, START(N) do
            reg:get(ids[i], A)
        end
    end)

    BENCH("Get 2 component", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:get(e, A)
            reg:get(e, B)
        end
    end)

    BENCH("Get 4 component", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:get(e, A)
            reg:get(e, B)
            reg:get(e, C)
            reg:get(e, D)
        end
    end)

    BENCH("Get 4 component (tuple)", function()
        for i = 1, START(N) do
            reg:get(ids[i], A, B, C, D)
        end
    end)
end

----------------------------------------
-- Removing components
----------------------------------------

print("Removing components")

do
    local N = 1e6

    BENCH("Remove 0 components", function()
        local reg = ecr.registry(N)
        local ids = table.create(N)

        for i = 1, N do
            ids[i] = reg:create()
        end

        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)

    BENCH("Remove 1 component", function()
        local reg = ecr.registry(N)
        local ids = table.create(N)

        for i = 1, N do
            ids[i] = reg:create()
            reg:set(ids[i], A, true)
        end

        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)

    BENCH("Remove 2 components", function()
        local reg = ecr.registry(N)
        local ids = table.create(N)

        for i = 1, N do
            ids[i] = reg:create()
            reg:set(ids[i], A, true)
            reg:set(ids[i], B, true)
        end

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A)
            reg:remove(e, B)
        end
    end)

    BENCH("Remove 4 components", function()
        local reg = ecr.registry(N)
        local ids = table.create(N)

        for i = 1, N do
            ids[i] = reg:create()
            reg:set(ids[i], A, true)
            reg:set(ids[i], B, true)
            reg:set(ids[i], C, true)
            reg:set(ids[i], D, true)
        end

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A)
            reg:remove(e, B)
            reg:remove(e, C)
            reg:remove(e, D)
        end
    end)
end

----------------------------------------
-- Viewing all components
----------------------------------------

local function viewBench(reg: ecr.Registry)
    BENCH("View all entities", function()
        local reg = reg

        START()

        for entity in reg:view() do end

        STOP()
        ITER(#reg:view())
    end)

    BENCH("View entities with 1 component", function()
        local reg = reg
        local A = A

        START()

        for entity in reg:view(A) do end

        STOP()
        ITER(#reg:view(A))
    end)

    BENCH("View entities with 2 components", function()
        local reg = reg
        local A = A

        START()

        for entity in reg:view(A, B) do end

        STOP()
        ITER(#reg:view(A, B))
    end)

    BENCH("View entities with 4 components", function()
        local reg = reg
        local A = A

        START()

        for entity in reg:view(A, B, C, D) do end

        STOP()
        ITER(#reg:view(A, B, C, D))
    end)

    BENCH("View entities and get 1 component", function()
        local reg = reg
        local A = A

        START()

        for entity in reg:view(A):each() do end

        STOP()
        ITER(#reg:view(A))
    end)

    BENCH("View entities and get 2 components", function()
        local reg = reg
        local A = A

        START()

        for entity in reg:view(A, B):each() do end

        STOP()
        ITER(#reg:view(A, B))
    end)

    BENCH("View entities and get 4 components", function()
        local reg = reg
        local A = A

        START()

        for entity in reg:view(A, B, C, D):each() do end

        STOP()
        ITER(#reg:view(A, B, C, D))
    end)
end

print("View all entities with ordered components")

do
    local N = 1e6
    local reg = ecr.registry(N)

    for i = 1, N do
        local entity = reg:create()
        reg:set(entity, A, true)
        reg:set(entity, B, true)
        reg:set(entity, C, true)
        reg:set(entity, D, true)
    end

    viewBench(reg)
end

print("View all entities with random components (even 50% distr.)")

do
    local N = 1e6
    local reg = ecr.registry(N)

    local function flip() return math.random() > 0.5 end -- TODO: investigate

    for i = 1, N do
        local entity = reg:create()
        if flip() then reg:set(entity, A, true) end
        if flip() then reg:set(entity, B, true) end
        if flip() then reg:set(entity, C, true) end
        if flip() then reg:set(entity, D, true) end
    end

    viewBench(reg)
end

print("View all entities with tagged random components (even 50% distr.)")

do
    local N = 1e6
    local reg = ecr.registry(N)

    local function flip() return math.random() > 0.8 end -- TODO: investigate

    for i = 1, N do
        local entity = reg:create()
        local a, b, c
        if flip() then a= true; reg:set(entity, A, true) end
        if flip() then b=true; reg:set(entity, B, true) end
        if flip() then c=true; reg:set(entity, C, true) end
        if a and b and c then reg:set(entity, D, true) end
    end

    viewBench(reg)
end

----------------------------------------
-- Destroying entities
----------------------------------------

print("Release entities")

BENCH("Release entity", function()
    local N = 1e6
    local reg = ecr.registry()
    local entities = table.create(N)
    for i = 1, N do
        entities[i] = reg:create()
    end

    START(N)

    for i = 1, N do
        reg:release(entities[i])
    end

    STOP()
end)

print("Destroy entities")

BENCH("Destroy entity with 0 components", function()
    local N = 1e6
    local reg = ecr.registry()
    local entities = table.create(N)
    for i = 1, N do
        entities[i] = reg:create()
    end

    START(N)

    for i = 1, N do
        reg:destroy(entities[i])
    end

    STOP()
end)

BENCH("Destroy entity with 1 components", function()
    local N = 1e6
    local reg = ecr.registry()
    local entities = table.create(N)
    for i = 1, N do
        local e = reg:create()
        reg:set(e, A, true)
        entities[i] = e
    end

    START(N)

    for i = 1, N do
        reg:destroy(entities[i])
    end

    STOP()
end)

BENCH("Destroy entity with 2 components", function()
    local N = 1e6
    local reg = ecr.registry()
    local entities = table.create(N)
    for i = 1, N do
        local e = reg:create()
        reg:set(e, A, true)
        reg:set(e, B, true)
        entities[i] = e
    end

    START(N)

    for i = 1, N do
        reg:destroy(entities[i])
    end

    STOP()
end)

BENCH("Destroy entity with 4 components", function()
    local N = 1e6
    local reg = ecr.registry()
    local entities = table.create(N)
    for i = 1, N do
        local e = reg:create()
        reg:set(e, A, true)
        reg:set(e, B, true)
        reg:set(e, C, true)
        reg:set(e, D, true)
        entities[i] = e
    end

    START(N)

    for i = 1, N do
        reg:destroy(entities[i])
    end

    STOP()
end)

BENCH("Destroy entity with 1 component (8 component registered)", function()
    local N = 1e6
    local reg = ecr.registry()
    local entities = table.create(N)
    for i = 1, N do
        local e = reg:create()
        reg:set(e, A, true)
        entities[i] = e
    end

    do
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

    START(N)

    for i = 1, N do
        reg:destroy(entities[i])
    end

    STOP()
end)

----------------------------------------
-- Valid and version checking
----------------------------------------

BENCH("registry::valid", function()
    local N = 1e6
    local reg = ecr.registry(N)
    local entities = table.create(N)
    for i = 1, N do
        entities[i] = reg:create()
    end

    START(N)

    for i = 1, N do
        reg:valid(entities[i])   
    end
end)

BENCH("registry::version", function()
    local N = 1e6
    local reg = ecr.registry(N)
    local entities = table.create(N)
    for i = 1, N do
        entities[i] = reg:create()
    end

    START(N)

    for i = 1, N do
        reg:version(entities[i])   
    end
end)

----------------------------------------
-- Signals
----------------------------------------

BENCH("registry::changed", function()
    local N = 1e6

    local reg = ecr.registry()
    local e = reg:create()
    reg:changed(A):connect(function() end)

    for i = 1, START(N) do
        reg:set(e, A, true)
    end
end)


BENCH("registry::removing", function()
    local N = 1e6

    local reg = ecr.registry()
    local e = reg:create()
    reg:removing(A):connect(function() end)

    for i = 1, START(N) do
        reg:remove(e, A)
    end
end)
