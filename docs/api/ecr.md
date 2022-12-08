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

    A *component* in `ECR` is just a unique integer identifier.

    For user-friendliness, it is recommend to typecast the result of this function
    to whatever type of value the component is supposed to represent.
    This allows you to use typechecking features with libary functions.

    It is recommended to define all components before creating any `Registry` instances,
    so that registries can allocate the correct amount of memory for faster operations.

    If given a function, the component can be assigned to an entity using [`registry:add()`](Registry#add),
    which will call the given function and assign the returned value.

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
    function ecr.registry(size: number = 0): Registry
    ```

- **Details**

    The `size` parameter is not a strict limit,
    the amount of entities can exceed the specified size.

    It is recommended to specify a size that you expect to not go over anyways
    as this allows the registry to allocate the correct amount of memory for faster operations.

    > ⚠️ Due to implementation details, the total amount of entities **cannot** exceed 1,048,575 no matter the size specified.
    > This is subject to change.
    > Attempting to go over this limit will throw an error on [`registry:create()`](Registry#create) call.

---
