--!strict
-- Every line marked `-- @error` must produce at least one type error.
-- No unmarked line may produce one.
local ecr = require("../../src/ecr")
type component<T> = ecr.component<T>
type read_component<T> = ecr.read_component<T>
type any_component = read_component<unknown>

local Number = ecr.component<<number>>()
local String = ecr.component<<string>>()
local Strings = ecr.component<<{ string }>>()

local reg = ecr.registry()
local e = reg:create()

--------------------------------------------------------------------------------
-- the original bug: value must match the component's type
--------------------------------------------------------------------------------

reg:set(e, Number, "not a number") -- @error
reg:set(e, String, 9999) -- @error
reg:insert(e, Strings, 1) -- @error
reg:find(Number, "nope") -- @error
reg:copy(Number, String) -- @error
reg:patch(e, Number, function(n: number) return "no" end) -- @error

--------------------------------------------------------------------------------
-- an erased component cannot be written through
--------------------------------------------------------------------------------

local function launder_set(r: ecr.Registry, id: ecr.entity, c: any_component)
	r:set(id, c, 1) -- @error
end

local function launder_typed(r: ecr.Registry, id: ecr.entity, c: read_component<number>)
	r:set(id, c, 1) -- @error
end

local function launder_patch(r: ecr.Registry, id: ecr.entity, c: any_component)
	r:patch(id, c) -- @error
end

local function launder_find(r: ecr.Registry, c: any_component)
	r:find(c, 1) -- @error
end

-- Pool.values is writable, so storage must not accept an erased component
local function launder_storage(r: ecr.Registry, c: any_component)
	return r:storage(c) -- @error
end

-- View:patch() writes values back, so views must not accept an erased component
local function launder_view(r: ecr.Registry, c: any_component)
	return r:view(c) -- @error
end

--------------------------------------------------------------------------------
-- reads keep their precise type; they are not silently widened
--------------------------------------------------------------------------------

local bad_get: string = reg:get(e, Number) -- @error
local m1: number, m2: number = reg:get(e, Number, String) -- @error
local bad_try: string? = reg:try_get(e, Number) -- @error
local bad_add: string = reg:add(e, Number) -- @error
local bad_handle: string = reg:handle(e):get(Number) -- @error

--------------------------------------------------------------------------------
-- container variance
--------------------------------------------------------------------------------

local list: { component<number> } = { Number }

-- a writable array of erased components would let the callee insert the
-- wrong component type into the caller's array
local function mutate(cs: { any_component }) end
mutate(list) -- @error

--------------------------------------------------------------------------------
-- non-components are rejected
--------------------------------------------------------------------------------

reg:clear("NotAComponent") -- @error
reg:has(e, 42) -- @error
reg:set(e, "NotAComponent", 1) -- @error
ecr.is_tag({}) -- @error

-- limitation: a table literal's named fields are not checked against a
-- `[string]` indexer, so `ecr.name` cannot validate its values at type level
-- The indexer is still required - it is what disambiguates the two overloads
ecr.name { Number = 5 }
ecr.name { 1, 2, 3, 4, 5} -- @error

--------------------------------------------------------------------------------
-- signals keep their value type
--------------------------------------------------------------------------------

reg:on_add(Number):connect(function(id, v: string) end) -- @error
