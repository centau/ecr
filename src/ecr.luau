----------------------------------------------------------------------
-- ecr.luau
-- v0.1.0
----------------------------------------------------------------------

--!optimize 2

type vector<T> = { T }
type map<T, U> = { [T]: U }

type ComponentId = number
type EntityId = number
export type Entity = EntityId

export type Registry = {
    create: (Registry) -> Entity,
    release: (Registry, entity: Entity) -> (),
    destroy: (Registry, entity: Entity) -> (),

    valid: (Registry, entity: Entity) -> boolean,
    version: (Registry, entity: Entity) -> number,
    current: (Registry, entity: Entity) -> number,

    orphan: (Registry, entity: Entity) -> boolean,
    set: <T>(Registry, entity: Entity, component: T, value: T?) -> (),
    has: <T...>(Registry, entity: Entity, T...) -> boolean,
    get: <T...>(Registry, entity: Entity, T...) -> T...,
    remove: <T...>(Registry, entity: Entity, T...) -> (),

    size: (Registry) -> number,
    capacity: (Registry) -> number,
    clear: <T...>(Registry, T...) -> (),

    view: <T...>(Registry, T...) -> View<T...>,
    track: <T, U...>(Registry, T, U...) -> Observer<(T?, U...)>,

    entities: <T>(Registry) -> vector<EntityId>,
    storage: <T>(Registry, component: T) -> Pool<T>,

    added: <T>(Registry, component: T) -> Signal<Registry, EntityId, T>,
    changed: <T>(Registry, component: T) -> Signal<Registry, EntityId, T>,
    removing: <T>(Registry, component: T) -> Signal<Registry, EntityId, T>,
}

export type View<T...> = typeof(setmetatable(
    {} :: {
        each: (View<T...>) -> () -> (EntityId, T...),
        exclude: <U...>(View<T...>, U...) -> View<T...>,
    },
    {} :: {
        __iter: (View<T...>) -> () -> (EntityId, T...),
        __len: (View<T...>) -> number
    }
))

export type Observer<T...> = View<T...> & {
    disconnect: (Observer<T...>) -> (),
    reconnect: (Observer<T...>) -> (),
    clear: (Observer<T...>) -> (),
}

export type Signal<T...> = {
    connect: ( Signal<T...>, (T...) -> () ) -> (),
    disconnect: ( Signal<T...>, (T...) -> () ) -> ()
}

local alloc = table.create

----------------------------------------------------------------------
-- Entity Id
----------------------------------------------------------------------

--[[
 - Entity Id implementation.
 -      53 bits total
 -      Upper 33 bits represents version (8,589,934,591)
 -      Lower 20 bits represents key (1,048,575)
 - Luau numbers are 64-bit floats so bitshifting is done through multiplication by power of 2
]]

local id_MASK_KEY = 0x000FFFFF -- first 20 bits
local _id_MASK_VERSION = 2^53-1 - id_MASK_KEY

local id_LSHIFT_VERSION = id_MASK_KEY + 1
local id_RSHIFT_VERSION = 1/id_LSHIFT_VERSION

local function id_encode(idx: number, ver: number): number
    --assert(idx <= id_mask_index)
    --assert(ver <= id_mask_version)
    return ver * id_LSHIFT_VERSION + idx
end

local function id_decode(id: number): (number, number) -- idx, ver
    local lower = bit32.band(id, id_MASK_KEY)
    local upper = (id - lower) * id_RSHIFT_VERSION
    return lower, upper
end

local function id_getkey(id: number): number
    return bit32.band(id, id_MASK_KEY)
end

local function id_getversion(id: number): number
    local lower = bit32.band(id, id_MASK_KEY)
    return (id - lower) * id_RSHIFT_VERSION
end

local function id_setkey(id: number, ver: number): number
    return id - bit32.band(id, id_MASK_KEY) + ver
end

----------------------------------------------------------------------
-- Entity Pool
----------------------------------------------------------------------

--[[
 - Specialized sparse-set implementation designated as "pool".
 - Composed of 3 arrays:
 -      Sparse array mapping entity key to an internal dense array index
 -      Dense array containing entity ids
 -      Dense array containing component values (sorted the same as above)
]]

