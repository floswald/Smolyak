#= 
	-------------------------------------
	Smolyak Grid for Julia version 0.3.7  
	-------------------------------------

This file contains code to define Smolyak Grid type. Both Anisotrophic and 
Isotrophic Grids are supported and they are constructed efficiently 
following the methodology outlined in JMMV (2014). The code is designed on 
latest stable Julia version: 0.3.7.

Key Refs: JMMV (2014), Burkhardt (2012), github: ECONFORGE/Smolyak

=#

IntOrVec = Union(Int64,Vector{Int64},Float64,Vector{Float64})

#= ***************************************** =#
#= Sub Funs called when creating SmolyakGrid =#
#= ***************************************** =#

# This fn returns theta = cos(x), where x are chebyshev nodes
function chebtheta(n::Int64)	
	if n == 1; return 0.5pi; end
	j = 1:n
	theta = [((j-1)./(n-1))pi]
	return theta
end	

function chebnodes(n::Int64)	
	return x = round(cos(chebtheta(n)),14)
end

# This is the map from index to number of grid points in each dimension
function m_i(i::Int64)
	if i ==1; return 1; end
	if i > 1; return 2.^(i-1)+1; end
end

# This is number of new points added by nested rule as function of index i ( = l+1 in Burkhardt)
function newpts(i::Int64)
	if i==1
		return 1 
	elseif i==2 
		return 2
	else
		return 2.^(i-2)
	end
end

# Disjoint Sets of Grid Points whose product are combined 
function grid_A_i(i::Int64)
	if i == 1; return 0.0; end
	if i == 2; return chebnodes(m_i(i))[1:2:m_i(i)]; end
	if i >2; return chebnodes(m_i(i))[2:2:m_i(i)]; end 	
end

#= ******************************* =#
#= Funs used to create SmolyakGrid =#
#= ******************************* =#

