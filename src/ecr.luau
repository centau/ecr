--------------------------------------------------------------------------------
-- ecr.luau
-- v0.8.0
--------------------------------------------------------------------------------

local ID_SIZE = 4
local MAX_ENTITIES = 0x0000_FFFF
local DEFER_ID_REUSE = false

--------------------------------------------------------------------------------
-- typedef
--------------------------------------------------------------------------------

type Array<T> = { [number]: T }
type Map<T, U> = { [T]: U }
type CType = unknown

export type entity = number

export type Signal<T...> = {
    connect: (self: Signal<T...>, listener: (T...) -> ()) -> Connection,
}

export type Connection = {
    disconnect: (self: Connection) -> (),
    reconnect: (self: Connection) -> ()
}

type Listener<T> = (id: entity, value: T) -> ()

type Pool<T> = {
    map_max: number, -- largest key that can fit
    map: buffer, -- map keys to internal indexes

    capacity: number, -- allocated amount
    size: number, -- used amount
    entities: buffer, -- all ids (0-indexed)
    values: Array<T>, -- all values (1-indexed)

    on_add: Array<Listener<T>> | false,
    on_change: Array<Listener<T>> | false,
    on_remove: Array<Listener<nil>> | false,
    group: GroupData<T> | false,

    reserve: (self: Pool<T>, size: number) -> ()
}

type EntityPool<T = nil> = Pool<T> & {
    free: number -- head of list
}

type GroupData<T = unknown> = {
    size: number, -- entity amount in group
    added: boolean, -- flag used to detect iter invalidation
    connections: Array<Connection>, -- listeners to add and remove from group
    [number]: Pool<T> -- all pools in group
}

export type Handle = typeof(setmetatable(
    {} :: { registry: Registry, entity: entity },
    {} :: HandleMT
))

type HandleMT = {
    __index: HandleMT,
    destroy: (self: Handle) -> (),
    has_none: (self: Handle) -> boolean,
    add: <T...>(self: Handle, T...) -> (),
    set: <T>(self: Handle, ctype: T, value: T) -> Handle,
    patch: <T>(self: Handle, ctype: T, patcher: (current: T) -> T) -> (),
    has: <T...>(self: Handle, T...) -> boolean,
    get: <T...>(self: Handle, T...) -> T...,
    try_get: <T>(self: Handle, T) -> T?,
    remove: <T...>(self: Handle, T...) -> (),
}

export type View<T...> = typeof(setmetatable({} :: {
    exclude: <U...>(self: View<T...>, U...) -> View<T...>,
    use: <T>(self: View<T...>, lead: T) -> View<T...>,
    iter: (self: View<T...>) -> () -> (entity, T...)
}, {} :: {
    __len: (self: View<T...>) -> number ,
    __iter: (self: View<T...>) -> () -> (entity, T...)
}))

export type Observer<T...> = typeof(setmetatable({} :: {
    exclude: <U...>(self: Observer<T...>, U...) -> Observer<T...>,
    disconnect: (self: Observer<T...>) -> Observer<T...>,
    reconnect: (self: Observer<T...>) -> Observer<T...>,
    persist: (self: Observer<T...>) -> Observer<T...>,
    clear: (self: Observer<T...>) -> Observer<T...>,
    iter: (self: Observer<T...>) -> () -> (entity, T...)
}, {} :: {
    __len: (self: Observer<T...>) -> number,
    __iter: (self: Observer<T...>) -> () -> (entity, T...)
}))

export type Group<T...> = typeof(setmetatable({} :: {
    iter: (self: Group<T...>) -> () -> (entity, T...)
}, {} :: {
    __len: (self: Group<T...>) -> number,
    __iter: (self: Group<T...>) -> () -> (entity, T...)
}))

export type Registry = {
    create: ((self: Registry, id: entity) -> entity) & ((self: Registry) -> entity),
    release: (self: Registry, id: entity) -> (),
    destroy: (self: Registry, id: entity) -> (),
    contains: (self: Registry, id: entity) -> boolean,

    has_none: (self: Registry, id: entity) -> boolean,
    add: <T...>(self: Registry, id: entity, T...) -> (),
    set: <T>(self: Registry, id: entity, ctype: T, value: T) -> (),
    patch: <T>(self: Registry, id: entity, ctype: T, patcher: (T) -> T) -> (),
    has: <T...>(self: Registry, id: entity, T...) -> boolean,
    get: <T...>(self: Registry, id: entity, T...) -> T...,
    try_get: <T>(self: Registry, id: entity, T) -> T?,
    remove: <T...>(self: Registry, id: entity, T...) -> (),

    view: <T...>(self: Registry, T...) -> View<T...>,
    track: <T...>(self: Registry, T...) -> Observer<T...>,
    group: <T...>(self: Registry, T...) -> Group<T...>,

    clear: <T...>(self: Registry, T...) -> (),
    storage: (<T>(self: Registry, ctype: T) -> Pool<T>) & (<T>(self: Registry) -> () -> (unknown, Pool<unknown>)),

    on_add: <T>(self: Registry, ctype: T) -> Signal<entity, T>,
    on_change: <T>(self: Registry, ctype: T) -> Signal<entity, T>,
    on_remove: <T>(self: Registry, ctype: T) -> Signal<entity, nil>,

    handle: ((self: Registry, id: entity) -> Handle) & ((self: Registry) -> Handle),
    context: (self: Registry) -> Handle
}

export type Queue<T...> = typeof(setmetatable({} :: {
    add: (self: Queue<T...>, T...) -> (),
    clear: (self: Queue<T...>) -> (),
    iter: (self: Queue<T...>) -> () -> (T...)
}, {} :: {
    __len: (self: Queue<T...>) -> number,
    __iter: (self: Queue<T...>) -> () -> (T...)
}))

local NIL = nil :: any

local function throw(msg: string)
    local s = 1
    repeat s += 1 until debug.info(s, "s") ~= debug.info(1, "s") 
    error(msg, s) -- stack trace begins at first call site outside of this file
end

local ASSERT = function<T>(v: T, msg: string): T
    if v then return v end
    return throw(msg)
end :: typeof(assert)

--------------------------------------------------------------------------------
-- entity id
--------------------------------------------------------------------------------

local RESERVED_BITS = 1

local ID_SIZE_BITS = ID_SIZE * 8
local ID_MAX = 2^(ID_SIZE_BITS - RESERVED_BITS) - 1

local ID_MASK_RES = 0xFFFF_FFFF - ID_MAX
local ID_MASK_KEY = MAX_ENTITIES
local ID_MASK_VER = ID_MAX - ID_MASK_KEY
local ID_MASK_VER_RES = ID_MASK_VER + ID_MASK_RES

local ID_LSHIFT = ID_MASK_KEY + 1
local ID_RSHIFT = 1/ID_LSHIFT

local ID_NULL_KEY = ID_MASK_KEY
local ID_CTX_KEY = 0

local ID_NULL_VER = 0
local ID_MIN_VER = 1 * ID_LSHIFT

local ID_MAX_VALID_KEY = ID_MASK_KEY - 1
local ID_MAX_CAPACITY = ID_MASK_KEY + 1

