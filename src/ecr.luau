--------------------------------------------------------------------------------
-- ecr.luau
-- v0.7.0
--------------------------------------------------------------------------------

local ID_SIZE = 4
local MAX_ENTITIES = 0x0000_FFFF
local INIT_STORAGE_SIZE = 1
local DEFER_ID_REUSE = true

-- type buffer = { __buffer: true }

-- type bufferlib = {
--     create: (size: number) -> buffer,
--     fromstring: (s: string) -> buffer,
--     tostring: (b: buffer) -> string,
--     len: (b: buffer) -> number,
--     copy: (tar_b: buffer, tar_off: number, src_b: buffer, src_off: number?, count: number?) -> (),
--     fill: (b: buffer, offset: number, value: number, count: number?) -> (),

--     readi8: (b: buffer, offset: number) -> number,
--     readu8: (b: buffer, offset: number) -> number,
--     readi16: (b: buffer, offset: number) -> number,
--     readu16: (b: buffer, offset: number) -> number,
--     readi32: (b: buffer, offset: number) -> number,
--     readu32: (b: buffer, offset: number) -> number,
--     readf32: (b: buffer, offset: number) -> number,
--     readf64: (b: buffer, offset: number) -> number,

--     writei8: (b: buffer, offset: number, value: number) -> number,
--     writeu8: (b: buffer, offset: number, value: number) -> number,
--     writei16: (b: buffer, offset: number, value: number) -> number,
--     writeu16: (b: buffer, offset: number, value: number) -> number,
--     writei32: (b: buffer, offset: number, value: number) -> number,
--     writeu32: (b: buffer, offset: number, value: number) -> number,
--     writef32: (b: buffer, offset: number, value: number) -> number,
--     writef64: (b: buffer, offset: number, value: number) -> number,
-- }

-- local buffer = buffer :: bufferlib

local NIL = nil :: any

type Array<T> = { [number]: T }
type Map<T, U> = { [T]: U }
type CType = unknown

export type Entity = number

export type Signal<T...> = {
    connect: (self: Signal<T...>, listener: (T...) -> ()) -> Connection,
}

export type Connection = {
    disconnect: (self: Connection) -> (),
    reconnect: (self: Connection) -> ()
}

type Listener<T> = (id: Entity, value: T) -> ()

type EntityPool<T = nil> = Pool<T> & {
    free: number -- head of list
}

type Pool<T> = {
    map_max: number, -- largest key map can fit
    capacity: number, -- max amount of entities
    size: number, -- cur amount of entities
    map: buffer, -- map keys to internal index
    entities: buffer, -- all ids
    values: Array<T>, -- all values

    -- false instead of nil to preserve table shape
    added: Array<Listener<T>> | false,
    changed: Array<Listener<T>> | false,
    removing: Array<Listener<nil>> | false,
    group: GroupData<T> | false,

    reserve: (self: Pool<T>, size: number) -> ()
}

