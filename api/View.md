---
permalink: /api/View
title: View
---

## Methods

### exclude()

Excludes entities with the given components from the view.

- **Type**

    ```lua
    function View:exclude<T...>(components: ...unknown): View<T...>
    ```

- **Details**

    The method will return the same view that it was called on.

    Any entities encountered with **any** of the excluded components, will not be returned during iteration.

---

### include()

Includes entities with the given components into the view.

- **Type**

    ```lua
    function View:include<T...>(components: ...unknown): View<T...>
    ```

- **Details**

    The method will return the same view that it was called on.

    Any entities that do not have **all** of the included components will be not be returned during iteration.

    Components given with this method will not have their values returned during iteration.

---

## Iteration

### each()

Returns a generator that can be used to iterate over all entities within the view.

- **Type**

    ```lua
    function View:each<T...>(): () -> (Entity, T...)
    ```

- **Details**

    The entity followed by its components (ordered the same as the argument list) are returned.

    Components can be added and changed during iteration. Newly added components and their entities will not be returned until the next iteration.

    Components can be removed during iteration as long as the component being removed belongs to the latest entity returned.
    - i.e. Do not remove components from entities outside of the for loop while the loop has not stopped yet for the given components.

    

- **Example**

    ```lua
    for entity, health, position in registry:view(Health, Position):each() do
        print(entity, health, position)
    end
    ```

---

### Generalized

- **Details**
  
  Generalized iteration functions identically to [`View:each()`](View#each).

- **Example**

    The need to call [`View:each()`](View#each) can be omitted.
    The following code functions identically to the previous example.

    ```lua
    for entity, health, position in registry:view(Health, Position) do
        print(entity, health, position)
    end
    ```

    > ⚠️ As of now, Luau is unable to correctly infer the return types with this method.

---
