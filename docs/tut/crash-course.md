# Crash Course

ECR is a sparse-set based ECS library heavily inspired by
[EnTT](https://github.com/skypjack/entt).

This is a brief introduction on how to use the library and some of the concepts
involved with it.

## Registry

The registry, or often called a *world*, is a container for entities and their
components.

```lua
local registry = ecr.registry()
```

## Entities

An entity represents an object in the world and is referenced using a unique id.

```lua
local id: ecr.entity = registry:create()
registry:contains(id) -- true

registry:destroy(id)
registry:contains(id) -- false
```

Entities can be freely created and destroyed.

## Components

A component is data that can be added to entities.

There is the *component type*, which represents a type of data, and there is
the *component value*, which is a value for a type added to an entity.

Component types are created by `ecr.component()`, which returns an id
representing that type. This can be typecasted to the type of value it
represents.

```lua
local Name = ecr.component() :: string
local Health = ecr.component() :: number
```

Entities can have any amount of components added to or removed from them,
whenever. Like tables, they can have any amount of key-value pairs, where the
component type is the key, and the component value is the value. Entities
initially have no components when created, and will have all their components
removed when destroyed.

```lua
registry:set(id, Health, 100) -- adds a new component with a value of 100
registry:get(id, Health) -- 100

registry:remove(id, Health) -- removes the component
registry:has(id, Health) -- false
```

Component values cannot be `nil`, components should be removed instead.

## Views

You can get all entities that have a specific set of components by using a view.

Views can include any amounts of components. A view only returns entities that
have *at least* all the components included.

```lua
for id, position, velocity in registry:view(Position, Velocity) do
    world:set(id, Position, position + velocity * 1/60)
end
```

You can add or remove components and create or destroy entities during
iteration.

Components added or entities created during iteration will not be returned
during that iteration.

For simpler view operations, the following can be done which is equivalent to
the above:

```lua
registry:view(Position, Velocity):patch(function(position, velocity)
    return position, position + velocity * 1/60
end)
```

You can also exclude component types from views. Any entities that have an
excluded type will not be included in the view.

```lua
local view = registry:view(A):exclude(B)
```

Views are cheap to create and do not store their own state, so they do not need
to be stored aside, and can be created on the fly as needed.

## Signals

The registry contains three different signals for when a component type is
added, changed or removed for any entity.

```lua
registry:on_add(type):connect(listener)
registry:on_change(type):connect(listener)
registry:on_remove(type):connect(listener)
```

All three listeners are called with:

1. The entity being acted on.
2. The new component value (always `nil` in the case of `on_remove`).

`on_add` is fired *after* the component is added.

`on_change` and `on_remove` is fired *before* the component is changed or
removed, so you can still retrieve the old value if needed.

You cannot modify the registry within a listener, they should only be used to
help track entities or clean up values.

## Observers

An observer is similar to a view, except it only returns entities whose
components have been added or changed and still have those components at the
time of iteration.

An observer can be created using `Registry:track()`.

```lua
local observer = registry:track(Position, Model)

return function()
    for entity, position, model in observer do
        print("changed: ", position, model)
    end
end
```

After iterating, the observer automatically clears so that only fresh changes
are iterated.

Observers provide a concise way to act only on a subset of entities that had
components updated since the last time a system ran.

Unlike a view, observers do store their own state, and must be stored aside to
keep track over time.

## Example Usage

All component types are defined in a single file to keep things organised. All
component types must also be defined before the registry using them is created.

::: code-group

```lua [cts.luau]
local ecr = require(ecr)

local cts = {
    Health = ecr.component() :: number,
    Poisoned = ecr.component() :: number
}

ecr.name(cts)

return cts
```

:::

`ecr.name()` can be used to associate names with components, for clearer error
messages when debugging.

The library doesn't have any bult-in support for systems, the user is free to
do this however they please.

Examples using plain functions:

::: code-group

```lua [deal_poison_damage.luau]
local cts = require(cts)

return function(world: ecr.Registry, dt: number)
    for id, health in world:view(cts.Health, cts.Poisoned) do
        world:set(id, health, health - 10 * dt)
    end
end
```

```lua [reduce_poison_timer.luau]
local cts = require(cts)

return function(world: ecr.Registry, dt: number)
    for id, time in world:view(cts.Poisoned) do
        local new_time = time - dt

        if new_time <= 0 then
            world:remove(id, cts.Poisoned)
        else
            world:set(id, cts.Poisoned, new_time)
        end
    end
end
```

```lua [destroy_dead.luau]
local cts = require(cts)

return function(world: ecr.Registry)
    for id, health in world:view(cts.Health) do
        if health <= 0 then
            world:destroy(id)
        end
    end
end
```

:::

::: code-group

```lua [main.luau]
local ecr = require(ecr)
local cts = require(cts)

local function loop(systems: {(ecr.Registry, number) -> ()}, world: ecr.Registry, dt: number)
    for _, system in systems do
        system(world, dt)
    end
end

local systems = {
    require(deal_poison_damage),
    require(reduce_poison_timer),
    require(destroy_dead)
}

local world = ecr.registry()

for i = 1, 10 do
    local id = world:create()
    world:set(id, cts.Health, 100)
    world:set(id, cts.Poisoned, math.random(3, 5)) -- poison randomly for 3-5 seconds
end

while true do
    loop(systems, world, 1/60)
end
```

:::

## End

At this point, the main concepts and features of ECR have been covered.
You can read other guides on more advanced usage or view the API for more
details.
