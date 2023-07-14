--------------------------------------------------------------------------------
-- ecr.luau
-- v0.6.1
--------------------------------------------------------------------------------

local ID_SIZE_BITS = 53
local MAX_ENTITIES = 0x000F_FFFF
local INIT_STORAGE_SIZE = 100

assert(ID_SIZE_BITS <= 53 and ID_SIZE_BITS > 1)
assert(MAX_ENTITIES < 0xFFFF_FFFF and MAX_ENTITIES > 0)
assert(bit32.band(MAX_ENTITIES + 1, MAX_ENTITIES) == 0)

type Array<T> = { [number]: T }
type Map<T, U> = { [T]: U }

type CType = unknown
export type Entity = number

export type Signal<T...> = {
    connect: (self: Signal<T...>, self: (T...) -> ()) -> Connection,
}

export type Connection = {
    disconnect: (self: Connection) -> ()
}

type Listener<T> = (id: Entity, value: T) -> ()

type Pool<T> = {
    size: number,
    map: Array<number?>,
    entities: Array<Entity>,
    values: Array<T>,

    added: Array<Listener<T>> | false,
    changed: Array<Listener<T>> | false,
    removing: Array<Listener<nil>> | false,
    group: GroupData<T> | false
}

type GroupData<T = unknown> = {
    size: number,
    added: boolean,
    [number]: Pool<T>
}

export type Handle = typeof(setmetatable(
    {} :: { registry: Registry, entity: Entity },
    {} :: HandleMT
))

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

export type Group<T...> = typeof(setmetatable({} :: {
}, {} :: {
    __iter: (self: Group<T...>) -> () -> (Entity, T...),
    __len: (self: Group<T...>) -> number     
}))

export type Registry = typeof(setmetatable({} :: {
    create: ((self: Registry, id: Entity) -> Entity) & ((self: Registry) -> Entity),
    release: (self: Registry, id: Entity) -> (),
    destroy: (self: Registry, id: Entity) -> (),
    contains: (self: Registry, id: Entity) -> boolean,

    orphaned: (self: Registry, id: Entity) -> boolean,
    add: <T...>(self: Registry, id: Entity, T...) -> (),
    set: <T>(self: Registry, id: Entity, ctype: T, value: T?) -> (),
    patch: <T>(self: Registry, id: Entity, ctype: T, patcher: (T) -> T) -> (),
    has: <T...>(self: Registry, id: Entity, T...) -> boolean,
    get: <T...>(self: Registry, id: Entity, T...) -> T...,
    try_get: <T>(self: Registry, id: Entity, T) -> T?,
    remove: <T...>(self: Registry, id: Entity, T...) -> (),

    view: <T...>(self: Registry, T...) -> View<T...>,
    track: <T...>(self: Registry, T...) -> Observer<T...>,
    group: <T...>(self: Registry, T...) -> Group<T...>,

    clear: <T...>(self: Registry, T...) -> (),
    storage: <T>(self: Registry, ctype: T) -> Pool<T>,

    added: <T>(self: Registry, ctype: T) -> Signal<Entity, T>,
    changed: <T>(self: Registry, ctype: T) -> Signal<Entity, T>,
    removing: <T>(self: Registry, ctype: T) -> Signal<Entity, nil>,

    handle: ((self: Registry, id: Entity) -> Handle) & ((self: Registry) -> Handle),
    context: (self: Registry) -> Handle
}, {} :: {
    __iter: (self: Registry) -> () -> Entity,
    __len: (self: Registry) -> number
}))

export type Queue<T...> = typeof(setmetatable({} :: {
    add: (self: Queue<T...>, T...) -> (),
    clear: (self: Queue<T...>) -> ()
}, {} :: {
    __iter: (self: Queue<T...>) -> () -> (T...),
    __len: (self: Queue<T...>) -> number  
}))

-- error trace will always begin at callsite outside of file
local ERROR = function<T>(msg: T): never
    local stack = 1

    while debug.info(stack, "s") == debug.info(1, "s") do
        stack += 1    
    end

    error(msg, stack)  
end :: typeof(error)

local ASSERT = function<T>(v: T, msg: string): T
    if v then return v end
    ERROR(msg)
    return nil :: never
end :: typeof(assert)

local function strict(name: string)
    return function(_, idx: unknown)
        ERROR(`{tostring(idx)} is not a valid member of {name}`)
    end
end

--------------------------------------------------------------------------------
-- Entity Id
--------------------------------------------------------------------------------

local ID_MAX = 2^ID_SIZE_BITS - 1

local ID_INIT_VER = 1
local ID_INVALID_KEY = 0

local ID_MASK_KEY = MAX_ENTITIES
local ID_MASK_VER = ID_MAX - ID_MASK_KEY

local ID_LSHIFT = ID_MASK_KEY + 1
local ID_RSHIFT = 1/ID_LSHIFT

local ID_MAX_KEY = ID_MASK_KEY
local ID_MAX_VER = ID_MASK_VER * ID_RSHIFT

local function ID_CREATE(key: number, ver: number): number
    --assert(key <= ID_MAX_KEY)
    --assert(ver <= ID_MAX_VER)
    return ver * ID_LSHIFT + key
end

local function ID_KEY(id: number): number
    return bit32.band(id, ID_MASK_KEY)
end

