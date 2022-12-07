----------------------------------------------------------------------
-- ecr.luau
-- v0.1.0
----------------------------------------------------------------------

local INVALID = 0
local INITIAL_VERSION = 1
local MAX_ENTITIES = 0x000FFFFF -- must be a ^2 - 1

assert(bit32.band(MAX_ENTITIES, 0xFFFF_FFFF) == MAX_ENTITIES, "max entities must be one less than power of 2")

type vector<T> = { [number]: T }
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
    change: <T>(Registry, entity: Entity, component: T, value: T) -> (),
    patch: <T>(Registry, entity: Entity, component: T, patcher: (oldValue: T) -> T?) -> (),
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
    connect: ( Signal<T...>, (T...) -> () ) -> Connection,
}

export type Connection = {
    disconnect: (Connection) -> ()
}

----------------------------------------------------------------------
-- Entity Id
----------------------------------------------------------------------

--[[
 - entity id implementation
 -     53 bits total
 -     upper 33 bits represents version (8,589,934,591)
 -     lower 20 bits represents key (1,048,575)
 -
 - luau numbers are 64-bit floats so bitshifting is done through multiplication by power of 2
 -
 - the key is used as an array index for pools
 - the version is used to keep the actual identifier unique.
]]

local id_MASK_KEY = MAX_ENTITIES
local id_MASK_VERSION = 2^53-1 - id_MASK_KEY

local id_LSHIFT = id_MASK_KEY + 1
local id_RSHIFT = 1/id_LSHIFT

local id_MAX_KEY = id_MASK_KEY
local id_MAX_VERSION = id_MASK_VERSION * id_RSHIFT

-- encodes the given key and version into a single identifier
local function id_encode(key: number, ver: number): number
    --assert(key <= id_MAX_KEY)
    --assert(ver <= id_MAX_VERSION)
    return ver * id_LSHIFT + key
end

-- gets key and version from identifier
local function id_decode(id: number): (number, number) -- key, ver
    local lower = bit32.band(id, id_MASK_KEY)
    local upper = (id - lower) * id_RSHIFT
    return lower, upper
end

-- gets only key from identifier
local function id_key(id: number): number
    return bit32.band(id, id_MASK_KEY)
end

-- gets only version from identifier
local function id_version(id: number): number
    return (id - bit32.band(id, id_MASK_KEY)) * id_RSHIFT
end

-- returns an identifier with the same version but new key
local function id_rekey(id: number, key: number): (number, number) -- newid, oldkey
    local oldkey = bit32.band(id, id_MASK_KEY)
    return id - oldkey + key, oldkey
end

----------------------------------------------------------------------
-- Entity Pool
----------------------------------------------------------------------

--[[
 - specialized sparse-set implementation designated as "pool".
 - composed of 3 arrays:
 -     sparse array mapping entity key to an internal dense array index
 -     dense array containing entity ids
 -     dense array containing component values (ordered the same as above)
]]

type Pool<T> = {
    size: number,
    map: vector<number?>,
    entities: vector<number>,
    values: vector<T>
}

local function pool_create(size: number?): Pool<any>
    local n = size or 1
    return {
        size = 0,
        map = table.create(n),
        entities = table.create(n),
        values = table.create(n)
    }
end

-- gets internal index for key if exists
local function pool_has<T>(self: Pool<T>, k: number): number?
    return self.map[k]
end

-- gets value for key
local function pool_get<T>(self: Pool<T>, k: number): T?
    return self.values[self.map[k] :: number]
end

-- adds key, entity and value (undefined if key is already in pool)
local function pool_add<T>(self: Pool<T>, k: number, entity: EntityId, v: T)
    local n = self.size + 1; self.size = n
    self.map[k] = n
    self.entities[n] = entity
    self.values[n] = v     
end

-- adds key with given value if key is not in pool, else changes keys value
local function pool_set<T>(self: Pool<T>, k: number, entity: EntityId, v: T)
    local map = self.map
    local i = map[k]
    if i then
        self.values[i] = v
    else
        local n = self.size + 1; self.size = n
        map[k] = n
        self.entities[n] = entity
        self.values[n] = v   
    end 
end

-- change value for key (undefined if key is not in pool)
local function pool_change<T>(self: Pool<T>, k: number, v: T)
    self.values[self.map[k] :: number] = v
end

