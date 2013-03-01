###########################################################################################################################
#   diag helper functions
###########################################################################################################################
#fast diagonal calc
isDiag = function(x){ all(x[!diag(nrow(x))] == 0) }

takediag = function(x)
  ############# Function to take the diagonal; deals with R trying to think too much with diag()
{
  if(length(x)==1) return(x)
  if(!is.matrix(x)) stop("takediag: function requires a 2D matrix")
  d1=dim(x)[1]
  return(x[1 + 0:(d1 - 1)*(d1 + 1)])  #faster diag
}

makediag = function(x,nrow=NA)
  ############# Function to make a diagonal matrix; deals with R trying to think too much with diag()
{
  if(length(x)==1) 
  {
    if(is.na(nrow)) nrow=1
    return(diag(c(x),nrow))
  }
  if((is.matrix(x) | is.array(x)))
    if(!(dim(x)[1]==1 | dim(x)[2]==1))  stop("makediag: error in call to makediag; x is not vector")
  if(is.na(nrow)) nrow=length(x)
  return(diag(c(x),nrow))
}

############ The following functions are for testing the shapes of matrices
# these functions use as.character(x) to deal with the "feature" that in R (.01 + .14) == .15 is FALSE!!
is.equaltri = function(x) {
  #requires 2D matrix ; works on numeric, character or list matrices
  if(!is.matrix(x)) return(FALSE) #x must be 2D matrix; is.matrix returns false for 3D array
  #warning this returns TRUE if x is 1x1
  x = as.matrix(unname(x))
  if(dim(x)[1]==1 & dim(x)[2]==1) return(TRUE)
  if(dim(x)[1] != dim(x)[2]) return(FALSE)  #must be square
  #equal and non zero on diagonal; equal (zero ok) but different from diagonal on off-diagonal
  if(any(is.na(x))) return(FALSE)
  if(length(unique(as.character(x)))!=2) return(FALSE) #must be only 2 numbers in the matrix
  if(is.diagonal(x)) return(TRUE)  #diagonal is special case of equaltri
  #not diagonal
  diagx = takediag(x)
  tmp=table(as.character(diagx))
  namestmp = names(tmp)
  if(length(tmp)==1){
    if(length(unique(as.character(x)))!=2) return(FALSE) #not equal tri
    if(length(unique(as.character(x)))==2) return(TRUE) 
  }
  return(FALSE) #length(tmp)!=1; must be only 1 number on diagonal
}

is.diagonal = function(x, na.rm=FALSE) {
  #works on numeric matrices or list matrices
  #na.rm=TRUE means that NAs on the DIAGONAL are ignored
  #ok if there are 0s on diagonal
  if(!is.matrix(x)) return(FALSE) #x must be 2D matrix; is.matrix returns false for 3D array
  x=as.matrix(unname(x))
  if(na.rm==FALSE && any(is.na(x))) return(FALSE)
  nr = dim(x)[1]; nc = dim(x)[2];
  if(nr != nc) return(FALSE) #must be square
  #ok if there are 0s on diagonal
  #if(isTRUE( any(diagx==0) ) ) return(FALSE)
  dimx = dim(x)[1]
  if(length(x)==1) return(TRUE)
  x1=matrix(sapply(x,identical,0),dimx,dimx)
  if(isTRUE( all(x1[lower.tri(x)]) ) && isTRUE( all(x1[upper.tri(x)]) ) ) return(TRUE) #diagonal
  return(FALSE)
}


is.identity = function(x, dim=NULL) {
  #works on 2D numeric, character or list matrices; "1" is not identical to 1 however
  #if dim!=NULL, it means that a vec version of the matrix was passed in so dim specifies what the dim of the original matrix is
  if(!is.matrix(x)) stop("is.identity: argument must be a matrix") #x must be 2D matrix; is.matrix returns false for 3D array
  if(!is.null(dim)){
    if(length(dim)!=2) stop("is.identity: dim must be length 2 vector")
    if(!is.numeric(dim)) stop("is.identity: dim must be numeric")
    if(!all(sapply(dim, is.wholenumber)) | !all(dim>=0)) stop("is.identity: dim must be positive whole number")
    if(length(x)!=(dim[1]*dim[2])) stop("is.identity: dim is not the right size.  length(x)=dim1*dim2")
    x=unvec(x,dim=dim)
  }
  if(!is.diagonal(x)) return(FALSE)
  if(!all(sapply(takediag(x),identical,1))) return(FALSE)
  return(TRUE)
}

