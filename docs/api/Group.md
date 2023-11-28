# Group

Groups are used to efficiently iterate over a set of components.

## Iteration

Groups support generalized iteration.

```lua
for id: Entity, ...: T... in Group<T...> do
```

The entity followed by the component values are returned.

Components can be added, changed and removed during iteration.
Components added during iteration are not returned for that iteration.

::: warning
During iteration, adding or removing components from entities not currently
being iterated can invalidate the iterator.
:::

## Length

Returns the amount of entities in the group.

```lua
#Group<T...>: number
```
