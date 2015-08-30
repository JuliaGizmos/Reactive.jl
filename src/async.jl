
export remote_map,
       async_map

function async_map(f, inputs...;
                       init=f(map(value, inputs)...), typ=Any)

    node = Node(typ, init) 
    map(inputs...; init=init, typ=typ) do args...
        outer_task = current_task()
        task = @async begin
            try
                args = map(value, inputs)
                push!(node, f(args...))
            catch err
                bt = catch_backtrace()
                throwto(outer_task, ReactiveException(err, bt))
            end
        end
    end
    node
end

function remote_map(f, inputs...;
                        procid=myid(), init=f(map(value, inputs)...), typ=Any)

    node = Node(typ, init) 
    map(inputs...; init=init, typ=typ) do args...
        outer_task = current_task()
        @async begin
            try
                args = map(value, inputs)
                push!(node, remotecall_fetch(procid, () -> f(args...)))
            catch err
                bt = catch_backtrace()
                throwto(outer_task, ReactiveException(err, bt))
            end
        end
    end
    node
end

