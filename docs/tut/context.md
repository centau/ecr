# Context

All registries have a special entity, using a special id `ecr.context`, called
the *context entity*.

If you ever need to store general data about the world (like a round timer,
chosen map, etc) the context entity is a place to do this. Being an entity,
systems can still act on it saving you from having separate logic for normal
entity data and context data (like automatic replication).

This entity does not exist by default, it is automatically created the first
time [`Registry:context()`](../api/Registry#context) is called, subsequent calls
return the same entity.

```lua
local Round = ecr.component() :: number

registry:context():set(Round, 1)

-- or, if you prefer

registry:create(ecr.context)
registry:set(ecr.context, Round, 1)
```

This entity is still like any other, can show up in views, can still be
destroyed (and later recreated), and is affected by
[`Registry:clear()`](../api/Registry#clear).
