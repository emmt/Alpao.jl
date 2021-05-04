# Alpao.jl -
#
# Julia interface to Alpao's library for managing their deformable mirrors.
#
#------------------------------------------------------------------------------
#
# This file is part of the `Alpao.jl` package which is licensed under the MIT
# "Expat" License.
#
# Copyright (C) 2016-2021, Éric Thiébaut & Jonathan Léger.
#

module Alpao

export
    send!,
    send,
    stop

import Base: reset
import Sockets: send

@static if isdefined(Base, :stop)
    import Base: stop
end

isfile(joinpath(@__DIR__,"..","deps","deps.jl")) ||
    error("Alpao not properly installed.  Please run Pkg.build(\"Alpao\")")
include("../deps/deps.jl")

# Notes:
#
# C-types are defined in "asdkType.h" and function prototypes in
# "asdkWrapper.h" of the Alpao SDK.
#
# All functions but 2 return status with type `COMPL_STAT` which is an
# enumeration (hence a `Cint`) with 2 possible values: 0 for success and -1
# for failure.  The other functions are `asdkInit` which returns a pointer
# to a structure (considered as anonymous, hence a `Ptr{Cvoid}` here) and
# `asdkPrintLastError` which returns nothing.
#
# The other C types used in the API are `Int` and `UInt` which are 32-bit
# integers, `CString` and `CStrConst` which are C-strings, `Scalar` which
# is C `double` and `Size_T` which is `size_t`.
#
# The following table summarizes the types:
#
# -------------------------------------------------
# Alpao API      C Type        Julia Type
# -------------------------------------------------
# Char           char          Cchar
# UChar          uint8_t       UInt8
# Short          int16_t       Int16
# UShort         uint16_t      UInt16
# Int            int32_t       Int32
# UInt           uint32_t      UInt32
# Long           int64_t       Int64
# ULong          uint64_t      UInt64
# Size_T         size_t        Csize_t
# Scalar         double        Cdouble
# asdkDM*        struct DM*    Ptr{Cvoid}
# CString        char*         Cstring / Ptr{UInt8}
# CStrConst      char const*   Cstring / Ptr{UInt8}
# -------------------------------------------------
#

const Keyword = AbstractString
const Scalar  = Cdouble
struct Status; val::Cint; end

const SUCCESS = Status(0)
const FAILURE = Status(-1)
const CMDMAX = Scalar(1.0)
const CMDMIN = -CMDMAX

