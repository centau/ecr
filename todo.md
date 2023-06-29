# To do

List of things I would like to do with the library:

- Look into providing a flexible system scheduler
  - Splits frame into phases where certain components are added in one phase so
    that systems ran in the next phase know that entities operated on will have
    the needed components.
  - Allows scheduling of systems every frame or every x frames.
  - Automatic profiling.
  - Automatic error handling and better reporting.
  - Is this something ecr should provide?
- Look into component relationships
  - `ecr.pair(A, B)` to create new combinational component.
- More flexible observer API
  - Specify way to listen to only certain events (e.g. added or/and removed)
  - Is this even needed given that you can create custom observers already?
- Make `Registry:patch()` invoke constructor if no component is found.
  - Is there a case where this behavior is not wanted?
- Methods for bulk operations with entities and components
- Make `Registry:release()` safe
  - This is very hard to do performantly.
- Improve docs
- Optimize entity destruction
  - The O(n) check for all registered components is perturbing when in large
  amount.
  - Potential for parallelized checks?
  - Defer destruction to end of frame and perform bulk removal?
  - Track the components an entity has using a bitset?
  - Archetypal tracking?
- Allow `nil` component values?
  - Could improve memory usage for valueless components.
  - But could add ambiguity between `nil` components and not having the component at all.
  - Could then remove `ecr.tag()`.
- Make methods like `Registry:has()` and `Registry:try_get()` error when invalid entities are passed
  - Should they?
- Address behavior regarding adding to observers/queues during iteration
  - Currently newly added values are not returned during iteration, additionally
    clearing the observer/queue when iteration is completed means that any value
    that was added during iteration will not be returned the next time it is
    iterated. Is this the desired behavior?
- Also address behavior regarding clearing during iteration.
  - Currently should cause an error when it attempts to get the next element.
- Refactor and cleanup the codebase.
- Remove `Registry:size()` and `Registry:entities()` and replace with `__len` and `__iter` metamethods.
  - Define behavior when creating/destroying entities during iteration.
- Investigate if it is possible to free a bit in key and version parts of an id
  - Since we never use 0 and know that first bit is always 1 does this allow us to implicitly gain an extra bit?
  - This would double the total amount of keys we can have and double the total amount of versions.
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
