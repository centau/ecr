# ECR

## Functions

### registry()

Creates a new registry.

- **Type**

    ```lua
    function ecr.registry(): Registry
    ```

--------------------------------------------------------------------------------

### component()

Creates a new component type.

- **Type**

    ```lua
    function ecr.component(): unknown
    function ecr.component<T>(constructor: () -> T): T
    ```

- **Details**

    Returns a unique id representing a new component type.

    Component types can be given a constructor which can be invoked when
    [`registry:add()`](Registry#add.md) or
    [`registry:patch()`](Registry#patch.md) is used.

- **Example**

    No constructor.

    ```lua
    local Position = ecr.component() :: Vector3
    local Health = ecr.component() :: number
    ```

    With constructor.

    ```lua
    local Position = ecr.component(Vector3.new)

    local Health = ecr.component(function()
        return {
            Current = 100,
            Max = 100
        }
    end)
    ```

--------------------------------------------------------------------------------

### tag()

Creates a new tag component type.

- **Type**

    ```lua
    function ecr.tag(): nil
    ```

- **Details**

    Returns a unique id representing a new component type.

    Tag components are a special type of component that have no value.

--------------------------------------------------------------------------------

### is_tag()

Checks if a component type is a tag.

- **Type**

    ```lua
    function ecr.is_tag<T>(ctype: T): boolean
    ```

--------------------------------------------------------------------------------

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

    Accepts any signal object that matches the given interface. Will
    automatically connect a callback where any arguments it is called with are
    queued.

--------------------------------------------------------------------------------

### name()

Associates names with components for debugging.

- **Type**

    ```lua
    function ecr.name<T>(names: T & Map<string, Component>) -> T
    ```

- **Details**

    Allows for errors raised to display the component name instead of its
    argument position.

    The table returned is the same table object given and is also frozen.

--------------------------------------------------------------------------------

### buffer_to_array()

Converts a buffer of entities into an array of entities.

- **Type**

    ```lua
    function ecr.buffer_to_array(buf: buffer, size: number, arr: Array<entity>?) -> Array<entity>
    ```

- **Details**

    Copies the first `size` ids into a target array.

    If no target array is given, one will be created.

--------------------------------------------------------------------------------

### array_to_buffer()

Converts an array of entities into a buffer of entities.

- **Type**

    ```lua
    function ecr.buffer_to_array(arr: Array<entity>, size: number, buf: buffer?) -> buffer
    ```

- **Details**

    Copies the first `size` ids into a target buffer.

    If no target buffer is given, one will be created.

## Constants

### entity

A special component type that represents entities themselves.

- **Type**
  
    ```lua
    ecr.entity: entity
    ```

--------------------------------------------------------------------------------

### context

The context entity id.

- **Type**
  
    ```lua
    ecr.context: entity
    ```

--------------------------------------------------------------------------------

### null

The null entity id.

- **Type**
  
    ```lua
    ecr.null: entity
    ```

- **Details**

    Attempting to use this entity with a registry will error.

    The following expression will always return `false`:

    ```lua
    registry:contains(ecr.null)
    ```

--------------------------------------------------------------------------------

### id_size

The size of the entity id in bytes.

- **Type**
  
    ```lua
    ecr.id_size: number
    ```