is.validvarcov = function(x, method="kem"){
  #works on numeric and list matrices
  #x must be 2D matrix; is.matrix returns false for 3D array
  if(!is.matrix(x)) return(list(ok=FALSE, error="not a matrix "))
  x=as.matrix(unname(x))
  #no NAs
  if(any(is.na(x))) return(list(ok=FALSE, error="NAs are not allowed in varcov matrix "))
  nr = dim(x)[1]; nc = dim(x)[2];
  #square
  if(nr != nc) return(list(ok=FALSE, error="matrix is not square and all varcov matrices are "))
  #symmetric
  if(!isTRUE(all.equal(x,t(x)))) return(list(ok=FALSE, error="matrix is not symmetric and all varcov matrices are "))
  #all valid varcov are some kind of blockdiag
  if(!is.blockdiag(x)) return(list(ok=FALSE, error="matrix is not block diagonal and all varcov matrices are "))
  #any diagonal elements that are 0, must have all 0 row and col
  zero.diag=unlist( lapply(takediag(x),function(x){identical(x,0)} ))
  if(any(zero.diag)){
    #only need to check row, since matrix is symmetric
    if(!all(unlist(lapply(x[zero.diag, ],function(x){identical(x,0)}))))
      return(list(ok=FALSE, error="zero diagonal elements must have zero rows and columns "))
    #get rid of the zero row/cols
    x=x[!zero.diag,!zero.diag,drop=FALSE]
    nr = dim(x)[1]; nc = dim(x)[2];
    if(nr == 0) return(list(ok=TRUE, error=NULL))
  }
  #this tests the blocks to see if there is mixing of fixed and estimated elements
  #makes a lists of the block estimates to test that blocks with shared values are identical
  tmpx = x
  blocks=list()
  blockvals=list()
  isdiag = c()
  for(i in 1:nr){
    block = which(!sapply(tmpx[1,,drop=FALSE],identical,0))
    blocks=c(blocks,list(block))
    this.block=tmpx[block,block,drop=FALSE]
    vals = this.block[upper.tri(this.block, diag=TRUE)]
    #within a block, you cannot have fixed and estimated values.  They have to be one or the other
    if(!(all(unlist(lapply(vals, is.numeric))) | all(unlist(lapply(vals, is.character)))))
      return(list(ok=FALSE, error="numeric (fixed) and estimated values cannot mixed in a varcov matrix "))
    #if method="BFGS", then blocks must be diagonal or unconstrained, if estimated
    if(method=="BFGS" & is.character(vals[[1]])){ #only test first since all the same class
      if(any(duplicated(unlist(vals)))) return(list(ok=FALSE, error="when method=BFGS, no constraints can be put on varcov blocks except being diagonal "))
    }
    if(is.numeric(vals[[1]])){ #then the block is numeric and must be positive definite
      pos.flag=FALSE
      test.block = matrix(as.numeric(this.block),dim(this.block)[1],dim(this.block)[2])
      tmp = try( eigen(test.block, only.values=TRUE), silent=TRUE )
      if(class(tmp)=="try-error") pos.flag=TRUE
      else if(!all(tmp$values >= 0)) pos.flag=TRUE
      #if there is a problem
      if(pos.flag){
        return(list(ok=FALSE, error="One of the fixed blocks within the varcov matrix is not positive-definite "))
      }
      }
    isdiag= c(isdiag, length(block)==1)
    blockvals=c(blockvals, list( unlist(vals[unlist(lapply(vals,is.character))] )))
    notblock = which(sapply(tmpx[1,,drop=FALSE],identical,0))
    if(length(notblock)==0) break
    tmpx=tmpx[notblock,notblock,drop=FALSE]
    dim(tmpx) = c(length(notblock),length(notblock))
  }
  for(i in 1:length(blocks)){
    #find blocks where there are shared values
    shared = unlist(lapply(blockvals, function(x){any(x %in% blockvals[[i]])}))
    #shared are any blocks with shared values; exclude itself
    shared[i]=FALSE
    if(any(shared)){ #then must be identical
      if(all(isdiag[shared])) next #its ok since sharing only across diagonal 1x1 blocks
    }
    #go through list of blocks with which there are shared elements and check they are identical
    tmp=lapply(blockvals[shared],function(x){ identical(x, blockvals[[i]])})
    #it'll be a list, so unlist
    if(!all(unlist(tmp))) return(list(ok=FALSE, error="there are shared elements across non-identical blocks "))
  }

  return(list(ok=TRUE, error=NULL)) #got through the check without returning FALSE, so OK
  
}

