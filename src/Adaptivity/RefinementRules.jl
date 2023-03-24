
abstract type RefinementRuleType end
struct GenericRefinement <: RefinementRuleType end
struct WithoutRefinement <: RefinementRuleType end

struct RefinementRule{P,A<:DiscreteModel}
  T         :: RefinementRuleType
  poly      :: P
  ref_grid  :: A
  p2c_cache :: Tuple
end

function RefinementRule(T::RefinementRuleType,poly::Polytope,ref_grid::Grid)
  ref_model = UnstructuredDiscreteModel(ref_grid)
  return RefinementRule(T,poly,ref_model)
end

function RefinementRule(T::RefinementRuleType,poly::Polytope,ref_grid::DiscreteModel)
  ref_trian = Triangulation(UnstructuredDiscreteModel(ref_grid))
  p2c_cache = CellData._point_to_cell_cache(CellData.KDTreeSearch(),ref_trian)
  return RefinementRule(T,poly,ref_grid,p2c_cache)
end

function Base.show(io::IO,rr::RefinementRule{P}) where P
  T = RefinementRuleType(rr)
  print(io,"RefinementRule{$T,$P}")
end

ReferenceFEs.get_polytope(rr::RefinementRule) = rr.poly
get_ref_grid(rr::RefinementRule) = rr.ref_grid
num_subcells(rr::RefinementRule) = num_cells(rr.ref_grid)
num_ref_faces(rr::RefinementRule,d::Int) = num_faces(rr.ref_grid,d)
RefinementRuleType(rr::RefinementRule) :: RefinementRuleType = rr.T

function Geometry.get_cell_map(rr::RefinementRule)
  ref_grid = get_ref_grid(rr)
  return collect(Geometry.get_cell_map(ref_grid))
end

function get_inverse_cell_map(rr::RefinementRule)
  # Getting the underlying grid is important, otherwise we would not get affine maps for
  # simplicial meshes. For non-simplicial meshes we will still get LinearCombinationFields.
  # Note that this implies that (potentially)
  #            inverse_map(get_cell_map(rr)) != get_inverse_cell_map(rr)
  # This is on purpose, so that we may keep type stability in mixed-polytope meshes 
  # when only using the cell_maps. Using the inverse cell_maps in mixed meshes may 
  # result in type instabilities (only during fine-to-coarse transfers). 
  ref_grid = get_grid(get_ref_grid(rr))
  f2c_cell_map = collect(Geometry.get_cell_map(ref_grid))
  return map(Fields.inverse_map,f2c_cell_map)
end

function get_cell_measures(rr::RefinementRule)
  ref_grid  = get_ref_grid(rr)
  ref_trian = Triangulation(UnstructuredDiscreteModel(ref_grid))
  measures  = get_cell_measure(ref_trian)
  M = sum(measures)
  measures /= M
  return measures
end

function get_cell_polytopes(rr::Union{RefinementRule,AbstractArray{<:RefinementRule}})
  polys, cell_type = _get_cell_polytopes(rr)
  return CompressedArray(polys,cell_type)
end

function _get_cell_polytopes(rr::RefinementRule)
  ref_grid   = get_ref_grid(rr)
  polys      = get_polytopes(ref_grid)
  cell_types = get_cell_type(ref_grid)
  return polys, cell_types
end

function _get_cell_polytopes(rrules::AbstractArray{<:RefinementRule})
  rr_polys = lazy_map(rr->get_polytopes(rr.ref_grid),rrules)
  rr_cell_type = lazy_map(rr->get_cell_type(rr.ref_grid),rrules)

  # NOTE: The innermost `unique` is to optimize for CompressedArrays
  polys_new = unique(reduce(vcat,unique(rr_polys)))

  # This assumes that new subcells born from a RefinementRule have consecutive gids, such 
  # that the numbering of the new cells is 
  #           gid_new_cell = gid_RefRule_old_cell + child_id_new_cell
  rr2new_cell_type  = lazy_map(vp->map(p->findfirst(x->x==p,polys_new),vp),rr_polys)
  cell_type_new = reduce(vcat,lazy_map((gids,lids)->lazy_map(Reindex(gids),lids),rr2new_cell_type,rr_cell_type))

  return polys_new, cell_type_new
end

x_to_cell(rr::RefinementRule,x::Point) = CellData._point_to_cell!(rr.p2c_cache,x)

function bundle_points_by_subcell(rr::RefinementRule,x::AbstractArray{<:Point})
  npts      = length(x)
  nchildren = num_subcells(rr)

  child_ids = map(xi -> x_to_cell(rr,xi),x)
  ptrs      = fill(0,nchildren+1)
  for i in 1:npts
    ptrs[child_ids[i]+1] += 1
  end
  ptrs[1] = 1
  
  data = lazy_map(Reindex(x),sortperm(child_ids))
  return Table(data,ptrs)
end


# Faces to child faces, dof maps

# [Face dimension][Coarse Face id] -> [Fine faces]
function get_d_to_face_to_child_faces(rr::RefinementRule) 
  get_d_to_face_to_child_faces(rr,RefinementRuleType(rr))
end

function get_d_to_face_to_child_faces(::RefinementRule,::RefinementRuleType)
  @notimplemented
end

function _get_terms(poly::Polytope,orders)
  _nodes, facenodes = ReferenceFEs._compute_nodes(poly,orders)
  terms = ReferenceFEs._coords_to_terms(_nodes,orders)
  return terms
