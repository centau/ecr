------------------------------------------------------------------------------------------------------------------------
-- ecr.luau
-- v0.5.0
------------------------------------------------------------------------------------------------------------------------

local INITIAL_ENTITY_VERSION = 1
local MAX_ENTITIES = 0x000F_FFFF

type Array<T> = { [number]: T }
type Map<T, U> = { [T]: U }

type CType = unknown
export type Entity = number

export type Handle = typeof(setmetatable({} :: { registry: Registry, entity: Entity }, {} :: HandleMT))

type HandleMT = {
    __index: HandleMT,

    destroy: (self: Handle) -> (),
    orphaned: (self: Handle) -> boolean,
    add: <T...>(self: Handle, T...) -> (),
    set: <T>(self: Handle, ctype: T, value: T?) -> Handle,
    patch: <T>(self: Handle, ctype: T, patcher: (current: T) -> T) -> (),
    has: <T...>(self: Handle, T...) -> boolean,
    get: <T...>(self: Handle, T...) -> T...,
    try_get: <T>(self: Handle, T) -> T?,
    remove: <T...>(self: Handle, T...) -> (),
}

export type Registry = {
    create: (self: Registry, Id: Entity?) -> Entity,
    release: (self: Registry, entity: Entity) -> (),
    destroy: (self: Registry, entity: Entity) -> (),

    contains: (self: Registry, entity: Entity) -> boolean,
    version: (self: Registry, entity: Entity) -> number,
    current: (self: Registry, entity: Entity) -> number,

    orphaned: (self: Registry, entity: Entity) -> boolean,
    add: <T...>(self: Registry, entity: Entity, T...) -> (),
    set: <T>(self: Registry, entity: Entity, ctype: T, value: T?) -> (),
    patch: <T>(self: Registry, entity: Entity, ctype: T, patcher: (current: T) -> T) -> (),
    has: <T...>(self: Registry, entity: Entity, T...) -> boolean,
    get: <T...>(self: Registry, entity: Entity, T...) -> T...,
    try_get: <T>(self: Registry, entity: Entity, T) -> T?,
    remove: <T...>(self: Registry, entity: Entity, T...) -> (),

    size: (self: Registry) -> number,
    clear: <T...>(self: Registry, T...) -> (),

    view: <T...>(self: Registry, T...) -> View<T...>,
    track: <T...>(self: Registry, T...) -> Observer<T...>,
    group: <T...>(self: Registry, T...) -> Group<T...>,

    entities: (self: Registry) -> Array<Entity>,
    storage: <T>(self: Registry, ctype: T) -> Pool<T>,

    added: <T>(self: Registry, ctype: T) -> Signal<Entity, T>,
    changed: <T>(self: Registry, ctype: T) -> Signal<Entity, T>,
    removing: <T>(self: Registry, ctype: T) -> Signal<Entity, nil>,

    handle: (self: Registry, entity: Entity?) -> Handle
}

export type View<T...> = typeof(setmetatable({} :: {
    exclude: <U...>(self: View<T...>, U...) -> View<T...>,
    use: <T>(self: View<T...>, lead: T) -> View<T...>,
}, {} :: {
    __iter: (self: View<T...>) -> () -> (Entity, T...),
    __len: (self: View<T...>) -> number  
}))

export type Observer<T...> = typeof(setmetatable({} :: {
    exclude: <U...>(self: Observer<T...>, U...) -> Observer<T...>,
    disconnect: (self: Observer<T...>) -> Observer<T...>,
    reconnect: (self: Observer<T...>) -> Observer<T...>,

    persist: (self: Observer<T...>) -> Observer<T...>,
    clear: (self: Observer<T...>) -> Observer<T...>,
}, {} :: {
    __iter: (self: Observer<T...>) -> () -> (Entity, T...),
    __len: (self: Observer<T...>) -> number
}))

export type Group<T...> = typeof(setmetatable({} :: {}, {} :: {
    __iter: (self: Group<T...>) -> () -> (Entity, T...),
    __len: (self: Group<T...>) -> number     
}))

type GroupData = { size: number } & Array<Pool<unknown>>

export type Signal<T...> = {
    connect: (self: Signal<T...>, (T...) -> ()) -> Connection,
}

export type Connection = {
    disconnect: (self: Connection) -> ()
}

type Listener<T> = (entity: Entity, value: T) -> ()

type Pool<T> = {
    size: number,
    map: Array<number?>,
    entities: Array<number>,
    values: Array<T>
}

export type Queue<T...> = typeof(setmetatable({} :: {
    add: (self: Queue<T...>, T...) -> (),
    clear: (self: Queue<T...>) -> ()
}, {} :: {
    __iter: (self: Queue<T...>) -> () -> (T...),
    __len: (self: View<T...>) -> number  
}))

local ERROR = function<T>(msg: T): never
    local stack = 1

    while debug.info(stack, "s") == debug.info(1, "s") do
        stack += 1    
    end

    error(msg, stack)  
end :: typeof(error)

