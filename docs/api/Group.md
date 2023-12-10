# Group

Fast iterator for viewing entities and components in a registry.

```lua
type ecr.Group<T...>
```

## Iteration

Iterates over all entities in the group.

- **Type**

    ```lua
    for id: Entity, ...: T... in Group<T...> do
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

Returns the amount of entities in the group.

- **Type**

    ```lua
    #Group<T...>: number
    ```
