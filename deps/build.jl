using BinDeps
using Compat

@BinDeps.setup

libalpao = library_dependency("libasdk", aliases = ["ASDK"], runtime = true)

@BinDeps.install Dict(:libalpao => :DLL)
