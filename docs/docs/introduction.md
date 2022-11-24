---
permalink: /docs/introduction
title: Introduction
---

`ECR` is a fast and lightweight entity component system written in Luau.

Design is heavily based on the popular `EnTT` C++ ECS library.

`ECR` is designed to act just as a container, like a vector or hashmap.
It covers the *entity* and *component* in ECS, but does not attempt to impose any sort of control over the codebase with system scheduling, instead, the *system* is left up to the user to implement, either as plain functions or through a custom scheduler.

## Pools

`ECR` uses not an archetype design, but a sparse-set design for organizing entities and components.

A *pool* refers to a collection of entities and their associated component values, and is implemented as a sort of specialized sparse-set.
There is a single pool for each component in the registry.

All pools keep their entities and components packed contiguously in memory for fast iteration.

> This is just nice-to-know information, not necessary for using the library.

## The Registry

The registry stores and manages entities and their components.

A registry is used to create and destroy entities.

```lua
-- instantiate registry
local registry = ecr.registry()

-- create a new entity with no components, returns the entity
local entity = registry:create()

-- releases an entity and removes all its components
registry:destroy(entity)
```

The value returned by `registry:create()` is just an identifier used to refer to an entity. This identifier is usually just referred to as the "entity".

`registry:destroy(entity)` will probe all pools for the given entity and remove it if present before releasing the identifier. If it is known that an entity has no components, it is more efficient to call `registry:release(entity)` which will release the identifier without having to probe any pools.

## Components

A *component* is a type of data associated with an entity.

Components can be freely added, changed and removed from entities on the fly.

Components in `ECR` are simply unique identifiers that you can create by doing:

```lua
local component = ecr.component()
```

Each call to `ecr.component()` will return a new unique identifier.
All components should be defined within a single file that any file can require to use that component.

`ECR` is designed around the typechecking feature of Luau to write more organised code.
When a component is defined, it is recommended to cast the return value to the type the component will hold. Doing this will allow you to utilize type inference with `Registry` methods.

A practical example of defining components would look like:

```lua
-- components.luau

return {
    Health = ecr.component() :: number
    Name = ecr.component() :: string
}
```

You can add or change a component of an entity by doing the following:

```lua
registry:set(entity, component, true)
```

Components can be removed by either setting the value to `nil` or by calling `registry:remove()`.

```lua
-- both are equivalent
registry:set(entity, Health, nil)
registry:remove(entity, Health)
```

You can get components added to entity with the following:

```lua
-- get a single component
local health = registry:get(entity, Health)

-- get multiple components in one go
local health, name, model = registry:get(entity, Health, Name, Model)
```

`registry:get()` will return `nil` if the entity does not have the component.

If you don't care about the value you can check if they have a component using `Registry:has()` which will return a boolean indicating if they have the component or not.

```lua
local hasHealthn = registry:has(entity, Health)
```

You can check if an entity has multiple components as well:

```lua
-- will return true if the entity has EVERY component, else will return false
local hasAll = registry:has(Health, Name, Model)
```

## Views

A view allows you to look into the registry and iterate over all entities with specified components.

There are two types of views: single-type views and multi-type views (both have a common API).

### Single-type View

This view is the fastest type of view, iterating over the underlying component pool directly.

You can also check the amount of entities contained in a single-view with the `#` len operator.

### Multi-type View

These views are slower than single-type views (but still fast overall).
They iterate only entities that contain **all** of the specified components.

These views cannot iterate directly over a single pool, it performs checks in multiple pools per iteration to check if an entity has all of the specified components.

You cannot accurately check the amount of entities contained in a multi-type view without actually iterating through it.
The `#` len operator will however give an *estimate* of the amount of entities contained in it.
The actual amount of entities in a view will always be `<=` the estimated amount.

### Usage

Views can be created by doing the following:

```lua
-- single-type view
local view = registry:view(A)

-- multi-type view
local view = registry:view(A, B)
```

You can also filter based on excluded components:

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

All components specified in the argument list `registry:view(...)` will be returned during iteration. If you want to specify components that entities must have but do not want their values during iteration, you can do the following:

```lua
for entity, position in registry:view(Position):include(Velocity)
```

This will only return `Position` but ensures that all entities returned also have `Velocity`. This is still a multi-type view.

### Iteration Order

A view will iterate along the smallest component pool.

For example, for `registry:view(A, B)`, the view will first check the size of `A`s pool and `B`s pool, choosing to iterate over the smallest pool while prodding the other pool for each iteration.

### Modification During Iteration

It is safe to add, change and remove any components during view iteration as long as view iterations are not nested within each other.

Components that are added during iteration will not be returned for that iteration.

## Events

The registry contains three different events to listen to when a component for a given entity is added, changed or removed.

```lua
registry:added(component):connect(callback)
registry:changed(component):connect(callback)
registry:removing(component):connect(callback)
```

All three callbacks are called with:

1. The registry the entity belongs to.
2. The entity whose component is being changed.
3. The new component value (always `nil` in the case of `removing`).

`added` and `changed` are fired *after* the component is set.

`removing` is fired *before* the component is removed.

These events are useful for queuing entities that have had specific components changed for processing in one go.

`ECR` takes this a step further and provides a method for basic change tracking for you.

## Observers

The `Observer` class extends the `View` class.

On top of all the functionalities of views, observers also:

1. Store their own internal pools of components, which can be cleared at will.
2. Can be disconnected and reconnected to registries for when you want to temporarily stop tracking changes.

An observer can be created using the `registry:track()` method.

```lua
local changedPosition = registry:track(Position, Model)

for entity, position, model in changedPosition do
    print("new position: ", position)
    print("model: ", model)
end
```

`registry:track()` will track changes for the first component specified, while ensuring the entity also has all other components specified.

As the observer extends views, you can also use `:include()` and `:exclude()` which follow the same rules.

Observers can also track component removal, in which case `nil` will be returned for the tracked component.

It is important to note that the observer only returns entities once with their latest component values, no matter how many times their tracked component has been changed since the last time the observer was cleared.

The observer also only tracks entities that have *all* of the specified components at the moment that their tracked component is changed.

## Multithreading

The registry is generally not thread-safe.
However, views (with some restrictions) can be used concurrently.

1. A thread can iterate over and modify components as long as it is the only thread doing so with those components.
2. A single set of components can be iterated over by multiple threads concurrently as long as those components are not being modified at the same time.

## End

At this point, most of the main concepts and features of `ECR` have been covered.

However there are a lot more features that are not documented here. You can read other guides on specifics of the library or view the API to find out more.
