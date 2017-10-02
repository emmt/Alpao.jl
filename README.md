# Julia Interface to Alpao SDK

This module provides a Julia interface to
[ALPAO](https://www.alpao.com/adaptive-optics/) deformable mirrors.


## Installation

To be able to use this module, you must have installed
[ALPAO](https://www.alpao.com/adaptive-optics/) Software Development Kit (SDK)
and have one of their deformable mirror connected to your computer.

`Alpao.jl` is not yet an [official Julia package](https://pkg.julialang.org/)
so you have to clone the repository to install the module:

    Pkg.clone("https://github.com/emmt/Alpao.jl.git")
    Pkg.build("Alpao")

Later, it is sufficient to do:


    Pkg.update("Alpao")

to pull the latest version.


## Usage

First import `Alpao` module:

    import Alpao

or

    using Alpao

(the two are equivalent since this module does not export any symbols).  Then
create an instance, say `dm`, of `Alpao.DeformableMirror`:

    dm = Alpao.DeformableMirror(name)

where `name` identify Alpao's deformable mirror to manage.  This name must
match that of its configuration file (see [Configuration](#configuration)
below).

The deformable mirror instance `dm` can be used to set the shape of the
deformable mirror:

    send(dm, cmd)

where `cmd` is a vector of actuator values.  The number of actuators is given
by `length(dm)` and the type of the actuator values is given by `eltype(dm)`.
It is also possible to repeatedly send patterns to the deformable mirror with:

    send(dm, pat, rep)

To reset the deformable mirror values, call:

    reset(dm)

and to stop asynchronous commands sent to the deformable mirror, call:

    stop(dm)

Parameters of the mirror can be queried by:

    dm[key]

where `key` is the name of the keyword corresponding to the parameter.  To set
a parameter to a value, say `val`, simply do:

    dm[key] = val

The list of parameter keywords is given below (note that some parameter are
read or write only):

```
 -----------------------------------------------------------------------
 Keyword         Get  Set  Value  Description
 -----------------------------------------------------------------------
 "AckTimeout"     x    x    > 0   For Ethernet / USB interface only, set
                                  the time-out (ms); can be set in
                                  synchronous mode only (see SyncMode).
 "DacReset"            x    1     Reset all digital to analog converters
                                  of drive electronics.
 "ItfState"       x         0:1   Return 1 if PCI interface is busy or 0
                                  otherwise.
 "LogDump"             x    1     Dump the log stack on the standard
                                  output.
 "LogPrintLevel"  x    x    0:4   Changes the output level of the logger
                                  to the standard output.
 "NbOfActuator"   x         ≥ 1   Get the numbers of actuator for that
                                  mirror.
 "SyncMode"            x    0:1   0: Synchronous mode, will return when
                                     send is done.
                                  1: Asynchronous mode, return
                                     immediately after safety checks.
 "TriggerMode"         x    0:1   Set mode of the (optional) electronics
                                  trigger output. 0: long pulse width or
                                  1: short pulse width on each command.
 "TriggerIn"           x    0:2   Set mode of the (optional) input
                                  trigger. 0: disabled, 1: trig on rising
                                  edge or 2: trig on falling edge.
 "UseException"   x    x    0:1   Enables or disables the throwing of an
                                  exception on error.
 "VersionInfo"    x         > 0   Alpao SDK core version, e.g. 3040500612
                                  is SDK v3.04.05.0612 where 0612 is
                                  build number.
 ------------------------------------------------------------------------
```

The last error in the SDK can be retrieved with:

    Alpao.lasterror()

which pops the last error from the stack and returns an error code and the
corresponding message as a tuple: `(code, mesg)`.


## Configuration

All mirrors from ALPAO are referenced by a unique serial number, you can find
it on the back of the mirror, for example `S/N: BAL002` indicates that `BAL002`
is the serial number.

For each mirror you will find two configuration files (where `BXXYYY` is the
serial number):

* `BXXYYY.acfg` which is an ASCII files describing the interface.

* `BXXYYY` which is a binary file.

The configuration files should be in one of these folders: `.`, `..`,
`$ACECFG`, `$ACEROOT`, `./config`, `../config`, `$ACECFG/config` or
`$ACEROOT/config`.  These folders are searched in that order and `$ACECFG` and
`$ACEROOT` are the respective values of the environment variables `ACECFG`,
`ACEROOT`.


## Type Correspondences

C-types are defined in `asdkType.h` and function prototypes in `asdkWrapper.h`
of the Alpao SDK.

All functions but 2 return status with type `COMPL_STAT` which is an
enumeration (hence a `Cint`) with 2 possible values: 0 for success and -1 for
failure.  The other functions are `asdkInit` which returns a pointer to a
structure (considered as anonymous, hence a `Ptr{Void}` here) and
`asdkPrintLastError` which returns nothing.

The other C types used in the API are `Int` and `UInt` which are 32-bit
integers, `CString` and `CStrConst` which are C-strings, `Scalar` which is C
`double` and `Size_T` which is `size_t`.

The following table summarizes the types:

```
 -------------------------------------------------
 Alpao API      C Type        Julia Type
 -------------------------------------------------
 Char           char          Cchar
 UChar          uint8_t       UInt8
 Short          int16_t       Int16
 UShort         uint16_t      UInt16
 Int            int32_t       Int32
 UInt           uint32_t      UInt32
 Long           int64_t       Int64
 ULong          uint64_t      UInt64
 Size_T         size_t        Csize_t
 Scalar         double        Cdouble
 asdkDM*        struct DM*    Ptr{Void}
 CString        char*         Cstring / Ptr{UInt8}
 CStrConst      char const*   Cstring / Ptr{UInt8}
 -------------------------------------------------
```

