----------------------------------------------------------------------
-- ecr.luau
-- v0.1.0
----------------------------------------------------------------------

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
        include: <U...>(View<T...>, U...) -> View<T...>,
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

----------------------------------------------------------------------
-- Entity Id
----------------------------------------------------------------------

--[[
 - Entity Id implementation
 -      53 bits total
 -      Upper 33 bits represents version (8,589,934,591)
 -      Lower 20 bits represents key (1,048,575)
 -
 - Luau numbers are 64-bit floats so bitshifting is done through multiplication by power of 2
 -
 - The key is used as an array index for pools
 - The version is used to keep the actual identifier unique.
]]

local id_MASK_KEY = 0x000FFFFF -- first 20 bits
local id_MASK_VERSION = 2^53-1 - id_MASK_KEY

local id_LSHIFT_VERSION = id_MASK_KEY + 1
local id_RSHIFT_VERSION = 1/id_LSHIFT_VERSION

local id_MAX_KEY = id_MASK_KEY
local id_MAX_VERSION = id_MASK_VERSION * id_RSHIFT_VERSION

-- encodes the given key and version into a single identifier
local function id_encode(key: number, ver: number): number
    --assert(key <= id_MAX_KEY)
    --assert(ver <= id_MAX_VERSION)
    return ver * id_LSHIFT_VERSION + key
end

-- gets key and version from identifier
local function id_decode(id: number): (number, number) -- key, ver
    local lower = bit32.band(id, id_MASK_KEY)
    local upper = (id - lower) * id_RSHIFT_VERSION
    return lower, upper
end

-- gets only key from identifier
local function id_getKey(id: number): number
    return bit32.band(id, id_MASK_KEY)
end

-- gets only version from identifier
local function id_getVersion(id: number): number
    local lower = bit32.band(id, id_MASK_KEY)
    return (id - lower) * id_RSHIFT_VERSION
end

-- sets a new key for a given identifier
local function id_setKey(id: number, key: number): number
    return id - bit32.band(id, id_MASK_KEY) + key
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

local function pool_create(size: number?): Pool<any>
    local n = size or 1
    return {
        map = table.create(n),
        entities = table.create(n),
        values = table.create(n),
        size = 0
    }
end

--[[ Specialized pool functions ]]

-- maps entity key to internal index
-- returns nil if entity is not in pool
local function pool_mapKey<T>(self: Pool<T>, k: number): number?
    return self.map[k]
end

-- checks if entity key `k` is contained within the pool
local function pool_hasKey<T>(self: Pool<T>, k: number): boolean
    return self.map[k] ~= nil
end

-- get entity key value from pool
-- returns nil if entity not in pool or value is nil
local function pool_getKey<T>(self: Pool<T>, k: number): T?
    local i = self.map[k]
    return i and self.values[i] :: any
end

-- replaces value at internal index with new value
-- undefined behavior if index is not valid
local function pool_replaceIndex<T>(self: Pool<T>, i: number, v: T)
    self.values[i] = v
end

-- adds a new value to the pool using the given entity key `k`
-- undefined behavior if entity already exists in pool
local function pool_addKey<T>(self: Pool<T>, k: number, entity: EntityId, v: T)
    local n = self.size + 1; self.size = n
    self.map[k] = n
    self.entities[n] = entity
    self.values[n] = v   
end

-- removes given entity key `k` at the given index from pool
-- undefined behavior if entity is not already in pool
local function pool_eraseKeyAtIndex<T>(self: Pool<T>, k: number, i: number)
    local map = self.map
    local entities = self.entities
    local values = self.values
    local n = self.size

    local lastEntity = entities[n]
    entities[i] = lastEntity; entities[n] = nil
    map[id_getKey(lastEntity)] = i; map[k] = nil
    values[i] = values[n]; values[n] = nil
    self.size = n - 1   
end

--[[ General pool functions ]]

-- checks if the entity is contained within pool
local function pool_has<T>(self: Pool<T>, entity: EntityId): boolean
    return self.map[id_getKey(entity)] ~= nil
end

-- get entity value from pool
-- returns nil if entity not in pool or value is nil
local function pool_get<T>(self: Pool<T>, entity: EntityId): T?
    local i = self.map[id_getKey(entity)]
    return i and self.values[i] :: any -- TODO: resolve typechecking error
