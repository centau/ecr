----------------------------------------------------------------------
-- ecr.luau
-- v0.3.0
----------------------------------------------------------------------

local INITIAL_VERSION = 1
local MAX_ENTITIES = 0x000F_FFFF

assert(bit32.band(MAX_ENTITIES + 1, MAX_ENTITIES) == 0 and MAX_ENTITIES > 0, "max entities must be one less than a power of 2")

type Array<T> = { [number]: T }
type Map<T, U> = { [T]: U }

type Component = unknown
export type Entity = number

export type Registry = {
    create: (Registry, Id: Entity?) -> Entity,
    release: (Registry, entity: Entity) -> (),
    destroy: (Registry, entity: Entity) -> (),

    valid: (Registry, entity: Entity) -> boolean,
    version: (Registry, entity: Entity) -> number,
    current: (Registry, entity: Entity) -> number,

    orphan: (Registry, entity: Entity) -> boolean,
    add: <T...>(Registry, entity: Entity, T...) -> (),
    set: <T>(Registry, entity: Entity, component: T, value: T?) -> (),
    patch: <T>(Registry, entity: Entity, component: T, patcher: (current: T) -> T) -> (),
    has: <T...>(Registry, entity: Entity, T...) -> boolean,
    get: <T...>(Registry, entity: Entity, T...) -> T...,
    remove: <T...>(Registry, entity: Entity, T...) -> (),

    size: (Registry) -> number,
    clear: <T...>(Registry, T...) -> (),

    view: <T...>(Registry, T...) -> View<T...>,
    track: <T, U...>(Registry, track: T, U...) -> Observer<(T, U...)>,

    entities: (Registry) -> Array<Entity>,
    storage: <T>(Registry, component: T) -> Pool<T>,

    added: <T>(Registry, component: T) -> Signal<Entity, T>,
    changed: <T>(Registry, component: T) -> Signal<Entity, T>,
    removing: <T>(Registry, component: T) -> Signal<Entity, nil>,
}

