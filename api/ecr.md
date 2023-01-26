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

    Component types can be given a default value which are assigned using [`registry:add()`](Registry#add) by specifying a function. This function will be called and its return value used for each call.

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

    Registries store and manages entities and their components.

    It is recommended to define all component types before creating any `Registry` instances so that registries can allocate the correct amount of memory for faster operations.

---

<br><br>

## Constants

### null

A null entity.

- **Type**
  
    ```lua
    ecr.null: Entity
    ```

- **Details**

    The null entity is an entity that is guaranteed to be invalid.
  
    The following expression will always return `false`:

    ```lua
    registry:valid(ecr.null)
    ```

---
