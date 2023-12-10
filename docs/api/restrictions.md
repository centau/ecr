# Restrictions

The API omits sanity checks in areas that would be costly to do so, allowing you
to run into problems like iterator invalidation and undefined behavior. This
means that there are certain restrictions on what you can do. All restrictions
are documented here and at the relevant API references.

## Signals

- Listeners cannot disconnect other listeners. Listeners can disconnect
  themselves.

- The registry cannot be modified within a listener, you cannot add or remove
  components, and create or destroy entities.

## Modifying During Iteration

This applies to the iteration of views, observers and groups.

- During iteration, adding or removing components from entities not currently
  being iterated can *invalidate the iterator*.

## Pools

[`storage()`](Registry#storage.md) returns the underlying storages used
by the registry to store entities and components. You can use these for more
direct access than views and also modify the values of `Pool.values` directly.

- Changing `Pool.entities` or `Pool.size` is *undefined behavior*.

## Releasing Ids

- Destroying an entity that still has components with
[`release()`](Registry#release.md) is *undefined behavior*.

## Multithreading

- Components can be added or removed during iteration as long as it is the only
  thread doing so for that set of components.
  
  This does not apply if a component in that set belongs to a group that has
  other group components being used in another thread, e.g One thread can
  add/remove component `X` and another thread can add/remove `Y` and `Z` as long
  as `X` is not grouped with `Y` or `Z`.

- The same set of components can be iterated by multiple threads at the same
  time if they are reading only.