is.blockdiag = function(x) {
  #works on numeric and list matrices
  if(!is.matrix(x)) return(FALSE) #x must be 2D matrix; is.matrix returns false for 3D array
  x=as.matrix(unname(x))
  if(any(is.na(x))) return(FALSE)
  nr = dim(x)[1]; nc = dim(x)[2];
  if(nr != nc) return(FALSE)
  #0s on diag are ok
  #if(any(sapply(takediag(x),identical,0))) return(FALSE)  #no zeros allowed on diagonal
  
  #special cases. 1. diagonal
  if(is.diagonal(x)) return(TRUE)
  
  #special cases. 2. all non-zero
  if(!any(sapply(x,identical,0))) return(TRUE)
  
  tmpx = x
  nr=dim(x)[1]
  for(i in 1:nr){
    block = which(!sapply(tmpx[i,,drop=FALSE],identical,0))
    if(any(sapply(tmpx[block,block,drop=FALSE],identical,0)) ) return(FALSE)
    notblock = which(sapply(tmpx[i,,drop=FALSE],identical,0))
    if(!all(sapply(tmpx[notblock,block,drop=FALSE],identical,0))) return(FALSE)
    if(!all(sapply(tmpx[block,notblock,drop=FALSE],identical,0))) return(FALSE)
  }
  
  return(TRUE)
}

is.design = function(x, strict=TRUE, dim=NULL, zero.rows.ok=FALSE, zero.cols.ok=FALSE) {  #can be 2D or 3D
  #strict means only 0,1; not strict means 1s can be other numbers
  #zero.rows.ok means that the rowsums can be 0 (if that row is fixed, say)
  #if dim not null it means a vec-ed version of the matrix was passed in so dim is dim of orig matrix
  #can be a list matrix; 
  if(!is.array(x)) stop("is.design: function requires a 2D or 3D matrix") #x can be 2D or 3D matrix
  if(length(dim(x))==3)
    if(dim(x)[3]!=1){ stop("is.design: if 3D, 3rd dim of matrix must be 1")
    }else{ x=matrix(x, dim(x)[1], dim(x)[2]) }
  if(!is.null(dim)){
    if(length(dim)!=2) stop("is.design: dim must be length 2 vector")
    if(!is.numeric(dim)) stop("is.design: dim must be numeric")
    if(!all(sapply(dim, is.wholenumber)) | !all(dim>=0)) stop("is.design: dim must be positive whole number")
    if(length(x)!=(dim[1]*dim[2])) stop("is.design: dim is not the right size.  length(x)=dim1*dim2")
    x=unvec(x,dim=dim)
  }
  x=as.matrix(unname(x)) #so that all.equal doesn't fail
  if(any(is.na(x))) return(FALSE)
  if(!is.numeric(x)) return(FALSE)  #must be numeric
  if(any(is.nan(x))) return(FALSE)
  if(!strict){
      is.zero = !x
#     is.zero = sapply(lapply(x,all.equal,0),isTRUE) #funky to use near equality
      x[!is.zero]=1 
  } 
  if(!all(x %in% c(1,0))) return(FALSE)  #above ensured that all numeric
  if(!zero.cols.ok & dim(x)[1]<dim(x)[2]) return(FALSE) #if fewer rows than columns then not design
  if(is.list(x)) x=matrix(unlist(x),dim(x)[1],dim(x)[2])
  tmp = rowSums(x)
  if(!zero.rows.ok & !isTRUE(all.equal(tmp,rep(1,length(tmp))))) return(FALSE)
  if(zero.rows.ok & !isTRUE(all(tmp %in% c(0,1)))) return(FALSE)
  tmp = colSums(x)
  if(!zero.cols.ok & any(tmp==0) ) return(FALSE)
  return( TRUE )
}

