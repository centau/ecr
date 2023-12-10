# Signal

Manage listeners to an event.

```lua
type ecr.Signal<T...>
```

## Methods

### connect()

Connects a given function to the signal to be called whenever the signal is
fired.

- **Type**

    ```lua
    function Signal:connect<T...>((T...) -> ()): Connection
    ```

- **Details**

    New connections made within a listener will not be ran until the next time
    the signal is fired.

## Connection

```lua
type ecr.Connection<T...>
```

### disconnect()

Disconnects a listener from a signal.

- **Type**
  
    ```lua
    function Connection:disconnect()
    ```

- **Details**

    ::: warning
    Disconnecting other listeners from within a listener is not allowed.
    Disconnecting a listenener from within itself is allowed.
    :::

--------------------------------------------------------------------------------

### Reconnect()

Reconnects a listener to a signal.

- **Type**
  
    ```lua
    function Connection:reconnect()
    ```
