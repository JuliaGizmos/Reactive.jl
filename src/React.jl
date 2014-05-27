module React

export Signal, Input, lift, dropif, droprepeats,
       sampleon, mimewritable, show, display, stringmime

import Base: push!, reduce, merge, Display,
       show, display, mimewritable, stringmime

if isdefined(Main, :IPythonDisplay)
    import Main.IPythonDisplay.InlineDisplay
end

# A signal is a value that can change over time.
abstract Signal{T}

typealias Time Float64

# Unique ID
typealias UID Int

begin
    local last_id = 0
    guid() = last_id += 1
end

# Root nodes of the graph
roots = Signal[]

# An input is a root node in the signal graph.
# It must be created with a default value, and can be
# updated with a call to `update`.
type Input{T} <: Signal{T}
    id :: UID
    children :: Set{Signal}
    value :: T

    function Input(v :: T)
        self = new(guid(), Set{Signal}(), v)
        push!(roots, self)
        return self
    end
end
Input{T}(val :: T) = Input{T}(val)

type Node{T} <: Signal{T}
    id :: UID
    children :: Set{Signal}
    node_type :: Symbol
    value :: T

    recv :: Function

    function Node(val :: T, node_type=:Node)
        new(guid(), Set{Signal}(), node_type, val)
    end
end

function send{T}(node :: Signal{T}, timestep :: Time, changed :: Bool)
    for child in node.children
        child.recv(timestep, changed, node)
    end
end

# recv is called by update
function recv{T, U}(inp :: Input{T}, timestep :: Time,
                 originator :: Signal{U}, val :: U)
    # Forward it to children
    changed = originator == inp
    if changed
        inp.value = val
    end
    send(inp, timestep, changed)
end

# update method on an Input updates its value
# and notifies all dependent signals.
begin
    local pushing = false
    function push!{T}(inp :: Input{T}, value :: T)
        if pushing
            error("Encountered a signal loop! Did you call push! inside a lift?")
        end
        pushing = true
        timestep = time()
        for node in roots
            recv(node, timestep, inp, value)
        end
        pushing = false
    end
end

function lift(output_type :: DataType, f :: Function,
              inputs :: Signal...)
    local count = 0,
          n = length(inputs),
          ischanged = false # accumulate change info
    apply_f() = apply(f, [i.value for i in inputs])
    node = Node{output_type}(apply_f(), :lift)

    function recv(timestep :: Time, changed :: Bool, parent :: Signal)
        count += 1
        if changed
            ischanged = true
        end

        if count == n
            if ischanged
                # counting makes sure apply_f is called
                # just once in a given timestep
                node.value = apply_f()
            end
            send(node, timestep, ischanged)
            ischanged = false
            count = 0
        end
    end
    node.recv = recv

    for i in inputs
        push!(i.children, node)
    end
    return node
end

lift(f :: Function, inputs :: Signal...) = lift(Any, f, inputs...)
map(T :: DataType, f :: Function, input :: Signal) = lift(T, f, input)
map(f :: Function, input :: Signal) = lift(f, input)

# reduce over a stream of updates
function reduce{T, U}(f :: Function, v0 :: T, signal :: Signal{U})
    local a = v0
    function foldp(b)
        a = f(a, b)
    end
    lift(T, foldp, signal)
end

# merge signals
function merge{T}(signals :: Signal{T}...)

    first, _ = signals
    node = Node{T}(first.value, :merge)
    rank = {n => i for (i, n) in enumerate(signals)}
    
    local n = length(signals), count = 0, ischanged = false,
          minrank = n+1, val = node.value

    function recv(timestep :: Time, changed :: Bool, parent :: Signal)
        count += 1
        if changed
            ischanged = true
            if haskey(rank, parent)
                if minrank > rank[parent]
                    val = parent.value
                    minrank = rank[parent]
                end
            end
        end
        if count == n
            if ischanged
                node.value = val
                minrank = n+1
            end
            send(node, timestep, ischanged)
            ischanged = false
            count = 0
        end
    end

    for sig in signals
        push!(sig.children, node)
    end
    node.recv = recv

    return node
end

function dropif{T}(pred :: Function, v0 :: T, signal :: Signal)
    node = Node{T}(pred(signal.value) ? v0 : signal.value, :dropif)
    function recv(timestep :: Time, changed :: Bool, parent :: Signal)
        change = changed && ~pred(signal.value)
        if change node.value = signal.value end
        send(node, timestep, change)
    end
    push!(signal.children, node)
    node.recv = recv
    return node
end

function droprepeats{T}(signal :: Signal{T})
    node = Node{T}(signal.value, :droprepeats)
    function recv(timestep :: Time, changed :: Bool, parent :: Signal)
        change = changed && node.value != signal.value
        if change
            node.value = signal.value
        end
        send(node, timestep, change)
    end
    push!(signal.children, node)
    node.recv = recv
    return node
end

function sampleon{T, U}(s1 :: Signal{T}, s2 :: Signal{U})
    node = Node{U}(s2.value, :sampleon)
    local count = 0
    function recv(timestep :: Time, changed :: Bool, parent :: Signal)
        ischanged = parent == s1 ? changed : false;
        count += 1
        if count == 2
            if ischanged node.value = s2.value end

            send(node, timestep, ischanged)
            count = 0
            ischanged = false
        end
    end
    push!(s1.children, node)
    push!(s2.children, node)
    node.recv = recv
    return node
end

############################################################
# display methods for Signal data. We try to do in-place
# updates when IJulia is available.

function show{T}(node :: Signal{T})
    show(node.value)
end

function display{T}(d :: TextDisplay, signal :: Signal{T})
    if isa(signal, Input)
        "<input{$(T)}@$(signal.id)> " * show(signal)
    else
        "[$(signal.node_type){$(T)}@$(signal.id)] " * show(signal)
    end
end

if isdefined(Main, :IJulia) && isdefined(Main, :IPythonDisplay)
    const ipy_mime = [ "text/html", "text/latex", "image/svg+xml", "image/png", "image/jpeg", "text/plain" ]
    for mime in ipy_mime
        @eval begin
            function display{T}(d::InlineDisplay, ::MIME{symbol($mime)}, x :: Signal{T})
                send_ipython(publish, 
                             msg_pub(execute_msg, "display_data",
                                     ["source" => "julia", # optional
                                      "metadata" => {reactive=>true, signal_id=>x.id},
                                      "data" => [$mime => stringmime(MIME($mime), x.value)] ]))
            end
        end
    end

    function display{T}(d::InlineDisplay, x :: Signal{T})
        undisplay(x) # dequeue previous redisplay(x)
        send_ipython(publish, 
                     msg_pub(execute_msg, "display_data",
                             ["source" => "julia", # optional
                              "metadata" => {reactive=>true, signal_id=>x.id},
                              "data" => display_dict(x.value) ]))
    end
end

end # module
