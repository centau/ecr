---
permalink: /tut/crashcourse
title: Crash Course
---

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

An entity represents a unique object in the world. Entities are referenced using
unique ids and can be created and destroyed.

```lua
local id = registry:create()
registry:contains(id) -- true

registry:destroy(id)
registry:contains(id) -- false
```

## Components

A component is a type of value that can be assigned to entities.

There is the *component type*, which represents a type of data, and there is
the *component value*, which is a particular value associated with an entity.

Component types are referenced using unique ids returned by `ecr.component()`.
You can typecast this to the type of value it is supposed to represent to
use typechecking features.

```lua
local Name = ecr.component() :: string
local Health = ecr.component() :: number
```

Entities can have any amount of components added to or removed from them
at runtime. This behaves similarly to tables, where they can have any amount of
key-value pairs, where the component type and component value are the key-value
pair.

```lua
registry:set(id, Health, 100) -- adds a new component with a value of 100
registry:get(id, Health) -- 100

registry:remove(id, Health) -- removes the component from the entity
registry:has(id, Health) -- false
```

Eventually when an entity needs to be removed from the world you can destroy
the entity which will mark its id as dead and remove any components added to it.

## Views

A view allows you to look into the registry and get all entities that have a
set of components.

```lua
registry:view(Health)

registry:view(Position, Velocity)
```

You can also exclude components from views. Any entities that have an excluded
component will not be returned.

```lua
local view = registry:view(A, B):exclude(C)
```

To get all entities in a view you iterate over it.

```lua
for id, position, velocity in registry:view(Position, Velocity) do
    print(id, position, velocity)
end
```

You can add, change, remove components and create or destroy entities during
iteration.

Components added or entities created during iteration will not be returned
during that iteration.

## Signals

The registry contains three different signals for when a component type for a
given entity is added, changed or removed.

```lua
registry:added(type):connect(listener)
registry:changed(type):connect(listener)
registry:removing(type):connect(listener)
```

All three listeners are called with:

1. The entity whose component is being changed.
2. The new component value (always `nil` in the case of `removing`).

`added` and `changed` are fired *after* the component is set.

`removing` is fired *before* the component is removed, so you can still retrieve
it if needed.

These signals give you the ability to run side-effects like clean-up when
changing components.

## Observers

An observer is similar to a view, except it only returns entities whose
components have been changed or added and still have those components at the
time of iteration.

An observer can be created using the `Registry:track()` method.

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

Observers provide a concise way to track and act on only specific components
that have changed since the last time a system ran.

## Example Usage

All components are defined in a single file to keep things organised.

```lua
-- cts.luau

local ecr = require(ecr)

return {
    Position = ecr.component() :: Vector3,
    Velocity = ecr.component() :: Vector3,
    Health = ecr.component() :: number
}
```

The library doesn't have any bult-in support for systems, instead this is left
to the user to implement either as plain functions or through a custom scheduler.

```lua
-- updatePositions.luau

local cts = require(cts)

return function(world: ecr.Registry, dt: number)
    for id, pos, vel in world:view(cts.Position, cts.Velocity) do
        local newpos = pos + vel*dt
        world:set(id, cts.Position, newpos)
    end
end
```

```lua
-- killEntities.luau

local cts = require(cts)

return function(world: ecr.Registry)
    for id, health in world:view(cts.Health) do
        if health < 0 then
            world:destroy(id)
        end
    end
end
```

## End

At this point, the basics concepts and features of ECR have been covered.
You can read other guides on more specific usages or view the API for more
details.