-- assert but stack trace will always start at the callsite of library functions outside of this file
local ASSERT = function<T>(v: T, msg: string): T
    if v then return v end
    ERROR(msg)
    return nil :: never
end :: typeof(assert)

------------------------------------------------------------------------------------------------------------------------
-- Entity Id
------------------------------------------------------------------------------------------------------------------------

-- entity ids are composed of two parts: key and version
-- key (lower bits) used to index into arrays
-- version (upper bits) used to keep id unique when keys are reused

ASSERT(
    bit32.band(MAX_ENTITIES + 1, MAX_ENTITIES) == 0 -- is one less than a power of 2
    and MAX_ENTITIES <= 0xFFFF_FFFF -- can be represented using 32 bits
    and MAX_ENTITIES > 0,
    "invalid max entities limit"
)

local ID_INVALID_KEY = 0
local ID_MAX_INT = 2^53-1
local ID_MASK_KEY = MAX_ENTITIES
local ID_MASK_VER = ID_MAX_INT - ID_MASK_KEY

local ID_LSHIFT = ID_MASK_KEY + 1
local ID_RSHIFT = 1/ID_LSHIFT

local ID_MAX_KEY = ID_MASK_KEY
local ID_MAX_VERSION = ID_MASK_VER * ID_RSHIFT

local function ID_CREATE(key: number, ver: number): number
    --assert(key <= ID_MAX_KEY)
    --assert(ver <= ID_MAX_VERSION)
    return ver * ID_LSHIFT + key
end

local function ID_KEY(ID: number): number
    return bit32.band(ID, ID_MASK_KEY)
end

local function ID_KEY_VER(ID: number): (number, number)
    local key = ID_KEY(ID)
    local ver = (ID - key) * ID_RSHIFT
    return key, ver
end

local function ID_VER(ID: number): number
    return (ID - ID_KEY(ID)) * ID_RSHIFT
end

local function ID_SWAPKEY(ID: number, key: number): number
    return ID - ID_KEY(ID) + key
end

local ID_NULL = ID_CREATE(0, ID_MAX_VERSION)

------------------------------------------------------------------------------------------------------------------------
-- Pool
------------------------------------------------------------------------------------------------------------------------

-- pools are a datastructure (known as sparse-sets) used to store entities and components
-- one pool for each component type
-- entities and values are packed arrays of entity ids and corresponding component value
-- map maps the key portion of an id to an internal packed array index for that entity

local function pool_create(size: number?): Pool<unknown>
    local n = size or 1
    return {
        size = 0,
        map = table.create(n),
        entities = table.create(n),
        values = table.create(n)
    }
end

local function pool_add<T>(self: Pool<T>, key: number, id: Entity, v: T)
    local n = self.size + 1; self.size = n
    self.map[key] = ID_SWAPKEY(id, n)
    self.entities[n] = id
    self.values[n] = v     
end

--[[
local function pool_add_or_change<T>(self: Pool<T>, key: number, id: Entity, v: T)
    local map = self.map
    local idx_ver = map[key]
    if idx_ver then
        self.values[ID_KEY(idx_ver)] = v
    else
        local n = self.size + 1; self.size = n
        map[key] = ID_SWAPKEY(id, n)
        self.entities[n] = id
        self.values[n] = v   
    end 
end
]]

local function pool_remove<T>(self: Pool<T>, idx: number, key: number)
    local n = self.size; self.size = n - 1
    local map = self.map
    local entities = self.entities
    local values = self.values

    local lastid = entities[n]
    map[ID_KEY(lastid)] = ID_SWAPKEY(lastid, idx); map[key] = nil
    entities[idx] = lastid; entities[n] = nil
    values[idx] = values[n]; values[n] = nil
end

local function pool_add_id<T>(self: Pool<T>, id: Entity)
    local map = self.map

    local key = ID_KEY(id)
    local idx_ver = map[key]

    if idx_ver == nil then
        local n = self.size + 1; self.size = n
        map[key] = ID_SWAPKEY(id, n)
        self.entities[n] = id
    end 
end

local function pool_remove_id<T>(self: Pool<T>, id: Entity)
    local map = self.map
    local entities = self.entities

    local key = ID_KEY(id)
    local idx_ver = map[key]

    if idx_ver then
        local n = self.size; self.size = n - 1
        local idx = ID_KEY(idx_ver)
        local lastid = entities[n]
        map[ID_KEY(lastid)] = ID_SWAPKEY(lastid, idx); map[key] = nil
        entities[idx] = lastid; entities[n] = nil
    end
end

local function pool_swap<T>(self: Pool<T>, idx: number, key: number, id: number, target_idx: number)
    local map = self.map
    local entities = self.entities
    local values = self.values

    local id_swap = entities[target_idx]
    
    entities[target_idx], entities[idx] = id, id_swap
    values[target_idx], values[idx] = values[idx], values[target_idx]
    map[key] = ID_SWAPKEY(id, target_idx)
    map[ID_KEY(id_swap)] = ID_SWAPKEY(id_swap, idx)
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