end

-- adds an entity and value to pool
-- undefined behavior if entity is already in pool
local function pool_add<T>(self: Pool<T>, entity: EntityId, v: T)
    local n = self.size + 1; self.size = n
    self.map[id_getKey(entity)] = n
    self.entities[n] = entity
    self.values[n] = v
end

-- set an entity and value
-- changes value if entity is already in pool
-- adds entity and value if not in pool
local function pool_set<T>(self: Pool<T>, entity: EntityId, v: T)
    local k = id_getKey(entity)
    local i = self.map[k]
    if i then
        self.values[i] = v
    else
        local n = self.size + 1; self.size = n
        self.map[k] = n
        self.entities[n] = entity
        self.values[n] = v
    end
end

-- removes an entity and value
-- does nothing if entity is not in pool
-- order is not preserved (swap and pop)
local function pool_remove<T>(self: Pool<T>, entity: EntityId)
    local map = self.map
    local k = id_getKey(entity)
    local i = map[k] :: number
    if not i then return end

    local entities = self.entities
    local values = self.values
    local n = self.size

    local lastEntity = entities[n]
    entities[i] = lastEntity; entities[n] = nil
    map[id_getKey(lastEntity)] = i; map[k] = nil
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

local function hasNone(entity: EntityId, pools: vector<Pool<unknown>>): boolean
    local key = id_getKey(entity)
    for _, pool in next, pools do
        if pool_has(pool, key) then return false end
    end
    return true
end

local function hasAll(entity: EntityId, pools: vector<Pool<unknown>>): boolean
    local key = id_getKey(entity)
    for _, pool in next, pools do
        if not pool_hasKey(pool, key) then return false end
    end
    return true
end

