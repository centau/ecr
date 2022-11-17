---
permalink: /api/Registry
title: Registry
---

## Methods

### create()

Creates a new entity and returns the entity's identifier.

- ### Type

    ```lua
    function Registry:create(): Entity
    ```

- ### Details

    Identifiers are (mostly) guaranteed to be unique.

    The only case where identifiers may be repeated is if overflow
    occurs after an identifier is reused 2^33 times.

---

### release()

Releases the entity identifier, removing the entity from the registy.

- ### Type

    ```lua
    function Registry:release(e: Entity): ()
    ```

---

### set()

Sets an entity's component value.

- ### Type

    ```lua
    function Registry:set<T>(e: Entity, component: T, value: T?)
    ```

- ### Details

    Will add the component to the entity with the given value
    if the entity does not already have the component.

    If `value` is `nil` then the component will be removed from the entity.

---

### get()

Gets an entity's component value.

- ### Type

    ```lua
    function Registry:get<T...>(e: Entity, components: T...): T...
    ```

- ### Details

    Will return the value of each of the specified components.

    Will return `nil` if the entity does not own the component.

---

### view()

Creates a new registry view.

- ### Type

    ```lua
    function Registry:view<T...>(components: T...): View<T...>
    ```

- ### Details

    Creates a new view with the specified components.

    Entities in the view are guaranteed to have *at least* all of the specified components.

    Views are relatively cheap to create so it is encouraged to construct and throw them away after iteration on the fly.

---