------------------------------------------------------------------------------------------------------------------------
-- Component Type
------------------------------------------------------------------------------------------------------------------------

local ctype_n = 0
local ctype_names: Map<CType, string> = {}
local ctype_constructors: Map<CType, ((() -> unknown)?)> = table.create(1e3)

local function ctype_create<T>(constructors: ( () -> T )?): CType
    ctype_n += 1
    ASSERT(constructors == nil or type(constructors) == "function", "constructor must be a function")
    ctype_constructors[ctype_n] = constructors
    return ctype_n
end

local function ctype_valid(v: unknown): boolean
    return type(v) == "number" and math.floor(v) == v and v > 0 and v <= ctype_n  
end

local function ctype_name(ctype: CType, name: unknown)
    ASSERT(ctype_valid(ctype), `{name} refers to an invalid component`)
    ctype_names[ctype] = tostring(name)
end

local function ctype_debug(ctype: CType?, idx: number?)
    local name = ctype_names[ctype]

    return
        if name then `component "{name}"`
        elseif idx then `component (arg #{idx})`
        else "component (unknown)"
end

------------------------------------------------------------------------------------------------------------------------
-- Views
------------------------------------------------------------------------------------------------------------------------

local View, Observer, Group do
    local WEAK_VALUES = { __mode = "v" }

    local function has_any(pools: Array<Pool<unknown>>, key: number): boolean
        for _, pool in next, pools do
            if pool.map[key] then return true end
        end
        return false
    end

    local function smallest(pools: Array<Pool<unknown>>): Pool<unknown>
        local s: Pool<unknown>?
        for _, pool in next, pools do
            s = if s == nil or pool.size < s.size then pool else s
        end
        return assert(s, "no pools given")
    end

    local function get_pools(registry: Registry, ctypes: Array<CType>): Array<Pool<unknown>>
        local pools = table.create(#ctypes)
        for i, ctype in next, ctypes do
            pools[i] = registry:storage(ctype)
        end
        return pools
    end

    local function disconnect_all(connections: Array<Connection>)
        for _, connection in next, connections do
            connection:disconnect()
        end
    end

    type _View<T...> = View<T...> & {
        registry: Registry,
        includes: Array<CType>,
        excludes: Array<CType>?,
        lead: CType?
    }

    View = {}
    View.__index = View

    function View.new<T...>(reg: Registry, ...: T...): View<T...>
        assert(select("#", ...) > 0, "no components given")

        local self: _View<T...> = setmetatable({
            registry = reg,
            includes = {},
            excludes = nil,
            lead = nil
        }, View) :: any

        local includes = self.includes

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
            ASSERT(not table.find(includes, ctype), `duplicate { ctype_debug(ctype, i) } included`)
            table.insert(includes, ctype)
        end

        return self
    end

    function View.exclude<T..., U...>(self: _View<T...>, ...: U...): _View<T...>
        local includes = self.includes
        local excludes = self.excludes or (function()
            local t = {} 
            self.excludes = t
            return t
        end)()

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
            ASSERT(not table.find(includes, ctype), `cannot exclude { ctype_debug(ctype, i) }, component is a part of the view`)
            if table.find(excludes, ctype) then continue end
            table.insert(excludes, ctype)
        end

        return self
    end

    function View.use<T...>(self: _View<T...>, ctype: CType): _View<T...>
        ASSERT(ctype_valid(ctype), `invalid component type`)
        ASSERT(table.find(self.includes, ctype), "cannot lead with component; component is not a part of the view")
        self.lead = ctype
        return self
    end

    function View.__iter<T...>(self: _View<T...>): () -> (Entity, T...)
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
                        local idx_ver = b.map[ID_KEY(entity)]
                        if idx_ver == nil then continue end
                        local vb = b.values[ID_KEY(idx_ver :: number)]
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
                        local idx_ver = a.map[ID_KEY(entity)]
                        if idx_ver == nil then continue end
                        local va = a.values[ID_KEY(idx_ver :: number)]
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
        ): () -> (Entity, ...any)
            local source = lead or smallest(includes)
    
            local n = source.size
            local entities = source.entities
            local tuple = table.create(#includes)
    
            return function()
                for i = n, 1, -1 do
                    local entity = entities[i]
                    local key = ID_KEY(entity)
                    
                    if excludes and has_any(excludes, key) then continue end
    
                    local has_all = true
                    for ii, pool in next, includes do
                        local idx_ver = pool.map[key]
                        if idx_ver == nil then has_all = false; break end
                        tuple[ii] = pool.values[ID_KEY(idx_ver :: number) :: number]
                    end
                    if has_all == false then continue end
    
                    n = i - 1
                    return entity, unpack(tuple)
                end
                return nil :: any
            end
        end

        local includes = get_pools(self.registry, self.includes)
        local excludes = self.excludes and get_pools(self.registry, self.excludes)
        local lead = self.lead and self.registry:storage(self.lead)

        return if #includes == 1 and not excludes and not lead then
                single(includes[1])
            elseif #includes == 2  and not excludes and not lead then 
                double(includes[1], includes[2])
            else
                multi(includes, excludes, lead)
    end

    function View.__len<T...>(self: _View<T...>): number
        return smallest(get_pools(self.registry, self.includes)).size
    end

    type _Observer<T...> = Observer<T...> & {
        registry: Registry,
        pool: Pool<unknown>,
        includes: Array<CType>,
        excludes: Array<CType>?,
        connections: Array<Connection>?,
        persistent: boolean,
    }

    Observer = {}
    Observer.__index = Observer

    function Observer.new<T...>(reg: Registry, ...: T...): _Observer<T...>
        local ctype_first = select(1, ...) :: unknown
    
        local self: _Observer<T...> = setmetatable({
            registry = reg,
            pool = pool_clone(reg:storage(ctype_first)),
            includes = {},
            excludes = nil,
            connections = nil,
            persistent = false
        }, Observer) :: any

        local includes = self.includes

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
            ASSERT(not table.find(includes, ctype), `duplicate { ctype_debug(ctype, i) } included`)
            table.insert(includes, ctype)
        end

        local connections = {}
        local pool = self.pool
        local weakref = setmetatable({ self = self }, WEAK_VALUES)
        local function try_remove(id: number)
            if weakref.self == nil then disconnect_all(connections) end
            pool_remove_id(pool, id)
        end

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            table.insert(connections, reg:removing(ctype):connect(try_remove))
        end

        return self:reconnect() :: any
    end

    function Observer.disconnect<T...>(self: _Observer<T...>): Observer<T...>
        if not self.connections then return self end
        disconnect_all(self.connections)
        self.connections = nil
        return self
    end

    function Observer.reconnect<T...>(self: _Observer<T...>): Observer<T...>
        if self.connections then return self end

        local reg = self.registry
        local pool = self.pool
        local includes = self.includes

        local connections = {}

        for i, ctype in includes do
            local function listener(id)
                pool_add_id(pool, id)
            end
            
            table.insert(connections, reg:added(ctype):connect(listener))
            table.insert(connections, reg:changed(ctype):connect(listener))
        end

        self.connections = connections

        return self
    end

    function Observer.persist<T...>(self: _Observer<T...>): Observer<T...>
        self.persistent = true
        return self
    end

    function Observer.clear<T...>(self: _Observer<T...>): Observer<T...>
        pool_clear(self.pool)
        return self
    end

    function Observer.__iter<T...>(self: _Observer<T...>): () -> (Entity, T...)
        local pool = self.pool
        local reg = self.registry
        local includes = get_pools(reg, self.includes)
        local excludes = self.excludes and get_pools(reg, self.excludes)
        local persist = self.persistent


        local n = pool.size
        local entities = pool.entities

        local reg_pool = includes[1]
        local reg_map = reg_pool.map
        local reg_values = reg_pool.values

        local tuple = {} :: Array<any>

        return if #includes == 1 and not excludes then 
                function()
                    local i = n; n = i - 1
                    local id = entities[i]
                    if id == nil then
                        if not persist then self:clear() end
                        return nil :: any
                    end
                    local key = ID_KEY(id)
                    local value = reg_values[ID_KEY(
                        reg_map[key] :: number
                    )]
                    return id, value
                end 
            else
                function()
                    for i = n, 1, -1 do
                        local id = entities[i]
                        local key = ID_KEY(id)

                        if excludes and has_any(excludes, key) then continue end

                        local has_all = true
                        for ii, pool in next, includes do
                            local idx_ver = pool.map[key]
                            if idx_ver == nil then has_all = false; break end
                            tuple[ii] = pool.values[ID_KEY(idx_ver :: number) :: number]
                        end
                        if has_all == false then continue end

                        n = i - 1
                        return id, unpack(tuple)
                    end
                    if not persist then self:clear() end
                return nil :: any, nil :: any
            end
    end

    function Observer.exclude<T..., U...>(self: _Observer<T...>, ...: U...): Observer<T...>
        local excludes = self.excludes or (function()
            local t = {} 
            self.excludes = t
            return t
        end)()

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
            ASSERT(not table.find(self.includes, ctype), `cannot exclude { ctype_debug(ctype, i) }, component is being tracked`)
            if table.find(excludes, ctype) then continue end
            table.insert(excludes, ctype)
        end

        return self
    end

    function Observer.__len<T...>(self: _Observer<T...>): number
        return self.pool.size
    end

    type _Group<T...> = Group<T...> & {
        data: GroupData,
        pools: Array<Pool<unknown>>
    }

    Group = {}
    Group.__index = Group

    function Group.new<T...>(reg: Registry, data: GroupData, ...: T...): Group<T...>
        local self: _Group<T...> = setmetatable({
            data = data,
            pools = {}
        }, Group) :: any

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = reg:storage(ctype)
            assert(table.find(data, pool), "component type is not in group")
            self.pools[i] = pool 
        end

        return self
    end

    function Group.__iter<T...>(self: _Group<T...>): () -> (Entity, T...)
        local pools = self.pools
        local n = self.data.size
        local entities = pools[1].entities

        local values: Array<Array<unknown>> = table.create(#pools)
        for i, pool in next, pools do
            values[i] = pool.values
        end

        if #pools == 1 then
            local a = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i]  
            end
        elseif #pools == 2 then
            local a, b = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i], b[i] 
            end
        elseif #pools == 3 then
            local a, b, c = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i], b[i], c[i]
            end
        elseif #pools == 4 then
            local a, b, c, d = unpack(values)
            return function()
                local i = n; n = i - 1
                return entities[i], a[i], b[i], c[i], d[i]
            end
        else
            local tuple = table.create(#values) :: Array<any>
            return function()
                local i = n; n = i - 1
                for ii, v in next, values do
                    tuple[ii] = v[i]
                end
                return entities[i], unpack(tuple)
            end
        end
    end

    function Group.__len<T...>(self: _Group<T...>): number
        return self.data.size
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Signal
------------------------------------------------------------------------------------------------------------------------

local signal_create: () -> (Signal<...any>, Array<(...any) -> ()>) do
    type _Signal<T...> = {
        [(T...) -> ()]: true,
        pool: Pool<(T...) -> ()>,
        count: number
    }

    type _Connection = { signal: _Signal<...unknown>, id: number }

    local Connection = {}
    Connection.__index = Connection

    function Connection.disconnect(self: _Connection)
        local pool = self.signal.pool
        local idx_ver = pool.map[self.id]
        if idx_ver then
            pool_remove(self.signal.pool, ID_KEY(idx_ver), self.id)
        end
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

------------------------------------------------------------------------------------------------------------------------
-- Handle
------------------------------------------------------------------------------------------------------------------------

local Handle = (function(): HandleMT
    local Handle = {}
    Handle.__index = Handle

    function Handle.destroy(self: Handle)
        self.registry:destroy(self.entity)
    end

    function Handle.orphaned(self: Handle): boolean
        return self.registry:orphaned(self.entity)
    end

    function Handle.add<T...>(self: Handle, ...: T...)
        self.registry:add(self.entity, ...)
    end

    function Handle.set<T>(self: Handle, ctype: T, value: T?): Handle
        self.registry:set(self.entity, ctype, value)
        return self
    end

    function Handle.patch<T>(self: Handle, ctype: T, fn: (T) -> T)
        self.registry:patch(self.entity, ctype, fn)
    end

    function Handle.has<T...>(self: Handle, ...: T...): boolean
        return self.registry:has(self.entity, ...)
    end

    function Handle.get<T...>(self: Handle, ...: T...): T...
        return self.registry:get(self.entity, ...)
    end

    function Handle.try_get<T>(self: Handle, ctype: T): T?
        return self.registry:try_get(self.entity, ctype)
    end

    function Handle.remove<T...>(self: Handle, ...: T...)
        self.registry:remove(self.entity, ...)
    end

    return Handle
end)()

------------------------------------------------------------------------------------------------------------------------
-- Registry
------------------------------------------------------------------------------------------------------------------------

local function registry_create(): Registry
    local registry = {} :: Registry

    local size = 0
    local free = ID_INVALID_KEY
    local ids = table.create(1) :: Array<Entity>

    local pools: Map<CType, Pool<unknown>> = table.create(ctype_n)
    local groups: Map<CType, GroupData?> = table.create(ctype_n)

    local signals = {
        added = {} :: Map<CType, Signal<Entity, unknown>>,
        changed = {} :: Map<CType, Signal<Entity, unknown>>,
        removing = {} :: Map<CType, Signal<Entity, nil>>
    }

    local added_listeners: Map<CType, Array<Listener<unknown>>?> = table.create(ctype_n)
    local changed_listeners: Map<CType, Array<Listener<unknown>>?> = table.create(ctype_n)
    local removing_listeners: Map<CType, Array<Listener<unknown>>?> = table.create(ctype_n)

    -- lazily create pools on nil index to avoid having to check everywhere
    setmetatable(pools, {
        __index = function(self, v: unknown): Pool<unknown>
            ASSERT(ctype_valid(v), "invalid component type")
            local pool = pool_create(1)
            self[v] = pool
            return pool
        end
    })

    local function group_try_add(group: GroupData, key: number, id: number)
        for _, pool in ipairs(group) do
            if pool.map[key] == nil then
                return
            end
        end

        local n = group.size + 1
        group.size = n

        for _, pool in ipairs(group) do
            pool_swap(pool, ID_KEY(pool.map[key] :: number), key, id, n)
        end
    end

    -- returns new internal index of id
    local function group_try_remove(group: GroupData, index: number, key: number, id: number): number
        local n = group.size
        if index <= n then
            group.size = n - 1
            for _, pool in ipairs(group) do        
                pool_swap(pool, index, key, id, n)
            end
            return n
        else
            return index
        end
    end

    local function group_init(...: any): GroupData
        local group = { size = 0 }

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            group[i] = pools[ctype]
            groups[ctype] = group
        end

        local entities = pools[...].entities

        for _, id in next, entities do
            group_try_add(group, ID_KEY(id), id)
        end

        return group
    end

    local function add(ctype: CType, pool: Pool<unknown>, key: number, id: number, value: unknown)
        pool_add(pool, key, id, value)
        local group = groups[ctype]
        if group then
            group_try_add(group, key, id)
        end
    end

    local function remove(ctype: CType, pool: Pool<unknown>, index: number, key: number, id: number)
        local group = groups[ctype]
        if group then
            index = group_try_remove(group, index, key, id)
        end
        pool_remove(pool, index, key)
    end

    local function fire(listeners: Array<Listener<unknown>>, id: Entity, value: unknown)
        for i = #listeners, 1, -1 do
            listeners[i](id, value)         
        end 
    end

    local function fire_added<T>(ctype: CType, id: Entity, value: T)
        local listeners = added_listeners[ctype]
        if listeners then fire(listeners, id, value) end
    end

    local function fire_changed<T>(ctype: CType, id: Entity, value: T)
        local listeners = changed_listeners[ctype]
        if listeners then fire(listeners, id, value) end
    end

    local function fire_removing(ctype: CType, id: Entity)
        local listeners = removing_listeners[ctype]
        if listeners then fire(listeners, id) end
    end

    local function release(id: Entity)
        local key, ver = ID_KEY_VER(id)
        size -= 1

        if ver < ID_MAX_VERSION then
            ids[key] = ID_CREATE(free, ver + 1) -- recycle key
            free = key
        else
            ids[key] = ID_NULL -- permanently deprecate key
        end     
    end

    local function release_all()
        for i = #ids, 1, -1 do
            local id = ids[i]
            if ID_KEY(id) == i then -- if in use
                release(id)
            end
        end
    end

    local function clear(ctype: CType)
        local pool = pools[ctype]

        local listeners = removing_listeners[ctype]
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
        if free ~= ID_INVALID_KEY then
            local next = ID_KEY(ids[free])
            local newid = ID_SWAPKEY(ids[free], free)
            ids[free] = newid
            free = next
            return newid
        else
            local key = #ids + 1
            local newid = ID_CREATE(key, INITIAL_ENTITY_VERSION)
            ids[key] = newid
            return newid
        end  
    end

    local function create_using(id: Entity): Entity
        local key, ver = ID_KEY_VER(id)
        ASSERT(
            key >= 1 and ver >= 1 and
            key <= ID_MAX_KEY and ver <= ID_MAX_VERSION,
            "malformed id"
        )

        local n = #ids
        if key > n + 1 then -- if key has not been created yet
            for i = n+1, key-2 do
                ids[i] = ID_CREATE(i + 1, INITIAL_ENTITY_VERSION)
            end
            ids[key-1] = ID_CREATE(free, INITIAL_ENTITY_VERSION)
            free = n+1
        elseif key <= n then -- if key has been created before
            if ids[key] == ID_NULL then -- id is deprecated
                ids[key] = id   
            else
                ASSERT(
                    free ~= ID_INVALID_KEY -- an unused key exists
                    and ID_KEY(ids[key]) ~= key, -- desired key is not in use
                    "key is already in use"
                )   
                if free == key then -- if desired id is at head
                    local next = ID_KEY(ids[free])
                    free = next
                else -- desired id is somewhere along list
                    local previous = free
                    while true do -- find element before desired id
                        local next = ID_KEY(ids[previous])
                        if next == key then break end
                        previous = next
                    end
                    ids[previous] = ID_SWAPKEY(ids[previous], ID_KEY(ids[key]))
                end
            end
            
        end
        size += 1
        ids[key] = id
        return id
    end

    local function check_versions_equal(idx: number, idx_ver: number, key: number, id: number): boolean
        return idx_ver - idx + key == id
    end

    local function ASSERT_VERSIONS_EQUAL(idx: number, idx_ver: number, key: number, id: number)
        if idx_ver - idx + key ~= id then
            ASSERT(false, `invalid entity`)    
        end
    end

    local function ASSERT_VALID_ENTITY(key: number, id: Entity)
        if ids[key] ~= id then
            ASSERT(false, `invalid entity`)
        end
    end

    function registry:create(id: Entity?): Entity
        if size >= ID_MAX_KEY then ERROR("cannot create entity; registry is at max entities") end
        return id and create_using(id) or create()
    end

    function registry:release(id: Entity)
        ASSERT_VALID_ENTITY(ID_KEY(id), id)
        release(id)
    end

    function registry:destroy(id: Entity)
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)
        
        for ctype, pool in next, pools do
            local idx_ver = pool.map[key]
            if idx_ver then
                fire_removing(ctype, id)
                remove(ctype, pool, ID_KEY(idx_ver), key, id)
            end
        end

        release(id)
    end

    function registry:contains(id: Entity): boolean
        return ids[ID_KEY(id)] == id
    end

    function registry:version(id: Entity): number
        return ID_VER(id)
    end

    function registry:current(id: Entity): number
        return ID_VER(ids[ID_KEY(id)])
    end

    function registry:orphaned(id: Entity): boolean
        local key = ID_KEY(id)
        for _, pool in next, pools do
            if pool.map[key] then return false end
        end
        return true
    end

    function registry:add<T...>(id: Entity, ...: T...)
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = pools[ctype]
            if pool.map[key] then continue end

            local constructor = ctype_constructors[ctype] or ERROR(`no constructor defined for {ctype_debug(ctype, i)}`)
            local value = constructor()
            if value == nil then ERROR(`{ ctype_debug(ctype, i) } constructor did not return a value`) end

            add(ctype, pool, key, id, value)
            fire_added(ctype, id, value)
        end
    end

    function registry:set<T>(id: Entity, ctype: T, value: T?)
        local pool = pools[ctype] :: Pool<T>
        local key = ID_KEY(id)
        local idx_ver = pool.map[key]
        
        if value ~= nil then
            if idx_ver then
                local idx = ID_KEY(idx_ver)
                ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)
                pool.values[idx] = value
                fire_changed(ctype, id, value)
            else
                ASSERT_VALID_ENTITY(key, id)
                add(ctype, pool, key, id, value)
                fire_added(ctype, id, value)
            end
        elseif idx_ver then
            local idx = ID_KEY(idx_ver)
            ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)
            fire_removing(ctype, id)
            remove(ctype, pool, idx, key, id)
        end
    end
    
    function registry:patch<T>(id: Entity, ctype: T, patcher: (T) -> T?)
        local pool = pools[ctype] :: Pool<T>
        local key = ID_KEY(id)
        local idx_ver = pool.map[key] :: number
        if idx_ver == nil then ERROR("entity does not have component") end
        local idx = ID_KEY(idx_ver)

        ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)

        local values = pool.values
        local value = patcher(values[idx])
        if value == nil then ERROR("patcher cannot return nil") end

        values[idx] = value :: T
        fire_changed(ctype, id, value)
    end

    registry.has = (function(self: Registry, id: Entity, ...: unknown): boolean
        local a, b = ...
        local key = ID_KEY(id)
        if b == nil then
            local idx_ver = pools[a].map[key]
            return idx_ver ~= nil and check_versions_equal(ID_KEY(idx_ver), idx_ver, key, id)
        else
            for i = 1, select("#", ...) do
                local idx_ver = pools[select(i, ...)].map[key]
                if idx_ver == nil or not check_versions_equal(ID_KEY(idx_ver), idx_ver, key, id) then return false end
            end
            return true
        end  
    end :: any) :: <T...>(self: Registry, id: Entity, T...) -> boolean

    local function pool_safe_get(ctype: CType, key: number, id: number): unknown
        local pool = pools[ctype]
        local idx_ver = pool.map[key]
        if idx_ver == nil then ERROR(`entity does not have {ctype_debug(ctype, 1)}`) end
        local idx = ID_KEY(idx_ver :: number)
        ASSERT_VERSIONS_EQUAL(idx, idx_ver :: number, key, id)
        return pool.values[idx]
    end

    local function pool_get(ctype: CType, key: number, id: number): unknown
        local pool = pools[ctype]
        local idx_ver = pool.map[key]
        if idx_ver == nil then ERROR(`entity does not have {ctype_debug(ctype)}`) end
        return pool.values[ID_KEY(idx_ver:: number)]
    end

    registry.get = (function(self: Registry, id: Entity, ...: unknown): ...unknown
        local a, b, c, d, e = ...
        local key = ID_KEY(id)
        if b == nil then
            return pool_safe_get(a, key, id)
        elseif c == nil then
            return pool_safe_get(a, key, id), pool_get(b, key, id)
        elseif d == nil then
            return pool_safe_get(a, key, id), pool_get(b, key, id), pool_get(c, key, id)
        elseif e == nil then
            return pool_safe_get(a, key, id), pool_get(b, key, id), pool_get(c, key, id), pool_get(d, key, id)
        else
            local tuple: Array<any> = { ... }
            for i, v in next, tuple do
                tuple[i] = pool_get(v, key, id)
            end
            return unpack(tuple)
        end
    end :: any) :: <T...>(self: Registry, id: Entity, T...) -> T...

    function registry:try_get<T>(id: Entity, ctype: T): T?
        local key = ID_KEY(id)
        local pool = pools[ctype]
        local idx_ver = pool.map[key]
        if idx_ver == nil then return nil end
        local idx = ID_KEY(idx_ver)
        ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)
        return pool.values[idx] :: T
    end

    function registry:remove<T...>(id: Entity, ...: T...)
        local key = ID_KEY(id)
        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = pools[ctype]
            local idx_ver = pool.map[key] :: number
            if idx_ver == nil then continue end

            local idx = ID_KEY(idx_ver)
            ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)
            
            fire_removing(ctype, id)
            remove(ctype, pool, idx, key, id)
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
            release_all()
        end 
    end

    function registry:view<T...>(...: T...): View<T...>
        return View.new(registry, ...)
    end 

    function registry:track<T...>(...: T...): Observer<T...>
        return Observer.new(registry, ...)
    end

    function registry:group<T...>(...: T...): Group<T...>
        local argn = select("#", ...)
        ASSERT(argn > 1, "groups must contain at least 2 components")
        local group = groups[select(1, ...)]

        for i = 1, argn do
            local ctype = select(i, ...)
            ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
            ASSERT(groups[ctype] == group,
                `cannot create group; { ctype_debug(ctype, i) } is not owned by the same group as previous args`)
        end

        return Group.new(registry, group or group_init(...), ...)
    end

    function registry:entities(): Array<Entity>
        local entities = table.create(size)

        for i, id in next, ids do
            if ID_KEY(id) == i then
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
            added_listeners[ctype] = listeners
            return signal
        end)()) :: Signal<Entity, T>
    end

    function registry:changed<T>(ctype: T): Signal<Entity, T>
        return (signals.changed[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.changed[ctype] = signal
            changed_listeners[ctype] = listeners
            return signal    
        end)()) :: Signal<Entity, T>    
    end

    function registry:removing<T>(ctype: T): Signal<Entity, nil>
        return signals.removing[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.removing[ctype] = signal
            removing_listeners[ctype] = listeners
            return signal
        end)() :: Signal<Entity, nil>
    end

    function registry:handle(entity: Entity?): Handle
        return table.freeze(setmetatable({
            registry = self,
            entity = entity or self:create()
        }, Handle))
    end

    -- test method
    (registry :: any).set_entity_version = function(_, key: number, ver: number)
        ids[key] = ID_CREATE(ID_KEY(ids[key]), ver)
    end

    setmetatable(registry :: any, { __index = function(_, index)
        ERROR(`"{ tostring(index) }" is not a valid member of Registry`)    
    end })

    return table.freeze(registry)
