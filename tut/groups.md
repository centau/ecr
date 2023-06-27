---
permalink: /tut/groups
title: Groups
---

Groups are a technique used to optimize iteration over a set of components.
Groups achieve perfect [SoA](https://en.wikipedia.org/wiki/AoS_and_SoA) for the
best iteration performance at the cost of more expensive addition and removal of
group-owned components.

## Creation

Groups can be created as followed:

```lua
registry:group(A, B, C)
```

This creates a new group with components `A`, `B` and `C`.
These 3 components are now said to be *owned* by the group.

Each component type can only be owned by a single group. The following code
would result in an error:

```lua
registry:group(A, B)
registry:group(B, D)
```

This errors because 2 different groups cannot claim ownership of `B`.

Groups do not have to be stored aside when they are created, the first time a
group is created it is stored permanently inside the registry, future
`registry:group()` calls will just return the same group for the same set of
components.

Groups are initialized on the first call and will automatically re-arrange
entities in itself as you change components.

## Usage

The main use for groups is the ability to iterate over all entities with the
given set of components much faster than if you did so with a view.

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

- As mentioned before, each component type can only be owned by one group,
  groups cannot share components so you are required to plan ahead for what
  components you would like to group.

- Due to how groups organise their components in memory, when iterating a view
  that includes group-owned components, you cannot add any component owned by
  any of those groups unless you:
    1. specify a component to lead that is not owned by the same group as the components you intend to add.
    2. know that adding those group-owned components will not cause the entity to enter the group.

The library can detect and will error if the above rules are broken.

## Why use groups?

While views are fast, in certain situations like where a view contains many
components, iteration of a view may be the bottleneck of a system.
In such cases, by grouping components together, iteration becomes as fast as
possible at the cost of the above limitations.

You should only use grouping when you have benchmarked and identified that the
iteration of a view is the bottleneck of a system.
