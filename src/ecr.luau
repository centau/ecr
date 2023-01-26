----------------------------------------------------------------------
-- ecr.luau
-- v0.4.0
----------------------------------------------------------------------

local INITIAL_VERSION = 1
local MAX_ENTITIES = 0x000F_FFFF

type Array<T> = { [number]: T }
type Map<T, U> = { [T]: U }

type CType = unknown
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
    set: <T>(Registry, entity: Entity, ctype: T, value: T?) -> (),
    patch: <T>(Registry, entity: Entity, ctype: T, patcher: (current: T) -> T) -> (),
    has: <T...>(Registry, entity: Entity, T...) -> boolean,
    get: <T...>(Registry, entity: Entity, T...) -> T...,
    remove: <T...>(Registry, entity: Entity, T...) -> (),

    size: (Registry) -> number,
    clear: <T...>(Registry, T...) -> (),

    view: <T...>(Registry, T...) -> View<T...>,
    track: <T, U...>(Registry, track: T, U...) -> Observer<(T, U...)>,
    group: <T...>(Registry, T...) -> Group<T...>,

    entities: (Registry) -> Array<Entity>,
    storage: <T>(Registry, ctype: T) -> Pool<T>,

    added: <T>(Registry, ctype: T) -> Signal<Entity, T>,
    changed: <T>(Registry, ctype: T) -> Signal<Entity, T>,
    removing: <T>(Registry, ctype: T) -> Signal<Entity, nil>,
}

export type View<T...> = typeof(setmetatable(
    {} :: {
        each: (View<T...>) -> () -> (Entity, T...),
        exclude: <U...>(View<T...>, U...) -> View<T...>,
        use: <U>(View<T...>, lead: U) -> View<T...>,
    }, {} :: {
        __iter: (View<T...>) -> () -> (Entity, T...),
        __len: (View<T...>) -> number
    }
))

export type Observer<T...> = typeof(setmetatable(
    {} :: {
        each: (Observer<T...>) -> () -> (Entity, T...),
        exclude: <U...>(Observer<T...>, U...) -> Observer<T...>,
        disconnect: (Observer<T...>) -> (),
        reconnect: (Observer<T...>) -> (),
        clear: (Observer<T...>) -> (),
    }, {} :: {
        __iter: (Observer<T...>) -> () -> (Entity, T...),
        __len: (Observer<T...>) -> number
    }
))

export type Group<T...> = typeof(setmetatable(
    {} :: {
        each: (Group<T...>) -> () -> (Entity, T...)
    }, {} :: {
        __iter: (Group<T...>) -> () -> (Entity, T...),
        __len: (Group<T...>) -> number     
    }
))

type GroupData = { size: number } & Array<Pool<unknown>>

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

local function toarg(i: number): string
    return `component (arg #{i})`
end

----------------------------------------------------------------------
-- Identifier
----------------------------------------------------------------------

assert(
    bit32.band(MAX_ENTITIES + 1, MAX_ENTITIES) == 0 and MAX_ENTITIES > 0,
    "max entities must be greater than 0 and one less than a power of 2"
)

local id_INVALID_KEY = 0
local id_MAX_INT = 2^53-1
local id_MASK_KEY = MAX_ENTITIES
local id_MASK_VERSION = id_MAX_INT - id_MASK_KEY

assert(id_MASK_VERSION > 0, "max entities too high")

local id_LSHIFT = id_MASK_KEY + 1
local id_RSHIFT = 1/id_LSHIFT

local id_MAX_KEY = id_MASK_KEY
local id_MAX_VERSION = id_MASK_VERSION * id_RSHIFT

local function id_encode(key: number, ver: number): number
    --assert(key <= id_MAX_KEY)
    --assert(ver <= id_MAX_VERSION)
    return ver * id_LSHIFT + key
end

local function id_decode(id: number): (number, number) -- key, ver
    local lower = bit32.band(id, id_MASK_KEY)
    local upper = (id - lower) * id_RSHIFT
    return lower, upper
end

local function id_key(id: number): number
    return bit32.band(id, id_MASK_KEY)
end

