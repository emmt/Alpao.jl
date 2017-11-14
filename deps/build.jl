let dlext = (VERSION >= v"0.4.0-dev+3844" ? Base.Libdl : Base).dlext,
    dlopen_e = (VERSION >= v"0.4.0-dev+3844" ? Base.Libdl : Base).dlopen_e,
    path = "libasdk."*dlext

    if dlopen_e(path) == C_NULL
        error("Unable to load dynamic library \"$path\".\n\nPlease (re)install Alpao SDK, re-run \`Pkg.build(\"Alpao\")\`, and restart Julia.")
    end

    open(joinpath(dirname(@__FILE__),"deps.jl"), "w") do io
        write(io, "# This is an auto-generated file; do not edit.\n\n")
        write(io, "const DLL = \"$path\"\n")
    end
end
