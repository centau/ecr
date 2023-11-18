# To do

## High Priority

- Either an example or built-in class for serialization/continuous loading of one registry to another.
  - Support for id mapping layer.
- Optimize entity destruction.

## Low Priority

- Non-owning groups.
- Custom pools and storage based views.
- Disallow creation of handles for invalid entities?
- Look into component relationships
  - `ecr.pair(A, B)` to create new combinational component.
  - Why is this useful?
- More flexible observer API
  - Specify way to listen to only certain events (e.g. added or/and removed)
  - Is this even needed given that you can create custom observers already?
- Make `Registry:release()` safe
  - This is very hard to do performantly.
  - Or deprecate and remove it? We want a (nearly) completely safe API.
- Lower level access to underlying datastructures.
  - An API for pools returned by `Registry:storage()` like adding and removing.
  - Bypass pool lookups and safety check.
  - Bulk operations
    h an alternative API to work with ids
- Investigate if using Vector3s for internal storage can improve perf
  - Can reduce 16 B per component (map and entities arrays combined into 1)
    - A component would only take 32 B and a tag only 16 B!!
  - Using Vector3s for ids also makes extracting key and version faster
  - 33-50% reduced memory usage.
  - Significantly improve cpu cache perf (by 2x in some cases)
- Address how some registry private members are captured as upvalues
  - This means that doing `registryA.create(registryB)` can cause undefined behavior.
  - No one should be doing the above anyways so is it ok to leave it?
  - Switch from `:` to `.` to call methods? Not standard.
