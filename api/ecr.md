---
permalink: /api/ecr
title: ecr
---

## Functions

### component()

Creates a new component type.

- **Type**

    ```lua
    function ecr.component(): unknown
    function ecr.component<T>(default: () -> T): T
    ```

- **Details**

    Returns a unique identifier representing a new component type.

    If given a function, the component can be assigned to an entity using [`registry:add()`](Registry#add), which will call the given function and assign the returned value.

- **Example**

    No default value.

    ```lua
    local Health = ecr.component() :: number
    local Model = ecr.component() :: Model
    ```

    With default value.

    ```lua
    local Health = ecr.component(function()
        return {
            Current = 100,
            Max = 100
        }
    end)

    local Position = ecr.component(function()
        return Vector3.new()
    end)
    ```

---

### registry()

Creates a new registry.

- **Type**

    ```lua
    function ecr.registry(): Registry
    ```

- **Details**

    It is recommended to define all component types before creating any `Registry` instances so that registries can allocate the correct amount of memory for faster operations.

---
