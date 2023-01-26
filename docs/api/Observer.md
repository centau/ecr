---
permalink: /api/Observer
title: Observer
---

Observers are used to track component changes.

The observer records changed components that can be iterated over and cleared at will.

## Methods

### exclude()

Excludes entities with the given components from the observer.

- **Type**

    ```lua
    function Observer:exclude<T...>(components: ...unknown): View<T...>
    ```

- **Details**

    The method will return the same observer that it was called on.

    Any entities encountered with **any** of the excluded components, will not be returned during iteration.

### each()

Returns an iterator that can be used to iterate over all entities in the observer.

- **Type**

    ```lua
    function Observer:each<T...>(): () -> (Entity, T...)
    ```

- **Details**

    The entity followed by its components (ordered the same as the argument list) are returned.

    Components can be added and changed during iteration. Newly added components and their entities will not be returned until the next iteration.

    > ⚠️ During iteration, adding or removing components from entities not currently being iterated can *invalidate the iterator*.

---

### disconnect()

Disconnects the observer, stopping any new changes from being tracked

- **Type**

    ```lua
    function Observer:disconnect()
    ```

- **Details**

    > ⚠️ This must be called for the observer to be garbage collected.

---

### reconnect()

Reconnects the Observer and allows it to track future changes again.

- **Type**

    ```lua
    function Observer:reconnect()
    ```

---

### clear()

Clears all recorded changes.

- **Type**

    ```lua
    function Observer:clear(): ()
    ```

- **Details**

    Use to clear all recorded changes after they have been processed to avoid reprocessing the same changes again later.

---

## Iteration

Observers support generalized iteration.

---
