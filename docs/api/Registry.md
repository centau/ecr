# Registry

Container for entities and components.

```lua
type ecr.Registry
```

## Methods

::: warning
There are certain [restrictions](restrictions) with what you can do with the
registry that you should be aware of.
:::

### create()

Creates a new entity and returns the entity id.

- **Type**

    ```lua
    function Registry:create(): entity
    function Registry:create(id: entity): entity

    type entity = ecr.entity
    ```

- **Details**

    An entity can be created using a specific id that was created by another
    registry or previously by the same registry.

    A previously used but now unused id may be reused every `32,000` creations.

    ::: warning
    Be wary of storing ids of destroyed entities for long periods of time or
    they may eventually refer to a newly created entity.
    :::

    ::: warning
    The total amount of entities in a registry at any given time *cannot*
    exceed `65,535`. Attempting to exceed this limit will throw an error.
    :::

--------------------------------------------------------------------------------

### destroy()

Removes the entity from the registry and removes all of its components.

- **Type**

    ```lua
    function Registry:destroy(id: entity)
    ```

--------------------------------------------------------------------------------

### contains()

Checks if the given entity exists in the registry.

- **Type**

    ```lua
    function Registry:contains(id: entity): boolean
    ```

--------------------------------------------------------------------------------

### add()

Adds a component to an entity using its constructor.

- **Type**
  
    ```lua
    function Registry:add<T>(id: entity, component: read_component<T>): T
    ```

- **Details**

    Adds the component to the entity by using its constructor, or no value if it
    is a tag type. Returns the current value.

    Adding a component to an entity that already has the component will do
    nothing.

--------------------------------------------------------------------------------

### set()

Adds or changes an entity's component.

- **Type**

    ```lua
    function Registry:set<T>(id: entity, component: component<T>, value: T)
    ```

- **Details**

    Adds the component to the entity with the given value if the entity does not
    already have the component.

    Changes the component value for the given entity if the entity already has
    the component.

--------------------------------------------------------------------------------

### patch()

Updates an entity's component.

- **Type**

    ```lua
    function Registry:patch<T>(id: entity, component: component<T>, patcher: ((T) -> T)?): T
    ```

- **Details**

    Takes a callback which is given the current component value as the only
    argument. The value returned by the callback is then set as the new value.

    If there is a constructor defined for the given component and the entity
    does not have the component, the constructor will be called and the returned
    value passed into the callback.

- **Example**

    ```lua
    registry:patch(entity, Health, function(health)
        return health - 10
    end)
    ```

--------------------------------------------------------------------------------

### has()

Checks if an entity has all of the given components.

- **Type**

    ```lua
    function Registry:has(id: entity, components: ...read_component<unknown>): boolean
    ```

- **Details**

    Will return `true` only if the entity has *every* component given.

--------------------------------------------------------------------------------

### get()

Gets an entity's component values.

- **Type**

    ```lua
    function Registry:get<T>(id: entity, component: read_component<T>): T
    ```

- **Details**

    Will error if the entity does not have a component. There are overloads for
    two through four component types, each returning the matching value tuple.

--------------------------------------------------------------------------------

### try_get()

Gets an entity's component value.

- **Type**

    ```lua
    function Registry:try_get<T>(id: entity, component: read_component<T>): T?
    ```

- **Details**

    Will return `nil` if the entity does not have a component.

--------------------------------------------------------------------------------

### remove()

Removes the given components from an entity.

- **Type**

    ```lua
    function Registry:remove(id: entity, components: ...read_component<unknown>)
    ```

- **Details**

    Will do nothing if the entity does not have a component.

--------------------------------------------------------------------------------

### clear()

Removes all entities and components from the registry.

- **Type**

    ```lua
    function Registry:clear(components: ...read_component<unknown>)
    ```

- **Details**

    If components are given, removes all given components from all entities
    without destroying the entities.

    If no components are given, then all entities in the registry will be
    destroyed.

--------------------------------------------------------------------------------

### find()

Returns the first entity found that has a component matching the given value.

- **Type**

    ```lua
    function Registry:find<T>(component: component<T>, value: T): entity?
    ```

- **Details**

    This is a linear search.

--------------------------------------------------------------------------------

### copy()

Copies the values of a component and pastes it into another component

