# View

Iterator for viewing entities and components in a registry.

```lua
type ecr.View<T...>
```

## Methods

### exclude()

Excludes entities with the given components from the view.

- **Type**

    ```lua
    function View:exclude<T...>(components: ...unknown): View<T...>
    ```

- **Details**

    Entities with *any* of the excluded components, will not be returned during
    iteration.

--------------------------------------------------------------------------------

### patch()

Updates all entity components in the view using a given function.

- **Type**

    ```lua
    function View:patch<T...>(fn: (T...) -> T...)
    ```

- **Details**

    ::: warning
    Returning `nil` will result in undefined behavior.
    :::

## Iteration

Iterates all entities in the view.

- **Type**

    ```lua
    for id: Entity, ...: T... in View<T...> do
    ```

- **Details**

    The entity followed by the component values are returned.

    Components can be added, changed and removed during iteration.
    Components added during iteration are not returned for that iteration.

    ::: warning
    During iteration, adding or removing components from entities not currently
    being iterated can invalidate the iterator.
    :::

## Length

Returns the amount of entities in the view.

- **Type**

    ```lua
    #View<T...>: number
    ```

- **Details**

    For single component views, this returns the exact amount of entities in the
    view.

    For multiple component views, this returns an estimated amount of entities.
    This estimate will not be less than the actual amount of entities.
