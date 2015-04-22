#= 
	-----------------------------------------------------------------
	Smolyak Basis Functions on a Smolyak Grid for Julia version 0.3.7  
	-----------------------------------------------------------------

This file contains code to define Smolyak Constructtion of Chebyshev
basis functions. It is compatible with both AnisotroPsic and IsotroPsic 
Grids and are constructed efficiently following the methodology outlined
 in JMMV (2014). The code is designed on latest stable Julia version: 0.3.7.

Key Refs: JMMV (2014), Burkhardt (2012), github: ECONFORGE/Smolyak

=#

#= ---------------- =#
#= Within loop funs =#
#= ---------------- =#

VecOrArray = Union(Vector{Float64},Array{Float64,2}) 

function Tn!(T::Array{Float64,2},zpts::VecOrArray, MaxChebIdx::Int64, Dims::Int64)
	for n in 1:MaxChebIdx
		for d in 1:Dims
			if ==(n,1)
				T[n,d] = 1.0
			elseif ==(n,2)
				T[n,d] = zpts[d]
			else
				T[n,d] = 2*zpts[d]*T[n-1,d] - T[n-2,d]
			end
		end
	end
end


function Tn!(T::Array{Float64,2}, ∂T::Array{Float64,2}, zpts::VecOrArray, MaxChebIdx::Int64, Dims::Int64)
	for n in 1:MaxChebIdx
		for d in 1:Dims
			if ==(n,1)
				T[n,d] = 1.0
				∂T[n,d] = 0.0
			elseif ==(n,2)
				T[n,d] = zpts[d]
				∂T[n,d] = 1.0
			else
				T[n,d] = 2*zpts[d]*T[n-1,d] - T[n-2,d]
				∂T[n,d] = 2*T[n-1,d] + 2*zpts[d]*∂T[n-1,d] - ∂T[n-2,d]
			end
		end
	end
end

function Tn!(T::Array{Float64,2}, ∂T::Array{Float64,2}, ∂2T::Array{Float64,2}, zpts::VecOrArray, MaxChebIdx::Int64, Dims::Int64)
	for n in 1:MaxChebIdx
		for d in 1:Dims
			if ==(n,1)
				T[n,d] = 1.0
				∂T[n,d] = 0.0
				∂2T[n,d] = 0.0				
			elseif ==(n,2)
				T[n,d] = zpts[d]
				∂T[n,d] = 1.0
				∂2T[n,d] = 0.0				
			else
				T[n,d] = 2*zpts[d]*T[n-1,d] - T[n-2,d]
				∂T[n,d] = 2*T[n-1,d] + 2*zpts[d]*∂T[n-1,d] - ∂T[n-2,d]
				∂2T[n,d] = 4*∂T[n-1,d] + 2*zpts[d]*∂2T[n-1,d] - ∂2T[n-2,d]
			end
		end
	end
end

function Psi!(Psi::Array{Float64,2}, T::Array{Float64,2}, 
				GridIdx::Int64, BFIdx::Int64, DimIdx::Int64, sg::SmolyakGrid)
	ChebIdx = sg.Binds[BFIdx,DimIdx]+1 
	Psi[GridIdx,BFIdx] *= T[ChebIdx,DimIdx] 
end


function ∂Psi∂z!(∂Psi∂z::Array{Float64,3}, T::Array{Float64,2}, ∂T::Array{Float64,2}, 
					GridIdx::Int64, BFIdx::Int64, DimIdx::Int64, sg::SmolyakGrid)
	ChebIdx = sg.Binds[BFIdx,DimIdx]+1
	for i in 1:sg.D
		if ==(i,DimIdx)
			∂Psi∂z[GridIdx,BFIdx,i] *= ∂T[ChebIdx,DimIdx]
		else
			∂Psi∂z[GridIdx,BFIdx,i] *= T[ChebIdx,DimIdx]
		end
	end
end

function ∂2Psi∂z2!(∂2Psi∂z2::Array{Float64,4}, T::Array{Float64,2}, ∂T::Array{Float64,2}, ∂2T::Array{Float64,2},
					 GridIdx::Int64, BFIdx::Int64, DimIdx::Int64, sg::SmolyakGrid)
	ChebIdx = sg.Binds[BFIdx,DimIdx]+1
	for i in 1:sg.D
		for j in 1:sg.D
			if DimIdx==i==j
				∂2Psi∂z2[GridIdx,BFIdx,i,j] *= ∂2T[ChebIdx,DimIdx]
			elseif DimIdx==j!=i  
				∂2Psi∂z2[GridIdx,BFIdx,i,j] *= ∂T[ChebIdx,DimIdx]
			elseif DimIdx==i!=j
				∂2Psi∂z2[GridIdx,BFIdx,i,j] *= ∂T[ChebIdx,DimIdx]
			else
				∂2Psi∂z2[GridIdx,BFIdx,i,j] *= T[ChebIdx,DimIdx]
			end
		end
	end