-- removes key from pool (does nothing if already not in pool)
local function pool_remove<T>(self: Pool<T>, k: number)
    local map = self.map
    local i = map[k] :: number
    if not i then return end

    local n = self.size; self.size = n - 1
    local entities = self.entities
    local values = self.values

    local last = entities[n]
    map[id_key(last)] = i; map[k] = nil
    entities[i] = last; entities[n] = nil
    values[i] = values[n]; values[n] = nil
end

-- gets size of pool
local function pool_size<T>(self: Pool<T>): number
    return self.size
end

-- empties pool and sets size to 0
local function pool_clear<T>(self: Pool<T>)
    self.size = 0
    table.clear(self.map)
    table.clear(self.entities)
    table.clear(self.values)
end

-- clones pool
local function pool_clone<T>(self: Pool<T>): Pool<T>
    return {
        size = self.size,
        map = table.clone(self.map),
        entities = table.clone(self.entities),
        values = table.clone(self.values)
    }
end

-- gets value at given index (undefined if index is outside of range)
local function pool_getIndex<T>(self: Pool<T>, i: number): T?
    return self.values[i]
end

-- replaces value at given index (undefined if index is outside of range)
local function pool_changeIndex<T>(self: Pool<T>, i: number, v: T)
    self.values[i] = v
end

-- removes value at given index (undefined if index is outside of range)
local function pool_eraseIndex<T>(self: Pool<T>, i: number, k: number)
    local n = self.size; self.size = n - 1
    local map = self.map
    local entities = self.entities
    local values = self.values

    local lastEntity = entities[n]
    map[id_key(lastEntity)] = i; map[k] = nil
    entities[i] = lastEntity; entities[n] = nil
    values[i] = values[n]; values[n] = nil
end

----------------------------------------------------------------------
-- Views
----------------------------------------------------------------------

local function hasNone(pools: vector<Pool<unknown>>, key: number): boolean
    for _, pool in next, pools do
        if pool_has(pool, key) then return false end
    end
    return true
end

local function hasAll(pools: vector<Pool<unknown>>, key: number): boolean
    for _, pool in next, pools do
        if not pool_has(pool, key) then return false end
    end
    return true
end

