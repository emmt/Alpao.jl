using Libdl
let path = "libasdk."*dlext

    if dlopen_e(path) == C_NULL
        error("Unable to load dynamic library \"$path\".\n\nPlease (re)install Alpao SDK, re-run \`Pkg.build(\"Alpao\")\`, and restart Julia.")
    end

    open(joinpath(@__DIR__, "deps.jl"), "w") do io
        write(io, "# This is an auto-generated file; do not edit.\n\n")
        write(io, "const DLL = \"$path\"\n")
    end
end
