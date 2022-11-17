---
permalink: /docs/introduction
title: Introduction
---

`ECR` is a fast and lightweight entity component system written in Luau.

Design is heavily based on the popular `EnTT` ecs library.

`ECR` is designed to just be a container, like a vector or hashmap.
It only covers the *entity* and *component* part of ECS with the `Registry` class, the *system* is left up to the user to implement, either as plain functions or through a custom scheduler.

## Pools

`ECR` uses not an archetype design, but a sparse-set design for organizing entities and components.
A *pool* refers to a collection of entities and a specific component, and is implemented as a sort of specialized sparse-set.

All pools keep their entities and components packed contiguously in memory for fast iteration.

## The Registry

The registry stores and manages entities and their components.

An "entity" is actually just an unique identifier the registry uses to associate components with.
In this guide the word "entity" will refer to the unique identifier.

A registry is used to create and destroy entities.

```lua
local registry = ecr.registry()

-- create a new entity with no components, returns the entity
local entity = registry:create()

-- releases an entity and removes all its components
registry:destroy(entity)
```

If it is known that an entity has no components,
it can be released without poking into any pools.
This is lighter than calling `registry:destroy()`/

```lua
registry:release(entity)
```

## Components

A *component* is a type of data associated with an entity.

Each component should only be created once, preferably in a single file that any file can require to use that component.

Components in `ECR` are simply unique identifiers that you can create by doing:

```lua
local component = ecr.component()
```

You can assign an entity a component by doing the following:

```lua
registry:set(entity, component, true)
```

`ECR` is designed around the typechecking feature of Luau to write more organised code. A more practical example would look something like:

```lua
local Health = ecr.component() :: number

registry:set(entity, Health, 100)
```

Components can be removed by either setting the value to `nil` or by calling `registry:remove()`.

```lua
-- both are equivalent
registry:set(entity, Health, nil)
registry:remove(entity, Health)
```

You can get components assigned to entity with the following:

```lua
-- get a single component
local health = registry:get(entity, Health)

-- get multiple components in one go
local health, name, model = registry:get(entity, Health, Name, Model)
```

`registry:get()` will return `nil` if the entity does not have the component.

If you don't care about the value you can check if they have a component with:

```lua
local hasHealth: boolean = registry:has(entity, Health)
```

You can check if an entity has multiple components as well:

```lua
-- will return true if the entity has EVERY component, else will return false
hasAll = registry:has(Health, Name, Model)
```

## Views

A view allows you to look into the registry and iterate over all entities with specified components.

There are two types of views: single-type views and multi-type views (both have a common API interface).

### Single-type View

This view is the fastest type of view, iterating over the underlying component pool directly.

You can also check the amount of entities contained in a single-view with the `#` len operator.

### Multi-type View

These views are slower than single-type views (but still fast overall).
They iterate only entities that contain **all** of the specified components.

These views cannot iterate directly over a single pool, it performs random-access checks in multiple pools per iteration to check if an entity has all of the specified components.

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

Views are very cheap to construct relative to iterating over them. For this reason it is not recommend to store views aside for reuse, just create them on the fly.

Views can be iterated by doing the following:

```lua
for entity, position, velocity in registry:view(Position, Velocity) do
    print(entity, position, velocity)
end
```

> As typechecking for generalized iteration is currently broken, there exists an alternative `registry:view(Position, Velocity):each()`
> which functions identically to the above code sample.

### Iteration Order

A view will iterate along the smallest component pool.

For example, for `registry:view(A, B)`, the view will first check the size of `A`s pool and `B`s pool, choosing to iterate over the smallest pool while prodding the other pool for each iteration.

## Multithreading

The registry is not thread-safe, with the exception of views.

1. A thread can iterate over and modify components as long as it is the only thread doing so.
2. A single set of components can be iterated over by multiple threads concurrently as long as those components are not being modified at the same time.

## End

At this point you should have a decent understanding of how to use `ECR`.

There are a lot more features not documented here, it is recommended to refer to the API to find out more.
