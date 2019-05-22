module FESpacesTests

using Test

using Gridap
using Gridap.RefFEs
using Gridap.CellValues
using Gridap.CellMaps
using Gridap.Polytopes
using Gridap.Geometry
using Gridap.Geometry.Cartesian
using Gridap.CellMaps.Testers
using Gridap.CellIntegration
using Gridap.Vtkio

using Gridap.FESpaces

model = CartesianDiscreteModel(domain=(0.0,1.0,-1.0,2.0), partition=(2,2))

D = pointdim(model)

grid = Grid(model,D)
trian = triangulation(grid)
graph = FullGridGraph(model)
labels = FaceLabels(model)
tags = [1,2,3,4]

order = 1
orders = fill(order,D)
polytope = Polytope(fill(HEX_AXIS,D)...)
fe = LagrangianRefFE{D,Float64}(polytope, orders)

fespace = ConformingFESpace(fe,trian,graph,labels,tags)

@test num_free_dofs(fespace) == 5
@test num_diri_dofs(fespace) == 4

@test diri_tags(fespace) === tags

r = [[-1, 1, 2, 3], [1, -2, 3, 4], [2, 3, -3, 5], [3, 4, 5, -4]]

@test r == collect(fespace.cell_eqclass)

order = 2
orders = fill(order,D)
polytope = Polytope(fill(HEX_AXIS,D)...)
fe = LagrangianRefFE{D,Float64}(polytope, orders)

tags = [1,2,3,4,6,5]
fespace = ConformingFESpace(fe,trian,graph,labels,tags)

@test num_free_dofs(fespace) == 15
@test num_diri_dofs(fespace) == 10

r = [[-1, -2, 1, 2, -7, 4, 5, 6, 12], [-2, -3, 2, 3, -8, 7, 6, 8, 13],
     [1, 2, -4, -5, 4, -9, 9, 10, 14], [2, 3, -5, -6, 7, -10, 10, 11, 15]]

@test r == collect(fespace.cell_eqclass)

fun(x) = sin(x[1])*cos(x[2])

free_vals, diri_vals = interpolated_values(fespace,fun)

rf = [0.0, 0.420735, 0.598194, 0.078012, 0.0, 0.420735,
      0.214936, 0.598194, -0.0, -0.199511, -0.283662,
      0.420735, 0.73846, -0.199511, -0.350175]

rd = [0.0, 0.259035, 0.368291, 0.420735, 0.73846, 0.151174,
      0.239713, 0.660448, 0.151174, 0.265335]

@test isapprox(free_vals,rf,rtol=1.0e-5)
@test isapprox(diri_vals,rd,rtol=1.0e-5)

diri_vals = interpolated_diri_values(fespace,fun)

@test isapprox(diri_vals,rd,rtol=1.0e-5)

uh = FEFunction(fespace,free_vals,diri_vals)

@test free_dofs(uh) === free_vals
@test diri_dofs(uh) === diri_vals
@test FESpace(uh) === fespace

cellbasis = CellBasis(fespace)

quad = quadrature(trian,order=2)

a(v,u) = varinner(v,u)

bfun(x) = x[2] 

b(v) = varinner(v,cellfield(trian,bfun))

mmat = integrate(a(cellbasis,cellbasis),trian,quad)

bvec = integrate(b(cellbasis),trian,quad)

bvec2, dofs = apply_constraints(fespace,bvec)

@test bvec2 === bvec

@test dofs == fespace.cell_eqclass

mmat2, dofs = apply_constraints_rows(fespace,mmat)

@test mmat2 === mmat

@test dofs == fespace.cell_eqclass

mmat3, dofs = apply_constraints_cols(fespace,mmat)

@test mmat3 === mmat

@test dofs == fespace.cell_eqclass

uh = interpolate(fespace,fun)
@test isa(uh,FEFunction)

q = coordinates(quad)
uhq = evaluate(uh,q)

grad_uh = gradient(uh)
grad_uhq = evaluate(grad_uh,q)

v = collect(uhq)
g = collect(grad_uhq)

test_cell_map_with_gradient(uh,q,v,g)

fespace = ConformingFESpace(Float64,model,order,tags)

model = CartesianDiscreteModel(domain=(0.0,1.0,0.0,1.0), partition=(2,2))

order = 1
fespace = ConformingFESpace(Float64,model,order,tags)

grid = Grid(model,D)
trian = triangulation(grid)

fun1(x) = x[1]
uh1 = interpolate(fespace,fun1)

fun2(x) = x[1]*x[2]
uh2 = interpolate(fespace,fun2)

fun3(x) = sin(x[1])*cos(x[2])
uh3 = interpolate(fespace,fun3)

cellsize(uhq.a)

#writevtk(trian,"trian",nref=3,
#  cellfields=["uh1"=>uh1,"uh2"=>uh2,"uh3"=>uh3])

#@show uhq



end # module FESpacesTests