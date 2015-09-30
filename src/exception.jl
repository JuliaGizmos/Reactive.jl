 
if VERSION < v"0.4.0-dev"
    # Note: The one in 0.4 is slightly better
    type CapturedException
        ex
        bt
    end

    Base.show(io::IO, exp::CapturedException) = begin
        showerror(io, exp.ex)
        Base.show_backtrace(io, exp.bt)
    end
end

type ReactiveException <: Exception
    waiting::Bool
    node::Node
    value::Any
    timestep::Int
    meta::Any
    exception::CapturedException
end

Base.show(io::IO, rex::ReactiveException) = begin
    if rex.waiting
        println(io, "Task ended in error while waiting for updates (timestep $(rex.timestep))")
    else
        println(io, "Failed to push!")
        print(io, "    ")
        show(io, rex.value)
        println(io)
        println(io, "to node")
        print(io, "    ")
        show(io, rex.node)
        println(io, "at timestep $(rex.timestep)")
    end
    if rex.meta !== nothing
        println(io, "Debug info:")
        print(io, "    ")
        show(io, rex.meta)
        println(io)
    end

    println(io)
    showerror(io, rex.exception)
end
