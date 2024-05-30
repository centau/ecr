# Queue

Queues values to be processed later.

```lua
type ecr.Queue<T...>
```

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

Iterates all values added to the queue.

- **Type**

    ```lua
    for ...: T... in Queue<T...> do
    ```

- **Details**

    The queue returns in sets of values passed to `Queue:add()` in the same
    order it was called in.

    The queue automatically clears itself after iteration. `Queue:iter()`
    returns an iterator that will not automatically clear on completion.

    ::: warning
    Adding values during iteration will cause them to be cleared when iteration
    completes and they will never be iterated.
    :::
