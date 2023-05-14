---
permalink: api/restrictions
title: Restrictions
---

The API omits sanity checks in areas that would be costly to do so, allowing you to run into problems like iterator invalidation and undefined behavior. This means that there are certain restrictions on what you can do. All restrictions are documented here and at the relevant API references.

## Releasing Ids

Destroying an entity that still has components with [`release()`](Registry#release.md) can corrupt registry pools and lead to undefined behavior. If in doubt check first using [`orphaned()`](Registry#orphaned.md) or just use [`destroy()`](Registry#destroy.md).

## Signals

- Listeners cannot connect or disconnect other listeners. Listeners can disconnect themselves.

- Components cannot be added or removed from within a listener.

Breaking these restrictions can result in *undefined behavior*.

## Modifing During Iteration

This applies to the iteration of views, observers and groups.

- During iteration, adding or removing components from entities not currently being iterated can *invalidate the iterator*.

## Groups and Views

Using `Registry:group()` adds extra limitations to adding components during views.

- When iterating a view of a single component that is owned by a group, adding all the components required to add an entity to the group may *invalidate the iterator*.

- When iterating a view of multiple components lead by a group-owned component, adding all components required to add the entity to that same group will *invalidate the iterator*. [`View:use()`](View#use.md) can be used to specify a component to lead that is not owned by the same group to get around this.

    In short, when iterating a view that includes group-owned components, do not add any component owned by any of those groups unless you
    1. specify a component to lead that is not owned by the same group as the components you intend to add.
    2. know that adding those group-owned components will not cause the entity to enter the group.

## Pools

[`Registry:storage()`](Registry#storage.md) returns the underlying storages used in the registry to store data. You can iterate over these for more direct access than views and also modify the values of `Pool.values` directly. Changing `Pool.entities` or adding or removing fields from either table however will result in *undefined behavior*.

## Multithreading

- Components can be added and removed during iteration as long as it is the only thread doing so for that set of components. This does not apply if any component in that set belongs to a group that has other group components being used in another thread,

    e.g One thread can add/remove component `X` and another thread can add/remove `Y` and `Z` as long as `X` is not grouped with `Y` or `Z`.

- The same set of components can be iterated by multiple threads at the same time as long as no components are added or removed.
