#######################################################################################################
#   Parameter estimation using R's optim function
#   Minimal error checking is done.  You should run is.marssMLE() before calling this.
#   Likelihood computation is via  Kalman filter
#######################################################################################################
MARSSoptim = function(MLEobj) {
# This function does not check if user specified a legal MLE object.
  tmp = is.marssMLE(MLEobj)
  if(!isTRUE(tmp)) {
      cat(tmp)
      stop("Stopped in MARSSoptim() because marssMLE object is incomplete or inconsistent.\n", call.=FALSE)
    }
#  for(elem in c("Q","R")){
#    if(dim(MLEobj$model$free[[elem]])[3]>1)
#      stop(paste("Stopped in MARSSoptim() because function does not allow free$",elem," to be time-varying.\n",sep=""), call.=FALSE)      
#  }

#  if(MLEobj$model$diffuse)
#      stop(paste("Stopped in MARSSoptim() because version 3.0 does not allow diffuse=TRUE.\n",sep=""), call.=FALSE)      

  
  ## attach would be risky here since user might have one of these variables in their workspace    
  modelObj=MLEobj[["marss"]]
  y = modelObj$data #must have time going across columns
  free = modelObj$free
  fixed = modelObj$fixed
  tmp.inits = MLEobj$start
  control=MLEobj$control
  par.dims=attr(modelObj,"model.dims")
  m=par.dims[["x"]][1]
  n=par.dims[["y"]][1]
  
  ## Set up the control list for optim; only pass in optim control elements
  control.names=c("trace", "fnscale", "parscale", "ndeps", "maxit", "abstol", "reltol", "alpha", "beta", "gamma", "REPORT", "type", "lmm", "factr","pgtol", "temp", "tmax")
  optim.control=list()
  for(elem in control.names){
  if(!is.null(control[[elem]])) optim.control[[elem]]=control[[elem]]
  }
  if(is.null(control[["lower"]])){ lower = -Inf
  }else lower=control[["lower"]]
  if(is.null(control[["upper"]])){ upper = Inf
  }else upper=control$upper
  if(control$trace==-1)control$trace=0
    
  #The code is used to set things up to use MARSSvectorizeparam to just select inits for the estimated parameters
  tmp.MLEobj = MLEobj
  tmp.MLEobj$par = tmp.inits  #set initial conditions for estimated parameters
  for(elem in c("Q","R","V0")){ #need the chol for these
        f=sub3D(modelObj$fixed[[elem]],t=1) #initial conditions are based on t=1; arbitrary
        d=sub3D(modelObj$free[[elem]],t=1) #free[[elem]] is required to be time constant
        the.par=orig.par=unvec(f+d%*%tmp.inits[[elem]], dim=par.dims[[elem]][1:2])
        is.zero=diag(orig.par)==0   #where the 0s on diagonal are
        if(any(is.zero)) diag(the.par)[is.zero]=1    #so the chol doesn't fail if there are zeros on the diagonal
        the.par=t(chol(the.par))  #transpose of chol
        if(any(is.zero)) diag(the.par)[is.zero]=0  #set back to 0
        if(!is.fixed(free[[elem]])){
          tmp.MLEobj$par[[elem]] = solve(crossprod(d))%*%t(d)%*%(vec(the.par)-f) #from f+Dm=M and if f!=0, D==0
        }else{ tmp.MLEobj$par[[elem]] = matrix(0,0,1) }
        #when being passed to optim, pars for var-cov mat is the chol, so need to reset free and fixed
        #step 1, compute the D matrix corresponding to upper.tri=0 at in t(chol)
        tmp.list.mat=fixed.free.to.formula(sub3D(tmp.MLEobj$marss$fixed[[elem]],t=1),sub3D(tmp.MLEobj$marss$free[[elem]],t=1),par.dims[[elem]][1:2])
        tmp.list.mat[upper.tri(tmp.list.mat)]=0   #set upper tri to zero
        tmp.MLEobj$marss$free[[elem]]=convert.model.mat(tmp.list.mat)$free
        #step 2, set the fixed part to the t(chol); need to take the chol of fixed elements; upper tri will be set to 0
        tmp.fixed=unvec(f,dim=par.dims[[elem]][1:2])  #by definition the estimated elements will have f=0 since this is a varcov mat
        is.zero = diag(tmp.fixed)==0 #need to deal with zeros on diagonal
        if(any(is.zero)) diag(tmp.fixed)[is.zero]=1    #so the chol doesn't fail if there are zeros on the diagonal
        chol.fixed=t(chol(tmp.fixed)) #chol of the fixed part of var-cov matrix
        if(any(is.zero)) diag(chol.fixed)[is.zero]=0  #reset back to zero   
        tmp.MLEobj$marss$fixed[[elem]][,,1]=vec(chol.fixed) #above required that dim3 of fixed$Q and R is 1
    }
  # will return the inits only for the estimated parameters
  pars = MARSSvectorizeparam(tmp.MLEobj)
    
  if(substr(tmp.MLEobj$method,1,4)=="BFGS"){ optim.method="BFGS" }else{ optim.method="something wrong" }

  kf.function=MLEobj$fun.kf #used for printing
  optim.output = try(optim(pars, neglogLik, MLEobj=tmp.MLEobj, method = optim.method, lower = lower, upper = upper, control = optim.control, hessian = FALSE), silent=TRUE  )

  if(class(optim.output)=="try-error"){ #try MARSSkfss if the user did not use it
    if( MLEobj$fun.kf!="MARSSkfss" ){  #if user did not request MARSSkf
    cat("MARSSkfas returned error.  Trying MARSSkfss.\n")
    tmp.MLEobj$fun.kf="MARSSkfss"
    kf.function="MARSSkfss" #used for printing
    optim.output = try(optim(pars, neglogLik, MLEobj=tmp.MLEobj, method = optim.method, lower = lower, upper = upper, control = optim.control, hessian = FALSE), silent=TRUE  )
    }
  }
  
  #error returned
  if(class(optim.output)=="try-error"){
    optim.output = list(convergence=53, message=c("MARSSkfas and MARSSkfss tried to compute log likelihood and encountered numerical problems.\n", sep=""))
   }

       
  MLEobj.return=MLEobj
  MLEobj.return$iter.record=optim.output$message
#   MLEobj.return$control=MLEobj$control
#   MLEobj.return$model=MLEobj$model
  MLEobj.return$start = tmp.inits #set to what was used here
  MLEobj.return$convergence = optim.output$convergence
  if(optim.output$convergence %in% c(1,0)) {
      if((!control$silent || control$silent==2) && optim.output$convergence==0) cat(paste("Success! Converged in ",optim.output$counts[1]," iterations.\n","Function ",kf.function," used for likelihood calculation.\n",sep=""))
      if((!control$silent || control$silent==2) && optim.output$convergence==1) cat(paste("Warning! Max iterations of ", control$maxit," reached before convergence.\n","Function ", kf.function, " used for likelihood calculation.\n", sep=""))

      tmp.MLEobj = MARSSvectorizeparam(tmp.MLEobj, optim.output$par)
      #par has the fixed and estimated values using t chol of Q and R
      
      #back transform Q, R and V0 if needed from chol form to usual form
  for(elem in c("Q","R","V0")){   #this works because by def fixed and free blocks of var-cov mats are independent
     if(!is.fixed(modelObj$free[[elem]])) #get a new par if needed
        {
        d=sub3D(tmp.MLEobj$marss$free[[elem]],t=1) #this will be the one with the upper tri zero-ed out but ok since symmetric
        par.dim=par.dims[[elem]][1:2]
        L=unvec(tmp.MLEobj$marss$free[[elem]][,,1]%*%tmp.MLEobj$par[[elem]],dim=par.dim) #this by def will have 0 row/col at the fixed values
        the.par = tcrossprod(L)#L%*%t(L)
        tmp.MLEobj$par[[elem]]=solve(crossprod(d))%*%t(d)%*%vec(the.par)
        }
    } #end for
    
      pars = MARSSvectorizeparam(tmp.MLEobj)  #now the pars values are adjusted back to normal scaling
      #now put the estimated values back into MLEobj; fixed values set by $fixed
      MLEobj.return = MARSSvectorizeparam(MLEobj.return, pars)
      kf.out = MARSSkf(MLEobj.return)
      }else{
      if(optim.output$convergence==10) optim.output$message=c("degeneracy of the Nelder-Mead simplex\n",paste("Function ",kf.function," used for likelihood calculation.\n",sep=""),optim.output$message)
      optim.output$counts = NULL      
      if( !control$silent ) cat("MARSSoptim() stopped with errors. No parameter estimates returned.\n")
      if( control$silent==2 ) cat("MARSSoptim() stopped with errors. No parameter estimates returned. See $errors in output for details.\n")
 
      MLEobj.return$par = NULL
      MLEobj.return$errors = optim.output$message
      kf.out = NULL
      }
  
  if(!is.null(kf.out)){
    if(control$trace>0) MLEobj.return$kf = kf.out
    MLEobj.return$states = kf.out$xtT
    MLEobj.return$numIter = optim.output$counts[1]
    MLEobj.return$logLik = kf.out$logLik
  }
  MLEobj.return$method = MLEobj$method
  
  ## Add AIC and AICc to the object
  if(!is.null(kf.out)) MLEobj.return = MARSSaic(MLEobj.return)

# I don't want these added here
#   ## Calculate confidence intervals based on state std errors, see caption of Fig 6.3 (p337) Shumway and Stoffer
#   if(!is.null(kf.out)){
#     TT = dim(MLEobj.return$marss$data)[2]; m = dim(MLEobj.return$marss$fixed$x0)[1]
#     if(m == 1) states.se = sqrt(matrix(kf.out$VtT[,,1:TT], nrow=1))
#     if(m > 1) {
#       states.se = matrix(0, nrow=m, ncol=TT)
#       for(i in 1:TT) states.se[,i] = t(sqrt(takediag(kf.out$VtT[,,i])))
#     }
#     MLEobj.return$states.se = states.se
#     }
    
  return(MLEobj.return)
}