end

------------------------------------------------------------------------------------------------------------------------
-- Queue
------------------------------------------------------------------------------------------------------------------------

local Queue = {} do
    Queue.__index = Queue

    type _Queue = Queue<...unknown> & {
        size: number,
        columns: Array<Array<unknown>>
    }

    function Queue.new(): Queue<...unknown>
        local self: _Queue = setmetatable({
            size = 0,
            columns = {}
        }, Queue) :: any

        -- create new column lazily on nil index to avoid
        -- having to check when adding every time
        setmetatable(self.columns, {
            __index = function(columns: Array<Array<unknown>>, idx: number)
                local new = {}
                columns[idx] = new
                return new
            end
        })

        return self
    end

    function Queue.add(self: _Queue, ...: unknown)
        -- otherwise value will not be returned during iteration
        if ... == nil then ERROR("first value cannot be nil") end

        local columns = self.columns
        local n = self.size + 1; self.size = n

        for i = 1, select("#", ...) do
            local arg = select(i, ...)
            columns[i][n] = arg
        end
    end

    function Queue.clear(self: _Queue)
        self.size = 0
        for _, column in next, self.columns do
            table.clear(column)
        end
    end

    function Queue.__len(self: _Queue)
        return self.size
    end

    function Queue.__iter(self: _Queue)
        local n = self.size
        local i = 0
        local columns = self.columns

        if #columns == 0 then
            return function() end

        elseif #columns == 1 then
            local column = columns[1]
            return function()
                i += 1
                if i == n then return self:clear() end
                return column[i]
            end

        else--if #columns > 1 then
            local tuple = {}
            return function()
                i += 1
                if i == n then return self:clear() end
                for ci, column in next, columns do
                    tuple[ci] = column[i]
                end
                return unpack(tuple)
            end
        end
    end
end

type SignalInterface<T...> = {
    connect: (self: SignalInterface<T...>, listener: (T...) -> ()) -> ()
} | {
    Connect: (self: SignalInterface<T...>, listener: (T...) -> ()) -> ()
}

local queue_create = function(signal: SignalInterface<...any>?)
    local queue = Queue.new()

    -- todo: fix type error
    if signal then
        local connector = (signal :: any).connect or (signal :: any).Connect
        ASSERT(connector, "signal has no connector")
        connector(signal, function(...: unknown)
            queue:add(...)
        end)
    end

    return queue
end :: ( () -> Queue<...unknown> ) & ( <T...>(signal: SignalInterface<T...>) -> Queue<T...> )

------------------------------------------------------------------------------------------------------------------------
-- Return
------------------------------------------------------------------------------------------------------------------------

local ecr = {
    component = ctype_create :: (() -> unknown) & (<T>(constructor: () -> T) -> T),
    registry = registry_create,
    queue = queue_create,
    null = ID_NULL,

    name = function<T>(names: T & {}): T
        for name, ctype in next, names do
            ctype_name(ctype, name)
        end
        table.freeze(names)
        return names
    end
}

-- test functions
(ecr :: any).id = ID_CREATE


return table.freeze(ecr)