assert(ID_SIZE <= 4 and ID_SIZE >= 1)
assert(MAX_ENTITIES <= ID_MAX/2 and MAX_ENTITIES > 0)
assert(bit32.band(MAX_ENTITIES + 1, MAX_ENTITIES) == 0)

local function ID_CREATE(key: number, ver: number): number
    return ver + key
end

local function ID_KEY(id: number): number
    return bit32.band(id, ID_MASK_KEY)
end

local function ID_VER(id: number): number
    return bit32.band(id, ID_MASK_VER)
end

local function ID_REPLACE(id: number, new_key: number): number
    return ID_VER(id) + new_key
end

local function ID_VERSION_NOT_EQUAL(id1: number, id2: number)
    return ID_VER(id1) ~= ID_VER(id2)
end

local function ID_ASSERT_VERSION_EQUAL(id1: number, id2: number)
    if ID_VERSION_NOT_EQUAL(id1, id2) then
        throw("invalid entity")
    end
end

local ID_NULL = ID_CREATE(ID_NULL_KEY, ID_NULL_VER)
local ID_CTX = ID_CREATE(ID_CTX_KEY, ID_MIN_VER)

--------------------------------------------------------------------------------
-- component type
--------------------------------------------------------------------------------

-- a ctor set to `true` indicates the component is a tag
local ctype_ctors: Map<CType, (boolean | () -> unknown)> = {}
local ctype_names: Map<CType, string?> = {}
local ctype_n = 0

local function ctype_create<T>(ctor: boolean | () -> unknown): CType
    ctype_n += 1
    ctype_ctors[ctype_n] = ctor
    return ctype_n
end

local function ctype_create_tag(): CType
    return ctype_create(true)
end

local function ctype_is_tag(ctype: CType): boolean
    return ctype_ctors[ctype] == true
end

local function ctype_is_valid(v: unknown): boolean
    return type(v) == "number" and math.floor(v) == v and v > 0 and v <= ctype_n  
end

local function ctype_set_name(ctype: CType, name: unknown)
    ctype_names[ctype] = tostring(name)
end

local ctype_debug: (ctype: CType?, idx: number?) -> string = (function()
    return function(ctype: CType?, idx: number?)
        local name = ctype_names[ctype]
        return
            if name then `component "{name}"`
            elseif idx then `component (arg #{idx})`
            else "component (unknown)"
    end
end)()

-- built-in entity type
local ctype_entity = ctype_create(false)
ctype_set_name(ctype_entity, "entity")

