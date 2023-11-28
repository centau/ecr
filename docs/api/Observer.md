# Observer

Observers are used to track component changes.

The observer records changed components that can be iterated over and cleared at
will.

## Methods

### exclude()

Excludes entities with the given components from the observer.

- **Type**

    ```lua
    function Observer:exclude<T...>(components: ...unknown): Observer<T...>
    ```

- **Details**

    Any entities encountered with *any* of the excluded components, will not be
    returned during iteration.

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

### persist()

Stops automatic clearing of its entities when it is iterated.

- **Type**

    ```lua
    function Observer:persist<T...>(): Observer<T...>
    ```

- **Details**

--------------------------------------------------------------------------------

### clear()

Clears all stored entities.

- **Type**

    ```lua
    function Observer:clear<T...>(): Observer<T...>
    ```

## Iteration

Observers support generalized iteration.

```lua
for id: Entity, ...: T... in Observer<T...> do
```

The observer will return entities that have had any components given added or
changed since the last iteration and still have all components given at the time
of iteration.

The entity followed by the latest component values are returned.

Components can be added, changed and removed during iteration.
Components added during iteration are not returned for that iteration.

Will automatically clear the observer unless `Observer:persist()` was called.

::: warning
Adding values during iteration can cause them to be cleared when iteration
completes and they will never be iterated.
:::

::: warning
During iteration, adding or removing components from entities not currently
being iterated can invalidate the iterator.
:::

## Length

Returns the amount of entities in the observer.

```lua
#Observer<T...>: number
```
