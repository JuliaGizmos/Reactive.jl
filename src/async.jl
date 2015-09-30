
export remote_map,
       async_map

function async_map(f, init, inputs...; typ=typeof(init))

    node = Node(typ, init, inputs)
    map(inputs...; init=init, typ=typ) do args...
        outer_task = current_task()
        @async begin
            try
                push!(node, f(args...))
            catch err
                bt = catch_backtrace()
                # send exceptions back up to the runner task
                throwto(outer_task, CapturedException(err, bt))
            end
        end
    end
    node
end

function remote_map(f, init, inputs...; typ=typeof(init))

    node = Node(typ, init, inputs)
    map(inputs...; init=init, typ=typ) do args...
        outer_task = current_task()
        @async begin
            try
                push!(node, remotecall_fetch(procid, () -> f(args...)))
            catch err
                bt = catch_backtrace()
                throwto(outer_task, CapturedException(err, bt))
            end
        end
    end
    node
end