end

#= --------------------------------------- =#
#= Construct Basis Functions & Derivatives =#
#= --------------------------------------- =#

function check_domain(X::Array{Float64,2}, sg::SmolyakGrid)
	N,D = size(X) 	# Size of Array of Grid points
	@assert(is(D,sg.D ),
		"\n\tError: Dimension mismatch between 
			Smolyak Grid and Matrix of Grid Points")	# Check correct number of dims
	# Check x is in bounds
	minX = Inf*ones(Float64,D)
	maxX = zeros(Float64,D)
	for i in 1:N
		for d in 1:D
			minX[d] = min(minX[d],X[i,d])
			maxX[d] = max(maxX[d],X[i,d])
		end
	end
	for d in 1:D 										# Report if X not in Bounds
		>(maxX[d],sg.ub[d]) ? 
			println("\tWarning: X[$d] > Upper Bound") : nothing
		<(minX[d],sg.lb[d]) ?
			println("\tWarning: X[$d] < Lower Bound") : nothing
	end
end

function Psi_fun(sg::SmolyakGrid, k::Int64, SpOut::Int64)
	NBF = size(sg.Binds,1)
	M = maximum(sg.Binds)+1
	if ==(k,2)
		Psi = ones(Float64,sg.NumGrdPts, NBF)
		∂Psi∂z = ones(Float64,sg.NumGrdPts, NBF, sg.D)
		∂2Psi∂z2 = ones(Float64,sg.NumGrdPts, NBF, sg.D, sg.D)
		T = Array(Float64, M, sg.D)
		∂T = similar(T)
		∂2T = similar(T)
		for i in 1:sg.NumGrdPts
			Tn!(T, ∂T, ∂2T, sg.zGrid[i,:], M, sg.D)
			for p in 1:NBF
				for d in 1:sg.D
					Psi!(Psi, T, i, p, d, sg)
					∂Psi∂z!(∂Psi∂z, T, ∂T, i, p, d, sg)
					∂2Psi∂z2!(∂2Psi∂z2, T, ∂T, ∂2T, i, p, d, sg)
				end
			end
		end
		if ==(SpOut,1) 								# Return Sparse Basis Matrix
			Z1idx = sub2ind(size(∂Psi∂z),findn(∂Psi∂z)...)
			Z2idx = sub2ind(size(∂2Psi∂z2),findn(∂2Psi∂z2)...) 
			return Psi, sparsevec(Z1idx,∂Psi∂z[Z1idx]), sparsevec(Z2idx,∂2Psi∂z2[Z2idx])
		else										# Return Full Basis Matrix
			return Psi, ∂Psi∂z, ∂2Psi∂z2
		end
	elseif ==(k,1)
		Psi = ones(Float64, sg.NumGrdPts, NBF)
		∂Psi∂z = ones(Float64, sg.NumGrdPts,NBF, sg.D)
		T = Array(Float64, M, sg.D)
		∂T = similar(T)
		for i in 1:sg.NumGrdPts
			Tn!(T, ∂T, sg.zGrid[i,:], M, sg.D)
			for p in 1:NBF
				for d in 1:sg.D
					Psi!(Psi, T, i, p, d, sg)
					∂Psi∂z!(∂Psi∂z, T, ∂T, i, p, d, sg)
				end
			end
		end
		if ==(SpOut,1) 								# Return Sparse Basis Matrix
			Z1idx = sub2ind(size(∂Psi∂z),findn(∂Psi∂z)...)
			return Psi, sparsevec(Z1idx,∂Psi∂z[Z1idx]), Array(Float64,1,1,1,1)
		else										# Return Full Basis Matrix
			return Psi, ∂Psi∂z, Array(Float64,1,1,1,1)
		end
	elseif ==(k,0) 
		Psi = ones(Float64,sg.NumGrdPts,NBF)
		T = Array(Float64,M,sg.D)
		for i in 1:sg.NumGrdPts
			Tn!(T, sg.zGrid[i,:], M, sg.D)
			for p in 1:NBF
				for d in 1:sg.D
					Psi!(Psi, T, i, p, d, sg)
				end
			end
		end
		return Psi, Array(Float64,1,1,1), Array(Float64,1,1,1,1)
	else
		print("Warning: You must specify number of derivatives to be 0, 1, or 2")
	end
end

function Psi_fun(X::Array{Float64,2}, sg::SmolyakGrid, k::Int64, SpOut::Int64)

	# Convert to z in [-1,1]
	check_domain(X,sg)
	zX = x2z(X,sg.lb,sg.ub)					# Convert to z in [-1,1]

	N,D = size(X) 							# Size of Array of Grid points
	NBF = size(sg.Binds,1)
	M = maximum(sg.Binds)+1
	if ==(k,2)
		Psi = ones(Float64,N, NBF)
		∂Psi∂z = ones(Float64,N, NBF, sg.D)
		∂2Psi∂z2 = ones(Float64,N, NBF, sg.D, sg.D)
		T = Array(Float64, M, sg.D)
		∂T = similar(T)
		∂2T = similar(T)
		for i in 1:N
			Tn!(T, ∂T, ∂2T, zX[i,:], M, sg.D)
			for p in 1:NBF
				for d in 1:sg.D
					Psi!(Psi, T, i, p, d, sg)
					∂Psi∂z!(∂Psi∂z, T, ∂T, i, p, d, sg)
					∂2Psi∂z2!(∂2Psi∂z2, T, ∂T, ∂2T, i, p, d, sg)
				end
			end
		end
		if ==(SpOut,1) 								# Return Sparse Basis Matrix
			Z1idx = sub2ind(size(∂Psi∂z),findn(∂Psi∂z)...)
			Z2idx = sub2ind(size(∂2Psi∂z2),findn(∂2Psi∂z2)...) 
			return Psi, sparsevec(Z1idx,∂Psi∂z[Z1idx]), sparsevec(Z2idx,∂2Psi∂z2[Z2idx])
		else										# Return Full Basis Matrix
			return Psi, ∂Psi∂z, ∂2Psi∂z2
		end
	elseif ==(k,1)
		Psi = ones(Float64, N, NBF)
		∂Psi∂z = ones(Float64, N, sg.D)
		T = Array(Float64, M, sg.D)
		∂T = similar(T)
		for i in 1:N
			Tn!(T, ∂T, zX[i,:], M, sg.D)
			for p in 1:NBF
				for d in 1:sg.D
					Psi!(Psi, T, i, p, d, sg)
					∂Psi∂z!(∂Psi∂z, T, ∂T, i, p, d, sg)
				end
			end
		end
		if ==(SpOut,1) 								# Return Sparse Basis Matrix
			Z1idx = sub2ind(size(∂Psi∂z),findn(∂Psi∂z)...)
			return Psi, sparsevec(Z1idx,∂Psi∂z[Z1idx]), Array(Float64,1,1,1,1)
		else										# Return Full Basis Matrix
			return Psi, ∂Psi∂z, Array(Float64,1,1,1,1)
		end
	elseif ==(k,0) 
		Psi = ones(Float64,N,NBF)
		T = Array(Float64,M,sg.D)
		for i in 1:N
			Tn!(T, zX[i,:], M, sg.D)
			for p in 1:NBF
				for d in 1:sg.D
					Psi!(Psi, T, i, p, d, sg)
				end
			end
		end
		return Psi, Array(Float64,1,1,1), Array(Float64,1,1,1,1)
	else
		print("Warning: You must specify number of derivatives to be 0, 1, or 2")
	end
end

#= Derivative constant over grid points under linear transform =#
function ∂z∂x_fun(sg::SmolyakGrid)
	∂z∂x = 2./(sg.ub - sg.lb)
	∂2z∂x2 = ∂z∂x*∂z∂x'
	return ∂z∂x, ∂2z∂x2 
end



#= ************** =#
#= PolyBasis type =#
#= ************** =#

IntOrVec = Union(Int64,Vector{Int64},Float64,Vector{Float64})
SpArray = Union(SparseMatrixCSC,Array)

type SmolyakBasis
	D 			:: Int64				# Dimensions
	mu 			:: IntOrVec				# Index of mu
	NumPts  	:: Int64				# Number of points in = Num Rows Psi
	NumBasisFun	:: Int64				# Number of basis functions under D, mu = Num Cols Psi
	Psi 		:: Array{Float64,2} 	# Basis Funs
	pinvPsi		:: Array{Float64,2} 	# Inverse Basis Funs
	∂Psi∂z 		:: SpArray 				# 1st derivative basis funs
	∂2Psi∂z2 	:: SpArray			 	# 2nd derivative basis funs
	∂z∂x		:: Vector{Float64} 		# Gradient of transform z2x()
	∂2z∂x2		:: Array{Float64,2}		# Hessian of transform z2x()
	SpOut 		:: Int64				# Sparse Output indicator == 1 if Sparse, 0 Otherwise
	NumDeriv	:: Int64				# Number of derivatives: {0,1,2}

	function SmolyakBasis(sg::SmolyakGrid, NumDeriv::Int64, SpOut::Int64)
		Psi, ∂Psi∂z, ∂2Psi∂z2 = Psi_fun(sg, NumDeriv, SpOut)
		invPsi = inv(Psi)
		NGP, NBF = size(Psi)
		∂z∂x, ∂2z∂x2 = ∂z∂x_fun(sg)
		new(sg.D, sg.mu, NGP, NBF, Psi, invPsi, ∂Psi∂z, ∂2Psi∂z2, ∂z∂x, ∂2z∂x2, SpOut, NumDeriv)
	end
	
	function SmolyakBasis(X::Array{Float64,2}, sg::SmolyakGrid, NumDeriv::Int64, SpOut::Int64)
		Psi, ∂Psi∂z, ∂2Psi∂z2 = Psi_fun(X, sg, NumDeriv, SpOut)
		pinvPsi = pinv(Psi)		
		NGP, NBF = size(Psi)
		∂z∂x, ∂2z∂x2 = ∂z∂x_fun(sg)
		new(sg.D, sg.mu, NGP, NBF, Psi, pinvPsi, ∂Psi∂z, ∂2Psi∂z2, ∂z∂x, ∂2z∂x2, SpOut, NumDeriv)	
	end
	
end

function show(io::IO, sb::SmolyakBasis)
	msg = "\n\tCreated Smolyak Basis:\n"
	msg *= "\t- Dim: $(sb.D), mu: $(sb.mu)\n"
	msg *= "\t- NumPts: $(sb.NumPts)\n"
	msg *= "\t- Number of Basis Functions: $(sb.NumBasisFun)\n"
	if ==(sb.NumDeriv,0) msg *= "\t- No Derivative supplied. Do not call ∂Psi∂z or ∂2Psi∂z2!\n" end
	if ==(sb.NumDeriv,1) msg *= "\t- with ∂Psi∂z. Do not call ∂2Psi∂z2.\n" end
	if ==(sb.NumDeriv,2) msg *= "\t- with ∂Psi∂z & ∂2Psi∂z2\n" end
	print(io, msg)
end

function sparse2full(sb::SmolyakBasis)
	# Automatically Return NumDeriv in sb::SmolyakBasis 
	@assert(sb.SpOut>0,"Derivatives Not Sparse")	 
	if ==(sb.NumDeriv,1) 
		inds,vals = findnz(sb.∂Psi∂z) 
		dims = [sb.NumPts,sb.NumBasisFun,sb.D]
		maxind = inds[end]
		numel = prod(dims)
		return reshape([full(sb.∂Psi∂z),zeros(numel - maxind)],dims...)
	end
	if ==(sb.NumDeriv,2) 
		inds,vals = findnz(sb.∂2Psi∂z2)
		dims = [sb.NumPts,sb.NumBasisFun,sb.D,sb.D] 
		maxind = inds[end]
		numel = prod(dims)
		return reshape([full(sb.∂2Psi∂z2),zeros(numel - maxind)],dims...)
	end
end	

function sparse2full(sb::SmolyakBasis,k::Int64)
	# k specifies which sparse derivative to return to full 
	@assert(sb.SpOut>0,"Derivatives Not Sparse")	 
	if ==(k,1) 
		inds,vals = findnz(sb.∂Psi∂z) 
		dims = [sb.NumPts,sb.NumBasisFun,sb.D]
		maxind = inds[end]
		numel = prod(dims)
		return reshape([full(sb.∂Psi∂z),zeros(numel - maxind)],dims...)
	end
	if ==(k,2) 
		inds,vals = findnz(sb.∂2Psi∂z2)
		dims = [sb.NumPts,sb.NumBasisFun,sb.D,sb.D] 
		maxind = inds[end]
		numel = prod(dims)
		return reshape([full(sb.∂2Psi∂z2),zeros(numel - maxind)],dims...)
	end
end	