type Pool<T> = {
    map: vector<number?>,
    entities: vector<number>,
    values: vector<T>,
    size: number,
}

-- maps entity key to internal index
local function pool_map<T>(self: Pool<T>, k: number): number?
    return self.map[k]
end

-- replaces value at internal index with new value
-- undefined behavior if index is not valid
local function pool_replace<T>(self: Pool<T>, i: number, v: T)
    self.values[i] = v
end

-- 
local function pool_addk<T>(self: Pool<T>, k: number, entity: EntityId, v: T)
    local n = self.size + 1; self.size = n
    self.map[k] = n
    self.entities[n] = entity
    self.values[n] = v   
end

-- removes value 
local function pool_erase<T>(self: Pool<T>, k: number, i: number)
    local map = self.map
    local entities = self.entities
    local values = self.values
    local n = self.size

    local lastEntity = entities[n]
    entities[i] = lastEntity; entities[n] = nil
    map[id_getkey(lastEntity)] = i; map[k] = nil
    values[i] = values[n]; values[n] = nil
    self.size = n - 1   
end

local function pool_create(size: number?): Pool<any>
    local n = size or 1
    return {
        map = alloc(n),
        entities = alloc(n),
        values = alloc(n),
        size = 0
    }
end

-- a sparse set contains an element if `i <= self.size and self.entities[i] == entity`
-- but our indexes are initialized to nil so we suffice with `self.sparse[idx] ~= nil`
local function pool_has<T>(self: Pool<T>, entity: EntityId): boolean
    return self.map[id_getkey(entity)] ~= nil
end

-- get entity value from pool
-- returns nil if entity not in pool
local function pool_get<T>(self: Pool<T>, entity: EntityId): T?
    local i = self.map[id_getkey(entity)]
    return i and self.values[i] :: any -- TODO: resolve typechecking error
end

-- adds an entity and value to pool
-- undefined behavior if entity is already in pool
local function pool_add<T>(self: Pool<T>, entity: EntityId, v: T)
    local n = self.size + 1; self.size = n
    self.map[id_getkey(entity)] = n
    self.entities[n] = entity
    self.values[n] = v
end

local function pool_add_kn<T>(self: Pool<T>, entity: EntityId, k: number, n: number)
    self.size = n
    self.map[k] = n
    self.entities[n] = entity
end

-- set an entity and value
-- changes value if entity is already in pool
-- adds entity and value if not in pool
local function pool_set<T>(self: Pool<T>, entity: EntityId, v: T)
    local k = id_getkey(entity)
    local i = self.map[k]
    if i then
        pool_replace(self, i, v)
    else -- not in pool
        pool_addk(self, k, entity, v)
    end
end

-- removes an entity and value
-- does nothing if entity is not in pool
-- order is not preserved (swap and pop policy)
local function pool_remove<T>(self: Pool<T>, entity: EntityId)
    local map = self.map
    local k = id_getkey(entity)
    local i = map[k] :: number
    if not i then return end

    local entities = self.entities
    local values = self.values
    local n = self.size

    local lastEntity = entities[n]
    entities[i] = lastEntity; entities[n] = nil
    map[id_getkey(lastEntity)] = i; map[k] = nil
    values[i] = values[n]; values[n] = nil
    self.size = n - 1
end

local function pool_size<T>(self: Pool<T>): number
    return self.size
end

local function pool_clear<T>(self: Pool<T>)
    table.clear(self.map)
    table.clear(self.entities)
    table.clear(self.values)
    self.size = 0
end

-- fast remove
-- no check, works with entity index directly
-- does not remove value
-- undefined behavior if used on an entity not in the pool
local function pool_fremove_nv<T>(self: Pool<T>, removeIndex: number)
    local map = self.map
    local i = map[removeIndex] :: number

    local entities = self.entities
    local n = self.size

    local lastEntity = entities[n]
    entities[i] = lastEntity; entities[n] = nil
    map[id_getkey(lastEntity)] = i; map[removeIndex] = nil
    self.size = n - 1
end

local function pool_clone<T>(self: Pool<T>): Pool<T>
    return {
        map = table.clone(self.map),
        entities = table.clone(self.entities),
        values = table.clone(self.values),
        size = self.size
    }
end

