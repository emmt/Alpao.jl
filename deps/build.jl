module AlpaoInstall

using Libdl

path = get(ENV, "ALPAO_SDK_DLL", "libasdk."*dlext)
sym = :asdkInit
ptr1 = dlopen_e(path)
ptr2 = (ptr1 == C_NULL ? C_NULL : dlsym_e(ptr1, sym))
if ptr2 == C_NULL
    error("\n\n", (ptr1 == C_NULL ? "Unable to load" :
                   "Symbol `$sym` not found in"),
          " dynamic library:\n\n    $path\n\n",
          "Please (re)install Alpao SDK and re-run ",
          "\`Pkg.build(\"Alpao\")\`.  You may set the\nenvironment ",
          "variable ALPAO_SDK_DLL with the path of Alpao SDK dynamic ",
          "library\nbefore re-building.\n")
end

open(joinpath(@__DIR__, "deps.jl"), "w") do io
    write(io, "# This is an auto-generated file; do not edit.\n\n")
    write(io, "const DLL = \"$path\"\n")
end

end # module
