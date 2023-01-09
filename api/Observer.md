---
permalink: /api/Observer
title: Observer
---

Observers are used to track component changes.

Extends the [View](View) class.

The observer keeps track of changed components that can be iterated over and cleared at will.

## Methods

### disconnect()

Disconnects the observer, stopping any new changes from being tracked

- **Type**

    ```lua
    function Observer:disconnect(): ()
    ```

---

### reconnect()

Reconnects the Observer and allows it to track future changes again.

- **Type**

    ```lua
    function Observer:reconnect(): ()
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
