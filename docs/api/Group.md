---
permalink: /api/Group
title: Group
---

Groups are used to efficiently iterate over a set of components.

---

## Iteration

Groups support generalized iteration.

```lua
for id: Entity, ...: T... in Group<T...> do
```

The entity id followed by the group components are returned.

Components can be added, changed and removed during iteration. Newly added components and their entities will not be returned until the next iteration.

> ⚠️ During iteration, adding or removing components from entities not currently being iterated can invalidate the iterator.

---
