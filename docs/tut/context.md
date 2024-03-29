# Context

All registries have a special entity, that uses a reserved id `ecr.context`,
called the *context entity*.

Often you will need to store data about the world that isn't specific to an
entity, data such as a round counter, in-game timer, etc.

The context entity can be used to store data like this; the world's context.

This entity does not exist by default, it is automatically created the first
time [`Registry:context()`](../api/Registry#context) is called, subsequent calls
return the same entity.

```lua
local Round = ecr.component() :: number

registry:context():set(Round, 1)

-- or, if you prefer

registry:set(ecr.context, Round, 1)
```

This entity can still be destroyed (and later recreated), and is affected by
[`Registry:clear()`](../api/Registry#clear).