is.fixed = function(x, by.row=FALSE) { #expects the D (free) matrix; can be 3D or 2D; can be a numeric list matrix
  #by.row means it reports whether each row is fixed 
  if(!is.array(x)) stop("is.fixed: function requires a 2D or 3D free(D) matrix")
  if(!(length(dim(x)) %in% c(2,3))) stop("is.fixed: function requires a 2D or 3D free(D) matrix")
  if(!is.numeric(x)) stop("is.fixed: free(D) must be numeric")  #must be numeric
  if(any(is.na(x)) | any(is.nan(x))) stop("is.fixed: free(D) cannot have NAs or NaNs")
  if(dim(x)[2]==0){ 
    if(!by.row){ return(TRUE) }else{ return(rep(TRUE,dim(x)[1])) }
  }
  if(all(x==0)) return(TRUE)
  if(by.row) return( apply(x==0,1,all) )
  return(FALSE)
}

is.zero=function (x) 
{
  (abs(x) < .Machine$double.eps)
}

vec=function (x) 
{
  if (!is.array(x)) stop("vec:arg must be a 2D or 3D matrix")
  len.dim.x=length(dim(x))
  if (!(len.dim.x==2 | len.dim.x==3)) stop("vec: arg must be a 2D or 3D matrix")
  if (len.dim.x == 2){
    attr(x,"dim")=c(length(x),1)
    return(x)
  }
  #else it is an array
  return(array(x, dim = c(length(x[, , 1]), 1, dim(x)[3])))
}

unvec = function(x,dim=NULL){
  if(1==0){
    if(!is.vector(x) & !is.array(x)) stop("unvec: arg must be a vector or nx1 matrix)")
    
    if(is.array(x) & length(dim(x))>1){
      dim2p=dim(x)[2:length(dim(x))]
      if(any(dim2p!=1)) stop("unvec: if arg is a matrix it must be nx1 (or nx1x1)")
    }
    if(is.null(dim)) dim=c(length(x),1)
    if(!is.vector(dim) & length(dim)!=2) stop("unvec: dim must be a vector of length 2: c(nrows,ncols)")
    if(!is.numeric(dim)) stop("unvec: dim must be numeric")
    #if(!all(is.wholenumber(dim))) stop("unvec: dim must be a vector of 2 integers")
    if(dim[1]*dim[2]!=length(x)) stop("unvec: num elements in arg greater than dim[1]*dim[2]")
  }
  return(matrix(x,dim[1],dim[2]))
}

parmat = function( MLEobj, elem=c("B","U","Q","Z","A","R","x0","V0"), t=1, dims=NULL, model.loc="marss" ){
  #returns a list where each el in elem is an element.  Returns a 2D matrix.
  #needs MLEobj$marss and MLEobj$par
  #dims is an optional argument to pass in to tell parmat the dimension of elem (if it is not a MARSS model)
  #f=MLEobj$marss$fixed
  model=MLEobj[[model.loc]]
  pars=MLEobj[["par"]]
  f=model[["fixed"]]
  d=model[["free"]]
  if(!all(elem %in% names(f))) stop("parmat: one of the elem not one of the model parameter names.")
  par.mat=list()
  if(is.null(dims)) dims = attr(model, "model.dims")
  if(!is.list(dims) & length(elem)!=1) stop("parmat: dims needs to be a list if more than one elem passed in")
  if(!is.list(dims) & length(elem)==1){ tmp=dims; dims=list(); dims[[elem]]=tmp }
  for(el in elem){
    if(length(t)>1){ par.mat[[el]] = array(as.numeric(NA), dim=c(dims[[el]][1:2],length(t))) }
    for(i in t){
      if(dim(d[[el]])[3]==1){
        delem=d[[el]]
        attr(delem,"dim")=attr(delem,"dim")[1:2]
      }else{ delem=d[[el]][,,i] }
      if(dim(f[[el]])[3]==1){
        felem=f[[el]]
        attr(felem,"dim")=attr(felem,"dim")[1:2]
      }else{ felem=f[[el]][,,i] }
      if(length(t)==1){
        par.mat[[el]] = matrix(felem + delem%*%pars[[el]],dims[[el]][1],dims[[el]][2])
      }else{ 
        par.mat[[el]][,,i] = matrix(felem + delem%*%pars[[el]],dims[[el]][1],dims[[el]][2])
      }
    }
  }
  return(par.mat)
}

