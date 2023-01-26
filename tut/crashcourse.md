---
permalink: /tut/crashcourse
title: Crash Course
---

`ECR` is a fast entity component system written in Luau.

The design is heavily based on the popular `EnTT` C++ ECS library.

`ECR` is designed to just act as a container, like a vector or hashmap. It covers the *entity* and *component* in ECS,
but does not attempt to impose any sort of control over the codebase with system scheduling.
Instead, the *system* is left up to the user to implement, either as plain functions or through a custom scheduler.

## Pools

A *pool* refers to a collection of entities and their associated component values.
There is a single pool for each component type in the registry.

All pools keep their entities and components packed contiguously in memory for fast iteration.

The registry class is effectively a large wrapper for iterating and transforming the data in these pools.

## Components

Components are types of data and are represenented by unique identifiers that you can create by doing:

```lua
local component = ecr.component()
```

Each call to `ecr.component()` will return a new component identifier.

Entity components behave similarly to a Luau table. Any amount of components can be added, changed and removed dynamically.
Likewise, setting a component value to `nil` will remove the component from the entity.

## The Registry

The registry stores and manages entities and components.

```lua
-- create a new registry
local registry = ecr.registry()

-- create a new entity with no components
local entity = registry:create()
```

The value returned by `Registry:create()` is an identifier representing an entity. This identifier is usually just referred to as the "entity".

`registry:destroy(entity)` will probe all pools for the given entity and remove it if present before releasing the identifier. If it is known that an entity has no components, it is more efficient to call `registry:release(entity)` which will release the identifier without having to probe any pools.

Components are added to entities by specifying the component type followed by the value to set.

```lua
local Health = ecr.component()

registry:set(entity, Health, 100)
```

Alternatively, multiple components can be removed in one go using `Registry:remove()`.

```lua
-- both are equivalent
registry:set(entity, Health, nil)
registry:set(entity, Position, nil)

registry:remove(entity, Health, Position)
```

You can get entity component values with the following:

```lua
-- get a single component
local health = registry:get(entity, Health)

-- get multiple components in one go
local health, name, model = registry:get(entity, Health, Name, Model)
```

`Registry:get()` will return `nil` if the entity does not have the component.

If you do not care about the value of a component, you can check if an entity only has a component using `Registry:has()`, which will return a boolean indicating if it has the component or not.

```lua
local hasHealth = registry:has(entity, Health)
```

You can check if an entity has multiple components in one go as well.

```lua
-- will return true if the entity has EVERY component, else will return false
local hasAll = registry:has(entity, Health, Name, Model)
```

## Views

A view allows you to look into the registry and iterate over all entities with a specified set of components.

There are two types of views: single-type views and multi-type views (both have a common API).

### Single-type View

This view is the fastest type of view, iterating over the underlying component pool directly.

You can also check the amount of entities contained in a single-view with the `#` len operator.

### Multi-type View

This view slower than a single-type view (but still fast overall).
They iterate only entities that contain **all** of the specified components.

These views cannot iterate directly over a single pool, it performs checks in multiple pools per iteration to check if an entity has all of the specified components. The more components specified by the view the slower iteration will be.

You cannot accurately check the amount of entities contained in a multi-type view without actually iterating through it.
The `#` length operator will however give an *estimate* of the amount of entities contained in it.
The actual amount of entities in a view will not be greater than the estimated amount.

### Usage

Views can be created by doing the following:

```lua
-- single-type view
local view = registry:view(A)

-- multi-type view
local view = registry:view(A, B)
```

You can also filter components to exclude them from the view:

```lua
local view = registry:view(A, B):exclude(C)
```

This ensures that no entity returned with have component `C`.

Views are very cheap to construct relative to iterating over them. For this reason it is not recommend to store views aside for reuse, just create them on the fly.

Views can be iterated by doing the following:

```lua
for entity, position, velocity in registry:view(Position, Velocity) do
    print(entity, position, velocity)
end
```

All components specified in the argument list `registry:view(...)` will be returned during iteration in the same order.

### Iteration Order

A view will iterate along the smallest component pool.

For example, for `registry:view(A, B)`, the view will first check the size of `A`s pool and `B`s pool, choosing to iterate over the smallest pool while prodding the other pool for each iteration.

### Modification During Iteration

It is safe to add, change and remove any components for the entity currently being iterated during view iteration.

Components that are added during iteration will not be returned for that iteration.

## Events

The registry contains three different events to listen to when a component for a given entity is added, changed or removed.

```lua
registry:added(component):connect(callback)
registry:changed(component):connect(callback)
registry:removing(component):connect(callback)
```

All three callbacks are called with:

1. The entity whose component is being changed.
2. The new component value (always `nil` in the case of `removing`).

`added` and `changed` are fired *after* the component is set.

`removing` is fired *before* the component is removed.

These events are useful for queuing entities that have had specific components changed for later processing in one go.

`ECR` takes this a step further and provides a method for basic change tracking.

## Observers

Observers have the same interface as views as well as a few extra features.

On top of all the functionalities of views, observers also:

1. Store their own internal pools of components, which can be cleared at will.
2. Can be disconnected and reconnected to registries for when you want to temporarily stop tracking changes.

An observer can be created using the `Registry:track()` method.

```lua
local changedPosition = registry:track(Position, Model)

for entity, position, model in changedPosition do
    print("new position: ", position)
    print("model: ", model)
end
```

`Registry:track()` will track changes for the first component specified, while ensuring the entity also has all other components specified at the time of iteration.

You can also use `:exclude()` which follow the same rules as views.

## Multithreading

The registry is generally not thread-safe.
However, views (with some restrictions) can be used concurrently.

1. A thread can iterate over and modify components as long as it is the only thread doing so with those components.
2. A single set of components can be iterated over and read by multiple threads concurrently as long as those components are not being modified at the same time.

## Example Usage

All components should be defined within a single file that any file can require to use those components.

`ECR` is designed around the typechecking feature of Luau to write better structured code.
When a component is defined, it is recommended to cast the return value to the type the component will hold. Doing this will allow you to utilize type inference.

A simple example of defining components and creating a system:

```lua
-- components.luau

return {
    Health = ecr.component() :: number
    MaxHealth = ecr.component() :: number
    Position = ecr.component() :: Vector3
    Name = ecr.component() :: string
}
```

```lua
-- regenHealth.luau

return function(world: ecr.Registry, dt: number)
    for entity, health, maxHealth in world:view(Health, MaxHealth) do
        local new = health + 10*dt

        if new > maxHealth then
            new = maxHealth
        end

        world:set(entity, Health, new)
    end
end
```

## End

At this point, most of the main concepts and features of `ECR` have been covered.
You can read other guides on usage of the library or view the API for more details.