local function ID_KEY_VER(id: number): (number, number)
    local key = ID_KEY(id)
    local ver = (id - key) * ID_RSHIFT
    return key, ver
end

local function ID_VER(id: number): number
    return (id - ID_KEY(id)) * ID_RSHIFT
end

local function ID_SWAPKEY(id: number, key: number): number
    return id - ID_KEY(id) + key
end

local ID_NULL = ID_CREATE(0, ID_MAX_VER)
local ID_CONTEXT = ID_CREATE(0, 1)

--------------------------------------------------------------------------------
-- Component Type
--------------------------------------------------------------------------------

local ctype_n = 0
local ctype_names: Map<CType, string> = {}
local ctype_constructors: Map<CType, ((() -> unknown) | nil | true)> = table.create(1e3)

-- a constructor set to `ctype_TAG` indicates that the component is a tag
local ctype_TAG: true = true

local function ctype_create<T>(constructor: (() -> T)? | true): CType
    ctype_n += 1
    ctype_constructors[ctype_n] = constructor 
    return ctype_n
end

local function ctype_tag(): CType
    return ctype_create(true)
end

local function ctype_is_tag(ctype: CType): boolean
    return ctype_constructors[ctype] == true
end

local function ctype_valid(v: unknown): boolean
    return type(v) == "number" and math.floor(v) == v and v > 0 and v <= ctype_n  
end

local function ctype_name(ctype: CType, name: unknown)
    ctype_names[ctype] = tostring(name)
end

local function ctype_debug(ctype: CType?, idx: number?)
    local name = ctype_names[ctype]
    return
        if name then `component "{name}"`
        elseif idx then `component (arg #{idx})`
        else "component (unknown)"
end

local ctype_entity = ctype_tag()
ctype_name(ctype_entity, "entity")

--------------------------------------------------------------------------------
-- Pool
--------------------------------------------------------------------------------

local function fire<T>(listeners: Array<Listener<T>>, id: Entity, value: T)
    for i = #listeners, 1, -1 do
        listeners[i](id, value)         
    end 
end

local function check_versions_equal(idx: number, idx_ver: number, key: number, id: number): boolean
    return idx_ver - idx + key == id
end

local function ASSERT_VERSIONS_EQUAL(idx: number, idx_ver: number, key: number, id: number)
    if idx_ver - idx + key ~= id then
        ASSERT(false, `invalid entity`)    
    end
end

local function ASSERT_VALID_ENTITY(key: number, id: Entity, map: Array<Entity>)
    local idx_ver = map[key]
    if idx_ver <= 0 or check_versions_equal(ID_KEY(idx_ver), idx_ver, key, id) == false then
        ASSERT(false, `invalid entity`)
    end
end

local function pool_swap<T>(
    self: Pool<T>,
    idx: number,
    key: number,
    id: number,
    target_idx: number
)
    local map = self.map
    local entities = self.entities
    local values = self.values

    local id_swap = entities[target_idx]
    
    entities[target_idx], entities[idx] = id, id_swap
    values[target_idx], values[idx] = values[idx], values[target_idx]
    map[key] = ID_SWAPKEY(id, target_idx)
    map[ID_KEY(id_swap)] = ID_SWAPKEY(id_swap, idx)
end

local function group_try_add<T>(group: GroupData<T>, key: number, id: number)
    for _, pool in ipairs(group) do
        if pool.map[key] == nil then
            return
        end
    end

    local n = group.size + 1
    group.size = n

    group.added = true

    for _, pool in ipairs(group) do
        pool_swap(pool, ID_KEY(pool.map[key] :: number), key, id, n)
    end
end

-- returns new internal index of id
local function group_try_remove<T>(group: GroupData<T>, index: number, key: number, id: number): number
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

local function pool_create<T>(size: number?): Pool<T>
    local n = size or 1
    return {
        size = 0,
        map = table.create(n),
        entities = table.create(n),
        values = table.create(n),

        added = false,
        changed = false,
        removing = false,
        group = false
    }
end

local function pool_unsafe_add<T>(self: Pool<T>, key: number, id: Entity, v: T)
    local n = self.size + 1; self.size = n
    self.map[key] = ID_SWAPKEY(id, n)
    self.entities[n] = id
    self.values[n] = v

    if self.group then group_try_add(self.group, key, id) end
    if self.added then fire(self.added, id, v) end
end

-- adds id and value to pool, or changes value if already added
-- errors if id is invalid
local function pool_safe_set<T>(self: Pool<T>, id: Entity, v: T, ids: Array<Entity>)
    local key = ID_KEY(id)
    local idx_ver = self.map[key]

    if idx_ver then -- already added, change value
        local idx = ID_KEY(idx_ver)
        ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)
        self.values[idx] = v
        if self.changed then fire(self.changed, id, v) end
    else -- not added, add value
        ASSERT_VALID_ENTITY(key, id, ids)
        pool_unsafe_add(self, key, id, v)
    end
end

local function pool_unsafe_remove_key<T>(self: Pool<T>, key: number, id: Entity)
    local idx_ver = self.map[key]

    if idx_ver then
        if self.removing then fire(self.removing, id) end

        local idx = ID_KEY(idx_ver)

        if self.group then
            idx = group_try_remove(self.group, idx, key, id)
        end

        local n = self.size; self.size = n - 1
        local map = self.map
        local entities = self.entities
        local values = self.values

        local lastid = entities[n]
        map[ID_KEY(lastid)] = ID_SWAPKEY(lastid, idx); map[key] = nil
        entities[idx] = lastid; entities[n] = nil
        values[idx] = values[n]; values[n] = nil
    end
