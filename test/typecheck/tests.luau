--!strict
-- Every line in this file must typecheck cleanly.
local ecr = require("../../src/ecr")
type component<T> = ecr.component<T>
type read_component<T> = ecr.read_component<T>
type any_component = read_component<unknown>

local Number = ecr.component<<number>>()
local String = ecr.component<<string>>()
local Tags = ecr.component<<{ string }>>()
local Anything = ecr.component<<unknown>>()
local NumOrStr = ecr.component<<number | string>>()
local Tag = ecr.tag()

local reg = ecr.registry()
local e = reg:create()

--------------------------------------------------------------------------------
-- constructors
--------------------------------------------------------------------------------

local Inferred = ecr.component(function() return "hi" end)
local _: component<string> = Inferred

local _: component<nil> = Tag
local _: component<ecr.entity> = ecr.entity

--------------------------------------------------------------------------------
-- writing: exact value type required
--------------------------------------------------------------------------------

reg:set(e, Number, 1)
reg:set(e, String, "hi")
reg:set(e, Anything, 1)
reg:set(e, Anything, "also fine")
reg:set(e, NumOrStr, 1)
reg:set(e, NumOrStr, "x")
reg:set(e, Tag, nil)
reg:insert(e, Tags, "a")
reg:patch(e, Number, function(n: number) return n + 1 end)
local _: ecr.entity? = reg:find(Number, 1)
reg:copy(Number, Number)

--------------------------------------------------------------------------------
-- reading: inference is preserved through read_component<T>
--------------------------------------------------------------------------------

local _: number = reg:get(e, Number)
local _: number, _: string = reg:get(e, Number, String)
local h, n, t = reg:get(e, Number, String, Tags)
local _: number, _: string, _: { string } = h, n, t
local _: number? = reg:try_get(e, Number)
local _: number = reg:add(e, Number)

--------------------------------------------------------------------------------
-- erasure: multiple components in one call
--------------------------------------------------------------------------------

reg:clear(Number, String, Tags, Tag)
local _: boolean = reg:has(e, Number, String)
reg:remove(e, Number, String)
local _: boolean = ecr.is_tag(Tag)

--------------------------------------------------------------------------------
-- erasure: user-written wrappers
--------------------------------------------------------------------------------

-- the case from the PR discussion: an erased component can still be read
local function read_erased(r: ecr.Registry, id: ecr.entity, c: any_component): unknown
    return r:get(id, c)
end
local _: unknown = read_erased(reg, e, Number)
local _: unknown = read_erased(reg, e, Anything)

local function count(r: ecr.Registry, id: ecr.entity, ...: any_component): number
    local n = 0
    for i = 1, select("#", ...) do
        if r:has(id, (select(i, ...))) then n += 1 end
    end
    return n
end
local _: number = count(reg, e, Number, String)

-- a wrapper that keeps the value type
local function get_or<T>(r: ecr.Registry, id: ecr.entity, c: read_component<T>, fallback: T): T
    local v = r:try_get(id, c)
    return if v == nil then fallback else v
end
local _: number = get_or(reg, e, Number, 0)
local _: string = get_or(reg, e, String, "")

-- arrays of components, via a read-only indexer
local list: { component<number> } = { Number }
local function clear_all(r: ecr.Registry, cs: { read any_component })
    for _, c in cs do r:clear(c) end
end
clear_all(reg, list)

--------------------------------------------------------------------------------
-- views, observers, groups
--------------------------------------------------------------------------------

for id, hp, nm in reg:view(Number, String) do
    local _: ecr.entity, _: number, _: string = id, hp, nm
end
reg:view(Number):exclude(String, Tag)
reg:view(Number, String):patch(function(hp, nm) return hp + 1, nm end)
reg:view(Number):of({ e })

for id, hp in reg:track(Number) do
    local _: ecr.entity, _: number = id, hp
end
reg:track(Number):exclude(Tag):clear()

for id, hp, nm in reg:group(Number, String) do
    local _: ecr.entity, _: number, _: string = id, hp, nm
end

--------------------------------------------------------------------------------
-- signals and storage
--------------------------------------------------------------------------------

reg:on_add(Number):connect(function(id, v) local _: number = v end)
reg:on_change(String):connect(function(id, v) local _: string = v end)
reg:on_remove(Number):connect(function(id) end)
reg:on_clear(Number):connect(function() end)
reg:after_clear(Number):connect(function() end)

local pool = reg:storage(Number)
local _: number = pool.values[1]
pool.values[1] = 2

for c, p in reg:storage() do
    local _: any_component, _ = c, p
end

--------------------------------------------------------------------------------
-- handles
--------------------------------------------------------------------------------

local hnd = reg:handle(e)
hnd:set(Number, 1):set(String, "x")
local _: number = hnd:get(Number)
local _: number, _: string = hnd:get(Number, String)
local _: number? = hnd:try_get(Number)
local _: boolean = hnd:has(Number, String)
hnd:remove(Number, String)

--------------------------------------------------------------------------------
-- naming
--------------------------------------------------------------------------------

local named = ecr.name {
    Number = Number,
    String = String,
}
local _: component<number> = named.Number
local _: component<string> = named.String
local _: string? = ecr.name(Number)

--------------------------------------------------------------------------------
-- unions
--------------------------------------------------------------------------------

local function serdes(c: component<string> | component<number>) end
serdes(Number)
serdes(String)

local function serdes2(c: read_component<string | number>) end
serdes2(Number)
serdes2(String)
serdes2(NumOrStr)
