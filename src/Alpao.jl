# Alpao.jl -
#
# Julia interface to Alpao's library for managing their deformable mirrors.
#
#------------------------------------------------------------------------------
#
# This file is part of the `Alpao.jl` package which is licensed under the MIT
# "Expat" License.
#
# Copyright (C) 2016-2019, Éric Thiébaut & Jonathan Léger.
#

isdefined(Base, :__precompile__) && __precompile__(true)

module Alpao

import Base: getindex, setindex!, reset, length, eltype
import Sockets.send

@static if isdefined(Base, :stop)
    import Base: stop
end

export
    send!,
    stop

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

const Keyword = String
const Scalar  = Cdouble
const Status  = Cint

const SUCCESS = Status(0)
const FAILURE = Status(-1)

const depsfile = joinpath(dirname(@__FILE__),"..","deps","deps.jl")
if isfile(depsfile)
    include(depsfile)
else
    error("Alpao not properly installed.  Please run Pkg.build(\"Alpao\")")
end

"""
    dm = Alpao.DeformableMirror(name)

creates an instance `dm` to manage Alpao's deformable mirror identifed by the
name of its configuration file.

The deformable mirror instance `dm` can be used as follows:

    length(dm)          # yields number of actuators
    eltype(dm)          # yields bit type for an actuator command
    dm[key]             # yields value of keyword `key`
    dm[key] = val       # sets value of keyword `key`
    send(dm, cmd)       # sets the shape of the deformable mirror
    send!(dm, cmd)      # idem but, on return, `cmd` contains actual commands
    send(dm, pat, rep)  # repeatedly send patterns to the deformable mirror
    send!(dm, pat, rep) # idem but, on return, `pat` contains actual commands
    reset(dm)           # resets the deformable mirror values
    stop(dm)            # stops asynchronous commands sent to the deformable
                        # mirror


List of parameter keywords

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
"""
mutable struct DeformableMirror
    ptr::Ptr{Cvoid} # handle to device
    num::Int        # number of actuators
    function DeformableMirror(ident::AbstractString)
        local ptr::Ptr{Cvoid}, num::Int
        if '/' in ident
            odir = pwd()
            try
                cd(dirname(ident))
                ptr = ccall((:asdkInit, DLL), Ptr{Cvoid}, (Cstring,),
                            basename(ident))
            finally
                cd(odir)
            end
        else
            ptr = ccall((:asdkInit, DLL), Ptr{Cvoid}, (Cstring,), ident)
        end
        if ptr == C_NULL
            code, mesg = lasterror()
            error("failed to open $ident ($mesg)")
        end
        num = convert(Int, _get(ptr, "NbOfActuator")) :: Int
        return finalizer(_release, new(ptr, num))
    end
end

function _release(dm::DeformableMirror)
    if dm.ptr != C_NULL
        status = ccall((:asdkRelease, DLL), Status, (Ptr{Cvoid},), dm.ptr)
        dm.ptr = C_NULL
    end
end

length(dm::DeformableMirror) = dm.num
eltype(::DeformableMirror) = Scalar

const CMDMAX = Scalar(1.0)

"""
    send(dm, cmd)

sends actuator commands `cmd` to deformable mirror(s) `dm`.

    send(dm, pat, rep)

sends commands in `pat` to deformable mirror(s) `dm` as quickly as possible.


See also: [`send!`](@ref)
"""
send(dm::DeformableMirror, cmd::DenseVector{Scalar}) =
    send!(dm, copy(cmd))

send(dm::DeformableMirror, pat::DenseMatrix{Scalar}, rep::Integer) =
    send!(dm, copy(pat), rep)

