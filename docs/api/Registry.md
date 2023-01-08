---
permalink: /api/Registry
title: Registry
---

## Methods

> ⚠️ Using registry methods with invalid entity identifiers will result in unexpected behavior such as other entities having their components changed. When in doubt if an identifier is valid or not, use `Registry:valid()` to check.

### create()

Creates a new entity and returns the entity's identifier.

- **Type**

    ```lua
    function Registry:create(): Entity
    function Registry:create(id: Entity): Entity
    ```

- **Details**

    The first `8,589,934,592` new identifiers returned are guaranteed to be unique. After this, identifiers may be reused. Be wary of using stale references in situations where this number may be exceeded.

    Can also manually specify an entity identifier to use. Will error if the registry is unable to create a new entity with the given identifier.

    > ⚠️ Manually reusing an old identifier previously returned by this registry will no longer guarantee new identifiers returned to be unique.

    > ⚠️ The total amount of entities in a registry at any given time **cannot** exceed 1,048,575.
    > Attempting to go over this limit will throw an error.

---

### release()

Releases the entity identifier, making it invalid.

- **Type**

    ```lua
    function Registry:release(entity: Entity): ()
    ```

- **Details**

    > ⚠️ This method does **not** remove any of the entity's components.
    > If it is not known that an entity has components, use [`Registry:destroy()`](Registry#destroy) instead.

    > ⚠️ Using this method on an entity that still has components will result in *unexpected behavior*.

---

### destroy()

Releases the entity identifier and removes all of its components.

- **Type**

    ```lua
    function Registry:destroy(entity: Entity): ()
    ```

---

### valid()

Checks if the given entity identifier is valid.

- **Type**

    ```lua
    function Registry:valid(entity: Entity): boolean
    ```

- **Details**

    Valid identifiers are identifiers created with `Registry:create()` that have not yet been released.

---

### orphan()

Checks if the given entity has any components.

- **Type**

    ```lua
    function Registry:orphan(entity: Entity): boolean
    ```

- **Details**

    An entity is considered a orphan if it has no components.

---

### add()

Adds components with default values to an entity.

- **Type**
  
    ```lua
    function Registry:add<T...>(entity: Entity, components: T...)
    ```

- **Details**

    Adds the given components to the entity with their default values.

    The values assigned are the values returned by the functions used to define the components.

    > ⚠️ Attempting to add components with this method that do not have default values will throw an error.

    > ⚠️ Attempting to add a component to an entity that already has the component will throw an error.

---

### set()

Sets an entity's component.

- **Type**

    ```lua
    function Registry:set<T>(entity: Entity, component: T, value: T?)
    ```

- **Details**

    Adds the component to the entity with the given value
    if the entity does not already have the component.

    Changes the component's value for the given entity if the entity already owns the component.

    Removes the component from the entity if value is `nil`.

---

### patch()

Updates an entity's component.

- **Type**

    ```lua
    function Registry:patch<T>(entity: Entity, component: T, patcher: (T) -> T)
    ```

- **Details**

    Takes a callback which is given the current component value as the only argument.
    The value returned by the callback is then set as the new value.

    > ⚠️ Attempting to patch a component that an entity does not have will throw an error.

- **Example**

    ```lua
    registry:patch(entity, Health, function(health)
        return health - 10
    end)
    ```

---

### has()

Checks if an entity has all of the given components.

- **Type**

    ```lua
    function Registry:has<T...>(entity: Entity, components: T...): boolean
    ```

- **Details**

    Will return `true` only if the entity has *every* component specified.

---

### get()

Gets an entity's components.

- **Type**

    ```lua
    function Registry:get<T...>(entity: Entity, components: T...): T...
    ```

- **Details**

    Will return the value of each of the given components.

    Will return `nil` if the entity does not own a component.

---

### remove()

Removes the given components from the entity.

- **Type**

    ```lua
    function Registry:remove<T...>(entity: Entity, components: T...): ()
    ```

- **Details**

    Will do nothing if the entity does not own a component.

---

### view()

Creates a [`view`](View) for all entities with the specified components.

- **Type**

    ```lua
    function Registry:view<T...>(components: T...): View<T...>
    ```

- **Details**

    Creates a new view with the given components.

    Entities in the view are guaranteed to have *at least all* of the given components.

---

### track()

Creates an [`observer`](Observer) which tracks any changes that occur for a given component.

- **Type**

    ```lua
    function Registry:track<T, U...>(toTrack: T, includes: U...): Observer<T, U...>
    ```

- **Details**

    Only changes made to the component as the first argument are tracked, subsequent arguments are only included when iterating just like a `View`.

    The observer will return entities that:

    1. Are assigned the component when they previously did not own it.
    2. Have the component's value changed.
    3. Have all other components specified at the time of iteration.

    When an observer is first created, it treats all current entities with the given components in the registry as newly changed.

    > ⚠️ After iterating over an observer and processing the changes, call [`Observer:clear()`](Observer#clear) to clear all changes so you do not reprocess the same changes again.

---

### size()

Returns the current amount of valid entities in the registry.

- **Type**

    ```lua
    function Registry:size(): number
    ```

---

### entities()

Creates an array with all valid entities in the registry.

- **Type**

    ```lua
    function Registry:entities(): Array<Entity>
    ```

---

### storage()

Returns a [pool](Pool) containing every entity and corresponding value for a given component

- **Type**

    ```lua
    function Registry:storage<T>(component: T): Pool<T>
    ```

- **Details**
  
    The returned pool is direct access to the underlying datastructures the registry uses
    to store entities and components.

    Modifying the returned pool may result in *unexpected behavior*.

---

### added()

Returns a [signal](Signal) which is fired whenever the given component is added to an entity.

- **Type**

    ```lua
    function Registry:added<T>(component: T): Signal<Entity, T>
    ```

    > ⚠️ Removing a component of a given type from within a listener connected to the same type may result in *unexpected behavior*.

---

### changed()

Returns a [signal](Signal) which is fired whenever the given component's value is changed for an entity.

- **Type**

    ```lua
    function Registry:changed<T>(component: T): Signal<Entity, T>
    ```

    > ⚠️ Removing a component of a given type from within a listener connected to the same type may result in *unexpected behavior*.

---

### removing()

Returns a [signal](Signal) which is fired whenever the given component is being removed from an entity.

- **Type**

    ```lua
    function Registry:removing<T>(component: T): Signal<Entity, nil>
    ```

- **Details**

    The signal is fired *before* the component is actually removed. You can retrieve the component value within the signal listener.

    > ⚠️ Adding or removing a component of a given type from within a listener connected to the same type may result in
    > *unexpected behavior*. This type of listener is intended to allow users to perform cleanup and nothing else.

---

### version()

Probes the given identifier and returns the encoded version.

- **Type**

    ```lua
    function Registry:version(entity: Entity): number
    ```

---

### current()

Returns the current version of the given identifier.

- **Type**

    ```lua
    function Registry:current(entity: Entity): number
    ```

- **Details**

    Not to be confused with [`Registry:version()`](Registry#version). This method will return the latest version of the given identifer.

---
