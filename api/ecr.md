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

### tag()

Creates a new valueless component type.

- **Type**

    ```lua
    function ecr.tag(): unknown
    ```

- **Details**

    Returns a unique identifier representing a new component type.

    Tag components behave the same as normal components.

    It is recommend to only use tag components with [`add()`](Registry.md#add),
    [`remove()`](Registry.md#remove) and [`has()`](Registry.md#has).
    Using [`set()`](Registry.md#set) will not apply the valueless optimization
    and [`get()`](Registry.md#get) will return `nil`.

---

### is_tag()

Checks if a component type is a tag.

- **Type**

    ```lua
    function ecr.is_tag<T>(ctype: T): boolean
    ```

---

### queue()

Creates a new queue.

- **Type**

    ```lua
    function ecr.queue(): Queue<...unknown>
    function ecr.queue<T...>(signal: ISignal<T...>) -> Queue<T...>

    type ISignal<T...> = 
        { connect: (ISignal, (T...) -> ()) -> () } |
        { Connect: (ISignal, (T...) -> ()) -> () }
    ```

- **Details**

    Accepts any signal object that matches the given interface,
    any values passed into the signal callback will automatically be queued.

---

### name()

Associates names with components for debugging.

- **Type**

    ```lua
    function ecr.name<T>(names: T & Map<string, Component>) -> T
    ```

- **Details**

    Allows for errors raised to display the component name instead of its
    argument list position.

    The table returned is the same table object given and is also frozen.

<br><br>

## Constants

### entity

A special component type that refers to the registry entity pool.

- **Type**
  
    ```lua
    ecr.entity: Entity
    ```

- **Examples**

    View all entities:

    ```lua
    registry:view(ecr.entity)
    ```

    Listen to entity creation:

    ```lua
    registry:added(ecr.entity):connect()
    ```

---

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