function mufun(d::Int64,mu::IntOrVec)
	if isa(mu,Int64)
		maxmu = mu
		mubar = tuple([mu*ones(Int64,d)]...)
	else
		maxmu = 0
		for m = 1:length(mu)
			maxmu = max(maxmu,mu[m])
		end
		mubar = tuple(mu...) 
	end
	@assert(d == length(mubar),"\n\tError: Dimension mismatch: \n
								\tNumber of dimensions!= length of precision index (mu)\n")
	return mubar , maxmu
end

# Calculate Number of Grid Points & Construct Indices of Smolyak Grid
@ngenerate N (Int64,Array{Array{Int64,1},1}) function SmolIdx(maxmu::Int64,mu::NTuple{N,Int64}...)
	mubar = Int64[]
	ibar = Int64[]
	n = Int64[]
	NumGridPts = 0
	sum_i = 0 
	iList=Array{Int64,1}[]	
	@nexprs N j-> push!(mubar,mu_j)
	@nloops N i j->1:mubar[j]+1 begin
		@nexprs N j -> push!(n,newpts(i_j))
		@nexprs N j -> sum_i += i_j 
		if sum_i > N + maxmu
			ibar = Int64[]
			n = Int64[]
			sum_i=0
			break
		end
		@nexprs N j-> push!(ibar, i_j)
		push!(iList,ibar)
		NumGridPts += prod(n)
		ibar = Int64[]
		n = Int64[]
		sum_i=0
	end
	return NumGridPts, iList
end

# Constructs the Smolyak Grid
@ngenerate N (Array{Float64,2}) function Make_Grid(NGP::Int64,inds::Array{Array{Int64,1},1},mu::NTuple{N,Int64}...)
	H = Array(Float64,NGP,N)
	zH = 0
	for i = 1:length(inds)
		for j in product((@ntuple N k->grid_A_i(inds[i][k]))...)
			zH += 1
			H[zH,:] = [j...]
		end
	end
	return H
end

#= Functions switching between z in [-1,1] and x in [lb,ub] 
	- See ECONFORGE/Smolyak for unadjusted code =#

function z2x(zpts::Array{Float64,2},lb::Vector{Float64},ub::Vector{Float64})
	centers = lb + (ub - lb)./2
    radii = (ub - lb)./2
    xpts = centers' .+ zpts.*radii'::Array{Float64,2}
	return xpts
end

function x2z(xpts::Array{Float64,2},lb::Vector{Float64},ub::Vector{Float64})
 	centers = lb + (ub - lb)./2
    radii = (ub - lb)./2
    zpts = (xpts .- centers')./radii'::Array{Float64,2}
	return zpts
end

#= ******************************************* =#
#= Create Basis Funs Indices SmolyakGrid(d,mu) =#
#= ******************************************* =#

# Disjoint sets that define indexes for creation of Basis Indices
function A_pidx(ibar::Int64)
	A = {};
	#= A = [] in version 0.4 =#
	lb 	= 	[	1,
				2,
				2.^([3:ibar]-1) - 2.^([3:ibar]-2)+2];
	ub 	= 	[	1,
				2.^([2:ibar]-1)+1];
	for j = 1:ibar
		push!(A,[lb[j]:ub[j]])
	end
	return A
end

@ngenerate N Array{Int64,2} function BasisIdx(NGP::Int64,GridIdx::Array{Array{Int64,1},1},maxmu::Int64,mu::NTuple{N,Int64}...)
	A = A_pidx(maxmu+1)
	T = Array(Int64,NGP,N)
	zT = 0
	for i = 1:length(GridIdx)
		for j in product((@ntuple N k->A[GridIdx[i][k]])...)
			zT += 1
			T[zT,:] = [j...]-1
		end
	end
	return T
end

#= ***************** =#
#= Smolyak Grid Type =#
#= ***************** =#

type SmolyakGrid
	D 			::	Int64				# Dimensions
	mu 			::	IntOrVec			# Index of mu
	NumGrdPts 	::	Int64				# Number of Grid Points
	lb 			::	Vector{Float64}		# Lower Bounds of dimensions
	ub 			::	Vector{Float64}		# Upper Bounds of dimensions
	zGrid 		::	Array{Float64,2}	# Smolyak Grid on z = [-1,1]
	xGrid 		::	Array{Float64,2}	# Smolyak Grid on original domain x in [lb,ub]
	Binds    	::  Array{Int64,2}		# Input to construct Basis Funs for set of grid points -> Will depend on mu.

	function SmolyakGrid(	D::Int64, mu::IntOrVec,
							lb::Vector{Float64}, ub::Vector{Float64})
		
		#= z in [-1,1]^D and x[d] in [lb[d],ub[d]] for d = 1,...,D =#
		
		@assert(is(size(lb,1),D) || is(size(ub,1),D),
				"\n\tError: [lb,ub] does not equal dimension of grid")
		#= @assert(.<=(lb,ub),
				"\n\tError: lb >= ub") =#

		mubar, maxmu = mufun(D,mu) 
		NumGrdPts, Ginds = SmolIdx(maxmu,mubar...)
		zGrid = Make_Grid(NumGrdPts,Ginds,mubar...)	
		xGrid  = z2x(zGrid,lb,ub)
		Binds = BasisIdx(NumGrdPts,Ginds,maxmu,mubar...)

		new(D, mu, NumGrdPts, lb, ub, zGrid, xGrid, Binds)
	end
end

function show(io::IO, sg::SmolyakGrid)
	if !=(minimum(sg.mu),maximum(sg.mu))
			mu_print = strip(string(sg.mu))
			msg = "Anisotrophic Smolyak Grid:\n"
			msg *= "\tD: $(sg.D)\n\tmu: $(mu_print)\n\tNum Grid Points: $(sg.NumGrdPts)"
	else
		msg = "Isotrophic Smolyak Grid:\n"
		msg *= "\tD: $(sg.D)\n\tmu: $(sg.mu[1])\n\tNum Grid Points: $(sg.NumGrdPts)"
	end
	print(io, msg)
end