local function ASSERT_VALID_CTYPE(ctype: unknown, idx: number?)
    if not ctype_is_valid(ctype) then
        throw(`invalid component {idx and `arg #{idx}` or ""}`)
    end
end

--------------------------------------------------------------------------------
-- pool
--------------------------------------------------------------------------------

local function next_pow_of_2(x: number)
    assert(x > 0 and x <= 2^32)
    x -= 1
    x = bit32.bor(x, bit32.rshift(x, 1))
    x = bit32.bor(x, bit32.rshift(x, 2))
    x = bit32.bor(x, bit32.rshift(x, 4))
    x = bit32.bor(x, bit32.rshift(x, 8))
    x = bit32.bor(x, bit32.rshift(x, 16))
    return x + 1
end

local function fire<T>(listeners: Array<Listener<T>>, id: entity, value: T)
    for i = #listeners, 1, -1 do
        listeners[i](id, value)         
    end 
end

local function buffer_create(size: number): buffer
    return buffer.create(size * ID_SIZE)
end

local function BUFFER_GET(b: buffer, i: number): number
    return buffer.readu32(b, i * ID_SIZE)
end

local function BUFFER_SET(b: buffer, i: number, id: entity)
    buffer.writeu32(b, i * ID_SIZE, id)
end

local function buffer_fill(b: buffer, first: number, last: number, v: number)
    assert(buffer.len(b) >= last * ID_SIZE)
    for i = first * ID_SIZE, last * ID_SIZE, ID_SIZE do
        buffer.writeu32(b, i, v)
    end
end

local function buffer_resize(b: buffer, size: number): buffer
    local b_new = buffer.create(size * ID_SIZE)
    local n_old = buffer.len(b)
    
    buffer.copy(b_new, 0, b)

    for i = n_old, size * ID_SIZE - 1, ID_SIZE do
        buffer.writeu32(b_new, i, ID_NULL)
    end

    return b_new
end

local function buffer_clone(b: buffer): buffer
    local b_new = buffer.create(buffer.len(b))
    buffer.copy(b_new, 0, b)
    return b_new
end

-- wrappers to treat arrays as 0-indexed
local function ARRAY_SET<T>(t: Array<T>, i: number, v: T)
    t[i + 1] = v
end

local function ARRAY_GET<T>(t: Array<T>, i: number): T
    return t[i + 1]
end

local function ARRAY_SWAP<T>(t: Array<T>, a: number, b: number)
    a += 1
    b += 1
    t[a], t[b] = t[b], t[a]
end

local function ARRAY_SWAP_REMOVE<T>(t: Array<T>, remove: number, swap: number)
    swap += 1
    t[remove + 1] = t[swap]
    t[swap] = nil
end

local function POOL_CONTAINS<T>(pool: Pool<T>, key: number): boolean
    return pool.map_max >= key
end

local function POOL_HAS<T>(pool: Pool<T>, key: number): boolean
    return pool.map_max >= key and BUFFER_GET(pool.map, key) ~= ID_NULL
end

local function POOL_NOT_HAS<T>(pool: Pool<T>, key: number): boolean
    return pool.map_max < key or BUFFER_GET(pool.map, key) == ID_NULL
end

local function POOL_FIND(pool: Pool<any>, key: number): number
    if key > pool.map_max then return ID_NULL end
    return BUFFER_GET(pool.map, key)
end

local function pool_resize_entities<T>(self: Pool<T>, size: number)
    if self.capacity >= size then return end
    local new_capacity = next_pow_of_2(size)
    self.entities = buffer_resize(self.entities, new_capacity)
    self.capacity = new_capacity
end

local function pool_resize_map<T>(self: Pool<T>, size: number)
    if self.map_max + 1 >= size then return end
    local new_map_capacity = next_pow_of_2(size)
    self.map = buffer_resize(self.map, new_map_capacity)
    self.map_max = new_map_capacity - 1
end

local function POOL_CHECK_MAP_SIZE<T>(self: Pool<T>, key: number)
    if self.map_max < key then
        pool_resize_map(self, key + 1)
    end
end

local function POOL_SWAP<T>(
    self: Pool<T>,
    idx: number,
    idx_swap: number
)
    local map = self.map
    local entities = self.entities
    local values = self.values

    local id = BUFFER_GET(entities, idx)
    local id_swap = BUFFER_GET(entities, idx_swap)

    BUFFER_SET(entities, idx_swap, id)
    BUFFER_SET(entities, idx, id_swap)

    BUFFER_SET(map, ID_KEY(id), ID_REPLACE(id, idx_swap))
    BUFFER_SET(map, ID_KEY(id_swap), ID_REPLACE(id_swap, idx))
    
    ARRAY_SWAP(values, idx_swap, idx)
end

local function GROUP_ADD<T>(group: GroupData<T>, key: number)
    group.added = true -- used to test for invalidation
    local n = group.size
    group.size = n + 1
    for _, pool in ipairs(group) do
        POOL_SWAP(pool, ID_KEY(BUFFER_GET(pool.map, key)), n)
    end
end

local function GROUP_CAN_ADD<T>(group: GroupData<T>, key: number): boolean
    for _, pool in ipairs(group) do
        if POOL_NOT_HAS(pool, key) then
            return false
        end
    end
    return true
end

local function POOL_TRY_GROUP<T>(pool: Pool<T>, id: number)
    local group = pool.group :: GroupData<T>
    local key = ID_KEY(id)
    if GROUP_CAN_ADD(group, key) then
        GROUP_ADD(group, key)  
    end
end

local function GROUP_REMOVE<T>(group: GroupData<T>, idx: number)
    local n = group.size - 1
    group.size = n
    for _, pool in ipairs(group) do        
        POOL_SWAP(pool, idx, n)
    end
end

local function POOL_TRY_UNGROUP<T>(pool: Pool<T>, id: entity)
    local group = pool.group :: GroupData<T>
    local idx = ID_KEY(BUFFER_GET(pool.map, ID_KEY(id)))
    if idx < group.size then
        GROUP_REMOVE(group, idx)
    end
end

local function POOL_CHECK_ENTITIES_SIZE<T>(self: Pool<T>, size: number)
    if size == self.capacity then
        pool_resize_entities(self, self.capacity * 2)
    end
end

local function _POOL_ADD(self, i, id, v)
    BUFFER_SET(self.map, ID_KEY(id), ID_REPLACE(id, i))
    BUFFER_SET(self.entities, i, id)
    ARRAY_SET(self.values, i, v)
end
local function POOL_ADD<T>(self: Pool<T>, id: entity, v: T)
    local n = self.size
    POOL_CHECK_ENTITIES_SIZE(self, n)
    self.size = n + 1
    _POOL_ADD(self, n, id, v)
    if self.on_add then fire(self.on_add, id, v) end
end

local function _POOL_ADD_ID(self, i, id)
    BUFFER_SET(self.map, ID_KEY(id), ID_REPLACE(id, i))
    BUFFER_SET(self.entities, i, id)
end
local function POOL_ADD_ID<T>(self: Pool<T>, id: entity)
    local n = self.size
    POOL_CHECK_ENTITIES_SIZE(self, n)
    self.size = n + 1
    _POOL_ADD_ID(self, n, id)
    if self.on_add then fire(self.on_add, id, NIL) end
end

local function POOL_REMOVE<T>(self: Pool<T>, key, id)
    local map = self.map

    if self.on_remove then fire(self.on_remove, id) end

    local idx_ver = BUFFER_GET(map, key)
    local idx = ID_KEY(idx_ver)

    if ID_VERSION_NOT_EQUAL(idx_ver, id) then return end

    local n = self.size - 1
    self.size = n
    local entities = self.entities
    local values = self.values

    local id_last = BUFFER_GET(entities, n)

    BUFFER_SET(map, ID_KEY(id_last), ID_REPLACE(id_last, idx))
    BUFFER_SET(map, key, ID_NULL)

    BUFFER_SET(entities, idx, id_last)
    --BUFFER_SET(entities, n, ID_NULL)

    ARRAY_SWAP_REMOVE(values, idx, n)
end
local function POOL_TRY_REMOVE<T>(self: Pool<T>, id: entity)
    local key = ID_KEY(id)
    if POOL_HAS(self, key) then
        POOL_REMOVE(self, key, id)
    end
end

local function pool_clear<T>(self: Pool<T>)
    local signal = self.on_remove :: Array<Listener<nil>>

    -- disconnect group listeners to avoid needless swapping
    if self.group then
        for _, connection in self.group.connections do
            connection:disconnect()
        end
    end

    if signal then
        local entities = self.entities
        for i = 0, self.size - 1 do
            fire(signal, BUFFER_GET(entities, i))
        end
    end

    if self.group then
        self.group.size = 0
        for _, connection in self.group.connections do
            connection:reconnect()
        end
    end

    self.size = 0
    buffer_fill(self.map, 0, self.map_max, ID_NULL)
    table.clear(self.values)
end

local function pool_create<T>(size: number?): Pool<T>
    local n = size or 1

    local map = buffer_create(n)
    buffer_fill(map, 0, n - 1, ID_NULL)

    return {
        map_max = n - 1,
        capacity = n,
        size = 0,
        map = map,
        entities = buffer_create(n),
        values = table.create(n),

        on_add = false,
        on_change = false,
        on_remove = false,
        group = false,

        reserve = function(self: Pool<T>, size: number)
            pool_resize_map(self, size)
            pool_resize_entities(self, size)

            -- todo: why does this cause innacurate buffer alloc readings?
            do -- force array reallocation
                local values = self.values
                local n = next_pow_of_2(size)

                for i = self.size + 1, n do
                    values[i] = true :: any
                end

                for i = n, self.size + 1, -1 do
                    values[i] = nil
                end
            end
        end
    }
end

local function entity_pool_init(self: EntityPool, start: number, stop: number)
    for i = start, stop - 1 do
        BUFFER_SET(self.map, i, ID_CREATE(i + 1, ID_MIN_VER))
    end

    BUFFER_SET(self.map, stop, ID_CREATE(ID_NULL_KEY, ID_MIN_VER))
end

local function IS_IN_USE(id: number): boolean
    return bit32.band(id, ID_MASK_RES) > 0
end

local function MARK_IN_USE(id: number): number
    return bit32.bor(id, ID_MASK_RES)
end

local function entity_pool_resize(self: EntityPool, size: number)
    if self.capacity >= size then return end
    local new_capacity = next_pow_of_2(size)

    ASSERT(new_capacity <= ID_MAX_CAPACITY, "entity limit reached")

    local last = self.capacity - 1

    -- find end of list to append new free keys to tail
    if self.free ~= ID_NULL_KEY then
        local prev = self.free
        local i = 0; repeat i += 1 -- find key before desired key
            local next = ID_KEY(BUFFER_GET(self.map, prev))
            if next == ID_NULL_KEY then break end
            prev = next
        until i == ID_MASK_KEY
        ASSERT(i < ID_MASK_KEY, "timeout occured")
        BUFFER_SET(self.map, prev, ID_REPLACE(BUFFER_GET(self.map, prev), last + 1))
    else
        self.free = last + 1
    end

    self.map = buffer_resize(self.map, new_capacity)
    self.entities = buffer_resize(self.entities, new_capacity)
    entity_pool_init(self, last + 1, new_capacity - 1)
    self.map_max = new_capacity - 1
    self.capacity = new_capacity
end

local function entity_pool_create(): EntityPool
    local pool = pool_create(2) :: EntityPool
    -- leave key 0 unused - reserved for context entity
    entity_pool_init(pool, 1, 1)
    pool.free = 1

    pool.reserve = function(self: Pool<nil>, size: number)
        entity_pool_resize(self :: EntityPool, size)
    end

    return pool
end

local function entity_pool_add(self: EntityPool): entity
    if self.free == ID_NULL_KEY then
        if DEFER_ID_REUSE and self.capacity == ID_MAX_CAPACITY then
            -- search for a deprecated key
            for i = ID_CTX_KEY + 1, ID_MAX_VALID_KEY do
                if BUFFER_GET(self.map, i) == ID_NULL then
                    BUFFER_SET(self.map, i, ID_CREATE(ID_NULL_KEY, ID_MIN_VER))
                    self.free = i
                    break
                end
                ASSERT(self.free ~= ID_NULL_KEY, "entity limit reached")
            end
        else
            entity_pool_resize(self, self.capacity*2)
        end
    end
    
    assert(self.free ~= ID_NULL_KEY)
    local new_key = self.free
    local next_key_cur_ver = BUFFER_GET(self.map, new_key)
    local next_key = ID_KEY(next_key_cur_ver)
    local cur_ver = ID_VER(next_key_cur_ver)
    self.free = next_key

    local id = ID_CREATE(new_key, cur_ver)
    local n = self.size
    BUFFER_SET(self.entities, n, id)
    BUFFER_SET(self.map, new_key, MARK_IN_USE(ID_CREATE(n, cur_ver)))
    self.size = n + 1

    if self.on_add then fire(self.on_add, id) end

    return id
end

local function entity_pool_use(self: EntityPool, id: entity): entity
    local key, ver = ID_KEY(id), ID_VER(id)

    ASSERT(id == ID_CTX or key ~= ID_NULL_KEY and ver ~= ID_NULL_VER, "malformed id")

    local capacity = self.capacity
    local last = capacity - 1

    if key > last then -- if key has not been created yet
        entity_pool_resize(self, key + 1)
    end

    ASSERT(not IS_IN_USE(BUFFER_GET(self.map, key)), "key already in use")

    if id ~= ID_CTX then
        if self.free == key then -- if at head
            local next_free = ID_KEY(BUFFER_GET(self.map, self.free))
            self.free = next_free
        elseif BUFFER_GET(self.map, key) ~= ID_NULL then -- if not deprecated
            -- key is somewhere along list
            local prev = self.free
            local i = 0; repeat i += 1 -- find key before desired key
                local next = ID_KEY(BUFFER_GET(self.map, prev))
                if next == key then break end
                prev = next
            until i == ID_MAX_VALID_KEY
            ASSERT(i < ID_MAX_VALID_KEY, "key not found")

            BUFFER_SET( -- a -> b -> c, remove b, link a -> c
                self.map, prev,
                ID_REPLACE(
                    BUFFER_GET(self.map, prev),
                    ID_KEY(BUFFER_GET(self.map, key))
                )
            )
        end
    end

    local n = self.size
    self.size = n + 1
    BUFFER_SET(self.map, key, MARK_IN_USE(ID_REPLACE(id, n)))
    BUFFER_SET(self.entities, n, id)

    if self.on_add then fire(self.on_add, id) end

    return id
end

local function entity_pool_remove(self: EntityPool, id: entity)
    local key, ver = ID_KEY(id), ID_VER(id)

    if self.on_remove then fire(self.on_remove, id) end

    local last = self.size - 1
    self.size = last

    local map = self.map
    local entities = self.entities

    local idx_ver_res = BUFFER_GET(map, key)
    assert(IS_IN_USE(idx_ver_res))
    local idx = ID_KEY(idx_ver_res)
    local id_last = BUFFER_GET(entities, last)

    BUFFER_SET(entities, idx, id_last)
    BUFFER_SET(map, ID_KEY(id_last), MARK_IN_USE(ID_REPLACE(id_last, idx)))

    if id == ID_CTX then
        BUFFER_SET(map, key, ID_NULL)
    elseif ver < ID_MASK_VER then
        BUFFER_SET(map, key, ID_CREATE(self.free, ver + 1 * ID_LSHIFT)) -- inc version
        self.free = key
    elseif DEFER_ID_REUSE then
        BUFFER_SET(map, key, ID_NULL) -- deprecate key
    else
        BUFFER_SET(map, key, ID_CREATE(self.free, ID_MIN_VER)) -- reset version
        self.free = key
    end
end

local function ENTITY_POOL_HAS(self: EntityPool, id: number): boolean
    local key = ID_KEY(id)
    return
        self.capacity > key and
        MARK_IN_USE(ID_VER(id)) == bit32.band(BUFFER_GET(self.map, key), ID_MASK_VER_RES)
end

local function entity_pool_clear(self: EntityPool)
    local entities = self.entities

    if self.on_remove then
        for i = 0, self.size - 1 do
            fire(self.on_remove, BUFFER_GET(entities, i))
        end
    end

    -- todo: optimize
    for i = self.size - 1, 0, -1 do
        entity_pool_remove(self, BUFFER_GET(entities, i))
    end
end

--------------------------------------------------------------------------------
-- view
--------------------------------------------------------------------------------

local View, Observer, Group do

type IRegistry = {
    storage: <T>(self: IRegistry, ctype: T) -> Pool<T>,
    on_add: <T>(self: IRegistry, ctype: T) -> Signal<entity, T>,
    on_change: <T>(self: IRegistry, ctype: T) -> Signal<entity, T>,
    on_remove: <T>(self: IRegistry, ctype: T) -> Signal<entity, nil>,
}

local function HAS_ANY(pools: Array<Pool<unknown>>, key: number): boolean
    for _, pool in next, pools do
        if POOL_HAS(pool, key) then return true end
    end
    return false
end

local function get_smallest(pools: Array<Pool<unknown>>): Pool<unknown>
    local s: Pool<unknown>?
    for _, pool in next, pools do
        s = if s == nil or pool.size < s.size then pool else s
    end
    return assert(s, "no pools given")
end

local function get_pools(registry: IRegistry, ctypes: Array<CType>): Array<Pool<unknown>>
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
        throw("group reordered during iteration")
    end
end

-- specialized single-type view iterator
local function single<A>(pool: Pool<A>): () -> (entity, A)
    local n = pool.size
    local entities = pool.entities
    local values = pool.values

    clear_invalidation_flag(pool)

    return function()
        local i = n - 1; n = i

        if i < 0 then
            ASSERT_INVALIDATION(pool)
            return NIL, NIL
        end

        return BUFFER_GET(entities, i), ARRAY_GET(values, i)
    end
end

-- specialized double-type view iterator
local function double<A, B>(a: Pool<A>, b: Pool<B>): () -> (entity, A, B)
    local na, nb = a.size, b.size

    if na <= nb then
        local n = na
        local entities = a.entities
        local values = a.values

        clear_invalidation_flag(a)

        return function()
            for i = n - 1, 0, -1 do
                local id = BUFFER_GET(entities, i)
                local idx_ver = POOL_FIND(b, ID_KEY(id))
                if idx_ver == ID_NULL then continue end
                n = i
                return id, ARRAY_GET(values, i), ARRAY_GET(b.values, ID_KEY(idx_ver))
            end
    
            ASSERT_INVALIDATION(a)
            return NIL, NIL, NIL
        end
    else
        local n = nb
        local entities = b.entities
        local values = b.values

        clear_invalidation_flag(b)

        return function()
            for i = n - 1, 0, -1 do
                local id = BUFFER_GET(entities, i)
                local idx_ver = POOL_FIND(a, ID_KEY(id))
                if idx_ver == ID_NULL then continue end
                n = i
                return id, ARRAY_GET(a.values, ID_KEY(idx_ver)), ARRAY_GET(values, i)   
            end
    
            ASSERT_INVALIDATION(b)
            return NIL, NIL, NIL
        end
    end
end

-- generic multi-type view iterator
local function multi(
    includes: Array<Pool<unknown>>,
    excludes: Array<Pool<unknown>>?,
    lead: Pool<unknown>?
): () -> (entity, ...any)
    local source = lead or get_smallest(includes)
    local source_pos: number?
    for i, pool in next, includes do
        if pool == source then
            source_pos = i
            break
        end
    end
    assert(source_pos)

    local n = source.size
    local entities = source.entities
    local values = source.values

    local last_pos = #includes
    local tuple = table.create(last_pos)

    clear_invalidation_flag(source)

    return function()
        for i = n - 1, 0, -1 do
            local id = BUFFER_GET(entities, i)
            local key = ID_KEY(id)
            
            if excludes and HAS_ANY(excludes, key) then continue end

            local has_all = true

            for pos = 1, source_pos - 1 do
                local pool = includes[pos]
                local idx_ver = POOL_FIND(pool, key)
                if idx_ver == ID_NULL then has_all = false; break end
                tuple[pos] = ARRAY_GET(pool.values, ID_KEY(idx_ver))
            end

            if has_all == false then continue end
            
            for pos = source_pos + 1, last_pos do
                local pool = includes[pos]
                local idx_ver = POOL_FIND(pool, key)
                if idx_ver == ID_NULL then has_all = false; break end
                tuple[pos] = ARRAY_GET(pool.values, ID_KEY(idx_ver))
            end

            if has_all == false then continue end

            tuple[source_pos] = ARRAY_GET(values, i)
            n = i
            return id, unpack(tuple)
        end

        ASSERT_INVALIDATION(source)
        return NIL
    end
end

type _View<T...> = typeof(setmetatable({} :: {
    registry: IRegistry,
    includes: Array<CType>,
    excludes: Array<CType>?,
    lead: CType?,
    
    exclude: <U...>(_View<T...>, U...) -> _View<T...>,
    use: <T>(_View<T...>, T) -> _View<T...>,
    iter: (_View<T...>) -> () -> (entity, T...)
}, {} :: {
    __len: (_View<T...>) -> number,
    __iter: (_View<T...>) -> () -> (entity, T...)
}))

View = {}
View.__index = View

function View.new<T...>(reg: IRegistry, ...: T...): View<T...>
    local includes = {}

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)
        ASSERT_VALID_CTYPE(ctype, i)
        table.insert(includes, ctype)
    end

    local function iter(self: _View<T...>): () -> (entity, T...)
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

    local self: _View<T...> = setmetatable({
        registry = reg,
        includes = includes,
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
                ASSERT_VALID_CTYPE(ctype, i)
                ASSERT(not table.find(includes, ctype), `cannot exclude {ctype_debug(ctype, i)}, component is a part of the view`)
                if table.find(excludes, ctype) then continue end
                table.insert(excludes, ctype)
            end

            return self
        end,

        use = function<T>(self: _View<T...>, ctype: T): _View<T...>
            ASSERT_VALID_CTYPE(ctype)
            ASSERT(table.find(self.includes, ctype), "cannot lead with component; component is not a part of the view")
            self.lead = ctype
            return self
        end,

        iter = iter
    }, {
        __len = function(self: _View<T...>): number
            return get_smallest(get_pools(self.registry, self.includes)).size
        end,

        __iter = iter
    })

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
    iter: (_Observer<T...>) -> () -> (entity, T...)
}, {} :: {
    __len: (_Observer<T...>) -> number,
    __iter: (_Observer<T...>) -> () -> (entity, T...)
}))