end

local function pool_safe_remove<T>(self: Pool<T>, id: Entity)
    local key = ID_KEY(id)

    local map = self.map
    local entities = self.entities
    local values = self.values

    local idx_ver = map[key]

    if idx_ver then
        if self.removing then fire(self.removing, id) end

        local idx = ID_KEY(idx_ver)
        ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)

        if self.group then
            idx = group_try_remove(self.group, idx, key, id)
        end
    
        local n = self.size; self.size = n - 1
        local lastid = entities[n]
        map[ID_KEY(lastid)] = ID_SWAPKEY(lastid, idx); map[key] = nil
        entities[idx] = lastid; entities[n] = nil
        values[idx] = values[n]; values[n] = nil
    end
end

local function pool_safe_patch<T>(
    self: Pool<T>,
    id: Entity,
    fn: (T) -> T,
    ids: Array<Entity>,
    ctype: T
)
    local key = ID_KEY(id)
    local idx_ver = self.map[key]
    
    if idx_ver == nil then
        ASSERT_VALID_ENTITY(key, id, ids)
        local ctor = ctype_constructors[ctype]
        if ctor == nil or ctor == ctype_TAG then
            ERROR(`entity does not have component and no constructor for {ctype_debug(ctype)}`)
        end
        local value = fn((ctor :: () -> T)())
        if value == nil then ERROR("patcher cannot return nil") end
        pool_unsafe_add(self, key, id, value)
    else
        local idx = ID_KEY(idx_ver)
        ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)
        local value = fn(self.values[idx])
        if value == nil then ERROR("patcher cannot return nil") end
        self.values[idx] = value
        if self.changed then
            fire(self.changed, id, value)
        end
    end
end

local function pool_safe_try_get<T>(self: Pool<T>, id: Entity): T?
    local key = ID_KEY(id)
    local idx_ver = self.map[key]
    if idx_ver then
        local idx = ID_KEY(idx_ver)
        ASSERT_VERSIONS_EQUAL(idx, idx_ver, key, id)
        return self.values[idx]
    end
    return nil
end

local function pool_raw_add_id<T>(self: Pool<T>, id: Entity)
    local map = self.map

    local key = ID_KEY(id)
    local idx_ver = map[key]

    if idx_ver == nil then
        local n = self.size + 1; self.size = n
        map[key] = ID_SWAPKEY(id, n)
        self.entities[n] = id
    end 
end

local function pool_raw_remove_id<T>(self: Pool<T>, id: Entity)
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

local function pool_clear<T>(self: Pool<T>)
    if self.removing then
        for _, id in next, self.entities do
            fire(self.removing, id)
        end
    end

    if self.group then
        self.group.size = 0
    end

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
        values = table.clone(self.values),

        added = false,
        changed = false,
        removing = false,
        group = false
    }
end

type EntityPool = Pool<nil> & {
    capacity: number,
    free: number
}

local function entity_pool_create(): EntityPool
    local pool = pool_create() :: EntityPool
    pool.capacity = 0
    pool.free = ID_INVALID_KEY
    return pool
end

local function entity_pool_add(self: EntityPool): Entity
    local size = self.size + 1; self.size = size
    local free = self.free
    local id
    if free ~= ID_INVALID_KEY then -- reuse
        local data = - self.map[free] :: number
        local next_key = ID_KEY(data)
        id = ID_SWAPKEY(data, free)
        self.map[free] = ID_SWAPKEY(data, size)
        self.free = next_key
    else -- create new
        self.capacity += 1
        local key = self.capacity
        id = ID_CREATE(key, ID_INIT_VER)
        self.map[key] = ID_CREATE(size, ID_INIT_VER)
    end

    self.entities[size] = id
    if self.added then fire(self.added, id) end

    return id
end

local function entity_pool_reuse(self: EntityPool, id: Entity): Entity
    -- todo: assert valid
    local key, ver = ID_KEY_VER(id)
        ASSERT(
            key >= 1 and ver >= 1 and
            key <= ID_MAX_KEY and ver <= ID_MAX_VER,
            "malformed id"
        )

        local capacity = self.capacity
        local map = self.map :: Array<number>

        local free = self.free

        if key > capacity then -- if key has not been created yet
            if key > capacity + 1 then -- fill in gaps between last and new
                for i = capacity + 1, key - 2 do
                    map[i] = - ID_CREATE(i + 1, ID_INIT_VER)
                end
                map[key - 1] = - ID_CREATE(free, ID_INIT_VER)
                self.free = capacity + 1
            end
            self.capacity = key
        elseif key <= capacity then -- if key has been created before
            if map[key] == - ID_NULL then -- id is deprecated -- todo: test
               -- map[key] = id   
            else
                ASSERT(
                    free ~= ID_INVALID_KEY -- an unused key exists
                    and map[key] <= 0, -- desired key is not in use
                    "key is already in use"
                )   
                if free == key then -- if desired id is at head
                    local next_key = ID_KEY(- map[free])
                    self.free = next_key
                else -- desired id is somewhere along list
                    local previous = free
                    local i = 0
                    while true do -- find element before desired id
                        i += 1
                        --if - map[previous] > 0 then error(i) end
                        local next = ID_KEY(- map[previous])
                        if next == key then break end
                        previous = next
                    end
                    map[previous] = - ID_SWAPKEY(- map[previous], ID_KEY(- map[key]))
                end
            end
            
        end
        local n = self.size + 1; self.size = n
        map[key] = ID_SWAPKEY(id, n)
        self.entities[n] = id
        if self.added then fire(self.added, id) end
        return id
