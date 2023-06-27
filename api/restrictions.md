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

## Pools

[`Registry:storage()`](Registry#storage.md) returns the underlying storages used in the registry to store data. You can iterate over these for more direct access than views and also modify the values of `Pool.values` directly. Changing `Pool.entities` or adding or removing fields from either table however will result in *undefined behavior*.

## Multithreading

- Components can be added and removed during iteration as long as it is the only thread doing so for that set of components. This does not apply if any component in that set belongs to a group that has other group components being used in another thread,

    e.g One thread can add/remove component `X` and another thread can add/remove `Y` and `Z` as long as `X` is not grouped with `Y` or `Z`.

- The same set of components can be iterated by multiple threads at the same time as long as no components are added or removed.