neglogLik = function(x, MLEobj=NULL){  #NULL assignment needed for optim call syntax
#MLEobj is tmp.MLEobj so has altered free and fixed
#x is the paramvector
    MLEobj = MARSSvectorizeparam(MLEobj, x)
    free=MLEobj$marss$free
    fixed=MLEobj$marss$fixed
    pars=MLEobj$par
    par.dims=attr(MLEobj[["marss"]],"model.dims")
    m=par.dims[["x"]][1]
    n=par.dims[["y"]][1]
  for(elem in c("Q","R","V0")){
     if(!is.fixed(free[[elem]])) #recompute par if needed since par in parlist is transformed
        {        
        d=sub3D(free[[elem]],t=1) #this will be the one with the upper tri zero-ed out but ok since symmetric
        par.dim=par.dims[[elem]][1:2]
        #t=1 since D not allowed to be time-varying?
        L=unvec(free[[elem]][,,1]%*%pars[[elem]],dim=par.dim) #this by def will have 0 row/col at the fixed values
        the.par = tcrossprod(L)#L%*%t(L)
        #from f+Dm=M and if f!=0, D==0 so can leave off f
        MLEobj$par[[elem]]=solve(crossprod(d))%*%t(d)%*%vec(the.par)
        #solve(t(d)%*%d)%*%t(d)%*%vec(the.par)
        }
    } #end for over elem
    #kfsel selects the Kalman filter / smoother function based on MLEobj$fun.kf
    negLL = MARSSkf( MLEobj, only.logLik=TRUE, return.lag.one=FALSE )$logLik
    
    -1*negLL
     }