export type View<T...> = typeof(setmetatable(
    {} :: {
        each: (View<T...>) -> () -> (Entity, T...),
        exclude: <U...>(View<T...>, U...) -> View<T...>,
    }, {} :: {
        __iter: (View<T...>) -> () -> (Entity, T...),
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

type Listener = (Entity, unknown) -> ()

export type Connection = {
    disconnect: (Connection) -> ()
}

-- assert but stack trace will always start at the callsite of library functions outside of this file
local lassert = function<T>(v: T, msg: string): T
    if v then return v end

    local stack = 1

    while debug.info(stack, "s") == debug.info(1, "s") do
        stack += 1    
    end

    error(msg, stack)
end :: typeof(assert)

----------------------------------------------------------------------
-- Entity Id
----------------------------------------------------------------------

--[[
 - entity id implementation
 -     53 bits total - IEEE 754
 -     upper 33 bits represents version (8,589,934,591)
 -     lower 20 bits represents key (1,048,575)
 -
 - luau numbers are 64-bit floats so bitshifting is done through multiplication by power of 2
 -
 - the key is used as an array index for pools
 - the version is used to keep the overall identifier unique when a key is reused.
]]

local id_INVALID = 0
local id_MASK_KEY = MAX_ENTITIES
local id_MASK_VERSION = 2^53-1 - id_MASK_KEY

assert(id_MASK_VERSION > 0)

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

-- returns an identifier with the same version but different key
local function id_rekey(id: number, key: number): (number, number) -- newid, oldkey
    local oldkey = bit32.band(id, id_MASK_KEY)
    return id - oldkey + key, oldkey
end

local id_NULL = id_encode(1, 0)

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
    map: Array<number?>,
    entities: Array<number>,
    values: Array<T>
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
local function pool_add<T>(self: Pool<T>, k: number, entity: Entity, v: T)
    local n = self.size + 1; self.size = n
    self.map[k] = n
    self.entities[n] = entity
    self.values[n] = v     
end

-- adds entity with given value if key is not in pool, else changes entities value
local function pool_set<T>(self: Pool<T>, k: number, entity: Entity, v: T)
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

local function pool_size<T>(self: Pool<T>): number
    return self.size
end

local function pool_entities<T>(self: Pool<T>): Array<Entity>
    return self.entities
end

local function pool_values<T>(self: Pool<T>): Array<T>
    return self.values
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

local View, Observer do
    type _View =  {
        registry: Registry,
        components: Map<Component, boolean>,
        includes: Array<Pool<unknown>>,
        excludes: Array<Pool<unknown>>?
    }

    type _Observer = _View & Observer<...unknown> & {
        tracking: Component,
        changed: Pool<unknown>,
        connections: Array<Connection>?   
    }

    local function hasNone(pools: Array<Pool<unknown>>, key: number): boolean
        for _, pool in next, pools do
            if pool_has(pool, key) then return false end
        end
        return true
    end

    local function getSmallestPool(pools: Array<Pool<unknown>>): Pool<unknown>
        local smallest: Pool<unknown>?

        for _, pool in next, pools do
            if not smallest or pool_size(pool) < pool_size(smallest) then
                smallest = pool
            end
        end

        assert(smallest, "no pools given")

        return smallest
    end

    local function exclude(self: _View, ...: Component): _View
        if not self.excludes then self.excludes = {} end
        local excludes = assert(self.excludes)

        local components = self.components

        for i = 1, select("#", ...) do
            local component = select(i, ...)
            lassert(components[component] ~= false, "duplicate component excluded")
            lassert(components[component] ~= true, "cannot exclude an already included component")
            components[component] = false
            table.insert(excludes, self.registry:storage(component))
        end

        return self
    end

    View = {}
    View.__index = View

    function View.new<T...>(reg: Registry, ...: T...): View<T...>
        local argn = select("#", ...)
    
        local components, includes = {}, {}

        for i = 1, argn do
            local component = select(i, ...)
            lassert(not components[component], "duplicate component included")
            components[component] = true
            includes[i] = reg:storage(component)
        end

        return setmetatable({
            registry = reg,
            components = components,
            includes = includes,
            excludes = nil
        } :: _View, View) :: any
    end

    function View.__iter(self: _View): () -> (Entity, ...unknown)
        local includes = self.includes
        local excludes = self.excludes

        local function single<A>(source: Pool<A>): () -> (Entity, A)
            local n = pool_size(source)
            local entities = pool_entities(source)
            local values = pool_values(source)
    
            return function()
                local i = n; n = i - 1
                return entities[i], values[i]
            end
        end
    
        local function double<A, B>(a: Pool<A>, b: Pool<B>): () -> (Entity, A, B)
            local na, nb = pool_size(a), pool_size(b)
    
            if na <= nb then
                local n = na
                local entities = pool_entities(a)
                local values = pool_values(a)
    
                return function()
                    local i = n
                    while i > 0 do
                        local entity = entities[i]
                        local vb = pool_get(b, id_key(entity)) :: B
                        if vb == nil then i -= 1; continue end
                        n = i - 1
                        return entity, values[i], vb
                    end
                    return nil :: any, nil :: any, nil :: any
                end
            else
                local n = nb
                local entities = pool_entities(b)
                local values = pool_values(b)
    
                return function()
                    local i = n
                    while i > 0 do
                        local entity = entities[i]
                        local va = pool_get(a, id_key(entity)) :: A
                        if va == nil then i -= 1; continue end
                        n = i - 1
                        return entity, va, values[i]
                    end
                    return nil :: any, nil :: any, nil :: any
                end
            end
        end
    
        local function multi(includes: Array<Pool<unknown>>, excludes: Array<Pool<unknown>>?)
            local source = getSmallestPool(includes)
    
            local n = pool_size(source)
            local entities = pool_entities(source)
            local tuple = table.create(#includes)
    
            return function()
                local i = n
                while i > 0 do
                    local entity = entities[i]
                    local key = id_key(entity)
                    
                    if excludes and not hasNone(excludes, key) then i -= 1; continue end
    
                    local missing = false
                    for ii, pool in next, includes do
                        local index = pool_has(pool, key) :: number
                        if index == nil then missing = true; break end
                        tuple[ii] = pool.values[index]
                    end
                    if missing then i -= 1; continue end
    
                    n = i - 1
                    return entity, unpack(tuple)
                end
                return nil :: any
            end
        end

        return if #includes == 1 and not excludes then
                single(includes[1])
            elseif #includes == 2  and not excludes then 
                double(includes[1], includes[2])
            else
                multi(includes, excludes)
    end

    function View.__len(self: _View): number
        return pool_size(getSmallestPool(self.includes))
    end

    View.each = View.__iter
    View.exclude = exclude

    Observer = {}
    Observer.__index = Observer

    function Observer.new<T, U...>(reg: Registry, track: T, ...: U...): Observer<(T, U...)>
        local self: _Observer = View.new(reg, track, ...) :: any
        setmetatable(self, Observer)

        self.tracking = track
        self.changed = pool_clone(reg:storage(track))

        self:reconnect()

        return self :: any
    end

    function Observer.__iter(self: _Observer): () -> (Entity, ...unknown)
        local changed = self.changed
        local includes = self.includes
        local excludes = self.excludes

        local entities = changed.entities
        local values = changed.values

        local tuple = table.create(#includes)

        local n = pool_size(changed)
        return if #includes == 0 and not excludes then function()
                local i = n; n = i - 1
                return entities[i], values[i]
            end else function()
                local i = n
                while i > 0 do
                    local entity = entities[i]
                    local key = id_key(entity)

                    if excludes and not hasNone(excludes, key) then i -= 1; continue end

                    local missing = false
                    for ii, pool in next, includes do
                        local index = pool_has(pool, key) :: number
                        if index == nil then missing = true; break end
                        tuple[ii] = pool.values[index]
                    end
                    if missing then i -= 1; continue end

                    n = i - 1
                    return entity, values[i], unpack(tuple)
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

        local changed = self.changed

        local reg = self.registry
        local toTrack = self.tracking

        self.connections = {
            reg:added(toTrack):connect(function(entity, value)
                pool_set(changed, id_key(entity), entity, value)
            end),

            reg:changed(toTrack):connect(function(entity, value)
                pool_set(changed, id_key(entity), entity, value)
            end),

            reg:removing(toTrack):connect(function(entity)
                pool_remove(changed, id_key(entity))  
            end)
        }
    end

    function Observer.clear(self: _Observer)
        pool_clear(self.changed)
    end

    function Observer.__len(self: _Observer): number
        return pool_size(self.changed)
    end

    Observer.each = Observer.__iter
    Observer.exclude = exclude
end

----------------------------------------------------------------------
-- Signal
----------------------------------------------------------------------

local createSignal: () -> (Signal<...any>, Array<(...any) -> ()>) do
    type _Signal<T...> = {
        [(T...) -> ()]: true,
        pool: Pool<(T...) -> ()>,
        count: number
    }

    type _Connection = { signal: _Signal<...unknown>, id: number? }

    local Connection = {}
    Connection.__index = Connection

    function Connection.disconnect(self: _Connection)
        lassert(self.id, "connection already disconnected")
        pool_remove(self.signal.pool, self.id)
        self.id = nil
    end

    local Signal = {}
    Signal.__index = Signal

    function Signal.connect<T...>(self: _Signal<T...>, listener: (T...) -> ()): Connection
        local n = self.count + 1; self.count = n
        pool_add(self.pool, n, n, listener)
        return setmetatable({ signal = self, id = n }, Connection) :: any
    end

    function createSignal()
        local pool = pool_create(1)
        local signal: Signal<...unknown> = setmetatable({ pool = pool, count = 0 } :: _Signal<...any>, Signal) :: any
        return signal, pool.values
    end
end

----------------------------------------------------------------------
-- Component
----------------------------------------------------------------------

local componentN = 0
local componentDefaults: Map<Component, ((() -> unknown)?)> = {}

local createComponent = function(default: (() -> unknown)?): unknown
    componentN += 1
    componentDefaults[componentN] = default
    return componentN
end :: (<T>(default: () -> T) -> T) & (() -> unknown)

----------------------------------------------------------------------
-- Registry
----------------------------------------------------------------------

local function createRegistry(): Registry
    local registry = {} :: Registry

    local size = 0
    local freeKey = id_INVALID
    local ids = table.create(1) :: Array<Entity>

    local cpools: Map<Component, Pool<unknown>> = table.create(componentN)

    local addedListeners: Map<Component, Array<Listener>?> = table.create(componentN)
    local changedListeners: Map<Component, Array<Listener>?> = table.create(componentN)
    local removingListeners: Map<Component, Array<Listener>?> = table.create(componentN)
    local addedSignal: Map<Component, Signal<Entity, unknown>> = table.create(componentN)
    local changedSignal: Map<Component, Signal<Entity, unknown>> = table.create(componentN)
    local removingSignal: Map<Component, Signal<Entity, unknown>> = table.create(componentN)

    local function fireAdded<T>(component: Component, entity: Entity, value: T)
        local listeners = addedListeners[component]
        if listeners then
            for i = #listeners, 1, -1 do
                listeners[i](entity, value)         
            end
        end
    end

    local function fireChanged<T>(component: Component, entity: Entity, value: T)
        local listeners = changedListeners[component]
        if listeners then
            for i = #listeners, 1, -1 do
                listeners[i](entity, value)         
            end
        end
    end

    local function fireRemoving(component: Component, entity: Entity)
        local listeners = removingListeners[component]
        if listeners then
            for i = #listeners, 1, -1 do
                listeners[i](entity)
            end
        end
    end

    local function releaseAllEntities()
        local n = #ids
        for i = 1, n - 1 do
            local ver = id_version(ids[i])
            ids[i] = id_encode(i + 1, ver + 1)
        end
        ids[n] = id_encode(id_INVALID, id_version(ids[n]) + 1)
        freeKey = 1
        size = 0
    end

    local function clearPool(component: Component)
        local pool = cpools[component]

        local listeners = removingListeners[component]

        if listeners then
            for _, entity in next, pool.entities do
                for i = #listeners, 1, -1 do
                    listeners[i](entity)
                end
            end    
        end
        
        pool_clear(pool)
    end

    setmetatable(cpools, {
        __index = function(self, v: unknown): Pool<unknown>
            lassert(type(v) == "number", "invalid component type")
            local pool = pool_create(1)
            self[v] = pool
            return pool
        end
    })

    local function create(ids: Array<Entity>, free: number, size: number): Entity
        if free ~= id_INVALID then
            local newid, nextFree = id_rekey(ids[free], free)
            freeKey = nextFree
            ids[free] = newid
            return newid
        else
            local newid = id_encode(size, INITIAL_VERSION)
            ids[size] = newid
            return newid
        end  
    end

    local function createWith(id: Entity, ids: Array<Entity>, free: number, size: number): Entity
        local key, version = id_decode(id)

        if key < 1 or version < 1 then error("attempted to use malformed id", 2) end

        local n = #ids

        if key > n + 1 then -- if ids have not been created yet
            for i = n+1, key-2 do
                ids[i] = id_encode(i + 1, INITIAL_VERSION)
            end
            ids[key-1] = id_encode(free, INITIAL_VERSION)
            freeKey = n+1
        elseif key <= n then -- if id has been created before
            lassert(free ~= id_INVALID and id_key(ids[key]) ~= key, "could not create entity with the given identifier")   

            if free == key then -- if desired id is at head
                local nextFree = id_key(ids[free])
                freeKey = nextFree
            else -- desired id is somewhere along list
                local previous = free
                while true do -- find element before desired id
                    local next = id_key(ids[previous])
                    if next == key then break end
                    previous = next
                end

                ids[previous] = id_rekey(ids[previous], id_key(ids[key]))
            end
        end

        ids[key] = id -- set desired id

        return id
    end

    function registry:create(entity: Entity?): Entity
        local n = size + 1
        if n > id_MAX_KEY then error("cannot create entity; registry is at max entity count ("..id_MAX_KEY..")", 2) end
        size = n

        local free = freeKey

        if entity == nil then
            return create(ids, free, n)
        else
            return createWith(entity, ids, free, n)
        end
    end

    local function release(entity: Entity)
        local key, ver = id_decode(entity)
        size -= 1
        ids[key] = id_encode(freeKey, ver < id_MAX_VERSION and ver + 1 or INITIAL_VERSION)
        freeKey = key
    end

    function registry:release(entity: Entity)
        release(entity)
    end

    function registry:destroy(entity: Entity)
        release(entity)
        local key = id_key(entity)
        for component, pool in next, cpools do
            fireRemoving(component, entity)
            pool_remove(pool, key)
        end
    end

    function registry:valid(entity: Entity): boolean
        return ids[id_key(entity)] == entity
    end

    function registry:version(entity: Entity): number
        return id_version(entity)
    end

    function registry:current(entity: Entity): number
        return id_version(ids[id_key(entity)])
    end

    function registry:orphan(entity: Entity): boolean
        local key = id_key(entity)
        for _, pool in next, cpools do
            if pool_has(pool, key) then return false end
        end
        return true
    end

    function registry:add<T...>(entity: Entity, ...: T...)
        local key = id_key(entity)
        for i = 1, select("#", ...) do
            local component = select(i, ...)
            local pool = cpools[component]
            local index = pool_has(pool, key) :: number
            if index then error("entity already has component", 2) end
            local default = componentDefaults[component] or error("no default value given", 2)
            local value = default()
            if value == nil then error("default value cannot be nil", 2) end
            pool_add(pool, key, entity, value)
        end
    end

    function registry:set<T>(entity: Entity, component: T, value: T?)
        local pool = cpools[component] :: Pool<T>
        local key = id_key(entity)
        local index = pool_has(pool, key)
        
        if value ~= nil then
            if index then
                pool.values[index] = value
                fireChanged(component, entity, value)
            else
                pool_add(pool, key, entity, value)
                fireAdded(component, entity, value)
            end
        elseif index then
            fireRemoving(component, entity)
            pool_eraseIndex(pool, index, key)
        end
    end
    
    function registry:patch<T>(entity: Entity, component: T, patcher: (T) -> T?)
        local pool = cpools[component] :: Pool<T>
        local key = id_key(entity)
        local index = pool_has(pool, key) :: number
        if index == nil then error("entity does not own the given component", 2) end

        local values = pool.values
        local value = patcher(values[index])

        if value == nil then error("error while patching, cannot set new value as nil", 2) end

        pool.values[index] = value :: T
        fireChanged(component, entity, value)
    end

    registry.has = (function(self: Registry, entity: Entity, ...: unknown): boolean
        local a, b = ...
        local key = id_key(entity)
        if b == nil then
            return pool_has(cpools[a] :: Pool<unknown>, key) ~= nil
        else
            for i = 1, select("#", ...) do
                if pool_has(cpools[select(i, ...)], key) == nil then return false end
            end
            return true
        end  
    end :: any) :: <T...>(self: Registry, entity: Entity, T...) -> boolean

    registry.get = (function(self: Registry, entity: Entity, ...: unknown): ...unknown
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
            local tuple: Array<any> = { ... }
            for i, v in next, tuple do
                tuple[i] = pool_get(cpools[v], key)
            end
            return unpack(tuple)
        end
    end :: any) :: <T...>(self: Registry, entity: Entity, T...) -> T...

    function registry:remove<T...>(entity: Entity, ...: T...)
        local key = id_key(entity)
        for i = 1, select("#", ...) do
            local component = select(i, ...)
            local pool = cpools[component]
            local index = pool_has(pool, key) :: number
            if not index then continue end
            fireRemoving(component, entity)
            pool_eraseIndex(pool, index, key)
        end
    end

    function registry:size(): number
        return size
    end

    function registry:clear<T...>(...: T...)
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

    function registry:view<T...>(...: T...): View<T...>
        return View.new(registry, ...)
    end

    function registry:track<T, U...>(track: T, ...: U...): Observer<(T, U...)>
        return Observer.new(registry, track, ...)
    end

    function registry:entities(): Array<Entity>
        local entities = table.create(size)

        for i, id in next, ids do
            if id_key(id) == i then
                table.insert(entities, id)
            end
        end

        return entities
    end

    function registry:storage<T>(component: T): Pool<T>
        return cpools[component] :: Pool<T>
    end

    function registry:added<T>(component: T): Signal<Entity, T>
        return (addedSignal[component] or (function() 
            local signal, listeners = createSignal()
            addedSignal[component] = signal
            addedListeners[component] = listeners
            return signal
        end)()) :: Signal<Entity, T>
    end

    function registry:changed<T>(component: T): Signal<Entity, T>
        return (changedSignal[component] or (function() 
            local signal, listeners = createSignal()
            changedSignal[component] = signal
            changedListeners[component] = listeners
            return signal    
        end)()) :: Signal<Entity, T>    
    end

    function registry:removing<T>(component: T): Signal<Entity, nil>
        return (removingSignal[component] or (function() 
            local signal, listeners = createSignal()
            removingSignal[component] = signal
            removingListeners[component] = listeners
            return signal
        end)()) :: Signal<Entity, nil>
    end

    -- internal test method
    (registry :: any).setEntityVersion = function(_, key: number, ver: number)
        ids[key] = id_encode(id_key(ids[key]), ver)
    end

    setmetatable(registry :: any, { __index = function(_, index)
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
    encode = id_encode,
    null = id_NULL
}
