---
permalink: /tut/groups
title: Groups
---

Groups are a technique used to optimize iteration over a set of components. Groups in fact achieve perfect [SoA](https://en.wikipedia.org/wiki/AoS_and_SoA) for the best iteration performance at the cost of more expensive addition and removal of group-owned components.

## Creation

Groups can be created as followed:

```lua
registry:group(A, B, C)
```

This creates a new group with components `A`, `B` and `C`.
These 3 components are now said to be *owned* by the group.

Each component type can only be owned by a single group. The following code would result in an error:

```lua
registry:group(A, B)
registry:group(B, D)
```

This errors because 2 different groups cannot claim ownership of `B`.

Groups do not have to be stored aside when they are created, the first time a group is created it is stored permanently inside the registry, future `registry:group()` calls will just return the same group for the same set of components.

Groups are initialized on the first call and will automatically add and remove entities from itself when you change components.

## Usage

The main use for groups is the ability to iterate over all entities with the given set of components *very quickly*.

```lua
for entity, position, velocity in registry:group(Position, Velocity) do
    registry:set(entity, Position, position + velocity*dt)
end
```

Components can be added, changed and removed during iteration.

The exact size of a group can also be read:

```lua
local size = #registry:group(A, B)
```

## Limitations

Groups, while powerful, do impose some limitations on the registry.

- As mentioned before, each component type can only be owned by one group, groups cannot share components. Because of this, you should only attempt to group components after you have identified identified iteration bottlenecks.

- Due to how groups organise their components in memory, creating a group means you can no longer freely add group-owned components during a view iteration where the view includes a component owned by the same group. Specifics can be read [here](../api/restrictions#groups-and-views).
