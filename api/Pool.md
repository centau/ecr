---
permalink: /api/Pool
title: Pool
---

The datastructure used internally to store all entities and values for a single component type.

## Properties

### size

The amount of entities contained in the pool.

- **Type**

    ```lua
    Pool.size: number
    ```

---

### entities

An array of all entities with the given component type.

- **Type**
  
    ```lua
    Pool.entities: Array<entity>
    ```

- **Details**

    This array is sorted in the same order as [`Pool.values`](Pool#values).

    - i.e. `entities[n]`'s component value is located at `values[n]`.

---

### values

An array of all values for the given component type.

- **Type**
  
    ```lua
    Pool.values: Array<T>
    ```

- **Details**

    This array is sorted in the same order as [`Pool.entities`](Pool#entities).

---