type GroupData<T = unknown> = {
    size: number,
    added: boolean, -- flag used to detect iter invalidation
    connections: Array<Connection>,
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

export type Registry = {
    create: ((self: Registry, id: Entity) -> Entity) & ((self: Registry) -> Entity),
    release: (self: Registry, id: Entity) -> (),
    destroy: (self: Registry, id: Entity) -> (),
    contains: (self: Registry, id: Entity) -> boolean,

    orphaned: (self: Registry, id: Entity) -> boolean,
    add: <T...>(self: Registry, id: Entity, T...) -> (),
    set: <T>(self: Registry, id: Entity, ctype: T, value: T) -> (),
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
}

export type Queue<T...> = typeof(setmetatable({} :: {
    add: (self: Queue<T...>, T...) -> (),
    clear: (self: Queue<T...>) -> ()
}, {} :: {
    __iter: (self: Queue<T...>) -> () -> (T...),
    __len: (self: Queue<T...>) -> number  
}))

-- stack trace will always begin at first callsite outside of this file
local ASSERT = function<T>(v: T, msg: string): T
    if v then return v end

    local stack = 1
    while debug.info(stack, "s") == debug.info(1, "s") do
        stack += 1    
    end

    error(msg, stack)  
    return nil :: never
end :: typeof(assert)

local function strict(name: string)
    return function(_, idx: unknown)
        ASSERT(false, `{tostring(idx)} is not a valid member of {name}`)
    end
end

local function next_pow_of_2(x: number)
    assert(x >= 1 and x < 2^32)
    x -= 1
    x = bit32.bor(x, bit32.rshift(x, 1))
    x = bit32.bor(x, bit32.rshift(x, 2))
    x = bit32.bor(x, bit32.rshift(x, 4))
    x = bit32.bor(x, bit32.rshift(x, 8))
    x = bit32.bor(x, bit32.rshift(x, 16))
    return x + 1
end

--------------------------------------------------------------------------------
-- Entity Id
--------------------------------------------------------------------------------

local RESERVED_BITS = 1

local ID_SIZE_BITS = ID_SIZE * 8
local ID_MAX = 2^(ID_SIZE_BITS - RESERVED_BITS) - 1

local ID_RESRVED_MASK = 0xFFFF_FFFF - ID_MAX

local ID_MASK_KEY = MAX_ENTITIES
local ID_MASK_VER = ID_MAX - ID_MASK_KEY

local ID_LSHIFT = ID_MASK_KEY + 1
local ID_RSHIFT = 1/ID_LSHIFT

local ID_NULL_KEY = ID_MASK_KEY
local ID_CTX_KEY = 0

local ID_NULL_VER = 0
local ID_MIN_VER = 1 * ID_LSHIFT

assert(ID_SIZE <= 4 and ID_SIZE >= 1)
assert(MAX_ENTITIES <= ID_MAX/2 and MAX_ENTITIES > 0)
assert(bit32.band(MAX_ENTITIES + 1, MAX_ENTITIES) == 0)

local function ID_CREATE(key: number, ver: number): number
    return ver + key
end

local function ID_KEY(id: number): number
    return bit32.band(id, ID_MASK_KEY)
end

local function ID_KEY_VER(id: number): (number, number)
    return bit32.band(id, ID_MASK_KEY), bit32.band(id, ID_MASK_VER)
end

local function ID_VER(id: number): number
    return bit32.band(id, ID_MASK_VER)
end

local function ID_SWAP_KEY(id: number, new_key: number): number
    return id - ID_KEY(id) + new_key
end

local function ID_VERSIONS_NOT_EQUAL(id1: number, id2: number)
    return ID_VER(id1) ~= ID_VER(id2)
end

local function ID_VERSIONS_EQUAL(id1: number, id2: number)
    return ID_VER(id1) == ID_VER(id2)
end

local function ID_ASSERT_VERSIONS_EQUAL(id1: number, id2: number)
    if ID_VERSIONS_NOT_EQUAL(id1, id2) then
        ASSERT(false, `invalid entity`)    
    end
end

local ID_NULL = ID_CREATE(ID_NULL_KEY, ID_NULL_VER) -- always rejected by registry
local ID_CTX = ID_CREATE(ID_CTX_KEY, ID_MIN_VER) -- special reserved entity

--------------------------------------------------------------------------------
-- Component Type
--------------------------------------------------------------------------------

-- a constructor set to `ctype_TAG` indicates that the component is a tag
local ctype_TAG: true = true

local ctype_n = 0
local ctype_names: Map<CType, string> = {}
local ctype_ctors: Map<CType, ((() -> unknown) | false | typeof(ctype_TAG)?)> = {}

local function ctype_create<T>(constructor: (() -> T) | typeof(ctype_TAG)): CType
    ctype_n += 1

    -- fill array to prevent conversion to hashmap
    for i = #ctype_ctors + 1, ctype_n - 1 do
        ctype_ctors[i] = false
    end

    ctype_ctors[ctype_n] = constructor
    return ctype_n
end

local function ctype_tag(): CType
    return ctype_create(ctype_TAG)
end

local function ctype_is_tag(ctype: CType): boolean
    return ctype_ctors[ctype] == ctype_TAG
end

local function ctype_valid(v: unknown): boolean
    return type(v) == "number" and math.floor(v) == v and v > 0 and v <= ctype_n  
end

local function ctype_name(ctype: CType, name: unknown)
    ctype_names[ctype] = tostring(name)
end

-- generates an error message for debugging
local ctype_debug: (ctype: CType?, idx: number?) -> () = (function()
    return function(ctype: CType?, idx: number?)
        local name = ctype_names[ctype]
        return
            if name then `component "{name}"`
            elseif idx then `component (arg #{idx})`
            else "component (unknown)"
    end
end)()

-- special entity component
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

local function BUFFER_GET(b: buffer, i: number): number
    return buffer.readu32(b, i * ID_SIZE)
end

local function BUFFER_SET(b: buffer, i: number, id: Entity)
    buffer.writeu32(b, i * ID_SIZE, id)
end

local function BUFFER_FILL(b: buffer, v: number)
    assert(buffer.len(b) % ID_SIZE == 0)
    for i = 0, buffer.len(b) - 1, ID_SIZE do
        buffer.writeu32(b, i, v)
    end
end

local function POOL_CONTAINS<T>(p: Pool<T>, i: number): boolean
    return p.map_max >= i
end

local function BUFFER_RESIZE(b: buffer, size: number): buffer
    local b_new = buffer.create(size * ID_SIZE)
    local n_old = buffer.len(b)

    buffer.copy(b_new, 0, b)

    for i = n_old, size * ID_SIZE - 1, ID_SIZE do
        buffer.writeu32(b_new, i, ID_NULL)
    end

    return b_new
end

local function BUFFER_CLONE(b: buffer): buffer
    local b_new = buffer.create(buffer.len(b))
    buffer.copy(b_new, 0, b)
    return b_new
end

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

local function ARRAY_REMOVE_BY_SWAP<T>(t: Array<T>, remove: number, swap: number)
    remove += 1
    swap += 1
    t[remove] = t[swap]
    t[swap] = nil
end

local function pool_resize_entities<T>(self: Pool<T>, size: number)
    if self.capacity >= size then return end

    local new_capacity = next_pow_of_2(size)
    self.entities = BUFFER_RESIZE(self.entities, new_capacity)
    self.capacity = new_capacity
end

local function pool_resize_map<T>(self: Pool<T>, size: number)
    local new_map_capacity = next_pow_of_2(size)
    self.map = BUFFER_RESIZE(self.map, new_map_capacity)
    self.map_max = new_map_capacity - 1
end

local function pool_check_map_size<T>(self: Pool<T>, size: number)
    if self.map_max < size then -- todo
        pool_resize_map(self, size + 1) -- todo: why + 1
    end
end

-- swaps position of two internal elements
local function POOL_SWAP<T>(
    self: Pool<T>,
    idx: number,
    target_idx: number
)
    local map = self.map
    local entities = self.entities
    local values = self.values

    local id = BUFFER_GET(entities, idx)
    local key = ID_KEY(id)

    local id_swap = BUFFER_GET(entities, target_idx)
    local key_swap = ID_KEY(id_swap)

    BUFFER_SET(entities, target_idx, id)
    BUFFER_SET(entities, idx, id_swap)

    BUFFER_SET(map, key, ID_SWAP_KEY(id, target_idx))
    BUFFER_SET(map, key_swap, ID_SWAP_KEY(id_swap, idx))
    
    ARRAY_SWAP(values, target_idx, idx)
end

local function POOL_HAS<T>(self: Pool<T>, id: Entity): boolean
    if self.map_max < ID_KEY(id) then return false end
    local idx_ver = BUFFER_GET(self.map, ID_KEY(id))
    return not ID_VERSIONS_NOT_EQUAL(id, idx_ver)
end

-- checks then moves elements into group
-- undefined if element is already in group
local function POOL_TRY_GROUP<T>(pool: Pool<T>, id: number)
    local group = pool.group :: GroupData<T>

    local key = ID_KEY(id)

    -- search through all pools in group to check if entity can be added
    for _, pool in ipairs(group) do
        if not POOL_CONTAINS(pool, key) or BUFFER_GET(pool.map, key) == ID_NULL then
            return
        end
    end

    local n = group.size
    group.size = n + 1

    group.added = true

    for _, pool in ipairs(group) do
        POOL_SWAP(pool, ID_KEY(BUFFER_GET(pool.map, key)), n)
    end
end

-- returns new internal index of id
local function POOL_TRY_UNGROUP<T>(pool: Pool<T>, id: Entity)
    local group = pool.group :: GroupData<T>

    local idx = ID_KEY(BUFFER_GET(pool.map, ID_KEY(id)))
    local n = group.size
    if idx < n then -- is in group, swap needed
        group.size = n - 1
        for _, pool in ipairs(group) do        
            POOL_SWAP(pool, idx, n - 1)
        end
    end
end

local function pool_check_entities_size<T>(self: Pool<T>)
    if self.size == self.capacity then
        pool_resize_entities(self, self.capacity * 2)
    end
end

-- adds id and value to pool
-- undefined if id is already in pool
local function POOL_ADD<T>(self: Pool<T>, id: Entity, v: T)
    pool_check_entities_size(self)
    
    local n = self.size
    self.size = n + 1

    BUFFER_SET(self.map, ID_KEY(id), ID_CREATE(n, ID_VER(id)))
    BUFFER_SET(self.entities, n, id)
    ARRAY_SET(self.values, n, v)

    if self.added then fire(self.added, id, v) end
end

-- removes id from pool
-- does nothing if not in pool
local function POOL_TRY_REMOVE<T>(self: Pool<T>, id: Entity)
    local key = ID_KEY(id)
    local map = self.map

    if POOL_CONTAINS(self, key) and BUFFER_GET(map, key) ~= ID_NULL then
        if self.removing then fire(self.removing, id) end

        local idx_ver = BUFFER_GET(map, key) -- double get cause of groups
        local idx = ID_KEY(idx_ver)

        -- todo:
        --ID_ASSERT_VERSIONS_EQUAL(idx_ver, id)
        if ID_VERSIONS_NOT_EQUAL(idx_ver, id) then return end

        local n = self.size - 1; self.size = n
        local entities = self.entities
        local values = self.values

        local last_id = BUFFER_GET(entities, n)
        local last_key = ID_KEY(last_id)

        BUFFER_SET(map, last_key, ID_SWAP_KEY(last_id, idx))
        BUFFER_SET(map, key, ID_NULL)

        BUFFER_SET(entities, idx, last_id)
        BUFFER_SET(entities, n, ID_NULL)

        ARRAY_REMOVE_BY_SWAP(values, idx, n)
    end
end

-- adds only id to pool
-- does nothing if already in pool
-- does not fire signals
local function POOL_TRY_ADD_ID<T>(self: Pool<T>, id: Entity)
    
    local key = ID_KEY(id)
    
    pool_check_map_size(self, key)
    local map = self.map

    local idx_ver = BUFFER_GET(map, key)

    if idx_ver == ID_NULL then
        pool_check_entities_size(self)
        local n = self.size; self.size = n + 1
        BUFFER_SET(map, key, ID_SWAP_KEY(id, n))
        BUFFER_SET(self.entities, n, id)
    end 
end

-- removes only id from pool
-- does nothing if already removed
-- does not fire signals
local function POOL_TRY_REMOVE_ID<T>(self: Pool<T>, id: Entity)
    local map = self.map
    local entities = self.entities

    local key = ID_KEY(id)

    if not POOL_CONTAINS(self, key) then return end
    local idx_ver = BUFFER_GET(map, key)

    if idx_ver ~= ID_NULL then
        local n = self.size - 1; self.size = n
        local idx = ID_KEY(idx_ver)
        local last_id = BUFFER_GET(entities, n)
        local last_key = ID_KEY(last_id)

        BUFFER_SET(map, last_key, ID_SWAP_KEY(last_id, idx))
        BUFFER_SET(map, key, ID_NULL)
        
        BUFFER_SET(entities, idx, last_id)
        BUFFER_SET(entities, n, ID_NULL)
    end
end

-- removes all elements in pool
local function POOL_CLEAR<T>(self: Pool<T>)
    -- todo: do not disconnect added listeners
    -- disconnect group listeners to avoid needless swapping
    if self.group then
        for _, connection in self.group.connections do
            connection:disconnect()
        end
    end

    local signal = self.removing :: Array<Listener<nil>>
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
    BUFFER_FILL(self.map, ID_NULL)
    table.clear(self.values)
end

local function pool_create<T>(size: number?): Pool<T>
    local n = size or 1

    local map = buffer.create(n * ID_SIZE)
    BUFFER_FILL(map, ID_NULL)

    return {
        map_max = n - 1,
        capacity = n,
        size = 0,
        map = map,
        entities = buffer.create(n * ID_SIZE),
        values = table.create(n),

        added = false,
        changed = false,
        removing = false,
        group = false,

        reserve = function(self: Pool<T>, size: number)
            pool_resize_map(self, size)
            pool_resize_entities(self, size)
        
            -- todo
            local values = self.values
            for i = self.size, size - 1 do
                values[i] = true :: any
            end
            for i = self.size, size - 1 do
                values[i] = nil
            end
        end
    }
end

local function pool_clone<T>(self: Pool<T>): Pool<T>
    return {
        map_max = self.map_max,
        capacity = self.capacity,
        size = self.size,
        map = BUFFER_CLONE(self.map),
        entities = BUFFER_CLONE(self.entities),
        values = table.clone(self.values),

        added = false,
        changed = false,
        removing = false,
        group = false,

        set = self.set,
        get = self.get,
        has = self.has,
        remove = self.remove,
        reserve = self.reserve
    }
end

local function entity_pool_initialize(self: EntityPool, start: number, stop: number)
    for i = start, stop - 1 do
        BUFFER_SET(self.map, i, ID_CREATE(i + 1, ID_MIN_VER))
    end

    BUFFER_SET(self.map, stop, ID_CREATE(ID_NULL_KEY, ID_MIN_VER))
end



local function IN_USE(id: number): boolean
    return bit32.band(id, ID_RESRVED_MASK) > 0
end

local function MARK_IN_USE(id: number): number
    return bit32.bor(id, ID_RESRVED_MASK)
end

local function MARK_UNUSED(id: number): number
    return bit32.band(id, bit32.bnot(ID_RESRVED_MASK))
end

local function entity_pool_expand(self: EntityPool, size: number)
    if self.capacity >= size then return end
    local new_capacity = next_pow_of_2(size)

    ASSERT(new_capacity - 1 <= ID_MASK_KEY, "entity limit reached")

    local last = self.capacity - 1

    if self.free ~= ID_NULL_KEY then -- find end of list
        local prev = self.free
        local i = 0; repeat i += 1 -- find id before desired id
            local next = ID_KEY(BUFFER_GET(self.map, prev))
            if next == ID_NULL_KEY then break end
            prev = next
        until i == ID_MASK_KEY
        ASSERT(i < ID_MASK_KEY, "timeout occured")
        BUFFER_SET(self.map, prev, ID_SWAP_KEY(BUFFER_GET(self.map, prev), last + 1))
    else
        self.free = last + 1
    end


    self.map = BUFFER_RESIZE(self.map, new_capacity)
    self.entities = BUFFER_RESIZE(self.entities, new_capacity)

    
    local new_last = new_capacity - 1

    entity_pool_initialize(self, last + 1, new_last)

    self.capacity = new_capacity
end

-- specialized pool used by the registry to track ids for reuse
local function entity_pool_create(): EntityPool
    local pool = pool_create(2) :: EntityPool
    entity_pool_initialize(pool, 1, 1)
    pool.free = 1

    pool.reserve = function(self, size)
        entity_pool_expand(self, size)
    end

    return pool
end

-- creates or reuses an id
local function entity_pool_add(self: EntityPool): Entity

    if self.free == ID_NULL_KEY then
        entity_pool_expand(self, self.capacity*2)
        assert(self.free ~= ID_NULL_KEY)
    end

    local next_key_ver = BUFFER_GET(self.map, self.free)
    local next_key = ID_KEY(next_key_ver)
    local new_key = self.free
    self.free = next_key
    local id = ID_SWAP_KEY(next_key_ver, new_key)
    BUFFER_SET(self.entities, self.size, id)
    BUFFER_SET(self.map, new_key, MARK_IN_USE(ID_SWAP_KEY(id, self.size)))
    self.size += 1
    if self.added then fire(self.added, id) end
    return id
end

-- reuses a specific id
local function entity_pool_reuse(self: EntityPool, id: Entity): Entity
    local key, ver = ID_KEY_VER(id)

    if id ~= ID_CTX then
        ASSERT(key ~= ID_NULL_KEY and ver ~= ID_NULL_VER, "malformed id")
    end

    local capacity = self.capacity

    local last = capacity - 1

    if key > last then -- key has not been created yet
        entity_pool_expand(self, key + 1)
    else
        ASSERT(
            not IN_USE(BUFFER_GET(self.map, key)), -- key is not in use
            "key already in use"
        )
    end

    if id == ID_CTX then

    elseif self.free == key then -- desired id is at head
        local next_free = ID_KEY(BUFFER_GET(self.map, self.free))
        self.free = next_free
    elseif BUFFER_GET(self.map, key) == ID_NULL then -- key is deprecated

    else -- desired id is somewhere along list
        local prev = self.free
        local i = 0; repeat i += 1 -- find id before desired id
            --if not POOL_CONTAINS(self, prev) then print(i) end
            local next = ID_KEY(BUFFER_GET(self.map, prev))
            if next == key then break end
            prev = next
        until i == ID_MASK_KEY
        ASSERT(i < ID_MASK_KEY, "timeout occured")
        BUFFER_SET(self.map, prev, ID_SWAP_KEY(BUFFER_GET(self.map, prev), ID_KEY(BUFFER_GET(self.map, key))))
    end

    local n = self.size; self.size = n + 1
    BUFFER_SET(self.map, key, MARK_IN_USE(ID_SWAP_KEY(id, n)))
    BUFFER_SET(self.entities, n, id)
    if self.added then fire(self.added, id) end
    return id


--[[
    local capacity = self.capacity
    local map = self.map :: Array<number>

    local free = self.free

    if key > capacity then -- if key has not been created yet
        if key > capacity + 1 then -- fill in gaps between last and new
            for i = capacity + 1, key - 2 do
                map[i] = - ID_CREATE(i + 1, ID_MIN_VER)
            end
            map[key - 1] = - ID_CREATE(free, ID_MIN_VER)
            self.free = capacity + 1
        end
        self.capacity = key
    elseif key <= capacity and map[key] ~= - ID_NULL then -- if key already exists and it isn't deprecated
        ASSERT(
            free ~= ID_NULL_KEY -- an unused key exists
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
            local prev = - map[previous]
            map[previous] = - ID_SWAP_KEY(prev, ID_KEY(- map[key]))
        end
    end
    local n = self.size + 1; self.size = n
    map[key] = ID_SWAP_KEY(id, n)
    self.entities[n] = id
    if self.added then fire(self.added, id) end
    return id]]
end

-- removes and marks an id for reuse
-- undefined if id is already marked for reuse
local function entity_pool_unsafe_remove(self: EntityPool, id: Entity)
    local key, ver = ID_KEY_VER(id)

    if self.removing then fire(self.removing, id) end

    local last = self.size - 1; self.size = last

    local map = self.map
    local entities = self.entities

    local idx = ID_KEY(BUFFER_GET(map, key))
    local last_id = BUFFER_GET(entities, last)
    local last_key = ID_KEY(last_id)

    BUFFER_SET(entities, idx, last_id)
    BUFFER_SET(map, last_key, MARK_IN_USE(ID_SWAP_KEY(last_id, idx)))

    if id == ID_CTX then
        BUFFER_SET(map, key, ID_NULL)
    elseif ver < ID_MASK_VER then
        BUFFER_SET(map, key, ID_CREATE(self.free, ver + ID_MIN_VER)) -- recycle key
        self.free = key
    elseif DEFER_ID_REUSE then
        BUFFER_SET(map, key, ID_NULL) -- deprecate key
    else
        BUFFER_SET(map, key, ID_CREATE(self.free, ID_MIN_VER)) -- reset version and recycle key
        self.free = key
    end 
end

-- checks if an id is not marked for reuse and is contained in the pool
local function entity_pool_has(self: EntityPool, id: number): boolean
    return self.capacity > ID_KEY(id) and ID_SWAP_KEY(BUFFER_GET(self.map, ID_KEY(id)), ID_KEY(id)) == MARK_IN_USE(id)
end

local function entity_pool_clear(self: EntityPool)
    local entities = self.entities

    if self.removing then
        for i = self.size, 1, -1 do
            fire(self.removing, BUFFER_GET(entities, i - 1))
        end
    end

    -- todo: optimize
    for i = self.size, 1, -1 do
        entity_pool_unsafe_remove(self, BUFFER_GET(entities, i - 1))
    end
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

local View, Observer, Group do

type IRegistry = {
    storage: <T>(self: IRegistry, ctype: T) -> Pool<T>,
    added: <T>(self: IRegistry, ctype: T) -> Signal<Entity, T>,
    changed: <T>(self: IRegistry, ctype: T) -> Signal<Entity, T>,
    removing: <T>(self: IRegistry, ctype: T) -> Signal<Entity, nil>,
}

local WEAK_VALUES = { __mode = "v" }

-- checks if any of the given pools contain a key
local function has_any(pools: Array<Pool<unknown>>, key: number): boolean
    for _, pool in next, pools do
        if BUFFER_GET(pool.map, key) ~= ID_NULL then return true end
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
        local i = n - 1; n = i
        if i < 0 then
            ASSERT_INVALIDATION(pool)
            return NIL, NIL
        end
        return BUFFER_GET(entities, i), ARRAY_GET(values, i)
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
            for i = n - 1, 0, -1 do
                local id = BUFFER_GET(entities, i)
                local idx_ver = BUFFER_GET(b.map, ID_KEY(id))
                if idx_ver == ID_NULL then continue end
                local vb = ARRAY_GET(b.values, ID_KEY(idx_ver))
                n = i
                return id, ARRAY_GET(values, i), vb
            end
            return ASSERT_INVALIDATION(a)
        end
    else
        local n = nb
        local entities = b.entities
        local values = b.values

        clear_invalidation_flag(b)

        return function()
            for i = n - 1, 0, -1 do
                local id = BUFFER_GET(entities, i)
                local idx_ver = BUFFER_GET(a.map, ID_KEY(id))
                if idx_ver == ID_NULL then continue end
                local va = ARRAY_GET(a.values, ID_KEY(idx_ver))
                n = i
                return id, va, ARRAY_GET(values, i)   
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
        for i = n - 1, 0, -1 do
            local id = BUFFER_GET(entities, i)
            local key = ID_KEY(id)
            
            if excludes and has_any(excludes, key) then continue end

            local has_all = true
            for ii, pool in next, includes do
                local idx_ver = BUFFER_GET(pool.map, key)
                if idx_ver == ID_NULL then has_all = false; break end
                tuple[ii] = ARRAY_GET(pool.values, ID_KEY(idx_ver))
            end
            if has_all == false then continue end

            n = i
            return id, unpack(tuple)
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
            ASSERT(false, `invalid { ctype_debug(nil, i) }`)
        end

        if table.find(includes, ctype) then
            ASSERT(false, `duplicate { ctype_debug(ctype, i) } included`)
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
        pool = pool_clone(reg:storage(ctype_first)), -- treat all initial ids as changed
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
                    ASSERT(false, `invalid { ctype_debug(nil, i) }`)
                end

                if table.find(self.includes, ctype) then
                    ASSERT(false, `cannot exclude { ctype_debug(ctype, i) }, component is being tracked`)
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
                    POOL_TRY_ADD_ID(pool, id)
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
            POOL_CLEAR(self.pool)
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
                        local i = n - 1; n = i
                        if i == -1 then
                            if not persist then self:clear() end
                            return nil :: any
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
        
                            if excludes and has_any(excludes, key) then continue end
        
                            local has_all = true
                            for ii, pool in next, includes do
                                local idx_ver = BUFFER_GET(pool.map, key)
                                if idx_ver == ID_NULL then has_all = false; break end
                                tuple[ii] = ARRAY_GET(pool.values, ID_KEY(idx_ver))
                            end
                            if has_all == false then continue end
        
                            n = i
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

    -- must keep remove listener connected after `Observer:disconnect()`
    -- weakref is used to check if the observer has been garbage collected
    local weakref = setmetatable({ self = self }, WEAK_VALUES) :: any
    local function try_remove(id: number)
        if weakref.self == nil then disconnect_all(connections) end
        POOL_TRY_REMOVE_ID(pool, id) -- todo: inline
    end

    for i = 1, select("#", ...) do
        local ctype = select(i, ...)
        table.insert(connections, reg:removing(ctype):connect(try_remove))
    end

    return self:reconnect()
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
                    local ari = n
                    if ari == 0 then return NIL end
                    local i = ari - 1; n = i
                    return BUFFER_GET(entities, i), a[ari]  
                end
            elseif #pools == 2 then
                local a, b = unpack(values)
                return function()
                    local ari = n
                    if ari == 0 then return NIL end
                    local i = ari - 1; n = i
                    return BUFFER_GET(entities, i), a[ari], b[ari] 
                end
            elseif #pools == 3 then
                local a, b, c = unpack(values)
                return function()
                    local ari = n
                    if ari == 0 then return NIL end
                    local i = ari - 1; n = i
                    return BUFFER_GET(entities, i), a[ari], b[ari], c[ari]
                end
            elseif #pools == 4 then
                local a, b, c, d = unpack(values)
                return function()
                    local ari = n
                    if ari == 0 then return NIL end
                    local i = ari - 1; n = i
                    return BUFFER_GET(entities, i), a[ari], b[ari], c[ari], d[ari]
                end
            else
                local tuple = table.create(#values) :: Array<any>
                return function()
                    local ari = n
                    if ari == 0 then return NIL end
                    local i = ari - 1; n = i
                    for ii, v in next, values do
                        tuple[ii] = v[ari]
                    end
                    return BUFFER_GET(entities, i), unpack(tuple)
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
            connected = true, -- track in case of id reuse

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
                pool_check_map_size(self.pool, n)
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
-- Registry
--------------------------------------------------------------------------------

local function registry_create(): Registry
    local registry = {}

    local id_pool = entity_pool_create()

    --INSPECT_IDS(id_pool, true)



    --INSPECT_IDS(id_pool, true)

    local all_pools: Map<CType, Pool<unknown>> = table.create(ctype_n)
    all_pools[ctype_entity] = id_pool :: Pool<any>

    -- excludes entity pool, operations not allowed on it
    local ctype_pools: Map<CType, Pool<unknown>> = table.create(ctype_n)

    local signals = {
        added = {} :: Map<CType, Signal<Entity, unknown>>,
        changed = {} :: Map<CType, Signal<Entity, unknown>>,
        removing = {} :: Map<CType, Signal<Entity, nil>>
    }

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
        local group = { size = 0, added = false, connections = {} }

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = get_ctype_pool(ctype)
            group[i] = pool
            pool.group = group

            table.insert(group.connections, registry:added(ctype):connect(function(id)
                POOL_TRY_GROUP(pool, id)
            end))

            table.insert(group.connections, registry:removing(ctype):connect(function(id)
                POOL_TRY_UNGROUP(pool, id)
            end))
        end

        local pool = get_ctype_pool((...))

        -- add any entities already in pools to group
        local entities = pool.entities
        for i = 0, pool.size - 1 do
            POOL_TRY_GROUP(pool, BUFFER_GET(entities, i))
        end

        return group
    end

    local function ASSERT_VALID_ENTITY(key: number, id: Entity)
        if entity_pool_has(id_pool, id) == false then
            ASSERT(false, `invalid entity`)
        end
    end

    local function ASSERT_NOT_RESERVED(key: number, id: Entity)
        if key == 0 then
            ASSERT(false, "cannot release id")
        end
    end

    function registry.create(self: Registry, id: Entity?): Entity
        if id_pool.size >= ID_MASK_KEY then ASSERT(false, "cannot create entity; registry is at max entities") end
        return id and entity_pool_reuse(id_pool, id) or entity_pool_add(id_pool)
    end

    function registry.release(self: Registry, id: Entity)
        ASSERT_VALID_ENTITY(ID_KEY(id), id)
        --ASSERT_NOT_RESERVED(ID_KEY(id), id)
        entity_pool_unsafe_remove(id_pool, id)
    end

    function registry.destroy(self: Registry, id: Entity)
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)
       -- ASSERT_NOT_RESERVED(ID_KEY(id), id)
        
        for _, pool in next, ctype_pools do
            POOL_TRY_REMOVE(pool, id)
        end

        entity_pool_unsafe_remove(id_pool, id)
    end

    function registry.contains(self: Registry, id: Entity): boolean
        return entity_pool_has(id_pool, id)
    end

    function registry.orphaned(self: Registry, id: Entity): boolean
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)

        for _, pool in next, ctype_pools do
            if BUFFER_GET(pool.map, key) ~= ID_NULL then return false end
        end
        return true
    end

    function registry.add<T...>(self: Registry, id: Entity, ...: T...)
        local key = ID_KEY(id)
        ASSERT_VALID_ENTITY(key, id)

        for i = 1, select("#", ...) do
            local ctype = select(i, ...)
            local pool = get_ctype_pool(ctype)

            pool_check_map_size(pool, key)

            -- continue if already added
            if BUFFER_GET(pool.map, key) ~= ID_NULL then continue end

            local constructor = ctype_ctors[ctype] or ASSERT(false, `no constructor defined for {ctype_debug(ctype, i)}`)
            local value
            if constructor ~= ctype_TAG then
                value = (constructor :: () -> unknown)()
                if value == nil then ASSERT(false, `{ ctype_debug(ctype, i) } constructor did not return a value`) end   
            end
            
            POOL_ADD(pool, id, value)
        end
    end

    function registry.set<T>(self: Registry, id: Entity, ctype: T, value: T)
        if value == nil then ASSERT(false, "cannot set nil value") end
        local pool = get_ctype_pool(ctype)

        local key = ID_KEY(id)

        pool_check_map_size(pool, key)

        local idx_ver = BUFFER_GET(pool.map, key)

        if idx_ver ~= ID_NULL then -- already added, change value
            ID_ASSERT_VERSIONS_EQUAL(idx_ver, id)
            ARRAY_SET(pool.values, ID_KEY(idx_ver), value)
            if pool.changed then fire(pool.changed, id, value) end
        else -- not added, add value
            ASSERT_VALID_ENTITY(key, id)
            POOL_ADD(pool, id, value)
        end
    end
    
    function registry.patch<T>(self: Registry, id: Entity, ctype: T, fn: (T) -> T)
        local pool = get_ctype_pool(ctype)

        local key = ID_KEY(id)

        pool_check_map_size(pool, key)

        local idx_ver = BUFFER_GET(pool.map, key)

        if idx_ver == ID_NULL then
            ASSERT_VALID_ENTITY(key, id)
            local ctor = ctype_ctors[ctype]
            if not ctor or ctor == ctype_TAG then
                ASSERT(false, `entity does not have component and no constructor for {ctype_debug(ctype)}`)
            end
            local value = fn((ctor :: () -> T)())
            if value == nil then ASSERT(false, "patcher cannot return nil") end
            POOL_ADD(pool, id, value)
        else
            local idx = ID_KEY(idx_ver)
            ID_ASSERT_VERSIONS_EQUAL(idx_ver, id)
            local value = fn(ARRAY_GET(pool.values, idx))
            if value == nil then ASSERT(false, "patcher cannot return nil") end
            ARRAY_SET(pool.values, idx, value)
            if pool.changed then fire(pool.changed, id, value) end
        end
    end

    registry.has = (function(self: Registry, id: Entity, ...: unknown): boolean
        local key = ID_KEY(id)
        for i = 1, select("#", ...) do
            local pool = get_ctype_pool(select(i, ...))
            if not POOL_CONTAINS(pool, key) then return false end
            local idx_ver = BUFFER_GET(pool.map, key)
            if idx_ver == ID_NULL or ID_VERSIONS_NOT_EQUAL(idx_ver, id) then return false end
        end
        return true
    end :: any) :: <T...>(self: Registry, id: Entity, T...) -> boolean

    local function pool_get(ctype: CType, key: number, id: number): unknown
        local pool = get_ctype_pool(ctype)
        if pool.map_max < key then ASSERT(false, `entity does not have {ctype_debug(ctype)}`) end
        local idx_ver = BUFFER_GET(pool.map, key)
        if idx_ver == ID_NULL then ASSERT(false, `entity does not have {ctype_debug(ctype)}`) end
        return ARRAY_GET(pool.values, ID_KEY(idx_ver)) 
    end

    registry.get = (function(self: Registry, id: Entity, a: unknown, ...: unknown): ...unknown
        local b, c, d, e = ...
        local key = ID_KEY(id)

        local pool = get_ctype_pool(a)
        if pool.map_max < key then ASSERT(false, `entity does not have {ctype_debug(a, 1)}`) end

        local idx_ver = BUFFER_GET(pool.map, key)
        if idx_ver == ID_NULL then ASSERT(false, `entity does not have {ctype_debug(a, 1)}`) end
        local idx = ID_KEY(idx_ver :: number)
        ID_ASSERT_VERSIONS_EQUAL(idx_ver :: number, id)
        local va = ARRAY_GET(pool.values, idx)

        if b == nil then
            return va
        elseif c == nil then
            return va, pool_get(b, key, id)
        elseif d == nil then
            return va, pool_get(b, key, id), pool_get(c, key, id)
        elseif e == nil then
            return va, pool_get(b, key, id), pool_get(c, key, id), pool_get(d, key, id)
        else
            local tuple: Array<any> = { ... }
            for i, v in next, tuple do
                tuple[i] = pool_get(v, key, id)
            end
            return va, unpack(tuple)
        end
    end :: any) :: <T...>(self: Registry, id: Entity, T...) -> T...

    function registry.try_get<T>(self: Registry, id: Entity, ctype: T): T?
        local pool = get_ctype_pool(ctype)
        local key = ID_KEY(id)

        if not POOL_CONTAINS(pool, key) then return nil end

        local idx_ver = BUFFER_GET(pool.map, key)
        if idx_ver == ID_NULL then return nil end

        local idx = ID_KEY(idx_ver)
        if ID_VERSIONS_NOT_EQUAL(idx_ver, id) then return nil end
        return ARRAY_GET(pool.values, idx)
    end

    function registry.remove<T...>(self: Registry, id: Entity, ...: T...)
        for i = 1, select("#", ...) do
            local pool = get_ctype_pool(select(i, ...))
            
            POOL_TRY_REMOVE(pool, id)
        end
    end

    function registry.clear<T...>(self: Registry, ...: T...)
        local argn = select("#", ...)
        if argn > 0 then
            for i = 1, argn do POOL_CLEAR(get_ctype_pool(select(i, ...))) end
        else
            for _, pool in next, ctype_pools do POOL_CLEAR(pool) end
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

    registry.group = nil :: any -- todo: why?
    function registry.group<T...>(self: Registry, ...: T...): Group<T...>
        local argn = select("#", ...)
        ASSERT(argn > 1, "groups must contain at least 2 components")
        local group = get_ctype_pool((select(1, ...))).group :: GroupData<unknown>

        for i = 1, argn do
            local ctype = select(i, ...)
            ASSERT(ctype_valid(ctype), `invalid { ctype_debug(nil, i) }`)
            ASSERT(get_ctype_pool(ctype).group == group,
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
        if not self:contains(ID_CTX) then
            self:create(ID_CTX)
        end
        return self:handle(ID_CTX)  
    end

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
        -- iteration will stop if first value is `nil`
        if ... == nil then ASSERT(false, "first value cannot be nil") end

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

    if signal then
        local connector = (signal :: any).connect or (signal :: any).Connect
        ASSERT(connector, "signal has no connector")
        connector(signal, function(...: T...)
            queue:add(...)
        end)
    end

    return queue
end :: ( <T...>() -> Queue<T...> ) & ( <T...>(signal: SignalInterface<T...>) -> Queue<T...> )

local function bnext(buf: buffer, i: number): (number, Entity)
    if i == 0 then return NIL, NIL end
    i -= 1
    return i, BUFFER_GET(buf, i)
end

local function copy_buffer_to_array(buf: buffer, arr: Array<Entity>, size: number)
    ASSERT(size * ID_SIZE <= buffer.len(buf), "buffer is smaller than given size")

    for i = 0, size - 1 do
        arr[i + 1] = BUFFER_GET(buf, i)
    end
end

local function copy_array_to_buffer(arr: Array<Entity>, buf: buffer, size: number)
    ASSERT(size * ID_SIZE <= buffer.len(buf), "size is larger than buffer size")

    for i, id in ipairs(arr) do
        BUFFER_SET(buf, (i - 1), id)
    end
end

--------------------------------------------------------------------------------
-- Export
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
    context = ID_CTX,

    bnext = bnext,
    copy_array_to_buffer = copy_array_to_buffer,
    copy_buffer_to_array = copy_buffer_to_array,
    id_size = ID_SIZE,

    _test = table.freeze {
        defer_id_reuse = DEFER_ID_REUSE,
        ver_shift = ID_LSHIFT,
        max_ver = ID_MASK_VER * ID_RSHIFT,

        get_names = function()
            return table.freeze(table.clone(ctype_names))
        end,

        create_id = function(key: number, ver: number)
            return ID_CREATE(key, ver * ID_LSHIFT)
        end,

        extract = function(id: Entity): (number, number)
            local key, ver = ID_KEY_VER(id)
            return key, ver * ID_RSHIFT
        end,

        set_key_version = function(pool: EntityPool, key: number, ver: number)
            local data = BUFFER_GET(pool.map, key)
            if IN_USE(data) then ASSERT(false, "attempt to set version of in-use entity") end
            BUFFER_SET(pool.map, key, ID_CREATE(ID_KEY(data), ver * ID_LSHIFT))
        end,
    
        get_key_version = function(pool: EntityPool, key: number): number
            ASSERT(POOL_CONTAINS(pool, key), "not contained")
            return ID_VER(BUFFER_GET(pool.map, key)) * ID_RSHIFT
        end,

        pool_entities_to_array = function<T>(pool: Pool<T>): Array<Entity>
            local array = table.create(pool.size)
            local entities = pool.entities
            for i = 0, pool.size - 1 do
                array[i + 1] = BUFFER_GET(entities, i)
            end
            return array
        end
    }
}

return table.freeze(ecr)
