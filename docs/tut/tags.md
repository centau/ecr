# Tags

Tags are a special component type that store no value.

A tag can be created with:

```lua
local Tag = ecr.tag()
```

Tags are still components, and can be used in the same way as other components,
with the exception that tag components will always have a `nil` value.

Tags can be used like so:

```lua
local Poisoned = ecr.tag()

registry:add(id, Poisoned)
registry:has(id, Poisoned) -- true

registry:remove(id, Poisoned)
registry:has(id, Poisoned) -- false
```

```lua
local Health = ecr.component() :: number

for id, health in world:view(Health, Poisoned) do
    world:set(id, health - 1)
end
```

To check if an entity has a tag, favor `Registry:has()` over `Registry:get()`,
since tags have no value and will return `nil`.

You can check if a component type is a tag type or not with `ecr.is_tag(ctype)`.