is.wholenumber = function(x, tol = .Machine$double.eps^0.5) {
  if(!is.numeric(x)) return(FALSE)
  test = abs(x - round(x)) < tol
  if(any(is.na(test))) return(FALSE)
  return(test)
}

Imat = function(x) return(diag(1,x))

rwishart=function (nu, V) 
{
  #function adapted from bayesm package
  #author Peter Rossi, Graduate School of Business, University of Chicago
  m = nrow(V)
  df = (nu + nu - m + 1) - (nu - m + 1):nu
  if (m > 1) {
    T = diag(sqrt(rchisq(c(rep(1, m)), df)))
    T[lower.tri(T)] = rnorm((m * (m + 1)/2 - m))
  }else {
    T = sqrt(rchisq(1, df))
  }
  U = chol(V)
  C = t(T) %*% U
  return(crossprod(C))
}

mystrsplit=function(x){
  stre=c()
  e=unlist(strsplit(x,split=""))
  j=1
  for(i in 1:length(e)){
    if(e[i]=="+"){
      if((i-1)<j) stop("mystrsplit: something is wrong with the eqn form.  must be a+b1*p1+b2*p2...")
      stre=c(stre,paste(e[j:(i-1)],collapse=""),"+")
      j=i+1
    }
    if(e[i]=="*"){
      if((i-1)<j) stop("mystrsplit: something is wrong with the eqn form.  must be a+b1*p1+b2*p2...")
      stre=c(stre,paste(e[j:(i-1)],collapse=""),"*")
      j=i+1
    }
  }
  stre=c(stre,paste(e[j:i],collapse=""))
  return(stre)
}

convert.model.mat=function(param.matrix){
  #uses the list matrix version of a parameter to make the fixed(f) and free(D) matrices; vec(param)=f+D*p
  #will take a numeric, character or list matrix
  #returns fixed and free matrices that are 3D as required for a marssMODEL form=marss model
  #if param.matrix is 3D then dim3 of f and D will equal dim3 of model.matrix
  #if param.matrix is 2D then dim3 of f and D will equal 1
  if(!is.array(param.matrix)) stop("convert.model.mat: function requires a 2D or 3D matrix")
  if(!(length(dim(param.matrix)) %in% c(2,3))) stop("convert.model.mat: arg must be a 2D or 3D matrix")
  Tmax=1
  if(length(dim(param.matrix))==3) Tmax=dim(param.matrix)[3]
  dim.f1=dim(param.matrix)[1]*dim(param.matrix)[2]
  fixed=array(0,dim=c(dim.f1,1,Tmax))
  #for(t in 1:Tmax){
  c=param.matrix
  varnames=c()
  d=array(sapply(c,is.character),dim=dim(c))
  f=array(list(0),dim=dim(c))
  f[!d]=c[!d]
  f=vec(f)
  f=array(unlist(f),dim=c(dim.f1,1,Tmax))
  
  is.char=c()
  if(any(d)){ #any character? otherwise all numeric
    is.char=which(d)
    if(any(grepl("[*]",c) | grepl("[+]",c))){  #any * or +, then do this really slow code to find the fixed bits
      for(i in is.char){
        e=mystrsplit(c[[i]])
        firstel=suppressWarnings(as.numeric(e[1]))
        if( length(e)==1 ){ e=c("0","+","1","*",e)
        }else{ if(is.na(firstel) || !is.na(firstel) & e[2]=="*" ) e=c("0","+",e) }
        pluses=which(e=="+")
        afterplus=suppressWarnings(as.numeric(e[pluses+1]))
        if(any(is.na(afterplus))){
          k=1
          for(j in pluses[is.na(afterplus)]){
            e=append(e, c("1","*"), after = j+(k-1)*2)
            k=k+1
          }
        }
        stars=which(e=="*")
        pluses=which(e=="+")
        if(length(stars)!=length(pluses)) stop("convert.model.mat: must use eqn form a+b1*p1+b2*p2...; extra p's can be left off")
        c[[i]]=paste(e,collapse="")
        f[[i]]=as.numeric(e[1])
        varnames=c(varnames,e[stars+1])      
      }
      varnames=unique(varnames)
    }else{
      varnames=unique(unlist(c[is.char]))
    }
  } 
  
  
  free=array(0,dim=c(dim.f1,length(varnames),Tmax))
  if(any(d)){ #any character? otherwise all numeric
    if(any(grepl("[*]",c) | grepl("[+]",c))){
      for(i in is.char){
        e=mystrsplit(c[[i]])
        stars=which(e=="*")
        e.vars=e[stars+1]
        
        for(p in varnames){
          drow=i%%dim.f1
          if(drow==0) drow=dim.f1
          if(p %in% e.vars) free[drow,which(p==varnames),ceiling(i/dim.f1)]=sum(as.numeric(e[(stars-1)[e[stars+1]==p]]))
        }
      }
    }else{ #no * or +? Then this is faster
      for(p in varnames){
        i = which(sapply(c,function(x){identical(x,p)})) #which(c==p); c==p fails if user uses names like "1"
        drow=i%%dim.f1
        drow[drow==0]=dim.f1
        free[drow,which(p==varnames),ceiling(i/dim.f1)]=1
      }
    }
  } #any characters?
  fixed=f
  colnames(free)=varnames 
  return(list(fixed=fixed,free=free))
}