"""
    dm = Alpao.DeformableMirror(name)

creates an instance `dm` to manage Alpao's deformable mirror identifed by the
`name` of its configuration file.

The deformable mirror instance `dm` can be used as follows:

```julia
length(dm)     # yields number of actuators
eltype(dm)     # yields bit type for an actuator command
dm[key]        # yields value of keyword `key`
dm[key] = val  # sets value of keyword `key`
dm[]           # yields the last commands sent to the mirror
dm[:]          # yields a copy of the last commands
dm[i]          # yields the value of i-th actuator in the last commands
send(dm, cmd)  # sets the shape of the deformable mirror
send!(dm, cmd) # idem but, on return, `cmd` contains actual commands
reset(dm)      # resets the deformable mirror values
stop(dm)       # stops asynchronous commands sent to the deformable mirror
close(dm)      # release the deformable mirror resources
minimum(dm)    # yields the minimum value of a command
maximum(dm)    # yields the maximum value of a command
extrema(dm)    # yields the minimum and maximum values of a command
```

List of parameter keywords

```
---------------------------------------------------------------------------
Keyword         Get  Set  Value  Description
---------------------------------------------------------------------------
"AckTimeout"     x    x    > 0   For Ethernet / USB interface only, set the
                                 time-out (ms); can be set in synchronous
                                 mode only (see SyncMode).
"DacReset"            x    1     Reset all digital to analog converters of
                                 drive electronics.
"ItfState"       x         0:1   Return 1 if PCI interface is busy or 0
                                 otherwise.
"LogDump"             x    1     Dump the log stack on the standard output.
"LogPrintLevel"  x    x    0:4   Changes the output level of the logger to
                                 the standard output.
"NbOfActuator"   x         ≥ 1   Get the numbers of actuator for that
                                 mirror.
"SyncMode"            x    0:1   0: Synchronous mode, will return when send
                                    is done.
                                 1: Asynchronous mode, return immediately
                                    after safety checks.
"TriggerMode"         x    0:1   Set mode of the (optional) electronics
                                 trigger output. 0: long pulse width or 1:
                                 short pulse width on each command.
"TriggerIn"           x    0:2   Set mode of the (optional) input trigger.
                                 0: disabled, 1: trig on rising edge or
                                 2: trig on falling edge.
"UseException"   x    x    0:1   Enables or disables the throwing of an
                                 exception on error.
"VersionInfo"    x         > 0   Alpao SDK core version, e.g. 3040500612 is
                                 SDK v3.04.05.0612 where 0612 is build
                                 number.
---------------------------------------------------------------------------
```

"""
mutable struct DeformableMirror
    ptr::Ptr{DeformableMirror} # handle to device
    num::Int                   # number of actuators
    cmd::Vector{Scalar}        # last command
    function DeformableMirror(ident::AbstractString)
        local ptr::Ptr{Cvoid}, num::Int
        if '/' in ident
            odir = pwd()
            try
                cd(dirname(ident))
                ptr = ccall((:asdkInit, libasdk), Ptr{Cvoid}, (Cstring,),
                            basename(ident))
            finally
                cd(odir)
            end
        else
            ptr = ccall((:asdkInit, libasdk), Ptr{Cvoid}, (Cstring,), ident)
        end
        if ptr == C_NULL
            code, mesg = lasterror()
            error("failed to open $ident ($mesg)")
        end
        # Create object first to be able to release resources in case of errors.
        dm = new(ptr, 0, Scalar[])
        try
            num = Int(dm["NbOfActuator"])
            dm.num = num
            fill!(resize!(dm.cmd, num), zero(Scalar))
        catch err
            close(dm)
            rethrow(err)
        end
        return finalizer(close, dm)
    end
end

function Base.close(dm::DeformableMirror)
    if dm.ptr != C_NULL
        status = ccall((:asdkRelease, libasdk), Status,
                       (Ptr{DeformableMirror},), dm.ptr)
        dm.ptr = C_NULL # to never release more than once
        _check(status)
    end
end

Base.length(dm::DeformableMirror) = dm.num
Base.eltype(::DeformableMirror) = Scalar
Base.unsafe_convert(::Type{Ptr{DeformableMirror}}, dm::DeformableMirror) =
    (dm.ptr != C_NULL ? dm.ptr : error("device has been closed"))
Base.extrema(dm::DeformableMirror) = (minimum(dm), maximum(dm))
Base.minimum(dm::DeformableMirror) = CMDMIN
Base.maximum(dm::DeformableMirror) = CMDMAX

"""
    send(dm, cmd) -> actcmd

sends actuator commands `cmd` to deformable mirror `dm` and returns a vector of
actual commands sent to the mirror.  The actual commands may be different from
`cmd` due to bound constraints.  Actual commands are stored in an internal
buffer specific to the deformable mirror instance and allocated at construction
time.

See also: [`send!`](@ref), [`Alpao.lastcommand`](@ref).

"""
function send(dm::DeformableMirror, cmd::AbstractVector{<:AbstractFloat})
    num = length(dm) # FIXME: there may be several mirrors
    axes(cmd,1) == Base.OneTo(num) ||
        throw(DimensionMismatch("invalid indices for commands"))
    length(dm.cmd) == num || resize!(dm.cmd, num)
    @inbounds for i in 1:num
        dm.cmd[i] = clamp(Scalar(cmd[i]), CMDMIN, CMDMAX)
    end
    _check(ccall((:asdkSend, libasdk), Status,
                 (Ptr{DeformableMirror}, Ptr{Scalar}),
                 dm, dm.cmd))
    return dm.cmd
