local BENCH, START = require("test/testkit").getBenchmarkTools()

local function TITLE(name: string)
    print("\27[1;4m"..name.."\27[0m")
end

local ecr = require "src/ecr"

local function rtrue() return true :: any end
local A, B, C, D = ecr.component(rtrue), ecr.component(rtrue), ecr.component(rtrue), ecr.component(rtrue)
local E, F, G, H = ecr.component(), ecr.component(), ecr.component(), ecr.component()

do TITLE "Entity creation and release"
    BENCH("Entity creation", function()
        local N = 1e6
        local reg = ecr.registry()

        for i = 1, START(N) do
            reg:create()
        end
    end)

    BENCH("Entity creation (no pre-alloc)", function()
        local N = 1e6
        local reg = ecr.registry()

        for i = 1, START(N) do
            reg:create()
        end
    end)

    BENCH("Entity release", function()
        local N = 1e6
        local reg = ecr.registry()

        local id = table.create(N)

        for i = 1, N do
            id[i] = reg:create()
        end

        for i = 1, START(N) do
            reg:release(id[i])
        end
    end)

    BENCH("Entity creation with desired id", function()
        local N = 1e6
        local sreg = ecr.registry()
        
        local id = table.create(N)

        for i = 1, N do
            id[i] = sreg:create()
        end

        local reg = ecr.registry()

        for i = 1, START(N) do
            reg:create(id[i])
        end
    end)
end

do TITLE "Adding components"
    local N = 1e6

    local function setup()
        local reg = ecr.registry()
        local ids = table.create(N)
        for i = 1, N do
            ids[i] = reg:create()
        end
        return reg, ids
    end

    do
        local reg, ids = setup()

        BENCH("Add 1 component", function()
            for i = 1, START(N) do
                reg:add(ids[i], A)
            end
        end)
    end

    do
        local reg, ids = setup()

        BENCH("Add 2 components", function()
            for i = 1, START(N) do
                reg:add(ids[i], A, B)
            end
        end)
    end

    do
        local reg, ids = setup()

        BENCH("Add 4 components", function()
            for i = 1, START(N) do
                reg:add(ids[i], A, B, C, D)
            end
        end)
    end
end


do TITLE "Setting components"
    local N = 1e6

    local function setup()
        local reg = ecr.registry()
        local ids = table.create(N)
        for i = 1, N do
            ids[i] = reg:create()
        end
        return reg, ids
    end

    do
        local reg, ids = setup()

        BENCH("Add 1 component", function()
            for i = 1, START(N) do
                reg:set(ids[i], A, true)
            end
        end)

        BENCH("Change 1 component", function()
            for i = 1, START(N) do
                reg:set(ids[i], A, true)
            end
        end)

        BENCH("Remove 1 component", function()
            for i = 1, START(N) do
                reg:set(ids[i], A, nil)
            end
        end)
    end

    do
        local reg, ids = setup()

        BENCH("Add 2 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
            end
        end)

        BENCH("Change 2 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
            end
        end)

        BENCH("Remove 2 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, nil)
                reg:set(e, B, nil)
            end
        end)
    end

    do
        local reg, ids = setup()
        BENCH("Add 4 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
                reg:set(e, C, true)
                reg:set(e, D, true)
            end
        end)

        BENCH("Change 4 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, true)
                reg:set(e, B, true)
                reg:set(e, C, true)
                reg:set(e, D, true)
            end
        end)

        BENCH("Remove 4 components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:set(e, A, nil)
                reg:set(e, B, nil)
                reg:set(e, C, nil)
                reg:set(e, D, nil)
            end
        end)
    end
end

do TITLE "Patching components"
    local N = 1e6

    local function setup()
        local reg = ecr.registry()
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

        BENCH("Update 1 existing component", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:patch(e, A, patcher)
            end
        end)
    end
    
    do
        local reg, ids = setup()
        
        BENCH("Update 2 existing components", function()
            for i = 1, START(N) do
                local e = ids[i]
                reg:patch(e, A, patcher)
                reg:patch(e, B, patcher)
            end
        end)
    end
    
    do
        local reg, ids = setup()
        
        BENCH("Update 4 existing components", function()
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

do TITLE "Has components"
    local N = 1e6

    local reg = ecr.registry()
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
            reg:has(e, A, B)
        end
    end)

    BENCH("Has 4 component", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:has(e, A, B, C, D)
        end
    end)
end

do TITLE("Getting components")
    local N = 1e6

    local reg = ecr.registry()
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

    BENCH("Get 1 component", function()
        for i = 1, START(N) do
            reg:get(ids[i], A)
        end
    end)

    BENCH("Get 2 component", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:get(e, A, B)
        end
    end)

    BENCH("Get 4 component", function()
        for i = 1, START(N) do
            local e = ids[i]
            reg:get(e, A, B, C, D)
        end
    end)

    BENCH("Get 8 components", function()
        for i = 1, START(N) do
            reg:get(ids[i], A, B, C, D, E, F, G, H)
        end
    end)
end

