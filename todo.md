# To do

## High Priority

- Support for singleton/context components
- Define behavior when creating/destroying entities during iteration of registry __len.
- Dedicated entity storage
  - Special component `ecr.entity` that can be used to retrieve entity storage.
  - Allows for:
    - Exclude-only views
    - Signals for creation and destruction of entities
    - Access to list of all living entities
- One of two:
  - Make `Registry:set()` error on `nil` set.
    - Avoids bug where user intends to set a value but value was `nil`.
    - Makes `Registry:remove()` less redundant.
    - Removes weird case where `entity:set(tag, entity:get(tag))` will remove
  - Allow `nil` component values?
    - Could add ambiguity between `nil` components and not having the component at all.
    - Could then remove `ecr.tag()`.
- Optimize entity destruction
  - The O(n) check for all registered components is perturbing when in large amount.
  - Potential for parallelized checks?
  - Defer destruction to end of frame and perform bulk removal?
  - Bitset tracking?
  - Archetypal tracking?

## Low Priority

- Add more docs
- Make codebase nicer.
- Optimize adding to group.
- Disallow creation of handles for invalid entities?
- Look into component relationships
  - `ecr.pair(A, B)` to create new combinational component.
  - Why is this useful?
- More flexible observer API
  - Specify way to listen to only certain events (e.g. added or/and removed)
  - Is this even needed given that you can create custom observers already?
- Make `Registry:release()` safe
  - This is very hard to do performantly.
  - Remove it altogether? We want a completely safe API.
- Lower level access to underlying datastructures.
  - An API for pools returned by `Registry:storage()` like adding and removing.
  - Bulk operations
- Make methods like `Registry:has()` and `Registry:try_get()` error when invalid entities are passed
  - Should they? (they currently just return `nil`)
  - Doing this will reduce performance.
- Create a class for snapshotting/serialization/loading of registries
- Consider revising `Handle` class to be a more natural part of the API.
  - What `Flecs`' C++ API does with `world.entity()` and being able to call
    methods on the entity directly is very appealing. Implementing the exact same
    in Luau however would have serious performance implications.
- Investigate if using Vector3s for internal storage can improve perf
  - Can reduce 16 B per component (map and entities arrays combined into 1)
    - A component would only take 32 B and a tag only 16 B!!
  - Using Vector3s for ids also makes extracting key and version faster
  - Should significantly improve cpu cache perf (by 2x in some cases?)
- Address how some registry private members are captured as constant upvalues
  - This means that doing `registryA.create(registryB)` can cause undefined behavior.
  - No one should be doing the above anyways so is it ok to leave it?
  - Switch from `:` to `.` to call methods? Not standard.
