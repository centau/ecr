# Tags

Tags are special component types that store no value.

A tag can be created with:

```lua
local Tag = ecr.tag()
```

Tags types are used in the same way as any other component type. They are useful
for marking entities in some state, and are more efficient than something like
`ecr.component() :: true`.

Example usage:

```lua
local Selected = ecr.tag()

registry:add(id, Selected)
registry:has(id, Selected) -- true

registry:remove(id, Selected)
registry:has(id, Selected) -- false
```

To check if an entity has a tag, favor `Registry:has()` over `Registry:get()`,
since tags have no value and will return `nil`.

You can check if a component type is a tag type or not with `ecr.is_tag(ctype)`.
