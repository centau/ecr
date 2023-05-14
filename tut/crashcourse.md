---
permalink: /tut/crashcourse
title: Crash Course
---

ECR is a sparse-set based ECS library heavily inspired by
[EnTT](https://github.com/skypjack/entt).

This is a brief introduction on how to use the library and some of the concepts
involved with it.

## Registry

The registry stores and manages entities and their components. It is used to
create entities, change components and view all entities with particular
components.

```lua
local registry = ecr.registry()
```

## Components

A component is a piece of data associated with an entity. A zombie entity could
have health, speed and a model. To create a new component type you must do the
following:

```lua
local Name = ecr.component() :: string
local Health = ecr.component() :: number
```

This returns a unique id that represents that type of component.

There is no limit on the amount of components you can create.

## Entities

An entity is a unique object in the world. Entities are referenced using unique
integer ids that are returned when you create a new entity.

```lua
-- create a new entity and get its id
local id = registry:create()

-- destroy entity, removing it and all of its components
registry:destroy(id)
```

Entities can have any amount of component types added to or removed from them
dynamically.

```lua
registry:set(id, Health, 100) -- adds a new component type to the entity with a value of 100
print(registry:get(id, Health)) -- "100"

registry:set(id, Health, nil) -- removes the component type from the entity
print(registry:has(id, Health)) -- "false" 
```

## Views

A view allows you to look into the registry and get all entities with a specific
set of components.

A view guarantees that all entities returned will have *at least* all the
components specified.

```lua
-- all entities with Health
local view = registry:view(Health)

-- all entities with Position and Velocity
local view = registry:view(Position, Velocity)
```

You can also filter components to exclude them from the view:

```lua
-- all entities with A and B and without C
local view = registry:view(A, B):exclude(C)
```

To get all entities in a view you iterate over it.

```lua
for id, position, velocity in registry:view(Position, Velocity) do
    registry:set(id, Position, position + velocity*dt)
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

You *cannot* add or remove components for entities in these listeners.

## Observers

An observer is similar to a view, except it only returns entities whose
components have been changed or added and still has those components at the time
of iteration.

An observer can be created using the `Registry:track()` method.

```lua
local observer = registry:track(Position, Model)

for entity, position, model in observer do
    print("new position: ", position)
    print("model: ", model)
end

observer:clear()
```

After iterating over the changes you can then clear the observer so it can track
new changes.

## Example Usage

All component types should be defined within a single file that any file can
require to use those types.

The library is also designed using the Luau typechecker. It is recommended
to cast component types to the type of values they represent.

A simple example of defining components and creating a system:

```lua
-- cts.luau

local ecr = require(ecr)

return {
    Position = ecr.component() :: Vector3
    Velocity = ecr.component() :: Vector3
    Model = ecr.component() :: Model
}
```

```lua
-- updatePositions.luau

local cts = require(cts)

return function(world: ecr.Registry, dt: number)
    for id, pos, vel, model in world:view(cts.Position, cts.Velocity, cts.Model) do
        local newpos = pos + vel*dt
        world:set(id, cts.Position, newpos)
        model.Position = newpos
    end
end
```

## End

At this point, the basics concepts and features of ECR have been covered.
You can read other guides on more specific usages or view the API for more
details.
