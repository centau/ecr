---
permalink: /api/Pool
title: Pool
---

> ⚠️ Pools are currently unstable and may change in a coming update to ecr.
>  
> As of now they're only intended for internal usage, while you can retrieve a Pool by using [`Registry:storage()`](Registry#storage), pools might be changed

## Properties

### map

A lookup table which is used to get the index of a entity inside a pool.

- #### Type

    ```lua
    Pool.map: {[Entity]: number}
    ```

- #### Details

    The value from this can be plugged into [`Pool.values`](Pool#values) to get the value of a component

---

### entities

A lookup table which is used to get the id of a Entity

- #### Type
  
    ```lua
    Pool.entities: {[number]: Entity}
    ```

- #### Details

    The index/key used to get the associated entity can also be used to get the component value from [`Pool.values`](Pool#values)

---

### values

A table containing a list of values associated with components of entities.

- #### Type
  
    ```lua
    Pool.values: {[number]: T}
    ```

- #### Details

    The index/key used to access the value of a entity can also be used to get the Entity id from [`Pool.entities`](Pool#entities)

---

### size

A number containing the amount of indexes or entities exist inside the pool.

- #### Type

    ```lua
    Pool.size: number
    ```

---