local function id_version(id: number): number
    return (id - bit32.band(id, id_MASK_KEY)) * id_RSHIFT
end

local function id_rekey(id: number, key: number): (number, number) -- newid, oldkey
    local oldkey = bit32.band(id, id_MASK_KEY)
    return id - oldkey + key, oldkey
end

local id_NULL = id_encode(1, 0)

----------------------------------------------------------------------
-- Pool
----------------------------------------------------------------------

--[[
 - specialized sparse-set implementation.
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

local function pool_find<T>(self: Pool<T>, k: number): number?
    return self.map[k]
end

local function pool_get<T>(self: Pool<T>, k: number): T?
    return self.values[self.map[k] :: number]
end

local function pool_add<T>(self: Pool<T>, k: number, id: Entity, v: T)
    local n = self.size + 1; self.size = n
    self.map[k] = n
    self.entities[n] = id
    self.values[n] = v     
end

local function pool_set<T>(self: Pool<T>, k: number, id: Entity, v: T)
    local map = self.map
    local i = map[k]
    if i then
        self.values[i] = v
    else
        local n = self.size + 1; self.size = n
        map[k] = n
        self.entities[n] = id
        self.values[n] = v   
    end 
end

local function pool_remove<T>(self: Pool<T>, k: number)
    local map = self.map
    local i = map[k]

    if i then
        local n = self.size; self.size = n - 1
        local entities = self.entities
        local values = self.values
    
        local lastid = entities[n]
        map[id_key(lastid)] = i; map[k] = nil
        entities[i] = lastid; entities[n] = nil
        values[i] = values[n]; values[n] = nil
    end
end

local function pool_erase<T>(self: Pool<T>, i: number, k: number)
    local n = self.size; self.size = n - 1
    local map = self.map
    local entities = self.entities
    local values = self.values

    local lastid = entities[n]
    map[id_key(lastid)] = i; map[k] = nil
    entities[i] = lastid; entities[n] = nil
    values[i] = values[n]; values[n] = nil
end

local function pool_swap<T>(self: Pool<T>, currenti: number, k: number, targeti: number)
    local map = self.map
    local entities = self.entities
    local values = self.values

    local idToSwap = entities[targeti]
    
    map[k] = targeti
    map[id_key(idToSwap)] = currenti
    entities[targeti], entities[currenti] = entities[currenti], idToSwap
    values[targeti], values[currenti] = values[currenti], values[targeti]
end

local function pool_clear<T>(self: Pool<T>)
    self.size = 0
    table.clear(self.map)
    table.clear(self.entities)
    table.clear(self.values)
end

local function pool_clone<T>(self: Pool<T>): Pool<T>
    return {
        size = self.size,
        map = table.clone(self.map),
        entities = table.clone(self.entities),
        values = table.clone(self.values)
    }
end

----------------------------------------------------------------------
-- Component Type
----------------------------------------------------------------------

local ctype_n = 0
local ctype_defaults: Map<CType, ((() -> unknown)?)> = {}

local function ctype_create<T>(default: ( () -> T )?): CType
    ctype_n += 1
    ctype_defaults[ctype_n] = default
    return ctype_n
end

local function ctype_valid(v: unknown): boolean
    return type(v) == "number" and math.floor(v) == v and v > 0 and v <= ctype_n  
end

----------------------------------------------------------------------
-- Views
----------------------------------------------------------------------

local View, Observer, Group do
    local WEAK_VALUES = { __mode = "v" }

    local function hasNone(pools: Array<Pool<unknown>>, key: number): boolean
        for _, pool in next, pools do
            if pool_find(pool, key) then return false end
        end
        return true
    end

    local function smallest(pools: Array<Pool<unknown>>): Pool<unknown>
        local s: Pool<unknown>?
        for _, pool in next, pools do
            s = if s == nil or pool.size < s.size then pool else s
        end
        return assert(s, "no pools given")
    end

    type BaseView = {
        registry: Registry,
        components: Map<CType, boolean>,
        includes: Array<Pool<unknown>>,
        excludes: Array<Pool<unknown>>?,
    }

    type _View = BaseView & {
        lead: Pool<unknown>?
    }

    local function include<T>(self: T & BaseView, ...: CType): T
        local includes = self.includes
        local components = self.components

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            lassert(ctype_valid(ctype), `invalid { toarg(i) }`)
            lassert(components[ctype] ~= true, `duplicate { toarg(i) } included`)
            lassert(components[ctype] ~= false, `cannot include { toarg(i) }, already excluded`)
            components[ctype] = true
            table.insert(includes, self.registry:storage(ctype))
        end

        return self
    end


    local function exclude<T>(self: T & BaseView, ...: CType): T
        local excludes = self.excludes or (function()
            local t = {} 
            self.excludes = t
            return t
        end)()

        local components = self.components

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            lassert(ctype_valid(ctype), `invalid { toarg(i) }`)
            lassert(components[ctype] ~= false, `duplicate { toarg(i) } excluded`)
            lassert(components[ctype] ~= true, `cannot exclude { toarg(i) }, already included`)
            components[ctype] = false
            table.insert(excludes, self.registry:storage(ctype))
        end

        return self
    end

    View = {}
    View.__index = View

    function View.new(reg: Registry, ...: CType): View<...unknown>
        lassert(select("#", ...) > 0, "no components given")

        local self: _View = setmetatable({
            registry = reg,
            components = {},
            includes = {}
        } :: _View, View) :: any

        include(self, ...)

        return self :: any
    end

    function View.use(self: _View, ctype: CType): _View
        lassert(ctype_valid(ctype), `invalid component type`)
        lassert(self.components[ctype], "cannot use component; component is not included in view")
        self.lead = self.registry:storage(ctype)
        return self
    end

    function View.__iter(self: _View): () -> (Entity, ...unknown)
        local function single<A>(pool: Pool<A>): () -> (Entity, A)
            local n = pool.size
            local entities = pool.entities
            local values = pool.values
    
            return function()
                local i = n; n = i - 1
                return entities[i], values[i]
            end
        end
    
        local function double<A, B>(a: Pool<A>, b: Pool<B>): () -> (Entity, A, B)
            local na, nb = a.size, b.size
    
            if na <= nb then
                local n = na
                local entities = a.entities
                local values = a.values
    
                return function()
                    for i = n, 1, -1 do
                        local entity = entities[i]
                        local vb = pool_get(b, id_key(entity))
                        if vb == nil then continue end
                        n = i - 1
                        return entity, values[i], vb :: B
                    end
                    return nil :: any, nil :: any, nil :: any
                end
            else
                local n = nb
                local entities = b.entities
                local values = b.values
    
                return function()
                    for i = n, 1, -1 do
                        local entity = entities[i]
                        local va = pool_get(a, id_key(entity))
                        if va == nil then continue end
                        n = i - 1
                        return entity, va :: A, values[i]   
                    end
                    return nil :: any, nil :: any, nil :: any
                end
            end
        end
    
        local function multi(
            includes: Array<Pool<unknown>>,
            excludes: Array<Pool<unknown>>?,
            lead: Pool<unknown>?
        ): () -> (Entity, ...unknown)
            local source = lead or smallest(includes)
    
            local n = source.size
            local entities = source.entities
            local tuple = table.create(#includes)
    
            return function()
                for i = n, 1, -1 do
                    local entity = entities[i]
                    local key = id_key(entity)
                    
                    if excludes and hasNone(excludes, key) == false then continue end
    
                    local hasAll = true
                    for ii, pool in next, includes do
                        local index = pool_find(pool, key)
                        if index == nil then hasAll = false; break end
                        tuple[ii] = pool.values[index :: number]
                    end
                    if hasAll == false then continue end
    
                    n = i - 1
                    return entity, unpack(tuple)
                end
                return nil :: any
            end
        end

        local includes = self.includes
        local excludes = self.excludes
        local lead = self.lead

        return if #includes == 1 and not excludes and not lead then
                single(includes[1])
            elseif #includes == 2  and not excludes and not lead then 
                double(includes[1], includes[2])
            else
                multi(includes, excludes, self.lead)
    end

    function View.__len(self: _View): number
        return smallest(self.includes).size
    end

    View.each = View.__iter
    View.exclude = exclude

    type _Observer = BaseView & {
        tracked: CType,
        connections: Array<Connection>?
    }

    Observer = {}
    Observer.__index = Observer

    function Observer.new(reg: Registry, tracked: CType, ...: CType): Observer<...unknown>
        local self: _Observer = View.new(reg, tracked, ...) :: any
        setmetatable(self, Observer)

        self.tracked = tracked
        local changed = pool_clone(reg:storage(tracked))
        self.includes[1] = changed
        
        local weakref = setmetatable({ self = self }, WEAK_VALUES)
        local onRemoving;
        onRemoving = reg:removing(tracked):connect(function(entity)
            -- disconnect self if observer is garbage collected
            if weakref.self == nil then onRemoving:disconnect() end
            pool_remove(changed, id_key(entity))  
        end)

        Observer.reconnect(self)

        return self :: any
    end

    function Observer.disconnect(self: _Observer)
        lassert(self.connections, "observer already disconnected")

        for _, connection in next, self.connections do
            connection:disconnect()
        end
        self.connections = nil
    end

    function Observer.reconnect(self: _Observer)
        lassert(not self.connections, "observer already connected")

        local reg = self.registry
        local changed = self.includes[1]
        local tracked = self.tracked
    
        self.connections = {
            reg:added(tracked):connect(function(entity, value)
                pool_set(changed, id_key(entity), entity, value)
            end),

            reg:changed(tracked):connect(function(entity, value)
                pool_set(changed, id_key(entity), entity, value)
            end)
        }
    end

    function Observer.clear(self: _Observer)
        pool_clear(self.includes[1])
    end

    function Observer.__iter(self: _Observer): () -> (Entity, ...unknown)
        local includes = self.includes
        local excludes = self.excludes

        local changed = includes[1]
        local n = changed.size
        local entities = changed.entities
        local values = changed.values

        local others = table.clone(includes)
        table.remove(others, 1)

        local tuple = table.create(#others)

        return if #includes == 1 and not excludes then function()
                local i = n; n = i - 1
                return entities[i], values[i]
            end else function()
                for i = n, 1, -1 do
                    local entity = entities[i]
                    local key = id_key(entity)

                    if excludes and hasNone(excludes, key) == false then continue end

                    local hasAll = true
                    for ii, pool in next, others do
                        local index = pool_find(pool, key)
                        if index == nil then hasAll = false; break end
                        tuple[ii] = pool.values[index :: number]
                    end
                    if hasAll == false then continue end

                    n = i - 1
                    return entity, values[i], unpack(tuple)
                end
                return nil :: any
            end
    end

    function Observer.__len(self: _Observer): number
        return smallest(self.includes).size
    end

    Observer.each = Observer.__iter
    Observer.exclude = exclude

    type _Group = BaseView & { data: GroupData }

    Group = {}
    Group.__index = Group

    function Group.new(reg: Registry, data: GroupData, ...: CType): Group<...unknown>
        local self: _Group = View.new(reg, ...) :: any
        setmetatable(self, Group)

        local includes = self.includes
        for _, pool in ipairs(data) do
            assert(table.find(includes, pool), "included pool is not in group")
        end

        self.data = data

        return self :: any
    end

    function Group.__iter(self: _Group): () -> (Entity, ...unknown)
        local includes = self.includes
        local n = self.data.size
        local entities = includes[1].entities

        local values: Array<Array<unknown>> = table.create(#includes)
        for i, pool in next, includes do
            values[i] = pool.values
        end

        if #includes == 1 then
            local a = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i]  
            end
        elseif #includes == 2 then
            local a, b = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i], b[i] 
            end
        elseif #includes == 3 then
            local a, b, c = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i], b[i], c[i]
            end
        elseif #includes == 4 then
            local a, b, c, d = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i], b[i], c[i], d[i]
            end
        else
            local tuple = table.create(#values)
            return function()
                local i = n; n = i - 1
                for ii, v in next, values do
                    tuple[ii] = v[i]
                end
                return entities[i], unpack(tuple)
            end
        end
    end

    function Group.__len(self: _Group): number
        return self.data.size
    end

    Group.each = Group.__iter
end

----------------------------------------------------------------------
-- Signal
----------------------------------------------------------------------

local signal_create: () -> (Signal<...any>, Array<(...any) -> ()>) do
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

    function signal_create()
        local pool = pool_create(1)
        local signal: Signal<...unknown> = setmetatable({ pool = pool, count = 0 } :: _Signal<...any>, Signal) :: any
        return signal, pool.values
    end
end

----------------------------------------------------------------------
-- Registry
----------------------------------------------------------------------

local function registry_create(): Registry
    local registry = {} :: Registry

    local size = 0
    local free = id_INVALID_KEY
    local ids = table.create(1) :: Array<Entity>

    local pools: Map<CType, Pool<unknown>> = table.create(ctype_n)
    local groups: Map<CType, GroupData?> = table.create(ctype_n)

    local signals = {
        added = {} :: Map<CType, Signal<Entity, unknown>>,
        changed = {} :: Map<CType, Signal<Entity, unknown>>,
        removing = {} :: Map<CType, Signal<Entity, nil>>
    }

    local addedListeners: Map<CType, Array<Listener>?> = table.create(ctype_n)
    local changedListeners: Map<CType, Array<Listener>?> = table.create(ctype_n)
    local removingListeners: Map<CType, Array<Listener>?> = table.create(ctype_n)

    setmetatable(pools, {
        __index = function(self, v: unknown): Pool<unknown>
            lassert(ctype_valid(v), "invalid component type")
            local pool = pool_create(1)
            self[v] = pool
            return pool
        end
    })

    local function group_tryadd(group: GroupData, key: number)
        for _, pool in ipairs(group) do
            if pool.map[key] == nil then
                return
            end
        end

        local n = group.size + 1
        group.size = n

        for _, pool in ipairs(group) do
            pool_swap(pool, pool.map[key] :: number, key, n)
        end
    end

    local function group_tryremove(group: GroupData, index: number, key: number): number
        local n = group.size
        if index <= n then
            group.size = n - 1
            for _, pool in ipairs(group) do        
                pool_swap(pool, index, key, n)
            end
            return n
        else
            return index
        end
    end

    local function group_init(...: CType): GroupData
        local group = { size = 0 }

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            group[i] = pools[ctype]
            groups[ctype] = group
        end

        local entities = pools[...].entities

        for _, id in next, entities do
            group_tryadd(group, id_key(id))
        end

        return group
    end

    local function add(ctype: CType, pool: Pool<unknown>, key: number, id: number, value: unknown)
        pool_add(pool, key, id, value)
        local group = groups[ctype]
        if group then
            group_tryadd(group, key)
        end
    end

    local function remove(ctype: CType, pool: Pool<unknown>, index: number, key: number)
        local group = groups[ctype]
        if group then
            index = group_tryremove(group, index, key)
        end
        pool_erase(pool, index, key)
    end

    local function fire(listeners: Array<Listener>, id: Entity, value: unknown)
        for i = #listeners, 1, -1 do
            listeners[i](id, value)         
        end 
    end

    local function added<T>(ctype: CType, id: Entity, value: T)
        local listeners = addedListeners[ctype]
        if listeners then fire(listeners, id, value) end
    end

    local function changed<T>(ctype: CType, id: Entity, value: T)
        local listeners = changedListeners[ctype]
        if listeners then fire(listeners, id, value) end
    end

    local function removing(ctype: CType, id: Entity)
        local listeners = removingListeners[ctype]
        if listeners then fire(listeners, id) end
    end

    local function releaseAll()
        local n = #ids
        for i = 1, n - 1 do
            local ver = id_version(ids[i])
            ids[i] = id_encode(i + 1, ver + 1)
        end
        ids[n] = id_encode(id_INVALID_KEY, id_version(ids[n]) + 1)
        free = 1
        size = 0
    end

    local function clear(ctype: CType)
        local pool = pools[ctype]

        local listeners = removingListeners[ctype]
        if listeners then
            for _, id in next, pool.entities do
                fire(listeners, id)
            end    
        end

        local group = groups[ctype]
        if group then
            group.size = 0
        end
        
        pool_clear(pool)
    end

    local function create(): Entity
        size += 1
        if free ~= id_INVALID_KEY then
            local newid, next = id_rekey(ids[free], free)
            ids[free] = newid
            free = next
            return newid
        else
            local newid = id_encode(size, INITIAL_VERSION)
            ids[size] = newid
            return newid
        end  
    end

    local function createWith(id: Entity): Entity
        local key, version = id_decode(id)
        if key < 1 or version < 1 then error("attempted to use malformed id", 2) end

        local n = #ids
        if key > n + 1 then -- if ids have not been created yet
            for i = n+1, key-2 do
                ids[i] = id_encode(i + 1, INITIAL_VERSION)
            end
            ids[key-1] = id_encode(free, INITIAL_VERSION)
            free = n+1
        elseif key <= n then -- if id has been created before
            lassert(free ~= id_INVALID_KEY and id_key(ids[key]) ~= key, "could not create entity with the given identifier")   
            if free == key then -- if desired id is at head
                local next = id_key(ids[free])
                free = next
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
        size += 1
        ids[key] = id
        return id
    end

    local function release(id: Entity)
        local key, ver = id_decode(id)
        size -= 1
        ids[key] = id_encode(free, ver < id_MAX_VERSION and ver + 1 or INITIAL_VERSION)
        free = key
    end

    function registry:create(id: Entity?): Entity
        if size >= id_MAX_KEY then error("cannot create entity; registry is at max entity count ("..id_MAX_KEY..")", 2) end
        return id and createWith(id) or create()
    end

    function registry:release(id: Entity)
        release(id)
    end

    function registry:destroy(id: Entity)
        release(id)
        local key = id_key(id)
        for ctype, pool in next, pools do
            local index = pool_find(pool, key)
            if index then
                removing(ctype, id)
                remove(ctype, pool, index, key)
            end
        end
    end

    function registry:valid(id: Entity): boolean
        return ids[id_key(id)] == id
    end

    function registry:version(id: Entity): number
        return id_version(id)
    end

    function registry:current(id: Entity): number
        return id_version(ids[id_key(id)])
    end

    function registry:orphan(id: Entity): boolean
        local key = id_key(id)
        for _, pool in next, pools do
            if pool_find(pool, key) then return false end
        end
        return true
    end

    function registry:add<T...>(id: Entity, ...: T...)
        local key = id_key(id)
        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = pools[ctype]
            if pool_find(pool, key) then error(`entity already has { toarg(i) }`, 2) end

            local default = ctype_defaults[ctype] or error(`{ toarg(i) } has no default value`, 2)
            local value = default()
            if value == nil then error(`{ toarg(i) } nil default value`, 2) end

            add(ctype, pool, key, id, value)
            added(ctype, id, value)
        end
    end

    function registry:set<T>(id: Entity, ctype: T, value: T?)
        local pool = pools[ctype] :: Pool<T>
        local key = id_key(id)
        local index = pool_find(pool, key)
        
        if value ~= nil then
            if index then
                pool.values[index] = value
                changed(ctype, id, value)
            else
                add(ctype, pool, key, id, value)
                added(ctype, id, value)
            end
        elseif index then
            removing(ctype, id)
            remove(ctype, pool, index, key)
        end
    end
    
    function registry:patch<T>(id: Entity, ctype: T, patcher: (T) -> T?)
        local pool = pools[ctype] :: Pool<T>
        local key = id_key(id)
        local index = pool_find(pool, key) :: number
        if index == nil then error("entity does not have component", 2) end

        local values = pool.values
        local value = patcher(values[index])
        if value == nil then error("cannot set new value as nil", 2) end

        values[index] = value :: T
        changed(ctype, id, value)
    end

    registry.has = (function(self: Registry, id: Entity, ...: unknown): boolean
        local a, b = ...
        local key = id_key(id)
        if b == nil then
            return pool_find(pools[a] :: Pool<unknown>, key) ~= nil
        else
            for i = 1, select("#", ...) do
                if pool_find(pools[select(i, ...)], key) == nil then return false end
            end
            return true
        end  
    end :: any) :: <T...>(self: Registry, id: Entity, T...) -> boolean

    registry.get = (function(self: Registry, id: Entity, ...: unknown): ...unknown
        local a, b, c, d, e = ...
        local key = id_key(id)
        if b == nil then
            return pool_get(pools[a], key)
        elseif c == nil then
            return pool_get(pools[a], key), pool_get(pools[b], key)
        elseif d == nil then
            return pool_get(pools[a], key), pool_get(pools[b], key), pool_get(pools[c], key)
        elseif e == nil then
            return pool_get(pools[a], key), pool_get(pools[b], key), pool_get(pools[c], key), pool_get(pools[d], key)
        else
            local tuple: Array<any> = { ... }
            for i, v in next, tuple do
                tuple[i] = pool_get(pools[v], key)
            end
            return unpack(tuple)
        end
    end :: any) :: <T...>(self: Registry, id: Entity, T...) -> T...

    function registry:remove<T...>(id: Entity, ...: T...)
        local key = id_key(id)
        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = pools[ctype]
            local index = pool_find(pool, key) :: number
            if index == nil then continue end
            
           removing(ctype, id)
           remove(ctype, pool, index, key)
        end
    end

    function registry:size(): number
        return size
    end

    function registry:clear<T...>(...: T...)
        local argn = select("#", ...)
        if argn > 0 then
            for i = 1, argn do
                clear(select(i, ...))
            end
        else
            for ctype in next, pools do clear(ctype) end
            releaseAll()
        end 
    end

    registry.view = (function(self: Registry, ...: unknown): View<...unknown>
        return View.new(registry, ...) :: any
    end :: any) :: <T...>(Registry, T...) -> View<T...>

    registry.track = (function(self: Registry, track: unknown, ...: unknown): Observer<...unknown>
        return Observer.new(registry, track, ...) :: any
    end :: any) :: <T, U...>(Registry, track: T, U...) -> Observer<(T, U...)>

    registry.group = (function(self: Registry, ...: unknown): Group<...unknown>
        local argn = select("#", ...)
        lassert(argn > 1, "groups must contain at least 2 components")
        local group: GroupData? = groups[...]

        for i = 1, argn do
            local ctype = select(i, ...)
            lassert(ctype_valid(ctype), `invalid { toarg(i) }`)
            lassert(groups[ctype] == group, `cannot create group; { toarg(i) } is already owned by another group`)
        end

        group = group or group_init(...)

        return Group.new(registry, group :: GroupData, ...)
    end :: any) :: <T...>(Registry, T...) -> Group<T...>

    function registry:entities(): Array<Entity>
        local entities = table.create(size)

        for i, id in next, ids do
            if id_key(id) == i then
                table.insert(entities, id)
            end
        end

        return entities
    end

    function registry:storage<T>(ctype: T): Pool<T>
        return pools[ctype] :: Pool<T>
    end

    function registry:added<T>(ctype: T): Signal<Entity, T>
        return (signals.added[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.added[ctype] = signal
            addedListeners[ctype] = listeners
            return signal
        end)()) :: Signal<Entity, T>
    end

    function registry:changed<T>(ctype: T): Signal<Entity, T>
        return (signals.changed[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.changed[ctype] = signal
            changedListeners[ctype] = listeners
            return signal    
        end)()) :: Signal<Entity, T>    
    end

    function registry:removing<T>(ctype: T): Signal<Entity, nil>
        return signals.removing[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.removing[ctype] = signal
            removingListeners[ctype] = listeners
            return signal
        end)() :: Signal<Entity, nil>
    end

    -- internal test method
    (registry :: any).setEntityVersion = function(_, key: number, ver: number)
        ids[key] = id_encode(id_key(ids[key]), ver)
    end

    setmetatable(registry :: any, { __index = function(_, index)
        error(`"{ tostring(index) }" is not a valid member of Registry`, 2)    
    end })

    return table.freeze(registry)
end

----------------------------------------------------------------------
-- Return
----------------------------------------------------------------------

return table.freeze {
    component = ctype_create :: (() -> unknown) & (<T>(default: (() -> T)?) -> T),
    registry = registry_create,
    null = id_NULL,

    -- test functions
    encode = id_encode
}