"""
    send!(dm, cmd)

sends actuator commands `cmd` to deformable mirror(s) `dm`.  The command
values in `cmd` may be modified due to bound constraints.  Thus, on return,
`cmd` contains the actual commands sent to the mirror.

    send!(dm, pat, rep)

sends commands in `pat` to deformable mirror(s) `dm` as quickly as possible and
leaves actual command values in `pat`. `rep` is the number of time to repeat
that pattern (some interface not allow you to use this feature).


See also: [`send`](@ref)
"""
function send!(dm::DeformableMirror, cmd::DenseVector{Scalar})
    @assert length(cmd) == length(dm) # FIXME: there may be several mirrors
    @inbounds for i in eachindex(cmd)
        cmd[i] = clamp(cmd[i], -CMDMAX, CMDMAX)
    end
    _check(ccall((:asdkSend, DLL), Status, (Ptr{Cvoid}, Ptr{Scalar}),
                 dm.ptr, cmd))
end

# Send patterns as quickly as possible.
function send!(dm::DeformableMirror, pat::DenseMatrix{Scalar}, rep::Integer)
    @assert size(pat, 1) == length(dm) # FIXME: there may be several mirrors
    @inbounds for i in eachindex(pat)
        pat[i] = clamp(pat[i], -CMDMAX, CMDMAX)
    end
    _check(ccall((:asdkSendPattern, DLL), Status,
                 (Ptr{Cvoid}, Ptr{Scalar}, UInt32, UInt32),
                 dm.ptr, pat, size(pat, 2), rep))
end

"""
    Alpao.lasterror() -> (code, mesg)

pops the last error from the stack and returns error code and corresponding
message.

"""
function lasterror()
    code = Ref{UInt32}(0)
    mesg = zeros(UInt8, 512) # message buffer filled with zeroes
    if ccall((:asdkGetLastError, DLL), Status,
             (Ptr{UInt32}, Ptr{UInt8}, Csize_t),
             code, mesg, sizeof(mesg)) != SUCCESS
        error("failed to retrieve last error message")
    end
    mesg[end] = 0
    (code[], String(mesg))
end

printlasterror() = ccall((:asdkPrintLastError, DLL), Cvoid, ())

function _check(status::Status)
    if status != SUCCESS
        code, mesg = lasterror()
        error(mesg)
    end
end

stop(dm::DeformableMirror) =
    _check(ccall((:asdkStop, DLL), Status, (Ptr{Cvoid},), dm.ptr))

reset(dm::DeformableMirror) =
    _check(ccall((:asdkReset, DLL), Status, (Ptr{Cvoid},), dm.ptr))

getindex(dm::DeformableMirror, key::Keyword) = _get(dm.ptr, key)

function _get(ptr::Ptr{Cvoid}, key::Keyword)
    @assert ptr != C_NULL
    val = Ref{Scalar}(0)
    _check(ccall((:asdkGet, DLL), Status, (Ptr{Cvoid}, Cstring, Ptr{Scalar}),
                 ptr, key, val))
    return val[]
end

setindex!(dm::DeformableMirror, val, key::Keyword) = _set!(dm, key, val)

_set!(dm::DeformableMirror, key::Keyword, val::Real) =
    _set!(dm, key, Scalar(val))

_set!(dm::DeformableMirror, key::Keyword, val::Scalar) =
    _check(ccall((:asdkSet, DLL), Status,
                 (Ptr{Cvoid}, Cstring, Scalar),
                 dm.ptr, key, val))

_set!(dm::DeformableMirror, key::Keyword, val::String) =
    _check(ccall((:asdkSetString, DLL), Status,
                 (Ptr{Cvoid}, Cstring, Cstring),
                 dm.ptr, key, val))

"""

`runtests(name)` run simple tests for deformable mirror identified by `name`.

"""
function runtests(name::String="BOL143")
    dm = DeformableMirror(name)
    val = length(dm)
    println("NB actuators ", round(Int, dm["NbOfActuator"]))
    println("NB actuators ", val)
    image_count = 0
    tot_image_count = 0
    data = Array(Cdouble, val)
    data[:] = 0.0
    time = 0.0
    while tot_image_count < 10000
        for i in 1:val
            data[i] = 0.12;
            dm.send( data );
            data[i] = 0.0;
            if time() - time >= 1.0
                print(image_count," FPS\r")
                image_count = 0
                time = time()
            end
            image_count += 1
            tot_image_count += 1
        end
    end
    println()
end

end # module Alpao
