# Storage

Each component type in the registry has its own [pool](../api/Pool.md). A pool
stores every entity that has that component type, and their corresponding value
for that component type. Pools are the underlying containers that the registry
directly modifies.

ECR was designed with transparent access to data in mind, and so, you can access
these pools directly if needed.

```lua
type Pool<T> = {
    -- amount of entities in the pool (so amount that have the component type)
    size: number,

    -- buffer (used as an array) of all entities in the pool
    entities: buffer,

    -- array of all component values (value for entities[i] is values[i])
    values: Array<T>
}
```

A pool for a type is retrieved like so:

```lua
local pool = registry:storage(ctype)
```

You can read from pools, but you cannot write to pools, with the exception
of writing to values of `Pool.values`. The registry maintains the size and
values of `Pool.entities`, so those should not be changed.

Buffers aren't nice to work with, so you can use
[`ecr.buffer_to_array()`](../api/ecr#buffer_to_array) to access entities easier.

```lua
local entities = ecr.buffer_to_array(pool.entities, pool.size)
```

This can be useful for e.g:

- Getting all entities and components to replicate a registry from server to
  client for the first time they join.

- Modifying values directly for performance systems.

If needed you can also get all pools inside the registry via an iterator.

```lua
for ctype, pool in registry:storage() do
```
