# Signal

ECR Signal class.

## Methods

### connect()

Connects a given function to the signal to be called whenever the signal is fired.

- **Type**

    ```lua
    function Signal:connect<T...>((T...) -> ()): Connection
    ```

- **Details**

    New connections made within a listener will not be ran until the next time the signal is fired.

---

## Connection

### disconnect()

Disconnects a listener from a signal.

- **Type**
  
    ```lua
    function Connection:disconnect()
    ```

- **Details**

    > ⚠️ Disconnecting other listeners from within a listener may result in *undefined behavior*.
    > Disconnecting a listenener from within itself is allowed.

---

### Reconnect()

Reconnects a listener to a signal.

- **Type**
  
    ```lua
    function Connection:reconnect()
    ```

---