end

local function entity_pool_remove(self: EntityPool, id: Entity)
    local key, ver = ID_KEY_VER(id)

    if self.removing then fire(self.removing, id) end

    local n = self.size; self.size = n - 1

    local map = self.map :: Array<number>
    local entities = self.entities

    -- todo: assert valid

    local idx = ID_KEY(map[key]) --
    local last_id = entities[n]
    local last_key = ID_KEY(last_id)
    entities[idx] = last_id; entities[n] = nil
    map[last_key] = ID_SWAPKEY(last_id, idx)


    if ver < ID_MAX_VER then
        map[key] = - ID_CREATE(self.free, ver + 1) -- recycle key
        self.free = key
    else
        map[key] = - ID_NULL -- permanently deprecate key
    end

   
end

local function entity_pool_has(self: EntityPool, id: number): boolean
    local key = ID_KEY(id)
    local data = self.map[key] :: number
    return data > 0 and ID_SWAPKEY(data, key) == id
end

local function entity_pool_clear(self: EntityPool)
    local entities = self.entities

    if self.removing then
        for i = self.size, 1, -1 do
            fire(self.removing, entities[i])
        end
    end

    for i = self.size, 1, -1 do
        entity_pool_remove(self, entities[i])
    end
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

local View, Observer, Group do

type IRegistry = typeof(setmetatable({} :: {
    storage: <T>(self: IRegistry, ctype: T) -> Pool<T>,
    added: <T>(self: IRegistry, ctype: T) -> Signal<Entity, T>,
    changed: <T>(self: IRegistry, ctype: T) -> Signal<Entity, T>,
    removing: <T>(self: IRegistry, ctype: T) -> Signal<Entity, nil>,
}, {}))

local WEAK_VALUES = { __mode = "v" }

-- checks if any of the given pools contain a key
local function has_any(pools: Array<Pool<unknown>>, key: number): boolean
    for _, pool in next, pools do
        if pool.map[key] then return true end
    end
    return false
end

-- gets the smallest pool from an array of pools
local function smallest(pools: Array<Pool<unknown>>): Pool<unknown>
    local s: Pool<unknown>?
    for _, pool in next, pools do
        s = if s == nil or pool.size < s.size then pool else s
    end
    return assert(s, "no pools given")
end

-- gets an array of pools given an array of ctypes
local function get_ctype_pools(
    registry: IRegistry,
    ctypes: Array<CType>
): Array<Pool<unknown>>
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

local function clear_invalidation_flag<T>(pool: Pool<T>)
    if pool.group then pool.group.added = false end
end

local function ASSERT_INVALIDATION<T>(pool: Pool<T>): ...any
    if pool.group and pool.group.added then
        pool.group.added = false
        ASSERT(false, "group reordered during iteration, iterator invalidaton occurred")
    end
end

-- specialized single-type view iterator
local function single<A>(pool: Pool<A>): () -> (Entity, A)
    local n = pool.size
    local entities = pool.entities
    local values = pool.values

    clear_invalidation_flag(pool)

    return function()
        local i = n; n = i - 1
        return entities[i] or ASSERT_INVALIDATION(pool), values[i]
    end
end

-- specialized double-type view iterator
local function double<A, B>(a: Pool<A>, b: Pool<B>): () -> (Entity, A, B)
    local na, nb = a.size, b.size

    if na <= nb then
        local n = na
        local entities = a.entities
        local values = a.values

        clear_invalidation_flag(a)

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
            return ASSERT_INVALIDATION(a)
        end
    else
        local n = nb
        local entities = b.entities
        local values = b.values

        clear_invalidation_flag(b)

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
            return ASSERT_INVALIDATION(b)
        end
    end
end

