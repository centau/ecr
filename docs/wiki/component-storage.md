# Component Storage

The choice of how components are stored in memory is what defines the
performance of an ECS. There are many different ways to do this, with two
popular approaches being:

- Archetype based storage
- Sparse set based storage

Archetype based storages are generally known to have fast iteration in
combinations of components while Sparse set based ECSs are known for fast adding
and removing of components.

ECR uses a sparse set approach which will now be covered in detail.

## The Sparse set

Firstly, ignore the ECS side of things and just try to understand the sparse set
on its own.

The sparse set is a datastructure used to store a set of integers.

The time complexities of a sparse set are as such:

- Insertion `O(1)`
- Removal `O(1)`
- Lookup `O(1)`
- Iteration `O(n)` where `n` is the amount of elements in the set.

A sparse set is composed of 2 arrays:

- Sparse arrray.

  Maps an integer to a dense array index.

- Dense array (contrary to the name).

  Stores all integers in the set without any spaces.

An implementation in Luau looks like so:

```lua
type Set = {
    size: number
    sparse: Array<number?>
    dense: Array<number>
}

local function has(self: Set, k: number): boolean
    return self.sparse[k] ~= nil
end

local function insert(self: Set, k: number)
    if not self.sparse[k] then -- do nothing if k is already in set
        local n = self.size + 1; self.size = n
        self.sparse[k] = n
        self.dense[n] = k
    end
end

local function remove(self: Set, k: number)
    local i = self.sparse[k]
    if i then -- do nothing if k is not in set
        local n = self.size; self.size = n - 1

        -- to remove from a sparse set,
        -- we move the last element in the dense array
        -- to the position of k in the dense array
        -- and update the sparse array to show the new
        -- position of the moved element and remove k 

        local last = self.dense[n]

        self.dense[i] = last
        self.dense[n] = nil

        self.sparse[last] = i
        self.sparse[k] = nil
    end
end
```

The main drawback of a sparse set is that the sparse array must grow to
accomodate the largest key in the set. This can cause wasted memory usage
when the set contains a small amount of integers with a large value.

This can be mitigated using techniques such as paging, but Luau automatically
handles sparse arrays for us by converting them into a hashmap when it is
sufficiently sparse to save memory. While a hashmap normally isn't the best
solution for this, it is better than any custom Luau solution since this is
built into Luau and is executed natively.

## Pools

Now, back to the ECS. The pool datastructure in ECR is a modified sparse set.

```lua
type Pool<T> = {
    size: number,
    map: Array<number?>, -- sparse array
    entities: Array<Entity>, -- dense array
    values: Array<T> -- second dense array
}
```

This structure uses a second dense array that is kept sorted the same as
the first. The `map` array maps an id to an internal index used to access
a dense array of ids and a dense array of corresponding component values.

When adding and removing ids, whatever operation done to the `entities` array is
also done to the `values` array so that `entities[i]` corresponds to `values[i]`.

The way in which `map` maps an id to an internal index is by extracting a key
from the id and using that key as an index for the `map` array.
Refer to [here](entity-identifier.md) for specifics on keys and ids.

In an ECS, each component type has its own pool. Given the properties of a
sparse set, this makes adding, removing, changing and checking for components
very fast operations. We have the best possible random-access and
sequential-access speeds because of the sparse and dense arrays. However,
because component pools are independent from each other, this approach suffers
when querying for multiple component types.

### Single component query

A query for a single component type is the best case scenario. To do so, you
simply iterate over the `entities` and `values` array of a pool as a straight
array with no cache misses.

### Multiple component query

Multiple component queries, while still fast, become slower the more components
that are involved in the query. To do so, you pick the smallest pool to iterate
along its entities (as an entity must contain every component in the query, we
know that every entity we need still exists in this pool so we iterate that to
reduce the amount of random checking we must do), while doing lookups in all
other pools to check if the entity has all other components, skipping that
entity if it does not. While this does introduce cache misses, it isn't as bad
as it sounds because of the very fast random-access property of sparse sets.

This drawback can also be mitigated using a technique called *grouping* which I
won't get into now.

Another thing to note is that while iteration of multiple components is
a large argument against the sparse-set ECS, more complex queries naturally
run more complex code in the loop body, making the overhead of iterating
multiple components less significant in many cases. In the less likely cases
where the iteration itself is the bottleneck, grouping can be used to eliminate
this entirely.

## Stale references

This section assumes familiarity with [entity ids](entity-identifier.md).

Consider the case where we have ids `ID(k=1, v=1)` and `ID(k=1, v=2)`. Both
of these ids would refer to the same internal index in the pool because the
pool only uses the key part and completely disregards the version. This leads to
issues such as destroyed ids being able to access data for new ids.

This can be prevented by checking the `entities` array to get the version when
performing a lookup. This however turns a lookup operation from a single array
index to two array indexes, which increases the chance of cache miss and harms
performance.

ECR instead stores the id version inside the `map` array as well.
Since the `map` array just stores the internal index for the dense arrays,
it is known that this internal index will never exceed the largest id key. This
is taken advantage of by also using the upper bits to store the id version.
This way we can get the internal index *and* the version using a single array
index. Then it is just a matter of checking if the version is equal to the
version of the id we are performing a lookup for.
