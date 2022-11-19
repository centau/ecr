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
    ```

- **Details**

    Identifiers are (mostly) guaranteed to be unique.

    The only case where identifiers may be repeated is if overflow
    occurs after an identifier is reused 2^33 times.

---

### release()

Releases the entity identifier, removing the entity from the registy.

- **Type**

    ```lua
    function Registry:release(entity: Entity): ()
    ```

- **Details**

    [`Registry:release()`](Registry#release) is a faster alternative to [`Registry:destroy()`](Registry#destroy) when entities are considered a [orphan](Registry#details-4).

    > ⚠️ [`Registry:release()`](Registry#release) does **not** remove any of it's entities components.
    > If you don't know if a entity has components but still want to remove it, use [`Registry:destroy()`](Registry#destroy) instead.

---

### destroy()

Releases the entity identifier and removes all of it's existing components.

- **Type**

    ```lua
    function Registry:destroy(entity: Entity): ()
    ```

---

### valid()

Returns if the given value is a entity inside the Registry

- **Type**

    ```lua
    function Registry:valid(possibleEntity: any): boolean
    ```

---

### version()

Returns the version of the given entity.

- **Type**

    ```lua
    function Registry:version(entity: Entity): number
    ```

- **Details**

    Not to be confused with [`Registry:current()`](Registry#current), [`Registry:version()`](Registry#version) will return the version encoded inside the entity. This is used to tell the difference between recycled entities.

- **Example**

     ```lua
    local entityA = registry:create()
    
    -- Will print 1, because this is the first version of the
    -- entity.
    print(registry:version(entityA))
    
    -- We release the entity, causing the id to be freed allowing
    -- it to be used again.
    registry:release(entityA)
    
    -- We create a new entity, which will now use the recycled id
    local entityB = registry:create()
    
    -- Will print 2, because this is the second version of this
    -- entity as the last version has been released.
    print(registry:version(entityB))
    -- Will still print 1, because this is from the first version
    -- of the entity
    print(registry:version(entityA))
    ```

---

### current()

Returns the current version of the given entity

- **Type**

    ```lua
    function Registry:current(entity: Entity): number
    ```

- **Details**

    Not to be confused with [`Registry:version()`](Registry#version), [`Registry:current()`](Registry#current) will return the latest version number of the entity. The version number is used to tell how many times a entity identifier has been recycled.

- **Example**

    ```lua
    local entityA = registry:create()
    registry:release()
    local entityB = registry:create()
    
    print(registry:version(entityA)) -- prints 1
    print(registry:current(entityA)) -- prints 2
    print(registry:version(entityB)) -- prints 2
    print(registry:current(entityB)) -- prints 2
    ```

---

### orphan()

Returns a boolean telling if the given entity is a orphan

- **Type**

    ```lua
    function Registry:orphan(entity: Entity): boolean
    ```

- **Details**

    A entity is considered a orphan if said entity has no components.

- **Example**

    ```lua
    
    local A = ecr.component() :: number
    
    local entity = registry:create()
    
    print(registry:orphan(entity)) -- Will print true
    
    registry:set(entity, A, 1) -- We give the entity a component
    print(registry:orphan(entity)) -- Will print false
    
    registry:remove(entity, A) -- Remove the component from the entity
    print(registry:orphan(entity)) -- Will print true
    
    ```

---

### set()

Sets an entity's component value.

- **Type**

    ```lua
    function Registry:set<T>(entity: Entity, component: T, value: T?)
    ```

- **Details**

    Will add the component to the entity with the given value
    if the entity does not already have the component.

    If `value` is `nil` then the component will be removed from the entity.

---

### patch()

Patches a entity's component value 

- **Type**

    ```lua
    function Registry:patch<T>(entity: Entity, component: T, patcher: (old: T) -> T?)
    ```
    
- **Details**

    Behaves similar to [`Registry:set()`](Registry#set) but instead of directly setting a value,
    you'll have to pass a function which will use the previous value to get a new value.
    
    This has the exact same behavior as `Registry:set()` and will remove components if `value` is `nil`.
    
- **Example**

    ```lua
    registry:patch(entity, Heatlh :: number, function(oldValue)
        return oldValue - 10
    end)
    ```
    
---

### has()

Returns if a entity has all of the given components.

- **Type**

    ```lua
    function Registry:has<T...>(entity: Entity, components: T...): boolean
    ```

---

### get()

Gets an entity's component value.

- **Type**

    ```lua
    function Registry:get<T...>(entity: Entity, components: T...): T...
    ```

- **Details**

    Will return the value of each of the specified components.
    Will return `nil` if the entity does not own the component.

---

### remove()

Removes the given components from a entity.

- **Type**

    ```lua
    function Registry:remove<T...>(entity: Entity, components: T...): ()
    ```

### view()

Creates a new registry view.

- **Type**

    ```lua
    function Registry:view<T...>(components: T...): View<T...>
    ```

- **Details**

    Creates a new view with the specified components.

    Entities in the view are guaranteed to have *at least* all of the specified components.

    Views are relatively cheap to create so it is encouraged to construct and throw them away after iteration on the fly.

---

### track()

Creates a [`Observer`](Observer) which tracks any changes that happen to entities with the given component.

- **Type**

    ```lua
    function Registry:track<T, U...>(trackingComponent: T, U...) -> Observer<(T?, U...)>
    ```

- **Details**

    Trackers are used to track changes that happen to a given component inside systems and grants control over when to track, stop tracking and start tracking again.

    Trackers should be created outside the system so they can track changes while the system isn't running.

    Only changes made to the first argument specified are tracked, subsequent arguments are only included when iterating just like a `View`.
    
    The observer will return entities that:

    1. Are assigned the component when they previously did not own it.
    2. Have the tracked component's value changed.
    3. Have the tracked component removed (value will be returned as `nil` during iterations).

    An entity must have **all** components specified to be included in the observer.

    A history of changes is not kept, the observer will only return entities whose tracked components have been changed with their latest values.

    When an observer is first created, it treats all current entities with the given component in the registry as newly changed.

    > ⚠️ After iterating over an observer and processing the changes, call [`Observer:clear()`](Observer#clear) to clear all changes so you do not reprocess the same changes again.

    > ⚠️ When tracking components for an entity that must have other components, e.g `Registry:track(A, B)`, if an entity contains `A` and then `B` is added, the entity will **not** be added to the tracker. The entity must have all components specified at the moment the *tracked* component `A` is changed.

- **Example**

    ```lua
    local Health = ecr.component() :: number
    
    local tracker = registry:track(Health)
    local entity = registry:create()
    
    -- When the entity's health component is set to 100
    -- The tracker will record that.
    registry:set(entity, Health, 100) 
    for id, health in tracker:each() do
        print(health) -- will print 100
    end
    
    -- We clear the currently recorded changes as we have no use
    -- For them anymore.
    tracker:clear()
    
    -- We remove the component from the entity which will also
    -- Be tracked
    registry:set(entity, Health) 
    for id, health in tracker:each() do
        print(health) -- Will print nil
    end
    
    ```

---

### entities()

Returns a list containing every single entity id that is used by the Registry.

- **Type**

    ```lua
    function Registry:entities() -> {Entity}
    ```

---

### storage()

Returns a [Pool](Pool) containing every entity that has the given component

- **Type**

    ```lua
    function Registry:storage<T>(component: T) -> Pool<T>
    ```

- **Details**
  
    > ⚠️ This function is not yet stable and it's return value will be changed to return something that is not a [Pool](Pool).

---

### added()

Returns a [Signal](Signal) which will be fired whenever the given component is added to a entity.

- **Type**

    ```lua
    function Registry:added<T>(component: T) -> Signal<Entity, T>
    ```

---

### changed()

Returns a [Signal](Signal) which will be fired whenever the given component is changed of a entity inside the Registry

- **Type**

    ```lua
    function Registry:changed<T>(component: T) -> Signal<Entity, T>
    ```

---

### removing()

Returns a [Signal](Signal) which will be fired whenever the given component is removed of a entity inside the Registry

- **Type**

    ```lua
    function Registry:removing<T>(component: T) -> Signal<Entity, T>
    ```

---