-- generic multi-type view iterator
local function multi(
    includes: Array<Pool<unknown>>,
    excludes: Array<Pool<unknown>>?,
    lead: Pool<unknown>?
): () -> (Entity, ...any)
    local source = lead or smallest(includes)

    local n = source.size
    local entities = source.entities
    local tuple = table.create(#includes)

    clear_invalidation_flag(source)

    return function()
        for i = n, 1, -1 do
            local entity = entities[i]
            local key = ID_KEY(entity)
            
            if excludes and has_any(excludes, key) then continue end

            local has_all = true
            for ii, pool in next, includes do
                local idx_ver = pool.map[key]
                if idx_ver == nil then has_all = false; break end
                tuple[ii] = pool.values[ID_KEY(idx_ver :: number)]
            end
            if has_all == false then continue end

            n = i - 1
            return entity, unpack(tuple)
        end
        return ASSERT_INVALIDATION(source)
    end
end

type _View<T...> = typeof(setmetatable({} :: {
    registry: IRegistry,
    includes: Array<CType>,
    excludes: Array<CType>?,
    lead: CType?,
    
    exclude: <U...>(_View<T...>, U...) -> _View<T...>,
    use: <T>(_View<T...>, T) -> _View<T...>,
}, {} :: {
    __iter: (_View<T...>) -> () -> (Entity, T...),
    __len: (_View<T...>) -> number  
}))

View = {}
View.__index = View

function View.new<T...>(reg: IRegistry, ...: T...): View<T...>
    assert(select("#", ...) > 0, "no components given")

    local self: _View<T...> = setmetatable({
        registry = reg,
        includes = {},
        excludes = nil,
        lead = nil,

        exclude = function<E...>(self: _View<T...>, ...: E...): _View<T...>
            local includes = self.includes
            local excludes = self.excludes or (function()
                local t = {} 
                self.excludes = t
                return t
            end)()

            for i = 1, select("#", ...) do
                local ctype = select(i, ...)
                ASSERT(ctype_valid(ctype), `invalid {ctype_debug(nil, i)}`)
                ASSERT(not table.find(includes, ctype), `cannot exclude {ctype_debug(ctype, i)}, component is a part of the view`)
                if table.find(excludes, ctype) then continue end
                table.insert(excludes, ctype)
            end

            return self
        end,

        use = function<T>(self: _View<T...>, ctype: T): _View<T...>
            ASSERT(ctype_valid(ctype), `invalid component type`)
            ASSERT(table.find(self.includes, ctype), "cannot lead with component; component is not a part of the view")
            self.lead = ctype
            return self
        end
    }, {
        __iter = function(self: _View<T...>): () -> (Entity, T...)
            local includes = get_ctype_pools(self.registry, self.includes)
            local excludes = self.excludes and get_ctype_pools(self.registry, self.excludes)
            local lead = self.lead and self.registry:storage(self.lead)
    
            return if #includes == 1 and not excludes and not lead then
                    single(includes[1])
                elseif #includes == 2  and not excludes and not lead then 
                    double(includes[1], includes[2])
                else
                    multi(includes, excludes, lead)   
        end,

        __len = function(self: _View<T...>): number
            return smallest(get_ctype_pools(self.registry, self.includes)).size
        end,

        --__index = strict("View")
    })

    local includes = self.includes

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)

        if not ctype_valid(ctype) then
            ERROR(`invalid { ctype_debug(nil, i) }`)
        end

        if table.find(includes, ctype) then
            ERROR(`duplicate { ctype_debug(ctype, i) } included`)
        end

        table.insert(includes, ctype)
    end

    return self
end

type _Observer<T...> = typeof(setmetatable({} :: {
    registry: IRegistry,
    pool: Pool<unknown>,
    includes: Array<CType>,
    excludes: Array<CType>?,
    connections: Array<Connection>?,
    persistent: boolean,

    exclude: <U...>(_Observer<T...>, U...) -> _Observer<T...>,
    disconnect: (_Observer<T...>) -> _Observer<T...>,
    reconnect: (_Observer<T...>) -> _Observer<T...>,

    persist: (_Observer<T...>) -> _Observer<T...>,
    clear: (_Observer<T...>) -> _Observer<T...>,
}, {} :: {
    __iter: (_Observer<T...>) -> () -> (Entity, T...),
    __len: (_Observer<T...>) -> number
}))

Observer = {}
Observer.__index = Observer

function Observer.new<T...>(reg: IRegistry, ...: T...): Observer<T...>
    local ctype_first = select(1, ...) :: unknown

    local self: _Observer<T...> = setmetatable({
        registry = reg,
        pool = pool_clone(reg:storage(ctype_first)),
        includes = {},
        excludes = nil,
        connections = nil,
        persistent = false,

        exclude = function<E...>(self: _Observer<T...>, ...: E...): _Observer<T...>
            local excludes = self.excludes or (function()
                local t = {} 
                self.excludes = t
                return t
            end)()
        
            for i = 1, select("#", ...) do
                local ctype = select(i, ...)

                if not ctype_valid(ctype) then
                    ERROR(`invalid { ctype_debug(nil, i) }`)
                end

                if table.find(self.includes, ctype) then
                    ERROR(`cannot exclude { ctype_debug(ctype, i) }, component is being tracked`)
                end

                if table.find(excludes, ctype) then continue end
                table.insert(excludes, ctype)
            end
        
            return self
        end,

        disconnect = function(self: _Observer<T...>): _Observer<T...>
            if not self.connections then return self end
            disconnect_all(self.connections)
            self.connections = nil
            return self
        end,

        reconnect = function(self: _Observer<T...>): _Observer<T...>
            if self.connections then return self end

            local reg = self.registry
            local pool = self.pool
            local includes = self.includes

            local connections = {}

            for i, ctype in includes do
                local function listener(id)
                    pool_raw_add_id(pool, id)
                end
                
                table.insert(connections, reg:added(ctype):connect(listener))
                table.insert(connections, reg:changed(ctype):connect(listener))
            end

            self.connections = connections

            return self
        end,

        persist = function(self: _Observer<T...>): _Observer<T...>
            self.persistent = true
            return self
        end,

        clear = function(self: _Observer<T...>): _Observer<T...>
            pool_clear(self.pool)
            return self
        end
    }, {
        __iter = function(self: _Observer<T...>): () -> (Entity, T...)
            local pool = self.pool
            local reg = self.registry
            local includes = get_ctype_pools(reg, self.includes)
            local excludes = self.excludes and get_ctype_pools(reg, self.excludes)
            local persist = self.persistent
        
        
            local n = pool.size
            local entities = pool.entities
        
            local reg_pool = includes[1]
            local reg_map = reg_pool.map
            local reg_values = reg_pool.values
        
            local tuple = table.create(#includes) :: Array<any>
        
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
                                tuple[ii] = pool.values[ID_KEY(idx_ver :: number)]
                            end
                            if has_all == false then continue end
        
                            n = i - 1
                            return id, unpack(tuple)
                        end
                        if not persist then self:clear() end
                    return nil :: any, nil :: any
                end
        end,

        __len = function(self: _Observer<T...>): number
            return self.pool.size
        end,

        --__index = strict("Observer")
    })

    local includes = self.includes

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)
        ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
        ASSERT(not table.find(includes, ctype), `duplicate { ctype_debug(ctype, i) } included`)
        table.insert(includes, ctype)
    end

    local connections = {}
    local pool = self.pool
    local weakref = setmetatable({ self = self }, WEAK_VALUES) :: any
    local function try_remove(id: number)
        if weakref.self == nil then disconnect_all(connections) end
        pool_raw_remove_id(pool, id)
    end

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)
        table.insert(connections, reg:removing(ctype):connect(try_remove))
    end

    return self:reconnect() :: any