- **Type**

    ```lua
    function Registry:copy<T>(copy: component<T>, paste: component<T>)
    ```

- **Details**

    This removes any entities that don't have a value in the copied component
    from the pasted component. It does not fire signals when called.

--------------------------------------------------------------------------------

### view()

Creates a [`view`](View) with the given component types.

- **Type**

    ```lua
    function Registry:view<T>(component: component<T>): View<T>
    ```

--------------------------------------------------------------------------------

### track()

Creates an [`observer`](Observer) with the given component types.

- **Type**

    ```lua
    function Registry:track<T>(component: read_component<T>): Observer<T>
    ```

--------------------------------------------------------------------------------

### group()

Creates a [`group`](Group.md) with the given component types.

- **Type**

    ```lua
    function Registry:group<A, B>(a: read_component<A>, b: read_component<B>): Group<A, B>
    ```

- **Details**

    Rearranges the internal storage of components for better iteration
    performance when iterated together.

    Groups must be mutually exclusive, i.e. each component type can only belong
    to a single group.

    ::: warning
    This method introduces [restrictions](../tuts/groups.md#limitations) on
    adding components during views.
    :::

--------------------------------------------------------------------------------

### on_add()

Returns a [signal](Signal) which is fired whenever the given component type is
added to an entity.

- **Type**

    ```lua
    function Registry:on_add<T>(component: read_component<T>): Signal<entity, T>
    ```

    The signal is fired *after* the component is changed.

    The listener is called with the entity and new component value.

    ::: warning
    The registry cannot be modified within a listener.
    :::

--------------------------------------------------------------------------------

### on_change()

Returns a [signal](Signal) which is fired whenever the given component type is
changed for an entity.

- **Type**

    ```lua
    function Registry:on_change<T>(component: read_component<T>): Signal<entity, T>
    ```

    The signal is fired *before* the component is changed.

    The listener is called with the entity and new component value.

    ::: warning
    The registry cannot be modified within a listener.
    :::

--------------------------------------------------------------------------------

### on_remove()

Returns a [signal](Signal) which is fired whenever the given component is
removed from an entity.

- **Type**

    ```lua
    function Registry:on_remove(component: read_component<unknown>): Signal<entity, nil>
    ```

- **Details**

    The signal is fired *before* the component is removed.

    The listener is called with the entity.

    ::: warning
    The registry cannot be modified within a listener.
    :::

--------------------------------------------------------------------------------

### on_clear()

Returns a [signal](Signal) fired when the given component type is cleared.

- **Type**

    ```lua
    function Registry:on_clear(component: read_component<unknown>): Signal<>
    ```

--------------------------------------------------------------------------------

### after_clear()

Returns a [signal](Signal) fired after the given component type is cleared.

- **Type**

    ```lua
    function Registry:after_clear(component: read_component<unknown>): Signal<>
    ```

--------------------------------------------------------------------------------

### handle()

Returns a [handle](Handle) to an entity.

- **Type**

    ```lua
    function Registry:handle(id: entity?): Handle
    ```

- **Details**

    If no entity is given then a new one is created.

    Handles are cached so that `registry:handle(id) == registry:handle(id)` is
    always true.

--------------------------------------------------------------------------------

### context()

Returns a [handle](Handle) to the context entity.

- **Type**

    ```lua
    function Registry:context(): Handle
    ```

- **Details**

    Will automatically create the context entity if it does not already exist.

--------------------------------------------------------------------------------

### storage()

Returns the [pool](Pool) for a given component type.

- **Type**

    ```lua
    function Registry:storage<T>(component: component<T>): Pool<T>
    function Registry:storage(): () -> (read_component<unknown>, Pool<unknown>)
    ```

- **Details**

    If called with no arguments, returns an iterator to get all component types
    and their corresponding pool in the registry.

--------------------------------------------------------------------------------

### has_none()

Checks if the given entity has no components.

- **Type**

    ```lua
    function Registry:has_none(id: entity): boolean
    ```

--------------------------------------------------------------------------------

### release()

Removes the entity from the registry.

- **Type**

    ```lua
    function Registry:release(id: entity)
    ```

- **Details**

    ::: danger
    This method does not remove any of the entity's components. Using this
    method on an entity that still has components is *undefined behavior*.
    :::
