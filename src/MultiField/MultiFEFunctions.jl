include("MultiAssemblers.jl")

module MultiFEFunctions

using Gridap
using Gridap.Helpers
using Gridap.FESpaces
using ..MultiFESpaces

export MultiFEFunction

import Base: length
import Base: getindex
import Base: iterate
import Base: zero
import Gridap.FESpaces: free_dofs

struct MultiFEFunction
  fields::Vector{<:FEFunction}
  free_dofs_all_fields::AbstractVector
end

function MultiFEFunction(
  free_dofs_all_fields::AbstractVector, fespaces::MultiFESpace)
  fields = [
    FEFunction(U,restrict_to_field(fespaces,free_dofs_all_fields,i))
    for (i,U) in enumerate(fespaces) ]
  MultiFEFunction(fields,free_dofs_all_fields)
end

free_dofs(self::MultiFEFunction) = self.free_dofs_all_fields

length(self::MultiFEFunction) = length(self.fields)

getindex(self::MultiFEFunction,field::Integer) = self.fields[field]

iterate(self::MultiFEFunction) = iterate(self.fields)

iterate(self::MultiFEFunction,state) = iterate(self.fields,state)

function zero(U::MultiFESpace{E}) where E
  n = num_free_dofs(U)
  x = zeros(E,n)
  MultiFEFunction(x,U)
end

end # module MultiFEFunctions