end

type _Group<T...> = typeof(setmetatable({} :: {
    data: GroupData,
    pools: Array<Pool<unknown>>
}, {} :: {
    __iter: (self: _Group<T...>) -> () -> (Entity, T...),
    __len: (self: _Group<T...>) -> number     
}))

Group = {}
Group.__index = Group

function Group.new<T...>(reg: Registry, data: GroupData, ...: T...): Group<T...>
    local self: _Group<T...> = setmetatable({
        data = data,
        pools = {}
    }, {
        __iter = function(self: _Group<T...>): () -> (Entity, T...)
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
        end,

        __len = function(self: _Group<T...>): number
            return self.data.size
        end,

        --__index = strict("Group")
    })

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)
        local pool = reg:storage(ctype)
        assert(table.find(data, pool), "component type is not in group")
        self.pools[i] = pool 
    end

    return self
end

end

--------------------------------------------------------------------------------
-- Signal
--------------------------------------------------------------------------------

local signal_create: <T...>() -> (Signal<T...>, Array<(T...) -> ()>) do
    type _Signal<T...> = {
        pool: Pool<(T...) -> ()>,
        count: number,

        connect: (_Signal<T...>, (T...) -> ()) -> _Connection<T...>,
    }
    
    type _Connection<T... = ...unknown> = {
        signal: _Signal<T...>,
        id: number,

        disconnect: (_Connection<T...>) -> ()
    }

    local Connection = {}
    

    function Connection.new<T...>(signal: _Signal<T...>, id: number): _Connection<T...>
        return {
            signal = signal,
            id = id,

            disconnect = function(self: _Connection<T...>)
                pool_safe_remove(self.signal.pool, self.id)
            end
        }
    end

    local Signal = {}

    function Signal.new<T...>(): _Signal<T...>
        local self: _Signal<T...> = {
            pool = pool_create(),
            count = 0,

            connect = function(self: _Signal<T...>, listener: (T...) -> ()): _Connection<T...>
                local n = self.count + 1; self.count = n
                pool_unsafe_add(self.pool, n, n, listener)
                return Connection.new(self, n)  
            end
        }

        return self
    end

    function signal_create<T...>(): Signal<T...>
        local signal = Signal.new()
        return signal :: any, signal.pool.values
    end
end

--------------------------------------------------------------------------------
-- Handle
--------------------------------------------------------------------------------