end

"""
    send!(dm, cmd) -> cmd

sends actuator commands `cmd` to deformable mirror `dm` and return, possibly
modified, commands.  The command values in `cmd` may be modified due to bound
constraints.  Thus, on return, `cmd` contains the actual commands sent to the
mirror.

See also: [`send`](@ref), [`Alpao.lastcommand`](@ref).

"""
send!(dm::DeformableMirror, cmd::AbstractVector{<:AbstractFloat}) =
    copy!(cmd, send(dm, cmd))

"""
    Alpao.lastcommand(dm) -> cmd

yields the last commands actually sent to the deformable mirror `dm`.

See also: [`send(::DeformableMirror)`](@ref).

"""
lastcommand(dm::DeformableMirror) = dm.cmd

"""
    Alpao.lasterror() -> (code, mesg)

pops the last error from the stack and returns error code and corresponding
message.

"""
function lasterror()
    code = Ref{UInt32}(0)
    mesg = zeros(UInt8, 512) # message buffer filled with zeroes
    if ccall((:asdkGetLastError, libasdk), Status,
             (Ptr{UInt32}, Ptr{UInt8}, Csize_t),
             code, mesg, sizeof(mesg)) != SUCCESS
        error("failed to retrieve last error message")
    end
    mesg[end] = 0
    (code[], String(mesg))
end

printlasterror() = ccall((:asdkPrintLastError, libasdk), Cvoid, ())

function _check(status::Status)
    if status != SUCCESS
        code, mesg = lasterror()
        error(mesg)
    end
end

stop(dm::DeformableMirror) =
    _check(ccall((:asdkStop, libasdk), Status, (Ptr{DeformableMirror},), dm))

function reset(dm::DeformableMirror)
    fill!(dm.cmd, Scalar(0))
    _check(ccall((:asdkReset, libasdk), Status, (Ptr{DeformableMirror},), dm))
end

Base.getindex(dm::DeformableMirror) = dm.cmd
Base.getindex(dm::DeformableMirror, ::Colon) = dm.cmd[:]
Base.getindex(dm::DeformableMirror, i::Integer) = dm.cmd[i]
Base.getindex(dm::DeformableMirror, i::AbstractUnitRange{<:Integer}) = dm.cmd[i]
function Base.getindex(dm::DeformableMirror, key::Keyword)
    val = Ref{Scalar}(0)
    _check(ccall((:asdkGet, libasdk), Status,
                 (Ptr{DeformableMirror}, Cstring, Ptr{Scalar}),
                 dm, key, val))
    return val[]
end

Base.setindex!(dm::DeformableMirror, val::Real, key::Keyword) = begin
    _check(ccall((:asdkSet, libasdk), Status,
                 (Ptr{DeformableMirror}, Cstring, Scalar),
                 dm, key, val))
    return dm
end

Base.setindex!(dm::DeformableMirror, val::AbstractString, key::Keyword) = begin
    _check(ccall((:asdkSetString, libasdk), Status,
                 (Ptr{DeformableMirror}, Cstring, Cstring),
                 dm, key, val))
    return dm
end

"""

`runtests(name)` run simple tests for deformable mirror identified by `name`.

"""
function runtests(name::String="BOL143")
    dm = DeformableMirror(name)
    num = length(dm)
    println("Number of actuators ", round(Int, dm["NbOfActuator"]))
    println("Number of actuators ", num)
    image_count = 0
    tot_image_count = 0
    cmd = zeros(Scalar, num)
    while tot_image_count < 10000
        for i in 1:num
            cmd[i] = 0.12;
            dm.send( cmd );
            cmd[i] = 0.0;
            if time() - t >= 1.0
                print(image_count," FPS\r")
                image_count = 0
                t = time()
            end
            image_count += 1
            tot_image_count += 1
        end
    end
    println()
end

end # module Alpao
