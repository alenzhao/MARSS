#######################################################################################################
#   Kalman filter and smoother function based on Koopman and Durbin's KFAS package
#   y_t = Z_t * alpha_t + eps_t (observation equation)
#   alpha_t+1 = T_t * alpha_t + R_t * eta_t(transition equation)
#   Note the different time indexing for transition equation
#   The y_t,y_{t-1} stacked vector with parameters vectors reconfigured to output the
#     smoothed lag-1 covariances needed by the EM algorithm
#######################################################################################################
MARSSkfas = function( MLEobj, only.logLik=FALSE, return.lag.one=TRUE, return.kfas.model=FALSE ) {
    modelObj = MLEobj$marss
    control = MLEobj$control
    diffuse=modelObj$diffuse
    
    n=dim(modelObj$data)[1]; TT=dim(modelObj$data)[2]; m=dim(modelObj$fixed$x0)[1]
    par.1=parmat(MLEobj, t=1)
    t.B=matrix(par.1$B,m,m,byrow=TRUE)
    #create the YM matrix
    YM=matrix(as.numeric(!is.na(modelObj$data)),n,TT)
      
    #Make sure the missing vals in yt are NAs if there are any
    yt=modelObj$data
    yt[!YM]=as.numeric(NA)
    
    #Stack the y so that we can get the lag-1 covariance smoother from the Kalman filter output
    stack.yt=rbind(yt[,1:TT,drop=FALSE],cbind(NA,yt[,1:(TT-1),drop=FALSE]))

    #KFS needs time going down rows so yt can be properly converted to ts object
    yt=t(yt)
    stack.yt=t(stack.yt)
    
    #Build the Zt matrix which is n x (m+1) or n x (m+1) x T; (m+1) because A is in Z
    if( (dim(modelObj$free$Z)[3] == 1) & (dim(modelObj$fixed$Z)[3] == 1) &  (dim(modelObj$free$A)[3] == 1) & (dim(modelObj$fixed$A)[3] == 1)){  
    #not time-varying
      Zt=cbind(par.1$Z,par.1$A)
      stack.Zt = matrix(0,n,2*(m+1))
      stack.Zt[1:n,1:(m+1)]=Zt
    }else{
      Zt=array(0,dim=c(n,m+1,TT))
      stack.Zt=array(0,dim=c(n,2*(m+1),TT))
      pars=parmat(MLEobj,c("Z","A"),t=1:TT)
      Zt[1:n,1:m,]=pars$Z
      Zt[1:n,m+1,]=pars$A
      stack.Zt[1:n,1:(m+1),]=Zt
    }

    #Build the Tt matrix which is (m+1) x (m+1) or (m+1) x (m+1) x T; (m+1) because x has extra row of 1s (for the A)
    #    Tt=cbind(rbind(parList$B,matrix(0,1,m)),matrix(c(parList$U,1),m+1,1))
    if( (dim(modelObj$free$B)[3] == 1) & (dim(modelObj$fixed$B)[3] == 1) &  (dim(modelObj$free$U)[3] == 1) & (dim(modelObj$fixed$U)[3] == 1)){  
    #not time-varying
      Tt=cbind(rbind(par.1$B,matrix(0,1,m)),matrix(c(par.1$U,1),m+1,1))
      stack.Tt=matrix(0,2*(m+1),2*(m+1))
      stack.Tt[1:(m+1),1:(m+1)]=Tt
      stack.Tt[(m+2):(2*m+2),1:(m+1)]=diag(1,m+1)
    }else{
      Tt=array(0,dim=c(m+1,m+1,TT))
      stack.Tt=array(0,dim=c(2*(m+1),2*(m+1),TT))
      pars=parmat(MLEobj,c("B","U"),t=1:TT)
      #pars uses i+1 because in KFAS x(t)=B(t-1)x(t-1) versus MARSS where x(t)=B(t)x(t-1)
      #KFAS sets prior on x(1) so recursions start at x(2); thus B(0) never appears in the KFAS recursions
      Tt[1:m,1:m,1:(TT-1)]=pars$B[,,2:TT]
      Tt[1:m,m+1,1:(TT-1)]=pars$U[,,2:TT]
      Tt[m+1,m+1,]=1; 
      #in KFAS T[,,TT] is not used since x(T)=B(t-1)x(t-1) is the last computation
      #Set to 0 since is.SSModel does like NA in any parameters
      Tt[,,TT]=0
      stack.Tt[(m+2):(2*m+2),1:(m+1),]=diag(1,m+1)
      stack.Tt[1:(m+1),1:(m+1),]=Tt
      stack.Tt[,,TT]=0 #see comment above re setting TT value
    }
    
    #Build the Ht (R) matrix which is n x n or n x n x T
    if( (dim(modelObj$free$R)[3] == 1) & (dim(modelObj$fixed$R)[3] == 1) ){  
    #not time-varying
      Ht=par.1$R
    }else{
      Ht=array(0,dim=c(n,n,TT))
      for(i in 1:TT){
        Ht[,,i]=parmat(MLEobj,"R",t=i)$R
      }
    }
    
    #Build the Qt matrix which is m+1 x m+1 or m+1 x m+1 x T; m+1 since x includes extra row of 1 (for A)
    if( (dim(modelObj$free$Q)[3] == 1) & (dim(modelObj$fixed$Q)[3] == 1) ){  
    #not time-varying
      Qt=matrix(0,m+1,m+1); Qt[1:m,1:m]=par.1$Q
      stack.Qt=matrix(0,2*(m+1),2*(m+1))
      stack.Qt[1:(m+1),1:(m+1)]=Qt
    }else{
      #See notes for Tt re differences in parameter indexing for the process equation
      Qt=array(0,dim=c(m+1,m+1,TT))
      stack.Qt=array(0,dim=c(2*(m+1),2*(m+1),TT))
      for(i in 1:(TT-1)){
        #i+1 since in KFAS my B(t) equals B(t-1)
        Qt[,,i]=matrix(0,m+1,m+1); Qt[1:m,1:m,i]=parmat(MLEobj,"Q",t=i+1)$Q
        stack.Qt[1:(m+1),1:(m+1),i]=Qt[,,i]
      }
      #see comments on setting of T re TT value; TT value never appears in the KFAS recursions
      #but is.SSModel check does like any NAs in the parameters
      Qt[,,TT]=0; stack.Qt[,,TT]=0
    }

    #Build the a1, Rt and P1 matrices
    #First compute x10 and V10 if tinitx=0
    if(modelObj$tinitx==0){ # Compute needed x_1 | x_0
       #B(1),U(1), and Q(1) correct here since equivalent to B(0), etc in KFAS terminology
       x00=par.1$x0; V00=par.1$V0
       x10 = par.1$B%*%x00 + par.1$U   #Shumway and Stoffer treatment of initial states   
       V10 = par.1$B%*%V00%*%t.B + par.1$Q          # eqn 6.20
    }else{
       x10=par.1$x0; x00=matrix(10,m,1) #dummy; not defined
       V10=par.1$V0; V00=diag(0,m) #dummy; not defined
    } 
    a1=rbind(x10,1); stack.a1=rbind(x10,1,x00,1)
    Rt=diag(1,m+1); stack.Rt=diag(1,2*(m+1)) 
    if( diffuse ) { 
      P1inf=matrix(0,m+1,m+1); P1inf[1:m,1:m]=V10;
      stack.P1inf=matrix(0,2*(m+1),2*(m+1))
      stack.P1inf[1:m,1:m]=V10; stack.P1inf[(m+2):(2*m+1),(m+2):(2*m+1)]=V00 
      P1=matrix(0,m+1,m+1)
      stack.P1=matrix(0,2*(m+1),2*(m+1))
    }else{ 
      P1inf=matrix(0,m+1,m+1)
      stack.P1inf=matrix(0,2*(m+1),2*(m+1))
      P1=matrix(0,m+1,m+1); P1[1:m,1:m]=V10
      #P1 is the var-cov matrix for the stacked x1,x0
      #it is matrix(c(V10,B*V00,V00*t(B),V00),2,2)
      #x1=B*x0+U+w; in the var-cov mat looks like
      # E[x1*t(x1)] E[(Bx0+U+w1)*t(x0)] -   E[x1]*E[x1]     E[(Bx0+U+w1)]E[t(x0)]
      # E[x0*t(Bx0+U+w1)] E[x0*t(x0)]       E[(Bx0+U+w1)]E[t(x0)] - E[x0]E[t(x0)]
      stack.P1=matrix(0,2*(m+1),2*(m+1))
      stack.P1[1:m,1:m]=V10; stack.P1[(m+2):(2*m+1),(m+2):(2*m+1)]=V00
      stack.P1[1:m,(m+2):(2*m+1)]=par.1$B%*%V00
      stack.P1[(m+2):(2*m+1),1:m]=V00%*%t(par.1$B)
    }

    if(!return.lag.one){
      if(packageVersion("KFAS")=="0.9.11") kfas.model=SSModel(y=yt, Z=Zt, T=Tt, R=Rt, H=Ht, Q=Qt, a1=a1, P1=P1, P1inf=P1inf)
      else kfas.model=SSModel(yt ~ -1+SSMcustom( Z=Zt, T=Tt, R=Rt, Q=Qt, a1=a1, P1=P1, P1inf=P1inf), H=Ht)
    }else{
      if(packageVersion("KFAS")=="0.9.11") kfas.model=SSModel(y=yt, Z=stack.Zt, T=stack.Tt, R=stack.Rt, H=Ht, Q=stack.Qt, a1=stack.a1, P1=stack.P1, P1inf=stack.P1inf)
      else kfas.model=SSModel(yt ~ -1+SSMcustom( Z=stack.Zt, T=stack.Tt, R=stack.Rt, Q=stack.Qt, a1=stack.a1, P1=stack.P1, P1inf=stack.P1inf), H=Ht)
    }
    
    if(only.logLik){
      return( list(logLik=logLik(kfas.model)) )
    }
    ks.out=KFS(kfas.model, simplify=FALSE) #simplify=FALSE so 1.0.0 returns LL
    #because 1.0.0 has time down columns instead of across rows
    if(packageVersion("KFAS")!="0.9.11"){
      ks.out$a=t(ks.out$a)
      ks.out$alphahat=t(ks.out$alphahat)
    }

    VtT = ks.out$V[1:m,1:m,,drop=FALSE]
    Vtt1 = ks.out$P[1:m,1:m,1:TT,drop=FALSE]
    if(!return.lag.one){ Vtt1T = NULL
    }else{ Vtt1T = ks.out$V[1:m,(m+2):(2*m+1),,drop=FALSE] }
    #zero out rows cols as needed when R diag = 0
    #Check that if any R are 0 then model is solveable
    #This works because I do not allow the location of 0s on the diagonal of R or Q to be time-varying
    if(n==1){ diag.R=unname(par.1$R) }else{ diag.R = unname(par.1$R)[1 + 0:(n - 1)*(n + 1)] }
    if( any(diag.R==0) ){
      VtT[abs(VtT)<.Machine$double.eps]=0
      Vtt1[abs(Vtt1)<.Machine$double.eps]=0
      if(return.lag.one) Vtt1T[abs(Vtt1T)<.Machine$double.eps]=0
    }

    x10T = ks.out$alphahat[1:m,1,drop=FALSE] 
    V10T = matrix(VtT[,,1],m,m)
    if(modelObj$tinitx==1){ 
      x00=matrix(NA,m,1); V00=matrix(NA,m,m)
      x0T=x10T; V0T=V10T
    }else{  #modelObj$tinitx==0
      Vtt1.1=sub3D(Vtt1,t=1)
      Vinv=pcholinv(Vtt1.1)
      if(m!=1) Vinv = symm(Vinv)  #to enforce symmetry after chol2inv call
      J0 = V00%*%t.B%*%Vinv  # eqn 6.49 and 1s on diag when Q=0; Here it is t.B[1]
      xtT.1=ks.out$alphahat[1:m,1,drop=FALSE] 
      x0T = x00 + J0%*%(ks.out$alphahat[1:m,1,drop=FALSE]-ks.out$a[1:m,1,drop=FALSE]);          # eqn 6.47
      V0T = V00 + J0%*%(VtT[,,1]-Vtt1[,,1])*t(J0)   # eqn 6.48
    }
   
    if(!return.kfas.model) kfas.model=NULL
    
#not using ks.out$v (Innov) and ks.out$F (Sigma) since I think there might be a bug when R is not diagonal.
par.R=parmat(MLEobj,"R",t=1:TT)$R
if(all(apply(par.R,3,is.diagonal))){
  innov.rtn=ks.out$v
  sigma.rtn=ks.out$F
}else{
  innov.rtn="R is not diagonal; use MARSSkfss to get innovations in this case"
  sigma.rtn="R is not diagonal; use MARSSkfss to get sigma in this case"
}
    rtn.list = list(
    xtT = ks.out$alphahat[1:m,,drop=FALSE],
    VtT = VtT, 
    Vtt1T = Vtt1T,
    x0T = x0T,
    V0T = V0T,
    x10T = ks.out$alphahat[1:m,1,drop=FALSE],
    V10T = V10T,
    x00T = x00,
    V00T = V00,
    Vtt = "Use MARSSkfss to get Vtt",
    Vtt1 = Vtt1,
    J="Use MARSSkfss to get J", 
    J0="Use MARSSkfss to get J0",
    Kt="Use MARSSkfss to get Kt", 
    xtt1 = ks.out$a[1:m,1:TT,drop=FALSE], 
    xtt= "Use MARSSkfss to get xtt",
    Innov=innov.rtn, Sigma=sigma.rtn,
    kfas.model=kfas.model,
    logLik=ks.out$logLik,
    ok=TRUE,
    errors = NULL
    )
}