Observer = {}
Observer.__index = Observer

function Observer.new<T...>(reg: IRegistry, ...: T...): Observer<T...>
    local includes = {}

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)
        ASSERT_VALID_CTYPE(ctype, i)
        table.insert(includes, ctype)
    end

    local function iter(self: _Observer<T...>): () -> (entity, T...)
        local pool = self.pool
        local reg = self.registry
        local includes = get_pools(reg, self.includes)
        local excludes = self.excludes and get_pools(reg, self.excludes)
        local persistent = self.persistent
    
        local n = pool.size
        local entities = pool.entities
    
        local reg_pool = includes[1]
        local reg_map = reg_pool.map
        local reg_values = reg_pool.values
    
        local tuple = table.create(#includes) :: Array<any>
    
        return if #includes == 1 and not excludes then 
                function()
                    local i = n - 1
                    n = i

                    if i < 0 then
                        if not persistent then self:clear() end
                        return NIL
                    end

                    local id = BUFFER_GET(entities, i)
                    local key = ID_KEY(id)

                    return id, ARRAY_GET(
                        reg_values,
                        ID_KEY(BUFFER_GET(reg_map, key))
                    ) :: any
                end 
            else
                function()
                    for i = n - 1, 0, -1 do
                        local id = BUFFER_GET(entities, i)
                        local key = ID_KEY(id)
    
                        if excludes and HAS_ANY(excludes, key) then continue end
    
                        local has_all = true
                        for pos, pool in next, includes do
                            local idx_ver = POOL_FIND(pool, key) -- todo: guarantee
                            if idx_ver == ID_NULL then has_all = false; break end
                            tuple[pos] = ARRAY_GET(pool.values, ID_KEY(idx_ver))
                        end

                        if has_all == false then continue end
    
                        n = i
                        return id, unpack(tuple)
                    end

                    if not persistent then self:clear() end
                return nil :: any, nil :: any
            end
    end

    local self: _Observer<T...> = setmetatable({
        registry = reg,
        pool = pool_create(), -- treat all initial ids as changed
        includes = includes,
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
                ASSERT_VALID_CTYPE(ctype, i)
                ASSERT(not table.find(self.includes, ctype), `cannot exclude { ctype_debug(ctype, i) }, component is being tracked`)
                if table.find(excludes, ctype) then continue end
                table.insert(excludes, ctype)
            end
        
            return self
        end,

        disconnect = function(self: _Observer<T...>): _Observer<T...>
            ASSERT(self.pool.size == 0, "attempt to disconnect a non-empty observer")
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
                local function added_or_changed_listener(id)
                    local key = ID_KEY(id)
                    POOL_CHECK_MAP_SIZE(pool, key)
                    local idx_ver = BUFFER_GET(pool.map, key)

                    if idx_ver == ID_NULL then
                        local n = pool.size
                        POOL_CHECK_ENTITIES_SIZE(pool, n)
                        pool.size = n + 1
                        BUFFER_SET(pool.map, key, ID_REPLACE(id, n))
                        BUFFER_SET(pool.entities, n, id)
                    end 
                end

                local function removed_listener(id: number)
                    local map = pool.map
                    local entities = pool.entities

                    local key = ID_KEY(id)
                    local idx_ver = POOL_FIND(pool, key)

                    if idx_ver ~= ID_NULL then
                        local n = pool.size - 1
                        pool.size = n
                        local idx = ID_KEY(idx_ver)
                        local id_last = BUFFER_GET(entities, n)
                
                        BUFFER_SET(map, ID_KEY(id_last), ID_REPLACE(id_last, idx))
                        BUFFER_SET(map, key, ID_NULL)
                        
                        BUFFER_SET(entities, idx, id_last)
                        --BUFFER_SET(entities, n, ID_NULL)
                    end
                end
                
                table.insert(connections, reg:on_add(ctype):connect(added_or_changed_listener))
                table.insert(connections, reg:on_change(ctype):connect(added_or_changed_listener))
                table.insert(connections, reg:on_remove(ctype):connect(removed_listener))
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
        end,

        iter = iter
    }, {
        __len = function(self: _Observer<T...>): number
            return self.pool.size
        end,

        __iter = iter
    })

    return self:reconnect()
end

type _Group<T...> = typeof(setmetatable({} :: {
    data: GroupData,
    pools: Array<Pool<unknown>>,

    iter: (self: _Group<T...>) -> () -> (entity, T...)
}, {} :: {
    __len: (self: _Group<T...>) -> number,
    __iter: (self: _Group<T...>) -> () -> (entity, T...)
}))

Group = {}
Group.__index = Group

function Group.new<T...>(reg: Registry, data: GroupData, ...: T...): Group<T...>
    local pools = {}

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)
        local pool = reg:storage(ctype)
        assert(table.find(data, pool), "component type is not in group")
        pools[i] = pool 
    end

    local function iter(self: _Group<T...>): () -> (entity, T...)
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
                local ia = n
                if ia == 0 then return NIL end
                local ib = ia - 1
                n = ib
                return BUFFER_GET(entities, ib), a[ia]  
            end
        elseif #pools == 2 then
            local a, b = unpack(values)
            return function()
                local ia = n
                if ia == 0 then return NIL end
                local ib = ia - 1
                n = ib
                return BUFFER_GET(entities, ib), a[ia], b[ia] 
            end
        elseif #pools == 3 then
            local a, b, c = unpack(values)
            return function()
                local ia = n
                if ia == 0 then return NIL end
                local ib = ia - 1
                n = ib
                return BUFFER_GET(entities, ib), a[ia], b[ia], c[ia]
            end
        elseif #pools == 4 then
            local a, b, c, d = unpack(values)
            return function()
                local ia = n
                if ia == 0 then return NIL end
                local ib = ia - 1
                n = ib
                return BUFFER_GET(entities, ib), a[ia], b[ia], c[ia], d[ia]
            end
        else
            local tuple = table.create(#values) :: Array<any>
            return function()
                local ia = n
                if ia == 0 then return NIL end
                local ib = ia - 1
                n = ib
                for pos, v in next, values do
                    tuple[pos] = v[ia]
                end
                return BUFFER_GET(entities, ib), unpack(tuple)
            end
        end
    end

    local self: _Group<T...> = setmetatable({
        data = data,
        pools = pools,

        iter = iter
    }, {
        __len = function(self: _Group<T...>): number
            return self.data.size
        end,

        __iter = iter
    })

    return self
end

end

--------------------------------------------------------------------------------
-- signal
--------------------------------------------------------------------------------

local signal_create: <T...>() -> (Signal<T...>, Array<(T...) -> ()>) do
    type _Signal<T...> = {
        pool: Pool<(T...) -> ()>,
        count: number,

        connect: (_Signal<T...>, (T...) -> ()) -> _Connection<T...>,
    }
    
    type _Connection<T... = ...unknown> = {
        signal: _Signal<T...>,
        fn: (T...) -> (),
        id: number,
        connected: boolean,

        disconnect: (_Connection<T...>) -> (),
        reconnect: (_Connection<T...>) -> ()
    }

    local Connection = {}

    function Connection.new<T...>(signal: _Signal<T...>, fn: (T...) -> (), id: number): _Connection<T...>
        return {
            signal = signal,
            fn = fn,
            id = id,
            connected = true,

            disconnect = function(self: _Connection<T...>)
                if self.connected then
                    POOL_TRY_REMOVE(self.signal.pool, self.id)
                    self.connected = false
                end
            end,

            reconnect = function(self: _Connection<T...>)
                if not self.connected then
                    local new = self.signal:connect(self.fn)
                    self.id = new.id
                    self.connected = true
                end
            end
        }
    end

    local Signal = {}

    function Signal.new<T...>(): _Signal<T...>
        local self: _Signal<T...> = {
            pool = pool_create(),
            count = 0,

            connect = function(self: _Signal<T...>, listener: (T...) -> ()): _Connection<T...>
                local n = self.pool.size
                POOL_CHECK_MAP_SIZE(self.pool, n)
                POOL_ADD(self.pool, n, listener)
                return Connection.new(self, listener, n)  
            end
        }

        return self
    end

    function signal_create<T...>(): (Signal<T...>, Array<Listener<unknown>>)
        local signal = Signal.new()
        return signal :: any, signal.pool.values
    end
end

--------------------------------------------------------------------------------
-- handle
--------------------------------------------------------------------------------

local Handle = (function(): HandleMT
    local Handle = {}
    Handle.__index = Handle

    function Handle.destroy(self: Handle)
        self.registry:destroy(self.entity)
    end

    function Handle.has_none(self: Handle): boolean
        return self.registry:has_none(self.entity)
    end

    function Handle.add<T...>(self: Handle, ...: T...)
        self.registry:add(self.entity, ...)
    end

    function Handle.set<T>(self: Handle, ctype: T, value: T): Handle
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
-- registry
--------------------------------------------------------------------------------

local function registry_create(): Registry
    local MAX_CTYPE = ctype_n

    local registry = {}

    local entity_pool = entity_pool_create()
    
    local signals = {
        on_add = {} :: Map<CType, Signal<entity, unknown>>,
        on_change = {} :: Map<CType, Signal<entity, unknown>>,
        on_remove = {} :: Map<CType, Signal<entity, nil>>
    }
    
    local handle_cache = {} :: Map<entity?, Handle?>
    setmetatable(handle_cache :: any, { __mode = "v" })
    
    local ctype_pools: Map<CType, Pool<unknown>> = table.create(MAX_CTYPE)
    setmetatable(ctype_pools, {
        __index = function(self, ctype: CType): Pool<unknown>
            ASSERT_VALID_CTYPE(ctype)
            ASSERT(ctype ~= ctype_entity, "attempt to use entity type")
            ASSERT(ctype :: number <= MAX_CTYPE, `cannot use {ctype_debug(ctype)}, component must be created before registry creation`)
            local pool = pool_create(1)
            self[ctype] = pool
            return pool
        end
    })

    local function GET_POOL<T>(ctype: T): Pool<T>
        return ctype_pools[ctype] :: Pool<any>
    end

    local function group_init(...: any): GroupData
        local group = { size = 0, added = false, connections = {} }

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = GET_POOL(ctype)
            group[i] = pool
            pool.group = group

            table.insert(group.connections, registry:on_add(ctype):connect(function(id)
                POOL_TRY_GROUP(pool, id)
            end))

            table.insert(group.connections, registry:on_remove(ctype):connect(function(id)
                POOL_TRY_UNGROUP(pool, id)
            end))
        end

        local pool = GET_POOL((...))
        for i = 0, pool.size - 1 do
            POOL_TRY_GROUP(pool, BUFFER_GET(pool.entities, i))
        end

        return group
    end

    local function ASSERT_VALID_ENTITY(id: entity)
        ASSERT(ENTITY_POOL_HAS(entity_pool, id), "invalid entity")
    end

    function registry.create(self: Registry, id: entity?): entity
        ASSERT(entity_pool.size < ID_MAX_CAPACITY, "cannot create entity; registry is at max entities")
        return id and entity_pool_use(entity_pool, id) or entity_pool_add(entity_pool)
    end

    function registry.release(self: Registry, id: entity)
        ASSERT_VALID_ENTITY(id)
        entity_pool_remove(entity_pool, id)
    end

    function registry.destroy(self: Registry, id: entity)
        ASSERT_VALID_ENTITY(id)
        local key = ID_KEY(id)

        for _, pool in next, ctype_pools do
            if POOL_HAS(pool, key) then
                POOL_REMOVE(pool, key, id)
            end
        end

        entity_pool_remove(entity_pool, id)
    end

    function registry.contains(self: Registry, id: entity): boolean
        return ENTITY_POOL_HAS(entity_pool, id)
    end

    function registry.has_none(self: Registry, id: entity): boolean
        ASSERT_VALID_ENTITY(id)
        local key = ID_KEY(id)

        for _, pool in next, ctype_pools do
            if POOL_HAS(pool, key) then return false end
        end

        return true
    end

    function registry.add<T...>(self: Registry, id: entity, ...: T...)
        ASSERT_VALID_ENTITY(id)
        local key = ID_KEY(id)

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = GET_POOL(ctype)

            POOL_CHECK_MAP_SIZE(pool, key)
            if BUFFER_GET(pool.map, key) ~= ID_NULL then continue end

            local ctor = ctype_ctors[ctype]

            if ctor == true then
                POOL_ADD_ID(pool, id)
            elseif ctor == false then
                throw(`no constructor defined for {ctype_debug(ctype, i)}`)
            else
                local value = (ctor :: () -> unknown)()
                if value == nil then throw(`{ctype_debug(ctype, i)} constructor did not return a value`) end   
                POOL_ADD(pool, id, value)
            end
        end
    end
    
    function registry.set<T>(self: Registry, id: entity, ctype: T, value: T)        
        local pool = GET_POOL(ctype)

        local key = ID_KEY(id)
        POOL_CHECK_MAP_SIZE(pool, key)
        local idx_ver = BUFFER_GET(pool.map, key)

        if value ~= nil then -- add tag
            if idx_ver ~= ID_NULL then -- already added, change value
                ID_ASSERT_VERSION_EQUAL(idx_ver, id)
                if pool.on_change then fire(pool.on_change, id, value) end
                ARRAY_SET(pool.values, ID_KEY(idx_ver), value)
            else -- not added, add value
                ASSERT_VALID_ENTITY(id)
                POOL_ADD(pool, id, value)
            end
        else
            ASSERT_VALID_ENTITY(id)
            ASSERT(ctype_is_tag(ctype), "cannot set component value to nil")
            if idx_ver ~= ID_NULL then return end
            POOL_ADD_ID(pool, id)
        end
    end
    
    function registry.patch<T>(self: Registry, id: entity, ctype: T, fn: (T) -> T)
        local pool = GET_POOL(ctype)

        local key = ID_KEY(id)
        POOL_CHECK_MAP_SIZE(pool, key)
        local idx_ver = BUFFER_GET(pool.map, key)

        if idx_ver ~= ID_NULL then
            ID_ASSERT_VERSION_EQUAL(idx_ver, id)
            local idx = ID_KEY(idx_ver)
            local value = fn(ARRAY_GET(pool.values, idx))
            ASSERT(value ~= nil, "patcher cannot return nil")
            if pool.on_change then fire(pool.on_change, id, value) end
            ARRAY_SET(pool.values, idx, value)
        else
            ASSERT_VALID_ENTITY(id)
            local ctor = ctype_ctors[ctype]
            if ctor == false or ctor == true then throw(`entity does not have component and no constructor for {ctype_debug(ctype)}`) end
            local value = fn((ctor :: () -> T)())
            ASSERT(value ~= nil, "patcher cannot return nil")
            POOL_ADD(pool, id, value)
        end
    end

    registry.has = (function(self: Registry, id: entity, a, b, c, d, e): boolean
        local key = ID_KEY(id)
        local idx_ver = POOL_FIND(GET_POOL(a), key)
        return
            idx_ver ~= ID_NULL and ID_VER(idx_ver) == ID_VER(id) and
            (b == nil or POOL_FIND(GET_POOL(b), key) ~= ID_NULL) and
            (c == nil or POOL_FIND(GET_POOL(c), key) ~= ID_NULL) and
            (d == nil or POOL_FIND(GET_POOL(d), key) ~= ID_NULL) and
            (e == nil or throw("args exceeded") :: never)
    end :: any) :: <T...>(self: Registry, id: entity, T...) -> boolean

    local function POOL_GET(ctype: CType, key: number): unknown
        local pool = GET_POOL(ctype)
        local idx_ver = POOL_FIND(pool, key)
        if idx_ver == ID_NULL then throw("entity does not have " .. ctype_debug(ctype)) end
        return ARRAY_GET(pool.values, ID_KEY(idx_ver)) 
    end

    registry.get = (function(self: Registry, id: entity, a, b, c, d, e): ...unknown
        local pool = GET_POOL(a)
    
        local key = ID_KEY(id)
        local idx_ver = POOL_FIND(pool, key)
        if idx_ver == ID_NULL then throw(`entity does not have {ctype_debug(a, 1)}`) end

        ID_ASSERT_VERSION_EQUAL(idx_ver, id)
        local va = ARRAY_GET(pool.values, ID_KEY(idx_ver))

        if b == nil then
            return va
        elseif c == nil then
            return va, POOL_GET(b, key)
        elseif d == nil then
            return va, POOL_GET(b, key), POOL_GET(c, key)
        elseif e == nil then
            return va, POOL_GET(b, key), POOL_GET(c, key), POOL_GET(d, key)
        else throw("args exceeded") end
    end :: any) :: <T...>(self: Registry, id: entity, T...) -> T...

    function registry.try_get<T>(self: Registry, id: entity, ctype: T): T?
        local pool = GET_POOL(ctype)
        local idx_ver = POOL_FIND(pool, ID_KEY(id))
        if idx_ver == ID_NULL or ID_VERSION_NOT_EQUAL(idx_ver, id) then return nil end
        return ARRAY_GET(pool.values, ID_KEY(idx_ver))
    end

    function registry.remove<T...>(self: Registry, id: entity, ...: T...)
        for i = 1, select("#", ...) do
            local pool = GET_POOL(select(i, ...))
            POOL_TRY_REMOVE(pool, id)
        end
    end

    function registry.clear<T...>(self: Registry, ...: T...)
        local argn = select("#", ...)
        if argn > 0 then
            for i = 1, argn do pool_clear(GET_POOL(select(i, ...))) end
        else
            for _, pool in next, ctype_pools do pool_clear(pool) end
            entity_pool_clear(entity_pool)
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

    registry.group = nil :: any -- todo: why?
    function registry.group<T...>(self: Registry, ...: T...): Group<T...>
        local argn = select("#", ...)
        ASSERT(argn > 1, "group must contain at least 2 components")
        local group = GET_POOL((select(1, ...))).group :: GroupData<unknown>

        for i = 1, argn do
            local ctype = select(i, ...)
            ASSERT_VALID_CTYPE(ctype, i)
            ASSERT(GET_POOL(ctype).group == group, `cannot create group; {ctype_debug(ctype, i)} is not owned by the same group as previous args`)
        end

        return Group.new(self, group or group_init(...), ...)
    end

    local function GET_POOL_OR_ENTITY_POOL<T>(ctype: T): Pool<T>
        return ctype == ctype_entity and entity_pool :: Pool<any> or GET_POOL(ctype)
    end

    function registry.storage<T>(self: Registry, ctype: T?): any
        if ctype then
            return GET_POOL_OR_ENTITY_POOL(ctype)
        else
            return coroutine.wrap(function()
                for ctype, pool in next, ctype_pools do
                    coroutine.yield(ctype, pool)
                end
            end)
        end
    end

    function registry.on_add<T>(self: Registry, ctype: T): Signal<entity, T>
        return (signals.on_add[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.on_add[ctype] = signal
            GET_POOL_OR_ENTITY_POOL(ctype).on_add = listeners
            return signal
        end)()) :: Signal<entity, T>
    end

    function registry.on_change<T>(self: Registry, ctype: T): Signal<entity, T>
        return (signals.on_change[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.on_change[ctype] = signal
            GET_POOL_OR_ENTITY_POOL(ctype).on_change = listeners
            return signal    
        end)()) :: Signal<entity, T>    
    end

    function registry.on_remove<T>(self: Registry, ctype: T): Signal<entity, nil>
        return signals.on_remove[ctype] or (function() 
            local signal, listeners = signal_create()
            signals.on_remove[ctype] = signal
            GET_POOL_OR_ENTITY_POOL(ctype).on_remove = listeners
            return signal
        end)() :: Signal<entity, nil>
    end

    function registry.handle(self: Registry, id: entity?): Handle
        id = id or self:create()

        local handle = handle_cache[id]

        if not handle then
            handle = table.freeze(setmetatable({
                registry = self,
                entity = id :: entity
            }, Handle))

            handle_cache[id] = handle
        end

        return assert(handle)
    end

    function registry.context(self: Registry): Handle
        if not self:contains(ID_CTX) then self:create(ID_CTX) end
        return self:handle(ID_CTX)  
    end

    return table.freeze(registry)
end

--------------------------------------------------------------------------------
-- queue
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

        setmetatable(self.columns, {
            __index = function(columns: Array<Array<unknown>>, idx: number)
                columns[idx] = {}
                return columns[idx]
            end
        })

        return self :: Queue<T...>
    end

    function Queue.add(self: _Queue, ...: unknown)
        -- iteration will stop if first value is `nil`
        ASSERT((...) ~= nil, "first argument cannot be nil")

        local columns = self.columns
        local n = self.size + 1
        self.size = n

        for i = 1, select("#", ...) do
            columns[i][n] = select(i, ...)
        end
    end

    function Queue.clear(self: _Queue)
        self.size = 0
        for _, column in next, self.columns do
            table.clear(column)
        end
    end

    local function iter(self: _Queue)
        local columns = self.columns
        local n = self.size
        local i = 0

        if #columns <= 1 then
            local column = columns[1]
            return function()
                i += 1
                local value = column[i]
                if i == n then self:clear() end
                return value
            end
        else
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

    Queue.iter = iter
    Queue.__iter = iter

    function Queue.__len(self: _Queue)
        return self.size
    end
end

type ISignal<T...> = {
    connect: (self: any, listener: (T...) -> ()) -> ()
} | {
    Connect: (self: any, listener: (T...) -> ()) -> ()
}

local queue_create = function<T...>(signal: ISignal<T...>?): Queue<T...>
    local queue = Queue.new()

    if signal then
        local connector = (signal :: any).connect or (signal :: any).Connect
        ASSERT(connector, "signal has no member `connect()`")
        connector(signal, function(...: T...)
            queue:add(...)
        end)
    end

    return queue
end :: ( <T...>() -> Queue<T...> ) & ( <T...>(signal: ISignal<T...>) -> Queue<T...> )

--------------------------------------------------------------------------------
-- buffer util
--------------------------------------------------------------------------------

local function buffer_to_array(buf: buffer, size: number, arr: Array<entity>?): Array<entity>
    ASSERT(size * ID_SIZE <= buffer.len(buf), "buffer is smaller than given size")

    arr = arr or table.create(size); assert(arr)

    for i = 0, size - 1 do
        arr[i + 1] = BUFFER_GET(buf, i)
    end

    return arr
end

local function array_to_buffer(arr: Array<entity>, size: number, buf: buffer?): buffer
    buf = buf or buffer.create(size * ID_SIZE); assert(buf)

    ASSERT(size * ID_SIZE <= buffer.len(buf), "size is larger than buffer size")

    for i, id in ipairs(arr) do
        BUFFER_SET(buf, (i - 1), id)
    end

    return buf
end

--------------------------------------------------------------------------------
-- export
--------------------------------------------------------------------------------

local ecr = {
    registry = registry_create,

    component = function(constructor: () -> ()?)
        ASSERT(constructor == nil or type(constructor) == "function", "constructor must be a function")
        return ctype_create(constructor or false)
    end :: (() -> unknown) & (<T>(constructor: () -> T) -> T),

    tag = ctype_create_tag :: () -> nil,

    is_tag = function<T>(ctype: T): boolean
        ASSERT_VALID_CTYPE(ctype)
        return ctype_is_tag(ctype)
    end,
    
    name = function<T>(v: T): T | string?
        if type(v) == "table" then
            for name, ctype in next, v do
                ASSERT(ctype_is_valid(ctype), `{name} refers to an invalid component`)
                ctype_set_name(ctype, name)
            end
            return v
        else
            ASSERT_VALID_CTYPE(v)
            return ctype_names[v]
        end
    end :: (<T>(names: T & {}) -> T) & (<T>(ctype: T) -> string?),
    
    queue = queue_create,
    
    array_to_buffer = array_to_buffer,
    buffer_to_array = buffer_to_array,

    entity = ctype_entity,
    null = ID_NULL,
    context = ID_CTX,
    id_size = ID_SIZE,

    inspect = function(id: entity): (number, number)
        local key, ver = ID_KEY(id), ID_VER(id)
        return key, ver * ID_RSHIFT
    end,
    
    _test = table.freeze {
        defer_id_reuse = DEFER_ID_REUSE,
        ver_shift = ID_LSHIFT,
        max_ver = ID_MASK_VER * ID_RSHIFT,
        max_creatable = ID_MASK_KEY - 1,

        create_id = function(key: number, ver: number)
            return ID_CREATE(key, ver * ID_LSHIFT)
        end,

        set_key_version = function(pool: EntityPool, key: number, ver: number)
            local data = BUFFER_GET(pool.map, key)
            if IS_IN_USE(data) then ASSERT(false, "attempt to set version of in-use entity") end
            BUFFER_SET(pool.map, key, ID_CREATE(ID_KEY(data), ver * ID_LSHIFT))
        end,
    
        get_key_version = function(pool: EntityPool, key: number): number
            ASSERT(POOL_CONTAINS(pool, key), "not contained")
            return ID_VER(BUFFER_GET(pool.map, key)) * ID_RSHIFT
        end
    }
}

return table.freeze(ecr)
