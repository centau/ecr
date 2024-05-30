# Observer

Tracks component changes, and can be cleared at will.

```lua
type ecr.Observer<T...>
```

## Methods

### exclude()

Excludes entities with the given components from the observer.

- **Type**

    ```lua
    function Observer:exclude<T...>(components: ...unknown): Observer<T...>
    ```

- **Details**

    Entities with *any* of the excluded components, will not be returned during
    iteration.

--------------------------------------------------------------------------------

### disconnect()

Disconnects the observer, stopping any new changes from being tracked

- **Type**

    ```lua
    function Observer:disconnect<T...>(): Observer<T...>
    ```

    The observer must be empty before it is disconnected.

    ::: warning
    This must be called for the observer to be garbage collected.
    :::

--------------------------------------------------------------------------------

### reconnect()

Reconnects the Observer and allows it to track changes again.

- **Type**

    ```lua
    function Observer:reconnect<T...>(): Observer<T...>
    ```

--------------------------------------------------------------------------------

### clear()

Clears all stored entities.

- **Type**

    ```lua
    function Observer:clear<T...>(): Observer<T...>
    ```

## Iteration

Iterates all entities in the observer.

- **Type**

    ```lua
    for id: Entity, ...: T... in Observer<T...> do
    ```

- **Details**

    The observer will return entities that had any of the given components added
    or changed since it was last cleared and still have all given components at
    the time of iteration.

    The entity followed by the latest component values are returned.

    Components can be added, changed and removed during iteration.
    Components added during iteration are not returned for that iteration.

    Will automatically clear the observer on completion. `Observer:iter()`
    returns an iterator that will not automatically clear on completion.

    ::: warning
    Adding values during iteration can cause them to be cleared when iteration
    ends and they will never be iterated.
    :::

    ::: warning
    During iteration, adding or removing components from entities not currently
    being iterated can invalidate the iterator.
    :::

## Length

Returns the amount of entities in the observer.

- **Type**

    ```lua
    #Observer<T...>: number
    ```
