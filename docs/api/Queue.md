# Queue

A class for queuing values to be processed together later.

## Methods

### add()

Adds a set of values to a queue.

- **Type**

    ```lua
    function Queue:add<T...>(...: T...)
    ```

- **Details**

    Each time this method is called, the size of the queue increases by one.

    All arguments given are later returned together in the same iteration.

    Queues are FIFO.

    ::: warning
    The first value in the argument list cannot be `nil` since that will cause
    iteration to stop early.
    :::

--------------------------------------------------------------------------------

### clear()

Clears the queue.

- **Type**

    ```lua
    function Queue:clear<T...>()
    ```

## Iteration

Queues support generalized iteration.

```lua
for ...: T... in Queue<T...> do
```

The queue returns in sets of values passed to `Queue:add()` in the same
order it was called in.

Values added during iteration are not returned.

The queue automatically clears itself after iteration.

::: warning
Adding values during iteration will cause them to be cleared when iteration
completes and they will never be iterated.
:::
