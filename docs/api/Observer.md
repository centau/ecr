---
permalink: /api/Observer
title: Observer
---

Observers are used to track changes on components and iterate through these changes inside ecr.

Inherits from [View](View)<br>
You can get this object through [`Registry:track()`](Registry#track).

## Methods

### disconnect()

Disconnects the Observer stopping any new changes from being tracked

- #### Type

    ```lua
    function Observer:disconnect(): ()
    ```

---

### reconnect()

Reconnects the Observer and allows it to start tracking changes again

- #### Type

    ```lua
    function Observer:reconnect(): ()
    ```

---

### clear()

Clears all tracked changes and starts tracking new changes

- #### Type

    ```lua
    function Observer:clear(): ()
    ```

- #### Details

    When this is called, all currently recorded changes will be discarded. Make sure to call this everytime you finish with the currently recorded changes, as not calling this will keep changes you've already processed.

---
