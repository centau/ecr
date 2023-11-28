# Entity Type

Entities are stored in a special kind of pool inside the registry. These
entities are represented by a special componen type, `ecr.entity`.

This can be used in the same way as custom components types, except instead of
dealing with components, deals with entities themselves.

This type cannot be used to modify the registry, methods like `add()`, `set()`,
`remove()` do not work with this component.

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

You can get all entities without certain components with:

```lua
for entity in registry:view(ecr.entity):exclude(...) do end
```

## Listeners

You can listen to when an entity is created with:

```lua
registry:added(ecr.entity):connect(function)
```

And when an entity is destroyed with:

```lua
registry:removed(ecr.entity):connect(function)
```
