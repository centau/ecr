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

### each()

Returns an iterator that can be used to iterate over all entities in the view.

- **Type**

    ```lua
    function View:each<T...>(): () -> (Entity, T...)
    ```

- **Details**

    The entity followed by its components (ordered the same as the argument list) are returned.

    Components can be added and changed during iteration. Newly added components and their entities will not be returned until the next iteration.

    > ⚠️ During iteration, adding or removing components from entities not currently being iterated can *invalidate the iterator*.

---

### use()

Specifies a component to iterate along.

- **Type**

    ```lua
    function View:use<T...>(component: unknown): View<T...>
    ```

- **Details**

    Views, by default, iterate along the smallest pool within the given set of components. This function allows a specific pool to be iterated along instead as long as the component is included in the view.

---

## Iteration

Views support generalized iteration.

- **Example**

    The need to call [`View:each()`](View#each) can be omitted.
    The following code functions identically to the previous example.

    ```lua
    for entity, health, position in registry:view(Health, Position) do
        print(entity, health, position)
    end
    ```

---
