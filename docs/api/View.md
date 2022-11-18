---
permalink: /api/View
title: View
---

## Methods

### exclude()

Excludes entities with the given component from the view.

- ### Type

    ```lua
    function View:exclude<T...>(components: ...unknown): View<T...>
    ```

- ### Details

    The method will return the same view that it was called on.

    Any entities encountered with **any** of the excluded components, will be skipped over in iteration.

## Iteration

### each()

Returns a generator that can be used to iterate over all entities within the view.

- ### Type

    ```lua
    function View:each<T...>(): () -> (Entity, T...)
    ```

- ### Details

    The entity followed by its components (ordered the same as the argument list) is returned.

- ### Example

    ```lua
    for entity, health, position in registry:view(Health, Position):each() do
        print(entity, health, position)
    end
    ```

---

### Generalized

- ### Example

    The need to call [`view:each()`](View#each) can be omitted.
    The following code functions identically to the previous example.

    ```lua
    for entity, health, position in registry:view(Health, Position) do
        print(entity, health, position)
    end
    ```

    > ⚠️ As of now, Luau is unable to correctly infer the return types with this method.

---