local Handle = (function(): HandleMT
    local Handle = {}
    Handle.__index = Handle

    setmetatable(Handle :: any, { __index = strict("Handle") })

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

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

local function registry_create(): Registry
    local registry = {}

    local id_pool = entity_pool_create()

    id_pool.map[0] = ID_CONTEXT

    local all_pools: Map<CType, Pool<unknown>> = table.create(ctype_n)
    local ctype_pools: Map<CType, Pool<unknown>> = table.create(ctype_n)

    local groups: Map<CType, GroupData?> = table.create(ctype_n) -- todo: is this needed?

    local signals = {
        added = {} :: Map<CType, Signal<Entity, unknown>>,
        changed = {} :: Map<CType, Signal<Entity, unknown>>,
        removing = {} :: Map<CType, Signal<Entity, nil>>
    }

    all_pools[ctype_entity] = id_pool :: Pool<any>

    -- lazily create pools on nil index to avoid having to check everywhere
    setmetatable(all_pools, {
        __index = function(self, ctype: CType): Pool<unknown>
            ASSERT(ctype_valid(ctype), "invalid component type")
            local pool = pool_create(INIT_STORAGE_SIZE)
            self[ctype] = pool
            return pool
        end
    })

    setmetatable(ctype_pools, {
        __index = function(self, ctype: CType): Pool<unknown>
            ASSERT(ctype ~= ctype_entity, "cannot modify entity pool")
            local pool = all_pools[ctype]
            self[ctype] = pool
            return pool
        end
    })

    local function get_any_pool<T>(ctype: T): Pool<T>
        return all_pools[ctype] :: Pool<any>
    end

    local function get_ctype_pool<T>(ctype: T): Pool<T>
        return ctype_pools[ctype] :: Pool<any>
    end

    local function group_init(...: any): GroupData
        local group = { size = 0, added = false }

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = get_ctype_pool(ctype)
            group[i] = pool
            groups[ctype] = group
            pool.group = group
        end

        local entities = get_ctype_pool((...)).entities

        for _, id in next, entities do
            group_try_add(group, ID_KEY(id), id)
        end

        return group
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
        if entity_pool_has(id_pool, id) == false then
            ASSERT(false, `invalid entity`)
        end
    end

    local function ASSERT_NOT_RESERVED(key: number, id: Entity)
        if key == 0 then
            ERROR("cannot release id")
        end
    end

    function registry.create(self: Registry, id: Entity?): Entity
        if id_pool.size >= ID_MAX_KEY then ERROR("cannot create entity; registry is at max entities") end
        return id and entity_pool_reuse(id_pool, id) or entity_pool_add(id_pool)
    end

    function registry.release(self: Registry, id: Entity)
        ASSERT_VALID_ENTITY(ID_KEY(id), id)
        ASSERT_NOT_RESERVED(ID_KEY(id), id)
        entity_pool_remove(id_pool, id)
    end

    function registry.destroy(self: Registry, id: Entity)
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)
        ASSERT_NOT_RESERVED(ID_KEY(id), id)
        
        for _, pool in next, ctype_pools do
            pool_unsafe_remove_key(pool, key, id)
        end

        entity_pool_remove(id_pool, id)
    end

    function registry.contains(self: Registry, id: Entity): boolean
        return entity_pool_has(id_pool, id)
    end

    function registry.orphaned(self: Registry, id: Entity): boolean
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)

        for _, pool in next, ctype_pools do
            if pool.map[key] then return false end
        end
        return true
    end

    function registry.add<T...>(self: Registry, id: Entity, ...: T...)
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = get_ctype_pool(ctype)

            -- continue if already added
            if pool.map[key] then continue end

            local constructor = ctype_constructors[ctype] or ERROR(`no constructor defined for {ctype_debug(ctype, i)}`)
            local value
            if constructor ~= ctype_TAG then
                value = (constructor :: () -> unknown)()
                if value == nil then ERROR(`{ ctype_debug(ctype, i) } constructor did not return a value`) end   
            end
            
            pool_unsafe_add(pool, key, id, value)
        end
    end

    function registry.set<T>(self: Registry, id: Entity, ctype: T, value: T?)
        if value ~= nil then
            pool_safe_set(get_ctype_pool(ctype), id, value, id_pool.map)
        else
            pool_safe_remove(get_ctype_pool(ctype), id)
        end
    end
    
    function registry.patch<T>(self: Registry, id: Entity, ctype: T, fn: (T) -> T)
        pool_safe_patch(get_ctype_pool(ctype), id, fn, id_pool.map, ctype)
    end

    registry.has = (function(self: Registry, id: Entity, ...: unknown): boolean
        local a, b = ...
        local key = ID_KEY(id)
        if b == nil then
            local idx_ver = get_ctype_pool(a).map[key]
            return idx_ver ~= nil and check_versions_equal(ID_KEY(idx_ver), idx_ver, key, id)
        else
            for i = 1, select("#", ...) do
                local idx_ver = get_ctype_pool(select(i, ...)).map[key]
                if idx_ver == nil or not check_versions_equal(ID_KEY(idx_ver), idx_ver, key, id) then return false end
            end
            return true
        end  
    end :: any) :: <T...>(self: Registry, id: Entity, T...) -> boolean

    local function pool_safe_get(ctype: CType, key: number, id: number): unknown
        local pool = get_ctype_pool(ctype)
        local idx_ver = pool.map[key]
        if idx_ver == nil then ERROR(`entity does not have {ctype_debug(ctype, 1)}`) end
        local idx = ID_KEY(idx_ver :: number)
        ASSERT_VERSIONS_EQUAL(idx, idx_ver :: number, key, id)
        return pool.values[idx]
    end

    local function pool_get(ctype: CType, key: number, id: number): unknown
        local pool = get_ctype_pool(ctype)
        local idx_ver = pool.map[key]
        if idx_ver == nil then ERROR(`entity does not have {ctype_debug(ctype)}`) end
        return pool.values[ID_KEY(idx_ver :: number)]
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

    function registry.try_get<T>(self: Registry, id: Entity, ctype: T): T?
        return pool_safe_try_get(get_ctype_pool(ctype), id)
    end

    function registry.remove<T...>(self: Registry, id: Entity, ...: T...)
        for i = 1, select("#", ...) do
            pool_safe_remove(get_ctype_pool(select(i, ...)), id)
        end
    end

    function registry.clear<T...>(self: Registry, ...: T...)
        local argn = select("#", ...)
        if argn > 0 then
            for i = 1, argn do pool_clear(get_ctype_pool(select(i, ...))) end
        else
            for _, pool in next, ctype_pools do pool_clear(pool) end
            entity_pool_clear(id_pool)
        end 
    end

    function registry.view<T...>(self: Registry, ...: T...): View<T...>
        ASSERT(select("#", ...) > 0, "view must contain at least 1 component")
        return View.new(self, ...)
    end 

    function registry.track<T...>(self: Registry, ...: T...): Observer<T...>
        ASSERT(select("#", ...) > 0, "observer must contain at least 1 component")
        return Observer.new(self, ...)
    end

    function registry.group<T...>(self: Registry, ...: T...): Group<T...>
        local argn = select("#", ...)
        ASSERT(argn > 1, "groups must contain at least 2 components")
        local group = groups[select(1, ...)]

        for i = 1, argn do
            local ctype = select(i, ...)
            ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
            ASSERT(groups[ctype] == group,
                `cannot create group; {ctype_debug(ctype, i)} is not owned by the same group as previous args`)
        end

        return Group.new(self, group or group_init(...), ...)
    end

    function registry.storage<T>(self: Registry, ctype: T): Pool<T>
        return get_any_pool(ctype)
    end

    function registry.added<T>(self: Registry, ctype: T): Signal<Entity, T>
        return (signals.added[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.added[ctype] = signal
            get_any_pool(ctype).added = listeners
            return signal
        end)()) :: Signal<Entity, T>
    end

    function registry.changed<T>(self: Registry, ctype: T): Signal<Entity, T>
        return (signals.changed[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.changed[ctype] = signal
            get_any_pool(ctype).changed = listeners
            return signal    
        end)()) :: Signal<Entity, T>    
    end

    function registry.removing<T>(self: Registry, ctype: T): Signal<Entity, nil>
        return signals.removing[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.removing[ctype] = signal
            get_any_pool(ctype).removing = listeners
            return signal
        end)() :: Signal<Entity, nil>
    end

    local handle_cache = {} :: Map<Entity?, Handle?>
    setmetatable(handle_cache :: any, { __mode = "v" })

    function registry.handle(self: Registry, id: Entity?): Handle
        id = id or self:create()

        local handle = handle_cache[id]

        if handle == nil then
            handle = table.freeze(setmetatable({
                registry = self,
                entity = id :: Entity
            }, Handle))

            handle_cache[id] = handle
        end

        return handle :: Handle
    end

    function registry.context(self: Registry): Handle
        return self:handle(ID_CONTEXT)  
    end

    -- test methods
    (registry :: any).set_entity_version = function(_, key: number, ver: number)
        local data = id_pool.map[key] :: number
        if data > 0 then ERROR("attempt to set version of in-use entity") end
        id_pool.map[key] = - ID_CREATE(ID_KEY(math.abs(data)), ver)
    end

    (registry :: any).get_current_entity_version = function(_, id: Entity): number
        return ID_VER(math.abs(id_pool.map[ID_KEY(id)] :: number))
    end

    setmetatable(registry, {
        __iter = function(self: Registry): () -> Entity
            local n = id_pool.size
            local entities = id_pool.entities

            return function()
                local i = n; n = i - 1
                return entities[i]
            end
        end,

        __len = function(self: Registry): number
            return id_pool.size
        end,

        __index = strict("Registry")
    })

    return table.freeze(registry)
