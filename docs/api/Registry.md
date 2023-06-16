---
permalink: /api/Registry
title: Registry
---

## Methods

> ⚠️ There are certain [restrictions](restrictions) with what you can do with the registry that you should be aware of.

### create()

Creates a new entity and returns the entity's identifier.

- **Type**

    ```lua
    function Registry:create(): Entity
    function Registry:create(id: Entity): Entity
    ```

- **Details**

    All ids returned are guaranteed to be unique unless an old id is explicitly reused.

    An entity can be created using a specific id that was created by another registry or previously by the same registry. Will error if it is unable to do so.

    > ⚠️ Reusing an old identifier previously returned by this registry will no longer guarantee new identifiers returned to be unique.

    > ⚠️ The total amount of entities in a registry at any given time **cannot** exceed `1,048,575`.
    > Attempting to exceed this limit will throw an error.

---

### release()

Removes the entity from the registry.

- **Type**

    ```lua
    function Registry:release(id: Entity)
    ```

- **Details**

    > ⚠️ This method does **not** remove any of the entity's components.
    > If it is not known that an entity has components, use [`Registry:destroy()`](Registry#destroy.md) instead.

    > ⚠️ Using this method on an entity that still has components will result in *undefined behavior*.

---

### destroy()

Removes the entity from the registry and removes all of its components.

- **Type**

    ```lua
    function Registry:destroy(id: Entity)
    ```

---

### contains()

Checks if the given entity exists in the registry.

- **Type**

    ```lua
    function Registry:contains(id: Entity): boolean
    ```

---

### orphaned()

Checks if the given entity no components.

- **Type**

    ```lua
    function Registry:orphan(id: Entity): boolean
    ```

- **Details**

    An entity is considered an orphan if it has no components.

---

### add()

Adds all components specified to an entity.

- **Type**
  
    ```lua
    function Registry:add<T...>(id: Entity, components: T...)
    ```

- **Details**

    Adds the given components to the entity by calling each component constructor.

    Adding a component to an entity that already has the component will do nothing.

    > ⚠️ Attempting to add components with this method that do not have constructors will error.

---

### set()

Sets an entity's component.

- **Type**

    ```lua
    function Registry:set<T>(id: Entity, component: T, value: T?)
    ```

- **Details**

    Adds the component to the entity with the given value
    if the entity does not already have the component.

    Changes the component's value for the given entity if the entity already has the component.

    Removes the component from the entity if value is `nil`.

---

### patch()

Updates an entity's component.

- **Type**

    ```lua
    function Registry:patch<T>(id: Entity, component: T, patcher: (T) -> T)
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
    function Registry:has<T...>(id: Entity, components: T...): boolean
    ```

- **Details**

    Will return `true` only if the entity has *every* component specified.

---

### get()

Gets an entity's component values.

- **Type**

    ```lua
    function Registry:get<T...>(id: Entity, components: T...): T...
    ```

- **Details**

    Will error if the entity does not own a component.

---

### try_get()

Gets an entity's component value.

- **Type**

    ```lua
    function Registry:try_get<T>(id: Entity, components: T): T?
    ```

- **Details**

    Will return `nil` if the entity does not own a component.

---

### remove()

Removes the given components from an entity.

- **Type**

    ```lua
    function Registry:remove<T...>(id: Entity, components: T...): ()
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

Creates an [`observer`](Observer) which records changes that occur for a given component.

- **Type**

    ```lua
    function Registry:track<T...>(...: T...): Observer<T...>
    ```

- **Details**

    Tracks all components in the argument list.

    The observer will only return entities that:

    1. Are assigned the component when they previously did not own it.
    2. Have the component value changed.
    3. Have all components specified in the observer at the time of iteration.

    When an observer is first created, it treats all current entities with the given components in the registry as newly changed.

    > ⚠️ After iterating over an observer and processing the changes, call [`Observer:clear()`](Observer#clear.md) to clear all changes so you do not reprocess the same changes again.

---

### size()

Returns the current amount of entities in the registry.

- **Type**

    ```lua
    function Registry:size(): number
    ```

---

### entities()

Creates an array with all entities in the registry.

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

    Modifying the returned pool results in *undefined behavior*.

---

### added()

Returns a [signal](Signal) which is fired whenever the given component is added to an entity.

- **Type**

    ```lua
    function Registry:added<T>(component: T): Signal<Entity, T>
    ```

    The signal is fired *after* the component is changed.

    > ⚠️ Components cannot be added or removed within a listener.

---

### changed()

Returns a [signal](Signal) which is fired whenever the given component's value is changed for an entity.

- **Type**

    ```lua
    function Registry:changed<T>(component: T): Signal<Entity, T>
    ```

    The signal is fired *after* the component is changed.

    > ⚠️ Components cannot be added or removed within a listener.

---

### removing()

Returns a [signal](Signal) which is fired whenever the given component is being removed from an entity.

- **Type**

    ```lua
    function Registry:removing<T>(component: T): Signal<Entity, nil>
    ```

- **Details**

    The signal is fired *before* the component is actually removed. You can retrieve the component value within the signal listener.

    > ⚠️ Components cannot be added or removed within a listener.

---

### handle()

Returns a [handle](Handle) for an entity.

- **Type**

    ```lua
    function Registry:handle(id: Entity?): Handle
    ```

- **Details**

    If no entity is given then a new will one be created.

---
