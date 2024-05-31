# Entity Type

Entities are represented by a special component type, `ecr.entity`.

This can be used in the same way as other components types, except instead of
representing components, represents entities.

This type cannot be used to modify the registry, methods like `add()`, `set()`,
`remove()` do not work with this type.

## Get all entities

You can get all entities that currently exist in the registry with:

```lua
for id in registry:view(ecr.entity) do
    print(id)
end

-- or

local entities = registry:storage(ecr.entity).entities
```

## Exclude-only views

You can get all entities without specific components with:

```lua
for entity in registry:view(ecr.entity):exclude(...) do end
```

## Listeners

You can listen to when an entity is created with:

```lua
registry:on_add(ecr.entity):connect(function)
```

And when an entity is destroyed with:

```lua
registry:on_remove(ecr.entity):connect(function)
```