do TITLE("Removing components")
    local N = 1e6

    local function setup()
        local reg = ecr.registry()
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

    BENCH("Attempt remove of non-existant component", function()
        local reg, ids = setup()

        for i = 1, N do
            reg:remove(ids[i], A)
        end

        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)

    BENCH("Remove 1 component", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            reg:remove(ids[i], A)
        end
    end)

    BENCH("Remove 2 components", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A, B)
        end
    end)

    BENCH("Remove 4 components", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A, B, C, D)
        end
    end)

    BENCH("Remove 8 components", function()
        local reg, ids = setup()

        for i = 1, START(N) do
            local e = ids[i]
            reg:remove(e, A, B, C, D, E, F, G, H)
        end
    end)
end

do TITLE "Clear components"
    local N = 1e6

    local function setup()
        local reg = ecr.registry()
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

    BENCH("Clear 1 component", function()
        local reg = setup()

        START(N)
        reg:clear(A)
    end)

    BENCH("Clear 2 components", function()
        local reg = setup()

        START(N)
        reg:clear(A, B)
    end)

    BENCH("Clear 4 components", function()
        local reg = setup()

        START(N)
        reg:clear(A, B, C, D)
    end)

    BENCH("Clear 8 components", function()
        local reg = setup()

        START(N)
        reg:clear(A, B, C, D, E, F, G, H)
    end)

    BENCH("Clear all entities (no components)", function()
        local reg = ecr.registry()
        for i = 1, N do reg:create() end

        START(N)
        reg:clear()
    end)
end

do
    local N = 1e6

    local function viewBench(reg: ecr.Registry)
        local function getExactSize(view: ecr.View<...any>): number
            local i = 0
            for _ in view do
                i += 1
            end
            return i
        end

        BENCH("View 1 component", function()
            local view = reg:view(A)

            START(getExactSize(view))
            for entity, a in view do end
        end)

        BENCH("View 2 components", function()
            local view = reg:view(A, B)

            START(getExactSize(view))
            for entity, a, b in view do end
        end)

        BENCH("View 4 components", function()
            local view = reg:view(A, B, C, D)

            START(getExactSize(view))
            for entity, a, b, c, d in view do end
        end)

        BENCH("View 8 components", function()
            local view = reg:view(A, B, C, D, E, F, G, H)

            START(getExactSize(view))
            for entity, a, b, c, d, e, f, g, h in view do end
        end)
    end

    do TITLE("View all entities with ordered components")
        local reg = ecr.registry()

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

    do TITLE("View all entities with random components (50% distr.)")
        local reg = ecr.registry()

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

    do TITLE("View all entities with common component (50% distr.)")
        --[[
            7 components are randomly assigned to entities,
            any entities that receive all 7 will be tagged with an 8th component.
            This guarantees that when iterating over this 8th component, all
            entities iterated will also contain the other 7.
        ]]
        local reg = ecr.registry()

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
end

do TITLE("Destroying entities")
    local N = 1e6

    BENCH("Destroy entity with 0 components", function()
        local reg = ecr.registry()
        local entities = table.create(N)

        for i = 1, N do
            entities[i] = reg:create()
        end

        for i = 1, START(N) do
            reg:destroy(entities[i])
        end
    end)

    BENCH("Destroy entity with 1 components", function()
        local reg = ecr.registry()
        local entities = table.create(N)

        for i = 1, N do
            local e = reg:create()
            reg:set(e, A, true)
            entities[i] = e
        end

        for i = 1, START(N) do
            reg:destroy(entities[i])
        end
    end)

    BENCH("Destroy entity with 2 components", function()
        local reg = ecr.registry()
        local entities = table.create(N)

        for i = 1, N do
            local e = reg:create()
            reg:set(e, A, true)
            reg:set(e, B, true)
            entities[i] = e
        end

        for i = 1, START(N) do
            reg:destroy(entities[i])
        end
    end)

    BENCH("Destroy entity with 4 components", function()
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

        for i = 1, START(N) do
            reg:destroy(entities[i])
        end
    end)

    BENCH("Destroy entity with 1 component (8 component registered)", function()
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

        for i = 1, START(N) do
            reg:destroy(entities[i])
        end
    end)
end

do TITLE("Valid and version checking")
    BENCH("registry::valid", function()
        local N = 1e6
        local reg = ecr.registry()
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
        local reg = ecr.registry()
        local entities = table.create(N)
        for i = 1, N do
            entities[i] = reg:create()
        end

        START(N)

        for i = 1, N do
            reg:version(entities[i])   
        end
    end)
end

do TITLE ("Registry signals")
    local N = 1e5

    local reg = ecr.registry()
    local entities = table.create(N)

    for i = 1, N do
        entities[i] = reg:create()
    end

    BENCH("registry::added", function()
        reg:added(A):connect(function() end)

        for i = 1, START(N) do
            reg:set(entities[i], A, true)
        end
    end)

    BENCH("registry::changed", function()
        reg:changed(A):connect(function() end)

        for i = 1, START(N) do
            reg:set(entities[i], A, false)
        end
    end)


    BENCH("registry::removing", function()
        reg:removing(A):connect(function() end)

        for i = 1, START(N) do
            reg:remove(entities[i], A)
        end
    end)
end