fixed.free.to.formula=function(fixed,free,dim){ #dim is the 1st and 2nd dims of the outputed list matrix
  #this will take a 3D or 2D 
  if(length(dim)!=2) stop("fixed.free.to.formula: dim must be a length 2 vector")
  if(is.null(dim(fixed))) stop("fixed.free.to.formula: fixed must be matrix")
  if( !(length(dim(fixed)) %in% c(2,3)) ) stop("fixed.free.to.formula: fixed must be 2 or 3D matrix")
  if(is.null(dim(free))) stop("fixed.free.to.formula: free must be matrix")
  if( !(length(dim(free)) %in% c(2,3)) ) stop("fixed.free.to.formula: free must be 2 or 3D matrix")
  Tmax = 1
  if(length(dim(fixed))==2) fixed=array(fixed,dim=c(dim(fixed),1))
  colnames.free=colnames(free)
  if(length(dim(free))==2){ free=array(free,dim=c(dim(free),1)); colnames(free)=colnames.free }
  Tmax=max(Tmax,dim(fixed)[3],dim(free)[3])
  
  #turns a fixed/free pair to a list (possibly time-varying) matrix describing that MARSS parameter structure
  model=array(list(0),dim=c(dim(fixed)[1],dim(fixed)[2],Tmax)) 
  for(t in 1:Tmax){
    free.t = min(t,dim(free)[3])
    fixed.t = min(t,dim(fixed)[3])
    for(i in 1:dim(fixed)[1]){
      if(all(free[i,,free.t]==0) | dim(free)[2]==0){ model[i,1,t]=fixed[i,1,fixed.t]
      }else{
        if(fixed[i,1,fixed.t]==0) tmp=c() else tmp=c(as.character(fixed[i,1,fixed.t]))
        colnames.free=colnames(free)
        if(is.null(colnames(free))) colnames.free=as.character(1:dim(free)[2])
        for(j in 1:dim(free)[2]){
          if(free[i,j,free.t]!=0){
            if(is.null(tmp) & free[i,j,free.t]==1){ tmp=colnames.free[j]
            }else{ tmp=c(tmp,"+",as.character(free[i,j,free.t]),"*",colnames.free[j]) }
          }
        }
        if(tmp[1]=="+") tmp=tmp[2:length(tmp)]
        model[i,1,t]=paste(tmp,collapse="")
      }
    }
  }
  #return 2D matrix if Tmax is 1
  if(Tmax==1) model=array(model,dim=dim)
  else model=array(model,dim=c(dim,Tmax))
  return(model)
} 

