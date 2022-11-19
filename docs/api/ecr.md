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
    ```

- **Details**

    A *component* in `ECR` is actually just a unique integer identifier.

    For user-friendliness, it is recommend to typecast the result of this function
    to whatever type of value the component is supposed to represent.
    This allows you to get typechecking features when using `Registry` methods.

    It is recommended to define all components before creating any `Registry` instances,
    so that registries can allocate the correct amount of memory for faster operations.

- **Example**

    ```lua
    local Health = ecr.component() :: number
    local Model = ecr.component() :: Model
    local Transform = ecr.component() :: CFrame
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

    It is still recommended to specify a size that you expect to not go over anyways
    as this allows the registry to allocate the correct amount of memory for faster operations.

    > ⚠️ Due to implementation details, the total amount of entities **cannot** exceed 1,048,000 no matter the size specified.
    > This is subject to change.
    > Attempting to go over this limit will throw an error on `registry:create()` call.

---