local View = {} do
    type _View = View<...unknown> & {
        registry: Registry,
        components: map<ComponentId, boolean>,
        targets: vector<Pool<unknown>>,
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
                    local key = id_key(entity)

                    if 
                        includes and not hasAll(includes, key) or
                        excludes and not hasNone(excludes, key)
                    then i -= 1; continue end

                    local missing = false
                    for ii, target in next, targets do
                        local index = pool_has(target, key) :: number
                        if index == nil then missing = true; break end
                        tuple[ii] = pool_getIndex(target, index)
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

    function View.__iter(self: _View): () -> (EntityId, ...unknown)
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
        connections: vector<Connection>?
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
            connections = nil
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
        return function() -- general view
            local i = iu
            while i > 0 do
                local entity = entities[i]
                local key = id_key(entity)

                if 
                    includes and not hasAll(includes, key) or
                    excludes and not hasNone(excludes, key)
                then i -= 1; continue end

                tuple[1] = values[i]
                local missing = false
                for ii, target in next, targets do
                    local index = pool_has(target, key) :: number
                    if index == nil then missing = true; break end
                    tuple[ii + 1] = pool_getIndex(target, index)
                end
                if missing then i -= 1; continue end

                iu = i - 1
                return entity, unpack(tuple)
            end
            return nil :: any
        end
    end

    function Observer.disconnect(self: _Observer)
        assert(self.connections, "observer already disconnected")
        for _, connection in next, self.connections do
            connection:disconnect()
        end
        self.connections = nil
    end

    function Observer.reconnect(self: _Observer)
        assert(not self.connections, "observer already connected")
        
        local listener: (reg: Registry, entity: EntityId, value: unknown) -> ()

        local changed = self.changed
        local targets = self.targets
        local includes = self.includes
        local excludes = self.excludes

        function listener(_, entity, value)
            local key = id_key(entity)
            if includes and not hasAll(includes, key) then return end
            if excludes and not hasNone(excludes, key) then return end
            if not hasAll(targets, key) then return end
            pool_set(changed, key, entity, value)
        end

        local reg = self.registry
        local toTrack = self.tracking

        self.connections = {
            reg:added(toTrack):connect(listener),
            reg:changed(toTrack):connect(listener),
            reg:removing(toTrack):connect(listener)
        }
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

local createSignal: <T...>() -> (Signal<T...>, (T...) -> ()) do
    type _Signal<T...> = {
        [(T...) -> ()]: true,
        pool: Pool<(T...) -> ()>,
        count: number
    }

    type _Connection = { signal: _Signal<>, id: number? }

    local Connection = {}
    Connection.__index = Connection

    function Connection.disconnect(self: _Connection)
        assert(self.id, "connection already disconnected")
        pool_remove(self.signal.pool, self.id)
        self.id = nil
    end

    local Signal = {}
    Signal.__index = Signal

    function Signal.connect<T...>(self: _Signal<T...>, listener: (T...) -> ())
        local n = self.count + 1; self.count = n
        pool_add(self.pool, n, n, listener)
        return setmetatable({ signal = self, id = n }, Connection)
    end

    function createSignal()
        local pool = pool_create()
        local signal = setmetatable({ pool = pool, count = 0 }, Signal)

        local listeners = pool.values
        local function fire(...: any)
            for i = pool_size(pool), 1, -1 do
                listeners[i](...)
            end
        end

        return signal, fire
    end
end

----------------------------------------------------------------------
-- Component
----------------------------------------------------------------------

local componentN = 0
local function createComponent(): unknown
    componentN += 1
    return componentN
end

----------------------------------------------------------------------
-- Registry
----------------------------------------------------------------------

local function createRegistry(cap: number?): Registry
    local capacity = cap or 1

    local registry = {} :: any

    local size = 0
    local freeKey = INVALID
    local ids = table.create(capacity) :: vector<EntityId>

    do -- initialize ids
        table.clear(ids)
        for i = 1, capacity - 1 do
            ids[i] = id_encode(i + 1, INITIAL_VERSION)
        end
        ids[capacity] = id_encode(INVALID, INITIAL_VERSION)
        freeKey = 1
    end

    local cpools: map<ComponentId, Pool<unknown>> = table.create(componentN)

    local added: map<ComponentId, (Registry, EntityId, unknown) -> ()> = table.create(componentN)
    local changed: map<ComponentId, (Registry, EntityId, unknown) -> ()> = table.create(componentN)
    local removing: map<ComponentId, (Registry, EntityId, unknown) -> ()> = table.create(componentN)
    local addedSignal: map<ComponentId, Signal<Registry, EntityId, unknown>> = table.create(componentN)
    local changedSignal: map<ComponentId, Signal<Registry, EntityId, unknown>> = table.create(componentN)
    local removingSignal: map<ComponentId, Signal<Registry, EntityId, unknown>> = table.create(componentN)

    local function releaseAllEntities()
        local n = #ids
        for i = 1, n - 1 do
            local ver = id_version(ids[i])
            ids[i] = id_encode(i + 1, ver + 1)
        end
        ids[n] = id_encode(INVALID, id_version(ids[n]) + 1)
        freeKey = 1
        size = 0
    end

    local function fireSignal<T>(
        signals: map<ComponentId, (Registry, EntityId, unknown) -> ()>,
        component: ComponentId,
        entity: EntityId,
        value: T
    )
        local fire = signals[component]
        if fire then fire(registry, entity, value) end
    end

    local function clearPool(component: ComponentId)
        local pool = cpools[component]

        for _, entity in next, pool.entities do
            fireSignal(removing, component, entity, nil)
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

    function registry:create(): EntityId
        local n = size + 1
        if n > id_MAX_KEY then error("cannot create entity; registry is at max entity count ("..id_MAX_KEY..")", 2) end

        local free = freeKey
        if free ~= INVALID then
            local newid, nextFree = id_rekey(ids[free], free)
            size = n
            freeKey = nextFree
            ids[free] = newid
            return newid
        else
            local newid = id_encode(n, INITIAL_VERSION)
            size = n
            ids[n] = newid
            return newid
        end
    end

    local function release(entity: EntityId)
        local key, ver = id_decode(entity)
        size -= 1
        ids[key] = id_encode(freeKey, ver < id_MAX_VERSION and ver + 1 or INITIAL_VERSION)
        freeKey = key
    end

    function registry:release(entity: EntityId)
        release(entity)
    end

    function registry:destroy(entity: EntityId)
        release(entity)
        local key = id_key(entity)
        for component, pool in next, cpools do
            fireSignal(removing, component, entity, nil)
            pool_remove(pool, key)
        end
    end

    function registry:valid(entity: EntityId): boolean
        return ids[id_key(entity)] == entity
    end

    function registry:version(entity: EntityId): number
        return id_version(entity)
    end

    function registry:current(entity: EntityId): number
        return id_version(ids[id_key(entity)])
    end

    function registry:orphan(entity: EntityId): boolean
        local key = id_key(entity)
        for _, pool in next, cpools do
            if pool_has(pool, key) then return false end
        end
        return true
    end

    function registry:set(entity: EntityId, component: ComponentId, value: unknown)
        local pool = cpools[component]
        local key = id_key(entity)
        local index = pool_has(pool, key)
        
        if value ~= nil then
            if index then
                pool_changeIndex(pool, index, value)
                fireSignal(changed, component, entity, value)
            else
                pool_add(pool, key, entity, value)
                fireSignal(added, component, entity, value)
            end
        elseif index then
            fireSignal(removing, component, entity, nil)
            pool_eraseIndex(pool, index, key)
        end
    end
    
    function registry:patch(entity: EntityId, component: ComponentId, patcher: (unknown) -> unknown)
        local pool = cpools[component]
        local key = id_key(entity)
        local index = pool_has(pool, key) :: number
        local values = pool.values

        local value = patcher(values[index])

        if value ~= nil then
            pool.values[index] = value
            fireSignal(changed, component, entity, value)
        else
            fireSignal(removing, component, entity, nil)
            pool_eraseIndex(pool, index, key)
        end
    end

    function registry:has(entity: EntityId, ...: ComponentId): boolean
        local a, b = ...
        local key = id_key(entity)
        if b == nil then
            return pool_has(cpools[a], key) ~= nil
        else
            for i = 1, select("#", ...) do
                if not pool_has(cpools[select(i, ...)], key) then return false end
            end
            return true
        end
    end

    function registry:get(entity: EntityId, ...: ComponentId): ...unknown
        local a, b, c, d, e = ...
        local key = id_key(entity)
        if b == nil then
            return pool_get(cpools[a], key)
        elseif c == nil then
            return pool_get(cpools[a], key), pool_get(cpools[b], key)
        elseif d == nil then
            return pool_get(cpools[a], key), pool_get(cpools[b], key), pool_get(cpools[c], key)
        elseif e == nil then
            return pool_get(cpools[a], key), pool_get(cpools[b], key), pool_get(cpools[c], key), pool_get(cpools[d], key)
        else
            local tuple: vector<any> = { ... }
            for i, v in next, tuple do
                tuple[i] = pool_get(cpools[v], key)
            end
            return unpack(tuple)
        end
    end

    function registry:remove(entity: EntityId, ...: ComponentId)
        local key = id_key(entity)
        for i = 1, select("#", ...) do
            local component = select(i, ...)
            local pool = cpools[component]
            local index = pool_has(pool, key) :: number
            if not index then continue end
            fireSignal(removing, component, entity, nil)
            pool_eraseIndex(pool, index, key)
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
        return View.new(registry, ...)
    end

    function registry:track(...: ComponentId): Observer<...unknown>
        return Observer.new(registry, ...)
    end

    function registry:entities(): vector<EntityId>
        return ids
    end

    function registry:storage(component: ComponentId): Pool<unknown>
        return cpools[component]
    end

    function registry:added(component: ComponentId): Signal<unknown>
        return addedSignal[component] or (function() 
            local signal, fire = createSignal()
            addedSignal[component] = signal
            added[component] = fire
            return signal      
        end)()
    end

    function registry:changed(component: ComponentId): Signal<unknown>
        return changedSignal[component] or (function() 
            local signal, fire = createSignal()
            changedSignal[component] = signal
            changed[component] = fire
            return signal      
        end)()       
    end

    function registry:removing(component: ComponentId): Signal<unknown>
        return removingSignal[component] or (function() 
            local signal, fire = createSignal()
            removingSignal[component] = signal
            removing[component] = fire
            return signal      
        end)()
    end

    -- internal test method
    function registry:setEntityVersion(key: number, ver: number)
        ids[key] = id_encode(id_key(ids[key]), ver)
    end

    setmetatable(registry, { __index = function(_, index)
        error(tostring(index) .. " is not a valid member of Registry", 2)    
    end })

    return table.freeze(registry)
end

----------------------------------------------------------------------
-- Return
----------------------------------------------------------------------

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
    signal = createSignal,
    encode = id_encode
}