#From Alberto Monteiro posted in the R forum
matrix.power <- function(x, n)
{
  # test if mat is a square matrix
  # treat n < 0 and n = 0 -- this is left as an exercise
  # trap non-integer n and return an error
  if (n == 1) return(x)
  result <- diag(1, ncol(x))
  while (n > 0) {
    if (n %% 2 != 0) {
      result <- result %*% x
      n <- n - 1
    }
    x <- x %*% x
    n <- n / 2
  }
  return(result)
}

#function to take one time from a 3D matrix without R restructuring it
#Slower
# sub3D=function(x,dim1,dim2,t=1){
#   #if(length(t)>1) stop("sub3D: t must be length 1")
#   if(t==1 & missing(dim1) & missing(dim2) & dim(x)[3]==1){
#     dimns=attr(x,"dimnames")[1:2]
#     attr(x,"dim")=attr(x,"dim")[1:2]
#     attr(x,"dimnames")=dimns
#     return(x)
#   }else{
#     mat=x[dim1,dim2,t,drop=FALSE]
#   }
#   dims=dim(mat)
#   return(matrix(mat,dims[1],dims[2],dimnames=list(rownames(mat),colnames(mat))))
# }

# #old with dim1 and dim2
# sub3D=function(x,dim1,dim2,t=1){
#   if(!missing(dim1) | !missing(dim2)){
#     x=x[dim1,dim2,t,drop=FALSE]
#   }
#   x.dims = dim(x)
#   if(x.dims[1]!=1 & x.dims[2]!=1){
#     x=x[dim1,dim2,t]
#     return(x)
#   }else{
#     x=x[dim1,dim2,t,drop=FALSE]
#     dimns=attr(x,"dimnames")[1:2]
#     attr(x,"dim")=attr(x,"dim")[1:2]
#     attr(x,"dimnames")=dimns
#     return(x)
#   }
# }

#faster
sub3D=function(x,t=1){
  x.dims = dim(x)
  if(x.dims[1]!=1 & x.dims[2]!=1){
    x=x[,,t]
    return(x)
  }else{
    x=x[,,t,drop=FALSE]
    dimns=attr(x,"dimnames")[1:2]
    attr(x,"dim")=attr(x,"dim")[1:2]
    attr(x,"dimnames")=dimns
    return(x)
  }
}

#replace 0 diags with 0 row/cols; no error checking.  Need square symm matrix
pcholinv = function(x){
  dim.x=dim(x)[1]
  diag.x=x[1 + 0:(dim.x - 1)*(dim.x + 1)]
  if(any(diag.x==0)){
    if(any(diag.x!=0)){
      b=chol2inv(chol(x[diag.x!=0,diag.x!=0]))
      OMG.x=diag(1,dim.x)[diag.x!=0,,drop=FALSE]
      inv.x=t(OMG.x)%*%b%*%OMG.x
    }else{
      inv.x=matrix(0,dim.x,dim.x)
    }
  }else{
    inv.x=chol2inv(chol(x))
  }
  return(inv.x)
}

#pseudoinverse based on thin svd; x%*%x*%*%x =  x; x%*%x* not nec. I
pinv = function(x){
  dimx=dim(x)
  b=svd(x)
  tol=1.11e-15*max(dimx)*max(b$d)
  dp = b$d
  dp[dp<=tol]=0
  dp[dp>tol]=1/dp[dp>tol]  
  sigma.star=matrix(0,dimx[1],dimx[1])
  xinv=b$v%*%makediag(dp)%*%t(b$u)
  return(xinv)
}

#report on whether the linear system y=Ax is underconstrained, overconstrained, or 1 unique solution
is.solvable = function(A,y=NULL){
  dimA=dim(A)
  b=svd(A)
  tol=1.11e-16*max(dimA)*max(b$d)
  if(sum(b$d>tol)<dimA[2]) return("underconstrained")
  if(length(b$d)<dimA[2]){
    if(is.null(y)){ return("overconstrained")
    }else{
      if(!all(A%*%pinv(A)%*%y-y < tol)){ return("no solution")
      }else{ return("unique") }
    }
  }  
  return("unique")
}

all.equal.vector = function(x){
  all(sapply( as.list(x[-1]), FUN=function(z) {identical(z, unlist(x[1]))}))
}
