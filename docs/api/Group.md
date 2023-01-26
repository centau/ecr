---
permalink: /api/Group
title: Group
---

Groups are used to iterate over a grouped set of components.

Groups rearrange the pools of chosen components to optimize the iteration of specific sets of components.

## Methods

### each()

Returns an iterator that can be used to iterate over all entities in the group.

- **Type**

    ```lua
    function Group:each<T...>(): () -> (Entity, T...)
    ```

- **Details**

    The entity followed by its components (ordered the same as the argument list) are returned.

    Components can be added and changed during iteration. Newly added components and their entities will not be returned until the next iteration.

    > ⚠️ During iteration, adding or removing components from entities not currently being iterated can *invalidate the iterator*.

---

## Iteration

Groups support generalized iteration.

---
