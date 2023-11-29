# Storage

The registry gives you access to the underlying arrays used to store entities
and components.

Each component type within the registry has its own [pool](../api/Pool.md) which
stores all entities that have that component, as well as its corresponding
component values.

A pool is retrieved with:

```lua
local pool = registry:storage(ctype)

type Pool<T> = {
    size: number,
    entities: buffer,
    values: Array<T>
}
```

Pools are direct access to the underlying storage that the registry uses to
store entities and components.

It is safe to read from pools, but you cannot write to pools, with the exception
of writing to indexes of `Pool.values`. Writing to anything else is undefined
behavior.

Buffers aren't nice to work with, so you can use
[ecr.buffer_to_array()](../api/ecr#buffer_to_array) to access entities easier.

```lua
local entities = ecr.buffer_to_array(pool.entities, pool.size)
```

This can be useful for e.g:

- Getting all entities and components to replicate a registry from server to
  client for the first time they join.

- Modifying values directly for performance in systems acting on many entities.

    ```lua
    local Position = ecr.component(Vector3.new)
    local Velocity = ecr.component(Vector3.new)

    local function update_positions(dt: number)
        -- groups sort their pools so that all entities in all of the group's
        -- pools are sorted in the same order from 1 up to the group's size
        -- this makes positions[i] correspond to velocities[i] (perfect SoA)
        local n = #registry:group(Position, Velocity)
        local positions = registry:storage(Position).values
        local velocities = registry:storage(Velocity).values

        for i = 1, n do
            positions[i] += velocities[i] * dt
        end
    ```

If needed you can also get all pools inside the registry via an iterator.

```lua
for ctype, pool in registry:storage() do
```
