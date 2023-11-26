# To do

- Optimize entity destruction.
- Make view, observer and group modifiers not mutate.
- Non-owning groups.
- Custom pools and storage based views.
- Disallow creation of handles for invalid entities?
- Make `Registry:release()` safe
  - This is very hard to do performantly.
  - Or deprecate and remove it? We want a (nearly) completely safe API.
- Lower level access to underlying datastructures.
  - An API for pools returned by `Registry:storage()` like adding and removing.
  - Bypass pool lookups and safety check.
  - Bulk operations
- Address how some registry private members are captured as upvalues
  - This means that doing `registryA.create(registryB)` can cause undefined behavior.
  - No one should be doing the above anyways so is it ok to leave it?
  - Switch from `:` to `.` to call methods? Not standard.
