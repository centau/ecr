---
permalink: /tut/replication
title: Replication
---

Games often need to replicate data in the world from the server to clients.

A general method of how to do so is demonstrated below.

```lua
-- components.luau

local ecr = require(ecr)

-- table of all components to be replicated
return table.freeze {
    Health = ecr.component() :: number,
    Name = ecr.component() :: string,
    ...
}
```

## Server

```lua
-- replicate.server.luau

type CType = unknown

-- shape of serialized data
type Diff = {
    changes: Map<string, { -- map component name to data
        added_or_changed: { -- entities with added or changed component values
            entities: Array<ecr.Entity>,
            values: Array<unknown>
        },
        removed: Array<ecr.Entity> -- entities with removed components
    }>,
    destroyed: Array<ecr.Entity>, -- destroyed entities
}

-- components to replicate
local cts = require(shared.components)

-- unique value to mark a component that was removed
local REMOVED = {} 

-- structure used to serialize changes
local diff = {} :: Diff

do -- initialize diff
    diff.changes = {}
    for cname in cts do
        diff.changes[cname] = {
            added_or_changed = {
                entities = {},
                values = {}
            },
            removed = {}
        }
    end
    diff.destroyed = {}
end

-- keeps track of each component added, changed or removed for every entity
local updated_components = {} :: Map<string, Map<ecr.Entity, unknown>>

-- track any component updates for all replicated components
for cname, ctype in cts do
    local updated = {}
    updated_components[cname] = updated

    world:added(ctype):connect(function(id, value)
        updated[id] = value
    end)

    world:changed(ctype):connect(function(id, value)
        updated[id] = value
    end)

    world:removing(ctype):connect(function(id)
        updated[id] = REMOVED
    end)
end

return function()
    local destroyed = diff.destroyed

    -- serialize updated components for replication
    for cname, updated in updated_components do
        local changes = diff.changes[cname]

        for id, value in updated do
            if value == REMOVED then
                -- if removed then the entity may also be destroyed
                if world:contains(id) then 
                    table.insert(changes.removed, id)
                else
                    -- no need to also replicate the component removed here
                    -- since all of this entity's components are checked
                    -- on the client via destroy
                    table.insert(destroyed, id)
                end
            else
                table.insert(changes.added_or_changed.entities, id)
                table.insert(changes.added_or_changed.values, value)   
            end
        end
    end

    -- function defined by you to send the diff data over the network
    send_diff_to_clients(diff)

    -- we clear diff instead of creating a new diff to avoid having to
    -- reallocate memory every frame
    for _, changes in diff.changes do
        table.clear(changes.added_or_changed.entities)
        table.clear(changes.added_or_changed.values)
        table.clear(changes.removed)
    end
    table.clear(diff.destroyed)

    -- clear updated components so we do not re-replicate the same components
    -- on the next frame
    for _, updated in updated_components do
        table.clear(updated)
    end
end
```

## Client

```lua
-- replicate.client.luau

local cts = require(components)

-- array to cache all incoming diffs for processing in one go later
local diffs = {} :: Array<Diff>

local function on_receive(diff: Diff)
    -- add diff to buffer so all incoming replication data is processed in one
    -- go when the system runs
    table.insert(diffs, diff)
end

return function()
    for _, diff in diffs do
        -- process destroyed entities first as we will be creating ids after
        for _, id in diff.destroyed do
                -- entity may have been created then destroyed on server before it could replicate
                -- meaning the entity may not exist on the client
                if not world:contains(id) then continue end
                world:destroy(id)
            end

        for cname, changes in diff.changes do
            local ctype = cts[cname]
            local values = changes.added_or_changed.values

            for i, id in changes.added_or_changed.entities do
                -- entity may not exist for newly added components
                if not world:contains(id) then
                    world:create(id)
                end
                world:set(id, ctype, values[i])
            end

            for _, id in changes.removed do
                world:remove(id, ctype)
            end
        end
    end

    table.clear(diffs)
end
```

The case where a new client joins the server late is not covered. In such a case you would just serialize all of the replicated components currently in the world in the same shape as the `Diff` type instead of just the difference to send to that client.
