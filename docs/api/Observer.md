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
    function Observer:exclude<T...>(components: ...unknown): Observer<T...>
    ```

- **Details**

    The method will return the same observer that it was called on.

    Any entities encountered with **any** of the excluded components, will not be returned during iteration.

---

### disconnect()

Disconnects the observer, stopping any new changes from being tracked

- **Type**

    ```lua
    function Observer:disconnect<T...>(): Observer<T...>
    ```

- **Details**

    Returns the same observer that it was called on.

    > ⚠️ This must be called for the observer to be garbage collected.

---

### reconnect()

Reconnects the Observer and allows it to track future changes again.

- **Type**

    ```lua
    function Observer:reconnect<T...>(): Observer<T...>
    ```

- **Details**

    Returns the same observer that it was called on.

---

### persist()

Stops automatic clearing of the observer.

- **Type**

    ```lua
    function Observer:persist<T...>(): Observer<T...>
    ```

- **Details**

    Returns the same observer that it was called on.

    Stops the observer from automatically clearing after it is iterated.

---

### clear()

Clears all recorded changes.

- **Type**

    ```lua
    function Observer:clear<T...>(): Observer<T...>
    ```

- **Details**

    Returns the same observer that it was called on.

    Use to clear all recorded changes after they have been processed to avoid reprocessing the same changes again later.

---

## Iteration

Observers support generalized iteration.

```lua
for id: Entity, ...: T... in Observer<T...> do
```

The entity id followed by the group components are returned.

Components can be added, changed and removed during iteration. Newly added components and their entities will not be returned until the next iteration.

Will automatically clear the observer unless `Observer:persist()` was called.

> ⚠️ Adding values during iteration can cause them to be cleared when
> iteration completes and they will never be iterated.

> ⚠️ During iteration, adding or removing components from entities not currently being iterated can invalidate the iterator.

---