----------------------------------------------------------------------
-- Views
----------------------------------------------------------------------

local function hasNone(entity: EntityId, excludes: vector<Pool<unknown>>): boolean
    for _, pool in next, excludes do
        if pool_has(pool, entity) then return true end
    end
    return false
end

local function hasAll(entity: EntityId, pools: vector<Pool<unknown>>): boolean
    for _, pool in next, pools do
        if pool_has(pool, entity) == false then return false end
    end
    return true
end

-- true if criteria broken
local function filter(entity: EntityId, includes: vector<Pool<unknown>>, excludes: vector<Pool<unknown>>?): boolean
    return excludes and hasNone(entity, excludes) or not hasAll(entity, includes)
end

local View = {} do
    type _View = View<...unknown> & {
        registry: Registry,
        components: map<ComponentId, boolean>,
        includes: vector<Pool<unknown>>,
        excludes: vector<Pool<unknown>>?
    }

    View.__index = View

    function View.new(reg: Registry, ...: ComponentId): View<...unknown>
        local argn = select("#", ...)
    
        local components, includes = {}, {}

        for i = 1, argn do
            local component = select(i, ...)
            if components[component] then error("duplicate component", 3) end
            components[component] = true
            includes[i] = reg:storage(component)
        end

        return setmetatable({
            registry = reg,
            components = components,
            includes = includes,
            excludes = nil
        }, View) :: any
    end

    --[[
     - returns:
     -  1. smallest pool
     -  2. array of other pools
     -  3. original index of smallest pool
     -  4. array of original indexes of other pools (same order as 3.)
    ]]
    local function sortPools(pools: vector<Pool<unknown>>): (Pool<unknown>, vector<Pool<unknown>>, number, vector<number>)
        local smallest = pools[1]
        if smallest == nil then error("no pools given", 2) end
        local index = 1
        for i, pool in next, pools, 1 do
            if pool_size(pool) < pool_size(smallest) then
                smallest = pool
                index = i
            end
        end

        local others = alloc(#pools-1)
        local indexes = alloc(#pools-1)
        for i, pool in next, pools do
            if pool ~= smallest then
                table.insert(others, pool)
                table.insert(indexes, i)
            end
        end

        return smallest, others, index, indexes
    end

    local function iter(self: _View): () -> (EntityId, ...unknown)
        local includes = self.includes
        local minPool, otherPools, minPoolIndex, otherPoolsIndexes = sortPools(includes)
        local entities = minPool.entities
        local values = minPool.values
        local excludes = self.excludes
        local tuple = alloc(#includes)

        local i = pool_size(minPool)
        return if #otherPools == 0 and not excludes then -- single view
                function()
                    local _i = i; i = _i - 1
                    return entities[_i], values[_i]
                end
            elseif #otherPools and excludes then -- single view with excludes
                function()
                    local _i = i
                    while _i > 0 do 
                        local entity = entities[_i]
                        if hasNone(entity, excludes) then _i -= 1; continue end
                        i = _i - 1
                        return entity, values[_i]
                    end
                    return nil :: any
                end
            else function() -- multi view with excludes
                local _i = i
                while _i > 0 do
                    local entity = entities[_i]
                    if filter(entity, includes, excludes) then _i -= 1; continue end
                    tuple[minPoolIndex] = values[_i]
                    for ii, otherPools in next, otherPools do
                        tuple[otherPoolsIndexes[ii]] = pool_get(otherPools, entity) 
                    end
                    i = _i - 1
                    return entity, unpack(tuple)
                end
                return nil :: any
            end
    end

    function View.exclude(self: _View, ...: unknown): _View
        local excludes = self.excludes or (function()
            local t = {}
            self.excludes = t
            return t
        end)()

        local components = self.components

        for i = 1, select("#", ...) do
            local component = select(i, ...)
            if components[component] == true then error("cannot exclude an already included component", 2) end
            if components[component] == false then error ("duplicate component excluded", 2) end
            components[component] = false
            table.insert(excludes, self.registry:storage(component))
        end

        return self
    end

    function View.each(self: _View): () -> (EntityId, ...unknown)
        return iter(self) 
    end

    function View:__iter(): () -> (EntityId, ...unknown)
        return iter(self)
    end

    function View.__len(self: _View): number
        return pool_size((sortPools(self.includes)))
    end
end

----------------------------------------------------------------------
-- Observer W.I.P
----------------------------------------------------------------------

local Observer = {} do
    type _Observer = Observer<...unknown> & {
        registry: Registry,
        components: map<ComponentId, boolean>,
        includes: vector<Pool<unknown>>,
        excludes: vector<Pool<unknown>>?,

        tracking: ComponentId,
        changed: Pool<unknown>,
        listeners: vector<(Registry, EntityId, unknown) -> ()>?,
    }

    Observer.__index = Observer

    function Observer.new(reg: Registry, toTrack: ComponentId , ...: ComponentId)
        local argn = select("#", ...)

        local components, includes = {}, {}
        local changed = pool_clone(reg:storage(toTrack))

        for i = 1, argn do
            local component = select(i, ...)
            if components[component] then error("duplicate component", 3) end
            components[component] = true
            includes[i] = reg:storage(component)
        end

        local self: _Observer = setmetatable({
            registry = reg,
            components = components,
            includes = includes,
            excludes = nil,
            tracking = toTrack,
            changed = changed,
            listeners = nil
        }, Observer) :: any

        self:reconnect()

        return self
    end

    local function iter(self: _Observer): () -> (EntityId, ...unknown)
        local changed = self.changed

        local includes = self.includes
        local excludes = self.excludes

        local entities = changed.entities
        local values = changed.values

        local tuple = alloc(#includes + 1)

        local i = pool_size(changed)
        return function() -- multi view with excludes
            local _i = i
            while _i > 0 do
                local entity = entities[_i]
                if filter(entity, includes, excludes) then _i -= 1; continue end
                tuple[1] = values[_i]
                for ii, pool in next, includes do
                    tuple[ii + 1] = pool_get(pool, entity) 
                end
                i = _i - 1
                return entity, unpack(tuple)
            end
            return nil :: any
        end   
    end

    function Observer.disconnect(self: _Observer)
        if not self.listeners then error("observer already disconnected", 2) end; assert(self.listeners)
        for component, included in next, self.components do
            if not included then continue end
            for _, listener in next, self.listeners do
                self.registry:added(component):disconnect(listener)
                self.registry:changed(component):disconnect(listener)
                self.registry:removing(component):disconnect(listener)
            end
        end
        self.listeners = nil
    end

    function Observer.reconnect(self: _Observer)
        if self.listeners then error("tracker already connected", 2) end; assert(not self.listeners)
        
        local listener: (reg: Registry, entity: EntityId, value: unknown) -> ()

        local changed = self.changed
        local includes = self.includes
        local excludes = self.excludes

        function listener(_, entity, value)
            if filter(entity, includes, excludes) then return end
            pool_set(changed, entity, value)
        end

        local reg = self.registry
        local toTrack = self.tracking
        reg:added(toTrack):connect(listener)
        reg:changed(toTrack):connect(listener)
        reg:removing(toTrack):connect(listener)

        self.listeners = { listener }
    end

    function Observer.clear(self: _Observer)
        pool_clear(self.changed)
    end

    function Observer.exclude(self: _Observer, ...: ComponentId): _Observer
        if self.listeners then self:disconnect() end

        local excludes = self.excludes or (function()
            local t = {}
            self.excludes = t
            return t
        end)()

        local components = self.components

        for i = 1, select("#", ...) do
            local component = select(i, ...)
            if components[component] == true then error("cannot exclude an already included component", 2) end
            if components[component] == false then error ("duplicate component excluded", 2) end
            components[component] = false
            table.insert(excludes, self.registry:storage(component))
        end

        self:reconnect()
        return self
    end

    function Observer.each(self: _Observer): () -> (EntityId, ...unknown)
        return iter(self)    
    end

    function Observer.__iter(self: _Observer): () -> (EntityId, ...unknown)
        return iter(self)
    end

    function Observer.__len(self: _Observer): number
        return pool_size(self.changed)
    end
end

----------------------------------------------------------------------
-- Signal
----------------------------------------------------------------------

local createSignal: () -> (Signal<...any>, (...any) -> ()) do
    type _Signal = {
        [(...any) -> ...any]: true
    }

    local Signal = {}
    Signal.__index = Signal

    function Signal.connect(self: _Signal, listener: (...any) -> ())
        self[listener] = true
    end

    function Signal.disconnect(self: _Signal, listener: (...any) -> ())
        self[listener] = nil
    end

    function createSignal()
        local signal = setmetatable({}, Signal)

        local function fire(...: any)
            for listener in next, signal do
                listener(...)
            end
        end

        return signal, fire
    end
end

----------------------------------------------------------------------
-- Registry
----------------------------------------------------------------------

local INVALID = 0
local INITIAL_VERSION = 1

local componentN = 0
local function createComponent(): unknown
    componentN += 1
    return componentN
end

local function createRegistry(count: number?): Registry
    local size = count or 1

    local freeId: number = INVALID
    local ids = alloc(size)

    local entities: Pool<nil> = pool_create(size)
    local cpools: map<ComponentId, Pool<unknown>> = alloc(componentN)

    local fireAddedEvent: map<ComponentId, (Registry, EntityId, unknown) -> ()> = alloc(componentN)
    local fireChangedEvent: map<ComponentId, (Registry, EntityId, unknown) -> ()> = alloc(componentN)
    local fireRemovingEvent: map<ComponentId, (Registry, EntityId, unknown) -> ()> = alloc(componentN)
    local addedEvent: map<ComponentId, Signal<Registry, EntityId, unknown>> = alloc(componentN)
    local changedEvent: map<ComponentId, Signal<Registry, EntityId, unknown>> = alloc(componentN)
    local removingEvent: map<ComponentId, Signal<Registry, EntityId, unknown>> = alloc(componentN)

    local function fireEvent<T>(
        events: map<ComponentId, (Registry, EntityId, unknown) -> ()>,
        component: ComponentId,
        registry: Registry,
        entity: EntityId,
        value: T
    )
        if events[component] then events[component](registry, entity, value) end
    end

    local function initIds()
        table.clear(ids)
        freeId = 1
        for i = 1, size - 1 do
            ids[i] = id_encode(i + 1, INITIAL_VERSION)
        end
        ids[size] = id_encode(INVALID, INITIAL_VERSION)
    end

    setmetatable(cpools, {
        __index = function(self, component: ComponentId): Pool<unknown>
            if type(component) ~= "number" or math.sign(component) ~= 1 then
                error("Invalid component, component must be positive integer, got "..type(component), 2)
            end
            local pool = pool_create(size)
            self[component] = pool
            return pool
        end
    })

    initIds()

    local registry = {}

    function registry:create(): EntityId
        local entities = entities
        local n = pool_size(entities) + 1
        if n > id_MASK_KEY then error("cannot create entity; registry is at max entity count ("..id_MASK_KEY..")", 2) end

        if freeId ~= INVALID then
            local id = id_setkey(ids[freeId], freeId)
            pool_add_kn(entities, id, freeId, n)
            local oldFreeId = freeId
            freeId = id_getkey(ids[freeId])
            ids[oldFreeId] = id
            return id
        else
            local newId = id_encode(n, INITIAL_VERSION)
            table.insert(ids, newId)
            pool_add_kn(entities, newId, n, n)
            return newId
        end
    end

    local function release(entity: EntityId)
        local idx, ver = id_decode(entity)
        ids[idx] = id_encode(freeId, ver + 1)
        pool_remove(entities, entity)
        freeId = idx
    end

    function registry:release(entity: EntityId)
        release(entity)
    end

    function registry:destroy(entity: EntityId)
        release(entity)
        for component, pool in next, cpools do
            fireEvent(fireRemovingEvent, component, self, entity, nil)
            pool_remove(pool, entity)
        end   
    end

    function registry:valid(entity: EntityId): boolean
        return ids[id_getkey(entity)] == entity
    end

    function registry:version(entity: EntityId): number
        return id_getversion(entity)
    end

    function registry:current(entity: EntityId): number
        return id_getversion(ids[id_getkey(entity)])
    end

    function registry:orphan(entity: EntityId): boolean
        for _, pool in next, cpools do
            if pool_has(pool, entity) then return false end
        end
        return true
    end

    function registry:set(entity: EntityId, component: ComponentId, value: unknown)
        local pool = cpools[component]
        local idx = id_getkey(entity)
        local index = pool_map(pool, idx)
        
        if value ~= nil then
            if index then
                pool_replace(pool, index, value)   
                fireEvent(fireChangedEvent, component, self, entity, value)
            else
                pool_addk(pool, idx, entity, value)
                fireEvent(fireAddedEvent, component, self, entity, value)
            end
        elseif index then
            fireEvent(fireRemovingEvent, component, self, entity, nil)
            pool_erase(pool, idx, index)
        end
    end

    function registry:has(entity: EntityId, ...: ComponentId): boolean
        local a, b = ...
        if b == nil then
            return pool_has(cpools[a], entity)
        else
            for i = 1, select("#", ...) do
                if not pool_has(cpools[select(i, ...)], entity) then return false end
            end
            return true
        end
    end

    function registry:get(entity: EntityId, ...: ComponentId): ...unknown
        local a, b, c, d, e = ...
        if b == nil then
            return pool_get(cpools[a], entity)
        elseif c == nil then
            return pool_get(cpools[a], entity), pool_get(cpools[b], entity)
        elseif d == nil then
            return pool_get(cpools[a], entity), pool_get(cpools[b], entity), pool_get(cpools[c], entity)
        elseif e == nil then
            return pool_get(cpools[a], entity), pool_get(cpools[b], entity), pool_get(cpools[c], entity), pool_get(cpools[d], entity)
        else
            local tuple: vector<any> = { ... }
            for i, v in next, tuple do
                tuple[i] = pool_get(cpools[v], entity)
            end
            return unpack(tuple)
        end
    end

    function registry:remove(entity: EntityId, ...: ComponentId)
        local idx = id_getkey(entity)
        for i = 1, select("#", ...) do
            local component = select(i, ...)
            local pool = cpools[component]
            local i = pool_map(pool, idx) :: number
            if not i then return end
            fireEvent(fireRemovingEvent, component, self, entity, nil)
            pool_erase(pool, idx, i)
        end
    end

    function registry:size(): number
        return pool_size(entities)
    end

    function registry:capacity(): number
        return size
    end

    function registry:clear(...: ComponentId)
        local argn = select("#", ...)
        if argn > 0 then -- clear components
            for i = 1, argn do
                pool_clear(cpools[select(i, ...)])
            end
        else -- destroy all entities
            pool_clear(entities)
            initIds()
            for _, pool in next, cpools do pool_clear(pool) end
        end 
    end

    function registry:reset()
        registry:clear()
        initIds()
    end

    function registry:view(...: ComponentId): View<...unknown>
        if select("#", ...) == 0 then
            return View.new(registry :: any, 0)
        else
            return View.new(registry :: any, ...)
        end
    end

    function registry:track(...: ComponentId): Observer<...unknown>
        return Observer.new(registry :: any, ...)
    end

    function registry:entities(): vector<EntityId>
        return entities.entities
    end

    function registry:storage(component: ComponentId): Pool<unknown>
        return component == 0 and entities or cpools[component]
    end

    function registry:added(component: ComponentId): Signal<unknown>
        return addedEvent[component] or (function() 
            local signal, fire = createSignal()
            addedEvent[component] = signal
            fireAddedEvent[component] = fire
            return signal      
        end)()       
    end

    function registry:changed(component: ComponentId): Signal<unknown>
        return changedEvent[component] or (function() 
            local signal, fire = createSignal()
            changedEvent[component] = signal
            fireChangedEvent[component] = fire
            return signal      
        end)()       
    end

    function registry:removing(component: ComponentId): Signal<unknown>
        return removingEvent[component] or (function() 
            local signal, fire = createSignal()
            removingEvent[component] = signal
            fireRemovingEvent[component] = fire
            return signal      
        end)()
    end

    setmetatable(registry, { __index = function(_, index)
        error(tostring(index).." is not a valid member of registry", 2)    
    end })

    return table.freeze(registry) :: any
end

return {
    component = createComponent,
    registry = createRegistry,
    pool = {
        create = pool_create,
        has = pool_has,
        get = pool_get,
        set = pool_set,
        remove = pool_remove,
        size = pool_size,
        clear = pool_clear
    }
}