end

--------------------------------------------------------------------------------
-- Queue
--------------------------------------------------------------------------------

local Queue = {} do
    Queue.__index = Queue

    type _Queue = Queue<...any> & {
        size: number,
        columns: Array<Array<unknown>>
    }

    function Queue.new<T...>(): Queue<T...>
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

        return (self :: any) :: Queue<T...>
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
                local value = column[i]
                if i == n then self:clear() end
                return value
            end

        else--if #columns > 1 then
            local tuple = table.create(#columns)
            return function()
                i += 1
                for ci, column in next, columns do
                    tuple[ci] = column[i]
                end
                if i == n then self:clear() end
                return unpack(tuple)
            end
        end
    end
end

type SignalInterface<T...> = {
    connect: (self: any, listener: (T...) -> ()) -> ()
} | {
    Connect: (self: any, listener: (T...) -> ()) -> ()
}

local queue_create = function<T...>(signal: SignalInterface<T...>?): Queue<T...>
    local queue = Queue.new()

    -- todo: fix type error
    if signal then
        local connector = (signal :: any).connect or (signal :: any).Connect
        ASSERT(connector, "signal has no connector")
        connector(signal, function(...: T...)
            queue:add(...)
        end)
    end

    return queue
end :: ( <T...>() -> Queue<T...> ) & ( <T...>(signal: SignalInterface<T...>) -> Queue<T...> )

--------------------------------------------------------------------------------
-- Return
--------------------------------------------------------------------------------

local ecr = {
    registry = registry_create,

    component = function(constructor)
        ASSERT(
            constructor == nil or type(constructor) == "function",
            "constructor must be a function"
        )
        return ctype_create(constructor)
    end :: (() -> unknown) & (<T>(constructor: () -> T) -> T),

    tag = ctype_tag :: () -> nil,

    entity = ctype_entity,

    is_tag = function<T>(ctype: T): boolean
        ASSERT(ctype_valid(ctype), "invalid component")
        return ctype_is_tag(ctype)
    end,

    name = function<T>(names: T & {}): T
        for name, ctype in next, names do
            ASSERT(ctype_valid(ctype), `{name} refers to an invalid component`)
            ctype_name(ctype, name)
        end
        table.freeze(names)
        return names
    end,

    queue = queue_create,
    null = ID_NULL,

    extract = function(id: Entity): (number, number)
        return ID_KEY_VER(id)
    end
}

-- test functions
(ecr :: any).id = ID_CREATE

return table.freeze(ecr)
