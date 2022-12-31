---
permalink: /api/Registry
title: Registry
---

## Methods

### create()

Creates a new entity and returns the entity's identifier.

- **Type**

    ```lua
    function Registry:create(): Entity
    function Registry:create(id: Entity): Entity
    ```

- **Details**

    Identifiers are composed internally of two parts, a key and version.

    Keys can be reused to save memory while versions will be incremented to keep the
    overall identifier unique.

    The version can be incremented to a max value of `2^33 - 1` before it will overflow and reset back to 1.
    This means that ids returned are guaranteed to be unique unless a key has been reused `8,589,934,592` times or an old ID was given as an argument.

    Can specify a pre-existing entity ID to use. Will error if the registry is unable to create a new entity with the given ID.

---

### release()

Releases the entity identifier, allowing the identifier to be reused.

- **Type**

    ```lua
    function Registry:release(entity: Entity): ()
    ```

- **Details**

    > ⚠️ This method does **not** remove any of the entity's components.
    > If it is not known that an entity has components, use [`Registry:destroy()`](Registry#destroy) instead.

    > ⚠️ Using this method on an entity that still has components will result in *undefined behavior*.

---

### destroy()

Releases the entity identifier and removes all of its components.

- **Type**

    ```lua
    function Registry:destroy(entity: Entity): ()
    ```

---

### valid()

Checks if the given entity is a valid entity identifier.

- **Type**

    ```lua
    function Registry:valid(entity: Entity): boolean
    ```

- **Details**

    Released identifiers are **not** valid.

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

### orphan()

Checks if the given entity is an orphan (has no components).

- **Type**

    ```lua
    function Registry:orphan(entity: Entity): boolean
    ```

- **Details**

    A entity is considered a orphan if it has no components.

---

### add()

Adds components with default values to an entity.

- **Type**
  
    ```lua
    function Registry:add<T...>(entity: Entity, components: T...)
    ```

- **Details**

    Adds the given components to the entity with default values.

    The value assigned is the value returned by the function given when defining the component.

    > ⚠️ Attempting to add components with this method that do not have default values will throw an error.

    > ⚠️ Attempting to add a component to an entity that already has the component will throw an error.

---

### set()

Sets an entity's component value.

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

Updates an entity's component value.

- **Type**

    ```lua
    function Registry:patch<T>(entity: Entity, component: T, patcher: (T) -> T?)
    ```

- **Details**

    Takes a callback which is given the current component value as the only argument.
    The value returned by the callback is then set as the new value.

    If the value returned is `nil` then the component is removed from the entity.

    > ⚠️ Attempting to patch a component that an entity does not have will result in *undefined behavior*.

- **Example**

    ```lua
    registry:patch(entity, Health, function(health)
        return health - 10
    end)
    ```

---

### has()

Checks if a entity has all of the given components.

- **Type**

    ```lua
    function Registry:has<T...>(entity: Entity, components: T...): boolean
    ```

- **Details**

    If multiple components are given, it is checked if the entity has **every** component given.

---

### get()

Gets an entity's components.

- **Type**

    ```lua
    function Registry:get<T...>(entity: Entity, components: T...): T...
    ```

- **Details**

    Will return the value of each of the given components.

    Will return `nil` if the entity does not own the component.

---

### remove()

Removes the given components from an entity.

- **Type**

    ```lua
    function Registry:remove<T...>(entity: Entity, components: T...): ()
    ```

- **Details**

    Will do nothing if the entity does not own the given component.

---

### view()

Creates a [`view`](View) to see all entities with the specified components.

- **Type**

    ```lua
    function Registry:view<T...>(components: T...): View<T...>
    ```

- **Details**

    Creates a new view with the given components.

    Entities in the view are guaranteed to have *at least all* of the specified components.

    Views are relatively cheap to create so it is encouraged to construct and throw them away after iteration on the fly.

---

### track()

Creates an [`observer`](Observer) which tracks any changes that happen for a given component.

- **Type**

    ```lua
    function Registry:track<T, U...>(totrack: T, includes: U...): Observer<T, U...>
    ```

- **Details**

    Observers are used to track changes that happen to a given component and grants control over when to track, stop tracking and start tracking again.

    Only changes made to the first argument specified are tracked, subsequent arguments are only included when iterating just like a `View`.

    The observer will return entities that:

    1. Are assigned the component when they previously did not own it.
    2. Have the tracked component's value changed.

    An entity must have **all** components specified at the time of iteration to be returned during iteration.

    A history of changes is not kept, the observer will only return entities whose tracked components have been changed with their latest values.

    When an observer is first created, it treats all current entities with the given component in the registry as newly changed.

    > ⚠️ After iterating over an observer and processing the changes, call [`Observer:clear()`](Observer#clear) to clear all changes so you do not reprocess the same changes again.

- **Example**

    ```lua
    local Health = ecr.component() :: number
    
    local tracker = registry:track(Health)
    local entity = registry:create()
    
    -- when the entity's health component is set to 100
    -- the tracker will record that.
    registry:set(entity, Health, 100) 

    for id, health in tracker:each() do
        print(health) -- will print 100
    end
    
    -- we clear the currently recorded changes as we have no use
    -- for them anymore.
    tracker:clear()
    ```

---

### size()

Returns the current amount of entities in the registry.

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

    Modifying the returned pool may result in *undefined behavior*.

---

### added()

Returns a [signal](Signal) which is fired whenever the given component is added to an entity.

- **Type**

    ```lua
    function Registry:added<T>(component: T): Signal<Entity, T>
    ```

    > ⚠️ Removing a component of a given type from within a listener connected to the same type will result in *undefined behavior*.

---

### changed()

Returns a [signal](Signal) which is fired whenever the given component's value is changed for an entity.

- **Type**

    ```lua
    function Registry:changed<T>(component: T): Signal<Entity, T>
    ```

    > ⚠️ Removing a component of a given type from within a listener connected to the same type will result in *undefined behavior*.

---

### removing()

Returns a [signal](Signal) which is fired whenever the given component is being removed from an entity.

- **Type**

    ```lua
    function Registry:removing<T>(component: T): Signal<Entity, nil>
    ```

- **Details**

    The signal is fired *before* the component is actually removed. You can retrieve the component value within the signal listener.

    > ⚠️ Adding or removing a component of a given type from within a listener connected to the same type will result in
    > *undefined behavior*. This type of listener is intended to allow users to perform cleanup and nothing else.


---