end

function _get_face_orders(p::Polytope{Dc},D::Int,orders::Tuple) where Dc
  @check length(orders) == Dc
  @check 1 <= D < Dc
  @check is_n_cube(p)

  if D == 1 # Edges (2D, 3D)
    tangents = get_edge_tangent(p)
    face_orders = map(tangents) do t
      axis = findfirst(i -> abs(t[i]) > 0.5 ,1:Dc)
      return [orders[axis]]
    end
  elseif D == Dc-1 # Faces (3D)
    normals = get_facet_normal(p)
    face_orders = map(normals) do n
      mask = map(i -> abs(n[i]) < 1.e-3,1:Dc)
      return [orders[mask]...]
    end
  else
    @notimplemented
  end

  return face_orders
end

function get_face_subface_ldof_to_cell_ldof(rr::RefinementRule{ExtrusionPolytope{Dc}},
                                            fine_orders::NTuple{Dc,<:Integer},
                                            D::Int) where Dc
  poly  = get_polytope(rr)
  coarse_orders = 2 .* fine_orders
  coarse_reffe  = ReferenceFE(poly,lagrangian,Float64,coarse_orders)
  coarse_face_polys = CompressedArray(ReferenceFEs._compute_reffaces_and_face_types(poly,Val(D))...)
  c_edge_to_coarse_dof = coarse_reffe.face_nodes[get_dimranges(poly)[D+1]]
  
  model = get_ref_grid(rr)
  fine_face_grid = Grid(ReferenceFE{D},model)
  fine_face_polys = CompressedArray(map(get_polytope,get_reffes(fine_face_grid)),get_cell_type(fine_face_grid))
  
  d_to_face_to_child_faces = get_d_to_face_to_child_faces(rr)
  face_to_child_faces = d_to_face_to_child_faces[D+1]
  
  coarse_face_orders = _get_face_orders(poly,D,coarse_orders)
  fine_face_orders = _get_face_orders(poly,D,fine_orders)
  
  num_coarse_faces = num_faces(coarse_reffe,D)
  coarse_dofs_above_fine_dofs = Vector{Vector{Vector{Int32}}}(undef,num_coarse_faces)
  for cF in 1:num_coarse_faces
    coarse_face_poly = coarse_face_polys[cF]
    coarse_terms = _get_terms(coarse_face_poly,coarse_face_orders[cF])
    coarse_dofs  = zeros(Int32,Tuple(maximum(coarse_terms)))
    coarse_dofs[coarse_terms] .= c_edge_to_coarse_dof[cF]
  
    child_faces = face_to_child_faces[cF]
    fine_dofs = Vector{Vector{Int32}}(undef,length(child_faces))
    for (i,fF) in enumerate(child_faces)
      fine_face_poly = fine_face_polys[fF]
      fine_terms = _get_terms(fine_face_poly,fine_face_orders[cF])
  
      local_dof_range = map(o->(i-1)*o+1:i*o+1,fine_face_orders[cF])
      local_coarse_dofs = view(coarse_dofs,local_dof_range...)
      fine_dofs[i] = map(Reindex(local_coarse_dofs),fine_terms)
    end
    coarse_dofs_above_fine_dofs[cF] = fine_dofs
  end

  return coarse_dofs_above_fine_dofs
end


# GenericRefinement Rule

function RefinementRule(reffe::LagrangianRefFE{D},nrefs::Integer;kwargs...) where D
  partition = tfill(nrefs,Val{D}())
  return RefinementRule(get_polytope(reffe),partition;kwargs...)
end

function RefinementRule(reffe::LagrangianRefFE{D},partition::NTuple{D,Integer};kwargs...) where D
  return RefinementRule(get_polytope(reffe),partition;kwargs...)
end

function RefinementRule(poly::Polytope{D},nrefs::Integer;kwargs...) where D
  partition = tfill(nrefs,Val{D}())
  return RefinementRule(poly,partition;kwargs...)
end

function RefinementRule(poly::Polytope{D},partition::NTuple{D,Integer};kwargs...) where D
  ref_grid = UnstructuredGrid(compute_reference_grid(poly,partition))
  return RefinementRule(GenericRefinement(),poly,ref_grid;kwargs...)
end


# Tests 

function test_refinement_rule(rr::RefinementRule; debug=false)
  poly = get_polytope(rr)
  D = num_dims(poly)

  cmaps = get_cell_map(rr)
  inv_cmaps = Adaptivity.get_inverse_cell_map(rr)

  pts = map(x -> VectorValue(rand(D)),1:10)
  if Geometry.is_simplex(poly)
    filter!(p -> sum(p) < 1.0, pts)
  end

  # Checking that inv_cmaps ∘ cmaps = identity
  for p in pts
    ichild = Adaptivity.x_to_cell(rr,p)
    m = cmaps[ichild]
    m_inv = inv_cmaps[ichild]

    y = evaluate(m,p)
    z = evaluate(m_inv,y)
    @test p ≈ z
    debug && println(ichild, " :: ", p," -> ",y, " -> ", z, " - ", p ≈ z)
  end

  pts_bundled = bundle_points_by_subcell(rr,pts)
  cell_measures = get_cell_measures(rr)
  cell_polys = get_cell_polytopes(rr)

  return nothing
end