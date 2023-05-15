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
    function ecr.component<T>(constructor: () -> T): T
    ```

- **Details**

    Returns a unique identifier representing a new component type.

    Component types can be given a constructor which is called when [`registry:add()`](Registry#add.md) is used.

- **Example**

    No constructor.

    ```lua
    local Health = ecr.component() :: number
    local Model = ecr.component() :: Model
    ```

    With constructor.

    ```lua
    local Health = ecr.component(function()
        return {
            Current = 100,
            Max = 100
        }
    end)

    local Position = ecr.component(function()
        return Vector3.new(0, 0, 0)
    end)
    ```

---

### registry()

Creates a new registry.

- **Type**

    ```lua
    function ecr.registry(): Registry
    ```

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

    This id behaves like the id of an entity that has been destroyed.

    Attempting to add or remove components using this id will error.
  
    The following expression will always return `false`:

    ```lua
    registry:contains(ecr.null)
    ```

---
