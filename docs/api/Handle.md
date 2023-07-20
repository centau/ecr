---
permalink: /api/Handle
title: Handle
---

Thin wrapper around an entity and its registry.

## Properties

### registry

The registry the entity belongs to.

- **Type**

    ```lua
    Handle.registry: Registry
    ```

---

### entity

The entity the handle refers to.

- **Type**

    ```lua
    Handle.entity: Entity
    ```

---

## Methods

The `Handle` class wraps the following registry methods:

- destroy()
- orphaned()
- add()
- set()
- patch()
- has()
- get()
- try_get()
- remove()

One difference is that the `set()` method will return the handle it is called on.

- **Example**

    ```lua
    local handle = registry:handle()

    handle:set(A, 1)
          :set(B, 2)

    print(handle:get(A, B)) --> 1, 2
    ```

---
