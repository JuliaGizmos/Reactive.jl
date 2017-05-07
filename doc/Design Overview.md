### Node Creation Order Design

When a node is `push!`ed to in user code, this library must process it and ensure signal values stay consistent with the operations users used to define the chain of signals (e.g. map, foldp, etc.).

(N.b. "node" and "Signal" are used interchangeably in this doc and the code)

The design assumes:

1. The order which nodes are created is a correct [topological ordering](https://en.wikipedia.org/wiki/Topological_ordering) (with the edges of the signal graph  regarded as directed from parents to children)
2. Signals will end up in a correct state if the order in which each node is processed and their update actions (e.g. the mapped function in the case of a map) run, is the same as the order in which nodes were created.
3. Signal actions should be run for a given `push!` only if the node itself was pushed to or if one of their parents had their actions run.

This should ensure that parents of nodes update before their children, and signal values will be in a correct state after each `push!` has been processed.

#### Basics

Each node (`Signal`) is added to the end of a Vector called `nodes` on creation, so that `nodes` holds Signals in the order they were created.

Each Signal holds a field `actions` which are just 0-argument functions that update the value of the node or perform some helper function to that end. In some cases the action will update, push to, or set a Timer to update a different node.

Each Signal also has a field `active` which flags whether or not the node was `push!`ed to, or had/should have its actions run, in processing the current push. In essence it flags whether or not the node's value has been updated, or should be updated.

Nodes that are pushed to will always be set to active, other (downstream) nodes will be set to active, and their actions run if any of their parent `Signal`s were active in processing the current `push!`.

On processing each `push!`, we run through `nodes` and execute the actions of each node if it has been set to active, i.e. if it was pushed to, or if any of its parents were active.

#### Pushing to Non Input Nodes

Sometimes it is desirable to push! a value to a non-input node, e.g. a `map` on an input `Signal(...)`, rather than it attaining that value by running its action. In order for this pushed value to "stick", it's important that the map's action does not run after pushing to the node - since the map's action would update the map node to the return value of the function used to create the map, which in general would not be equal to the pushed value.

This is achieved simply by the check in `run_node` requiring an active parent in order to run the node's actions.

A consequence of this is any actions attached to a node with no parents, e.g. an input `Signal(...)` node, will not run. Accordingly, all actions that rely on an update to a node, are attached to a child of the node, and not the node itself. See [dev notes](dev%20notes.md) for more details.

#### Filter

Filter works by setting the filter node's active field to false when the filter condition is false. Downstream/descendent nodes check if at least one of their parents has been active, if none of them have been active then the node will not run its action, thus propagating the filter correctly.

#### More info

There is some info on each operator in the [dev notes](dev%20notes.md). Please feel free to open issues if things are not clear.