local View = {} do
    type _View = View<...unknown> & {
        registry: Registry,
        components: map<ComponentId, boolean>,
        targets: vector<Pool<unknown>>, -- components to return
        includes: vector<Pool<unknown>>?,
        excludes: vector<Pool<unknown>>?
    }

    View.__index = View

    function View.new(reg: Registry, ...: ComponentId): View<...unknown>
        local argn = select("#", ...)
    
        local components, targets = {}, {}

        for i = 1, argn do
            local component = select(i, ...)
            if components[component] then error("duplicate component included", 3) end
            components[component] = true
            targets[i] = reg:storage(component)
        end

        return setmetatable({
            registry = reg,
            components = components,
            targets = targets,
            includes = nil,
            excludes = nil
        }, View) :: any
    end

    -- sorts through targets and optional includes and returns the smallest pool
    local function getSmallestPool(targets: vector<Pool<unknown>>, includes: vector<Pool<unknown>>?): Pool<unknown>
        local smallest = targets[1]

        if smallest == nil then error("no pools given", 2) end

        local function check(pool)
            if pool_size(pool) < pool_size(smallest) then
                smallest = pool
            end
        end

        for _, pool in next, targets, 1 do check(pool) end
        if includes then
            for _, pool in next, includes do check(pool) end
        end

        return smallest
    end

    local function iter(self: _View): () -> (EntityId, ...unknown)
        local targets = self.targets
        local includes = self.includes
        local excludes = self.excludes

        local spool = getSmallestPool(targets, includes)
        local entities = spool.entities
        local values = spool.values
    
        local tuple = table.create(#targets)

        local iu = pool_size(spool)
        return if #targets == 1 and not includes and not excludes then -- pure single view
                function()
                    local i = iu; iu = i - 1
                    return entities[i], values[i]
                end
            else function() -- general view
                local i = iu
                while i > 0 do
                    local entity = entities[i]
                    if excludes and not hasNone(entity, excludes) or includes and not hasAll(entity, includes) then i -= 1; continue end

                    local key = id_getKey(entity)
                    local missing = false
                    for ii, target in next, targets do
                        local value = pool_getKey(target, key)
                        if value == nil then missing = true; break end
                        tuple[ii] = value
                    end
                    if missing then i -= 1; continue end

                    iu = i - 1
                    return entity, unpack(tuple)
                end
                return nil :: any
            end
    end

    function View.include(self: _View, ...: unknown): _View
        if not self.includes then self.includes = {} end
        local includes = assert(self.includes)

        local components = self.components

        for i = 1, select("#", ...) do
            local component = select(i, ...)
            if components[component] == true then error("duplicate component included", 2) end
            if components[component] == false then error("cannot include an already excluded component", 2) end
            components[component] = true
            table.insert(includes, self.registry:storage(component))
        end

        return self
    end

    function View.exclude(self: _View, ...: unknown): _View
        if not self.excludes then self.excludes = {} end
        local excludes = assert(self.excludes)

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
        return pool_size((getSmallestPool(self.targets, self.includes)))
    end
end

----------------------------------------------------------------------
-- Observer
----------------------------------------------------------------------

local Observer = {} do
    type _Observer = Observer<...unknown> & {
        registry: Registry,
        components: map<ComponentId, boolean>,
        targets: vector<Pool<unknown>>,
        includes: vector<Pool<unknown>>?,
        excludes: vector<Pool<unknown>>?,

        tracking: ComponentId,
        changed: Pool<unknown>,
        listeners: vector<(Registry, EntityId, unknown) -> ()>?,
    }

    Observer.__index = Observer

    function Observer.new(reg: Registry, toTrack: ComponentId , ...: ComponentId)
        local argn = select("#", ...)

        local components, targets = {}, {}
        local changed = pool_clone(reg:storage(toTrack))

        for i = 1, argn do
            local component = select(i, ...)
            if components[component] then error("duplicate component included", 3) end
            components[component] = true
            targets[i] = reg:storage(component)
        end

        local self: _Observer = setmetatable({
            registry = reg,
            components = components,
            targets = targets,
            includes = nil,
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
        local targets = self.targets
        local includes = self.includes
        local excludes = self.excludes

        local entities = changed.entities
        local values = changed.values

        local tuple = table.create(#targets + 1)

        local iu = pool_size(changed)
        return function() -- multi view
            local i = iu
            while i > 0 do
                local entity = entities[i]
                if excludes and not hasNone(entity, excludes) or includes and not hasAll(entity, includes) then i -= 1; continue end

                local key = id_getKey(entity)
                tuple[1] = values[i]
                local missing = false
                for ii, target in next, targets do
                    local v = pool_getKey(target, key)
                    if v == nil then missing = true; break end
                    tuple[ii + 1] = v
                end
                if missing then i -= 1; continue end

                iu = i - 1
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
        local targets = self.targets
        local includes = self.includes
        local excludes = self.excludes

        function listener(_, entity, value)
            if includes and not hasAll(entity, includes) then return end
            if excludes and not hasNone(entity, excludes) then return end
            if not hasAll(entity, targets) then return end
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

    function Observer.include(self: _Observer, ...: unknown): _Observer
        if not self.includes then self.includes = {} end
        local includes = assert(self.includes)

        local components = self.components

        for i = 1, select("#", ...) do
            local component = select(i, ...)
            if components[component] == true then error("duplicate component included", 2) end
            if components[component] == false then error("cannot include an already excluded component", 2) end
            components[component] = true
            table.insert(includes, self.registry:storage(component))
        end

        return self
    end

    function Observer.exclude(self: _Observer, ...: ComponentId): _Observer
        if not self.excludes then self.excludes = {} end
        local excludes = assert(self.excludes)

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
    local capacity = count or 1

    local registry = {}

    local size: number = 0
    local freeKey: number = INVALID
    local ids = table.create(capacity)

    local cpools: map<ComponentId, Pool<unknown>> = table.create(componentN)

    local fireAddedEvent: map<ComponentId, (Registry, EntityId, unknown) -> ()> = table.create(componentN)
    local fireChangedEvent: map<ComponentId, (Registry, EntityId, unknown) -> ()> = table.create(componentN)
    local fireRemovingEvent: map<ComponentId, (Registry, EntityId, unknown) -> ()> = table.create(componentN)
    local addedEvent: map<ComponentId, Signal<Registry, EntityId, unknown>> = table.create(componentN)
    local changedEvent: map<ComponentId, Signal<Registry, EntityId, unknown>> = table.create(componentN)
    local removingEvent: map<ComponentId, Signal<Registry, EntityId, unknown>> = table.create(componentN)

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
        freeKey = 1
        for i = 1, capacity - 1 do
            ids[i] = id_encode(i + 1, INITIAL_VERSION)
        end
        ids[capacity] = id_encode(INVALID, INITIAL_VERSION)
    end

    local function releaseAllEntities()
        freeKey = 1
        local n = #ids
        for i = 1, n - 1 do
            local ver = id_getVersion(ids[i])
            ids[i] = id_encode(i + 1, ver + 1)
        end
        ids[n] = id_encode(INVALID, id_getVersion(ids[n]) + 1)
    end

    local function clearPool(component: ComponentId)
        local pool = cpools[component]

        for _, entity in next, pool.entities do
            fireEvent(fireRemovingEvent, component, registry :: any, entity, nil)
        end
        
        pool_clear(pool)
    end

    setmetatable(cpools, {
        __index = function(self, component: ComponentId): Pool<unknown>
            if type(component) ~= "number" or math.sign(component) ~= 1 then
                error("Invalid component, component must be positive integer, got "..tostring(component), 2)
            end
            local pool = pool_create(capacity)
            self[component] = pool
            return pool
        end
    })

    initIds()

    function registry:create(): EntityId
        local n = size + 1
        if n > id_MASK_KEY then error("cannot create entity; registry is at max entity count ("..id_MASK_KEY..")", 2) end

        if freeKey ~= INVALID then
            local id = id_setKey(ids[freeKey], freeKey)
            local oldFreeKey = freeKey
            freeKey = id_getKey(ids[freeKey])
            ids[oldFreeKey] = id
            size = n
            return id
        else
            local newId = id_encode(n, INITIAL_VERSION)
            table.insert(ids, newId)
            size = n
            return newId
        end
    end

    local function release(entity: EntityId)
        local key, ver = id_decode(entity)
        ids[key] = id_encode(freeKey, ver < id_MAX_VERSION and ver + 1 or 1)
        freeKey = key
        size -= 1
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
        return ids[id_getKey(entity)] == entity
    end

    function registry:version(entity: EntityId): number
        return id_getVersion(entity)
    end

    function registry:current(entity: EntityId): number
        return id_getVersion(ids[id_getKey(entity)])
    end

    function registry:orphan(entity: EntityId): boolean
        for _, pool in next, cpools do
            if pool_has(pool, entity) then return false end
        end
        return true
    end

    function registry:set(entity: EntityId, component: ComponentId, value: unknown)
        local pool = cpools[component]
        local key = id_getKey(entity)
        local index = pool_mapKey(pool, key)
        
        if value ~= nil then
            if index then
                pool_replaceIndex(pool, index, value)   
                fireEvent(fireChangedEvent, component, self, entity, value)
            else
                pool_addKey(pool, key, entity, value)
                fireEvent(fireAddedEvent, component, self, entity, value)
            end
        elseif index then
            fireEvent(fireRemovingEvent, component, self, entity, nil)
            pool_eraseKeyAtIndex(pool, key, index)
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
        local key = id_getKey(entity)
        for i = 1, select("#", ...) do
            local component = select(i, ...)
            local pool = cpools[component]
            local index = pool_mapKey(pool, key) :: number
            if not index then return end
            fireEvent(fireRemovingEvent, component, self, entity, nil)
            pool_eraseKeyAtIndex(pool, key, index)
        end
    end

    function registry:size(): number
        return size
    end

    function registry:capacity(): number
        return capacity
    end

    function registry:clear(...: ComponentId)
        local argn = select("#", ...)
        if argn > 0 then
            for i = 1, argn do
                clearPool(select(i, ...))
            end
        else
            for component in next, cpools do clearPool(component) end
            releaseAllEntities()
        end 
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
        return ids
    end

    function registry:storage(component: ComponentId): Pool<unknown>
        return cpools[component]
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

    -- internal test method
    function registry:setEntityVersion(key: number, ver: number)
        ids[key] = id_encode(key, ver)
    end

    setmetatable(registry, { __index = function(_, index)
        error(tostring(index).." is not a valid member of Registry", 2)    
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
    },
    encode = id_encode
}
