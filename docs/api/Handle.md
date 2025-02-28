# Handle

Thin wrapper around an entity and its registry.

```lua
type ecr.Handle
```

## Properties

### registry

The registry the entity belongs to.

- **Type**

    ```lua
    Handle.registry: Registry
    ```

--------------------------------------------------------------------------------

### entity

The entity the handle refers to.

- **Type**

    ```lua
    Handle.entity: entity
    ```

## Methods

The `Handle` class wraps the following registry methods:

- destroy()
- has_none()
- add()
- set()
- insert()
- patch()
- has()
- get()
- try_get()
- remove()

The `set()` and `insert()` method will also return the handle it is called
on.

- **Example**

    ```lua
    local e = registry:handle()

    e:set(A, 1)
     :set(B, 2)

    print(e:get(A, B)) --> 1, 2
    ```
