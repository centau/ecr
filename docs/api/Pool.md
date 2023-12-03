# Pool

The container used by the registry internally to store entities and component
values for each component type.

## Properties

### size

The amount of entities contained in the pool.

- **Type**

    ```lua
    Pool.size: number
    ```

--------------------------------------------------------------------------------

### entities

A buffer of all entities with the given component type.

- **Type**
  
    ```lua
    Pool.entities: buffer
    ```

- **Details**

    0-indexed.

    Sorted in the same order as [`Pool.values`](Pool#values).

    - i.e. `entities[n]`'s component value is located at `values[n + 1]`.

--------------------------------------------------------------------------------

### values

An array of all values for the given component type.

- **Type**
  
    ```lua
    Pool.values: Array<T>
    ```

- **Details**

    1-indexed.

    Sorted in the same order as [`Pool.entities`](Pool#entities.md).
