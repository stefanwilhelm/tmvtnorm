! Gibbs sampling from a truncated multinormal distribution
!
! References 
! 1. Kotecha et al. (1999):
! Kotecha, J. H. & Djuric, P. M.
! "Gibbs sampling approach for generation of truncated multivariate Gaussian random variables",
! IEEE Computer Society, IEEE Computer Society, 1999, 1757-1760
!
! 2. Geweke (2005): Contemporary Bayesian Econometrics and
! Statistics. John Wiley and Sons, 2005, pp. 171-172
!
!
! Code written by Stefan Wilhelm <wilhelm@financial.com> as part of the R package tmvtnorm.
! (http://CRAN.R-project.org/package=tmvtnorm)
!
! To cite package tmvtnorm in publications use:
!
!  Stefan Wilhelm, Manjunath B G (2012). tmvtnorm: Truncated
!  Multivariate Normal Distribution. R package version 1.4-5.
!
! A BibTeX entry for LaTeX users is
!
!  @Manual{,
!    title = {{tmvtnorm}: Truncated Multivariate Normal Distribution},
!    author = {Stefan Wilhelm and Manjunath B G},
!    year = {2012},
!    note = {R package version 1.4-5},
!    url = {http://CRAN.R-project.org/package=tmvtnorm},
!  }
! 
!
! @param n number of random sample to generate by Gibbs sampling
! @param d dimension (d >= 2)
! @param mean mean vector of dimension d (d x 1)
! @param sigma covariance matrix (d x d)
! @param lower lower truncation points (d x 1)
! @param upper upper truncation points (d x 1)
! @param x0 Startvektor (d x 1)
! @param burnin Number of Burn-in samples to be discarded
! @param thinning thinning factor for thinning the Markov chain
! @return return value X --> vektor (n * d) --> can be coerced into a (n x d) matrix
subroutine rtmvnormgibbscov(n, d, mean, sigma, lower, upper, x0, burnin, thinning, X)

IMPLICIT NONE

integer :: n, d, i, j, k, l, ind = 0, burnin, thinning

! subindex "-i"
integer, dimension(d-1) :: minus_i

double precision :: unifrnd, qnormr, pnormr, u, q, prob, Fa, Fb, mu_i, s2
double precision, dimension(n*d), INTENT(INOUT) :: X
double precision, dimension(d-1)     :: s3
double precision, dimension(d)       :: x0, xr, mean, lower, upper, sd

! Kovarianzmatrix sigma und Partitionen Sigma_i, sigma_ii und S
double precision, dimension(d, d)    :: sigma
double precision, dimension(d, d-1)  :: Sigma_i
double precision                     :: sigma_ii
double precision, dimension(d-1,d-1) :: S
! S_inv (d-1 x d-1) ist die Inverse von S
double precision, dimension(d-1,d-1) :: S_inv

! Liste von d mal 1 x (d-1) Matrizen = d x (d-1) Matrix
double precision, dimension(d, d-1)   :: P

! Deklarationen f�rs Matrix-Invertieren mit LAPACK-Routinen (Dimension d-1)
double precision, dimension( d-1 )    :: work
! ipiv = pivot indices
integer, dimension( d-1 )             :: ipiv
! lda = leading dimension
integer                               :: m, lda, lwork, info

! initialise R random number generator
call rndstart()

m    =d-1
lda  =d-1
lwork=d-1
ind  = 0

! Partitioning of sigma
! sigma   = [ sigma_ii   Sigma_i     ]
! (d x d)   [ (1 x 1)    (1 x d-1)   ]
!           [ Sigma_i'   S           ]
!           [ (d-1 x 1)  (d-1 x d-1) ]
! List of conditional variances sd(i) can be precalculated
do i = 1,d
  ! subindex "-i"
  minus_i  = (/ (j, j=1,i-1), (j, j=i+1,d) /)

  S            = sigma(minus_i, minus_i) ! Sigma_{-i,-i} : (d-1) x (d-1)
  sigma_ii     = sigma(i,i)              ! Sigma_{i,i}   : 1 x 1
  Sigma_i(i,:) = sigma(i, minus_i)       ! Sigma_{i,-i}  : 1 x (d-1)

  ! Matrix S --> S_inv umkopieren
  do k=1,(d-1)
    do l=1,(d-1)
      S_inv(k,l)=S(k,l)
    end do
  end do

  ! Matrix invertieren
  ! LU-Faktorisierung (Dreieckszerlegung) der Matrix S_inv
  call dgetrf( m, m, S_inv, lda, ipiv, info )

  ! Inverse der LU-faktorisierten Matrix S_inv
  call dgetri( m, S_inv, lda, ipiv, work, lwork, info )
  P(i,:) = pack(matmul(Sigma_i(i,:), S_inv), .TRUE.)  ! (1 x d-1) %*% (d-1 x d-1) = (1 x d-1)
  s2 = 0
  do j = 1,d-1
    s2 = s2 + P(i,j) * Sigma_i(i,j)
  end do
  sd(i)        = sqrt(sigma(i,i) - s2) ! (1 x d-1) * (d-1 x 1) --> sd[[i]] ist (1,1)
end do

! start value
xr = x0

! Actual number of samples to create:
! #burn-in-samples + n * #thinning-factor

!For all samples n times the thinning factor
do j = 1,(burnin + n * thinning)

  ! For all dimensions
  do i = 1,d
    ! Berechnung von bedingtem Erwartungswert und bedingter Varianz:
    ! bedingte Varianz h�ngt nicht von x[-i] ab!
    ! subindex "-i"
    minus_i  = (/ (k, k=1,i-1), (k, k=i+1,d) /)

    ! mu_i     = mean(i)    + P[[i]] %*% (x(-i) - mean(-i))
    s3(1:(d-1))= xr(minus_i) - mean(minus_i)
    s2 = 0
    do k = 1,d-1
      s2 = s2 + P(i,k) * s3(k)
    end do
    mu_i       = mean(i) + s2

    Fa         = pnormr(lower(i), mu_i, sd(i), 1, 0)
    Fb         = pnormr(upper(i), mu_i, sd(i), 1, 0)
    u          = unifrnd()
    prob       = u * (Fb - Fa) + Fa
    q          = qnormr(prob, 0.0d0, 1.0d0, 1, 0)
    xr(i)      = mu_i + sd(i) * q

    ! Nur f�r j > burnin samples aufzeichnen, Default ist thinning = 1
    ! bei Thinning nur jedes x-te Element nehmen
    if (j > burnin .AND. mod(j - burnin,thinning) == 0) then
      ind        = ind + 1
      X(ind)     = xr(i)
    end if
  end do
end do

! reset R random number generator
call rndend()
end subroutine rtmvnormgibbscov

! Gibbs sampling based on covariance matrix and general linear constraints a <= Cx <= b
! with r >= d linear constraints. C is (r x d), x (d x 1), a,b (r x 1).
! x0 must satisfy the constraints a <= C x0 <= b.
!
! @param n number of random sample to generate by Gibbs sampling
! @param d dimension (d >= 2)
! @param r number of linear constraints
! @param mean mean vector of dimension d (d x 1)
! @param sigma covariance matrix (d x d)
! @param C matrix for linear constraints (r x d)
! @param a lower bound for linear constraints (r x 1)
! @param b upper bound for linear constraints (r x 1)
! @param x0 Startvektor (d x 1)
! @param burnin Number of Burn-in samples to be discarded
! @param thinning thinning factor for thinning the Markov chain
! @return return value X --> vektor (n * d) --> can be coerced into a (n x d) matrix
subroutine rtmvnormgibbscov2(n, d, r, mean, sigma, C, a, b, x0, burnin, thinning, X)

IMPLICIT NONE

integer :: n, d, r, i, j, k = 1, l, ind = 0, burnin, thinning

! subindex "-i"
integer, dimension(d-1) :: minus_i

double precision :: unifrnd, qnormr, pnormr, u, q, prob, Fa, Fb, mu_i, s2
double precision, dimension(n*d), INTENT(INOUT) :: X
double precision, dimension(d-1)     :: s3
double precision, dimension(d)       :: x0, xr, mean, sd
double precision, dimension(r)       :: a, b
double precision, dimension(r, d)    :: C
double precision :: bound1, bound2, lower, upper

! Kovarianzmatrix sigma und Partitionen Sigma_i, sigma_ii und S
double precision, dimension(d, d)    :: sigma
double precision, dimension(d, d-1)  :: Sigma_12
double precision                     :: Sigma_11
double precision, dimension(d-1,d-1) :: Sigma_22
! Sigma_22_inv (d-1 x d-1) ist die Inverse von Sigma_22
double precision, dimension(d-1,d-1) :: Sigma_22_inv

! Liste von d mal 1 x (d-1) Matrizen = d x (d-1) Matrix
double precision, dimension(d, d-1)   :: P

! Deklarationen f�rs Matrix-Invertieren mit LAPACK-Routinen (Dimension d-1)
double precision, dimension( d-1 )    :: work
! ipiv = pivot indices
integer, dimension( d-1 )             :: ipiv
! lda = leading dimension
integer                               :: m, lda, lwork, info

INTEGER, DIMENSION(1) :: seed
seed(1) = 12345

! initialise R random number generator
call rndstart()
!CALL RANDOM_SEED
!CALL RANDOM_SEED (SIZE=K)           ! Sets K = N
!CALL RANDOM_SEED (PUT = SEED (1:K)) ! Uses the starting value
!                                    !     given by the user


m    =d-1
lda  =d-1
lwork=d-1
ind  = 0

! Partitioning of sigma
! sigma   = [ Sigma_11 Sigma_12 ] = [ Sigma_{i,i}   Sigma_{i,-i} ]
! (d x d)   [                   ]   [ (1 x 1)        (1 x d-1)   ]
!           [ Sigma_21 Sigma_22 ]   [ Sigma_{-i,i}  Sigma_{-i,-i}]
!           [                   ]   [ (d-1 x 1)      (d-1 x d-1) ]
! List of conditional variances sd(i) can be precalculated
do i = 1,d
  ! subindex "-i"
  minus_i  = (/ (j, j=1,i-1), (j, j=i+1,d) /)

  Sigma_22      = sigma(minus_i, minus_i) ! Sigma_{-i,-i} : (d-1) x (d-1)
  Sigma_11      = sigma(i,i)              ! Sigma_{i,i}   : 1 x 1
  Sigma_12(i,:) = sigma(i, minus_i)       ! Sigma_{i,-i}  : 1 x (d-1)

  ! Matrix Sigma_22 --> Sigma_22_inv umkopieren
  do k=1,(d-1)
    do l=1,(d-1)
      Sigma_22_inv(k,l) = Sigma_22(k,l)
    end do
  end do

  ! Matrix invertieren
  ! LU-Faktorisierung (Dreieckszerlegung) der Matrix S_inv
  call dgetrf( m, m, Sigma_22_inv, lda, ipiv, info )

  ! Inverse der LU-faktorisierten Matrix S_inv
  call dgetri( m, Sigma_22_inv, lda, ipiv, work, lwork, info )
  P(i,:) = pack(matmul(Sigma_12(i,:), Sigma_22_inv), .TRUE.)  ! (1 x d-1) %*% (d-1 x d-1) = (1 x d-1)
  s2 = 0
  do j = 1,d-1
    s2 = s2 + P(i,j) * Sigma_12(i,j)
  end do
  sd(i)        = sqrt(sigma(i,i) - s2) ! (1 x d-1) * (d-1 x 1) --> sd[[i]] ist (1,1)
end do

! start value
xr = x0

! Actual number of samples to create:
! #burn-in-samples + n * #thinning-factor

!For all samples n times the thinning factor
do j = 1,(burnin + n * thinning)

  ! For all dimensions
  do i = 1,d
    !print '("i=",I3)',i
    ! Berechnung von bedingtem Erwartungswert und bedingter Varianz:
    ! bedingte Varianz h�ngt nicht von x[-i] ab!
    ! subindex "-i"
    minus_i  = (/ (k, k=1,i-1), (k, k=i+1,d) /)

    ! mu_i     = mean(i)    + P[[i]] %*% (x(-i) - mean(-i))
    s3(1:(d-1))= xr(minus_i) - mean(minus_i)
    s2 = 0
    do k = 1,d-1
      s2 = s2 + P(i,k) * s3(k)
    end do
    mu_i       = mean(i) + s2

    ! TODO: Set to -Inf/+Inf
    lower = -1000.0d0
    upper = 1000d0
    ! Determine lower bounds for x[i] using all linear constraints relevant for x[i]
    do k = 1,r
      if (C(k,i) == 0 ) then
        CYCLE
      end if
      s2 = dot_product(C(k,minus_i), xr(minus_i))
      bound1 = (a(k)- s2) /C(k, i)
      bound2 = (b(k)- s2) /C(k, i)

      if (C(k, i) > 0) then
        lower = max(lower, bound1)
        upper = min(upper, bound2)
      else
        lower = max(lower, bound2)
        upper = min(upper, bound1)
      end if
    end do

    !print '("mu_i = ",f6.3)', mu_i
    !print '("sd(i) = ",f6.3)', sd(i)
    !print '("lower = ",f6.3)', lower
    !print '("upper = ",f6.3)',upper
    Fa         = pnormr(lower, mu_i, sd(i), 1, 0)
    Fb         = pnormr(upper, mu_i, sd(i), 1, 0)
    u          = unifrnd()
    !call RANDOM_NUMBER(u)
    prob       = u * (Fb - Fa) + Fa
    q          = qnormr(prob, 0.0d0, 1.0d0, 1, 0)
    xr(i)      = mu_i + sd(i) * q
    !print '("xr(i)=",f6.3)',xr(i)

    ! Nur f�r j > burnin samples aufzeichnen, Default ist thinning = 1
    ! bei Thinning nur jedes x-te Element nehmen
    if (j > burnin .AND. mod(j - burnin,thinning) == 0) then
      ind        = ind + 1
      X(ind)     = xr(i)
    end if
  end do
end do

! reset R random number generator
call rndend()
end subroutine rtmvnormgibbscov2

! Gibbs sampling based on precision matrix H and a <= x <= b (no linear constraints)
! x,a,b are (d x 1).
!
! @param n number of random sample to generate by Gibbs sampling
! @param d dimension (d >= 2)
! @param mean mean vector of dimension d (d x 1)
! @param H precision matrix (d x d)
! @param lower lower truncation points (d x 1)
! @param upper upper truncation points (d x 1)
! @param x0 Startvektor (d x 1)
! @param burnin Number of Burn-in samples to be discarded
! @param thinning thinning factor for thinning the Markov chain
! @return return value X --> vektor (n * d) --> can be coerced into a (n x d) matrix
subroutine rtmvnormgibbsprec(n, d, mean, H, lower, upper, x0, burnin, thinning, X)

IMPLICIT NONE

integer :: n, d, i, j, k, ind = 0, burnin, thinning

! subindex "-i"
integer, dimension(d-1) :: minus_i

double precision :: unifrnd, qnormr, pnormr, u, q, prob, Fa, Fb, mu_i, s2
double precision, dimension(d, d)    :: H
! Liste von d mal 1 x (d-1) Matrizen = d x (d-1) Matrix  als H[i, -i]
double precision, dimension(d, d-1)   :: P
double precision, dimension(d)    :: H_inv_ii

double precision, dimension(n*d), INTENT(INOUT) :: X
double precision, dimension(d-1)     :: s3
double precision, dimension(d)       :: x0, xr, mean, lower, upper, sd

! initialise R random number generator
call rndstart()
! initialise Fortran random number generator
! CALL RANDOM_SEED

! SW: I do not know why, but we have to reset ind each time!!!
! If we forget this line, ind will be incremented further and then Fortran crashes!
ind  = 0

! List of conditional variances sd(i) can be precalculated
! Vector of conditional standard deviations sd(i | -i) = H_ii^{-1} = 1 / H[i, i] = sqrt(1 / diag(H))
! does not depend on x[-i] and can be precalculated before running the chain.
do i = 1,d
  minus_i = (/ (k, k=1,i-1), (k, k=i+1,d) /)
  H_inv_ii(i) = (1.0d0 / H(i, i)) ! H^{-1}(i,i) = 1 / H(i,i)
  sd(i) = sqrt(H_inv_ii(i)) ! sd(i) is sqrt(H^{-1}(i,i))
  P(i,:)  = H(i, minus_i)    ! 1 x (d-1)
end do

! start value
xr = x0

! Actual number of samples to create:
! #burn-in-samples + n * #thinning-factor

!For all samples n times the thinning factor
do j = 1,(burnin + n * thinning)

  ! For all dimensions
  do i = 1,d
    ! subindex "-i"
    minus_i  = (/ (k, k=1,i-1), (k, k=i+1,d) /)

    ! conditional mean mu[i] = E[i | -i] = mean[i] - H_ii^{-1} H[i,-i] (x[-i] - mean[-i])
    !                    mu_i           <- mean[i]  (1 / H[i,i]) * H[i,-i] %*% (x[-i] - mean[-i])
    s3(1:(d-1)) = xr(minus_i) - mean(minus_i)
    s2 = 0
    do k = 1,d-1
      s2 = s2 + P(i, k) * s3(k)
    end do
    mu_i       = mean(i) - H_inv_ii(i) * s2

    Fa         = pnormr(lower(i), mu_i, sd(i), 1, 0)
    Fb         = pnormr(upper(i), mu_i, sd(i), 1, 0)
    u          = unifrnd()
    !call RANDOM_NUMBER(u)
    prob       = u * (Fb - Fa) + Fa
    q          = qnormr(prob, 0.0d0, 1.0d0, 1, 0)
    xr(i)      = mu_i + sd(i) * q
    
    ! Nur f�r j > burnin samples aufzeichnen, Default ist thinning = 1
    ! bei Thinning nur jedes x-te Element nehmen
    if (j > burnin .AND. mod(j - burnin,thinning) == 0) then
      ind        = ind + 1
      X(ind)     = xr(i)
      !call intpr("ind=", 4, ind, 1)
      !call dblepr("X(ind)=", 7, X(ind), 1)
    end if
  end do
end do

! reset R random number generator
call rndend()
end subroutine rtmvnormgibbsprec

! Gibbs sampling based on precision matrix H and general linear constraints a <= Cx <= b
! with r >= d linear constraints. C is (r x d), x (d x 1), a,b (r x 1).
! x0 must satisfy the constraints a <= C x0 <= b.
!
! @param n number of random sample to generate by Gibbs sampling
! @param d dimension (d >= 2)
! @param r number of linear constraints
! @param mean mean vector of dimension d (d x 1)
! @param H precision matrix (d x d)
! @param C matrix for linear constraints (r x d)
! @param a lower bound for linear constraints (r x 1)
! @param b upper bound for linear constraints (r x 1)
! @param x0 start value (d x 1)
! @param burnin number of Burn-in samples to be discarded
! @param thinning thinning factor for thinning the Markov chain
! @return return value X --> vektor (n * d) --> can be coerced into a (n x d) matrix
subroutine rtmvnormgibbsprec2(n, d, r, mean, H, C, a, b, x0, burnin, thinning, X)

IMPLICIT NONE

integer :: n, d, r, i, j, k, ind = 0, burnin, thinning

! subindex "-i"
integer, dimension(d-1) :: minus_i

double precision :: unifrnd, qnormr, pnormr, u, q, prob, Fa, Fb, mu_i, s2
double precision, dimension(d, d)    :: H
! Liste von d mal 1 x (d-1) Matrizen = d x (d-1) Matrix  als H[i, -i]
double precision, dimension(d, d-1)   :: P
double precision, dimension(d)    :: H_inv_ii

double precision, dimension(n*d), INTENT(INOUT) :: X
double precision, dimension(d-1)     :: s3
double precision, dimension(d)       :: x0, xr, mean, sd
double precision, dimension(r)       :: a, b
double precision, dimension(r, d)    :: C
double precision :: bound1, bound2, lower, upper

! initialise R random number generator
call rndstart()
! initialise Fortran random number generator
! CALL RANDOM_SEED

! SW: I do not know why, but we have to reset ind each time!!!
! If we forget this line, ind will be incremented further and then Fortran crashes!
ind  = 0

! List of conditional variances sd(i) can be precalculated
! Vector of conditional standard deviations sd(i | -i) = H_ii^{-1} = 1 / H[i, i] = sqrt(1 / diag(H))
! does not depend on x[-i] and can be precalculated before running the chain.
do i = 1,d
  minus_i = (/ (k, k=1,i-1), (k, k=i+1,d) /)
  H_inv_ii(i) = (1.0d0 / H(i, i)) ! H^{-1}(i,i) = 1 / H(i,i)
  sd(i) = sqrt(H_inv_ii(i)) ! sd(i) is sqrt(H^{-1}(i,i))
  P(i,:)  = H(i, minus_i)    ! 1 x (d-1)
end do

! start value
xr = x0

! Actual number of samples to create:
! #burn-in-samples + n * #thinning-factor

!For all samples n times the thinning factor
do j = 1,(burnin + n * thinning)

  ! For all dimensions
  do i = 1,d
    ! subindex "-i"
    minus_i  = (/ (k, k=1,i-1), (k, k=i+1,d) /)

    ! conditional mean mu[i] = E[i | -i] = mean[i] - H_ii^{-1} H[i,-i] (x[-i] - mean[-i])
    !                    mu_i           <- mean[i]  (1 / H[i,i]) * H[i,-i] %*% (x[-i] - mean[-i])
    s3(1:(d-1)) = xr(minus_i) - mean(minus_i)
    s2 = 0
    do k = 1,d-1
      s2 = s2 + P(i, k) * s3(k)
    end do
    mu_i       = mean(i) - H_inv_ii(i) * s2
	
    ! TODO: Set to -Inf/+Inf
    lower = -1000.0d0
    upper = 1000d0
    ! Determine lower bounds for x[i] using all linear constraints relevant for x[i]
    do k = 1,r
      if (C(k,i) == 0 ) then
        CYCLE
      end if
      s2 = dot_product(C(k,minus_i), xr(minus_i))
      bound1 = (a(k)- s2) /C(k, i)
      bound2 = (b(k)- s2) /C(k, i)

      if (C(k, i) > 0) then
        lower = max(lower, bound1)
        upper = min(upper, bound2)
      else
        lower = max(lower, bound2)
        upper = min(upper, bound1)
      end if
    end do

    !print '("mu_i = ",f6.3)', mu_i
    !print '("sd(i) = ",f6.3)', sd(i)
    !print '("lower = ",f6.3)', lower
    !print '("upper = ",f6.3)',upper

    Fa         = pnormr(lower, mu_i, sd(i), 1, 0)
    Fb         = pnormr(upper, mu_i, sd(i), 1, 0)
    u          = unifrnd()
    !call RANDOM_NUMBER(u)
    prob       = u * (Fb - Fa) + Fa
    q          = qnormr(prob, 0.0d0, 1.0d0, 1, 0)
    xr(i)      = mu_i + sd(i) * q
    
    ! Nur f�r j > burnin samples aufzeichnen, Default ist thinning = 1
    ! bei Thinning nur jedes x-te Element nehmen
    if (j > burnin .AND. mod(j - burnin,thinning) == 0) then
      ind        = ind + 1
      X(ind)     = xr(i)
      !call intpr("ind=", 4, ind, 1)
      !call dblepr("X(ind)=", 7, X(ind), 1)
    end if
  end do
end do

! reset R random number generator
call rndend()
end subroutine rtmvnormgibbsprec2

 ! populate map (row --> linked list of matrix elements) for with all entries in Hi, Hj and Hv
 ! if upper_triangular is TRUE, then we assume that only matrix elements with Hi <= Hj are given and we will
 ! put two elements in the (Hi,Hj,Hv) and (Hj,Hi,Hv) to the list for all Hi <= Hj
subroutine populate_map(map, Hi, Hj, Hv, num_nonzero, d, upper_triangular)
 use linked_list
 integer :: num_nonzero, d
 integer, dimension(num_nonzero) :: Hi, Hj
 double precision, dimension(num_nonzero) :: Hv
 type(matrixrow), dimension(d), INTENT(INOUT) :: map
 type(matrixelem) :: newelem
 integer :: i, k
 logical :: upper_triangular

 !allocate(map(d)) ! and allocate our map
 do i=1,d
   nullify(map(i)%first)                    ! "zero out" our list
   nullify(map(i)%last)
 enddo

 ! populate map for with all entries in Hi, Hj and Hv
 do k=1,num_nonzero
   i = Hi(k)

   if (upper_triangular)  then
     !if only upper triangular elements (i,j,v) with (i <= j) are given,
     !insert element (i, j, v) and (j, i, v) f�r i <> j

     if (Hi(k) <= Hj(k)) then
       ! (i, j, v) element
       newelem%i = Hi(k)
       newelem%j = Hj(k)
       newelem%v = Hv(k)
       call insert_list_element(map(Hi(k)), newelem)
     end if

     if (Hi(k) < Hj(k)) then
       ! (j, i, v) element
       newelem%i = Hj(k)
       newelem%j = Hi(k)
       newelem%v = Hv(k)
       call insert_list_element(map(Hj(k)), newelem)
     end if
   else
     ! insert all elements given by (Hi, Hj, Hv)
     newelem%i = Hi(k)
     newelem%j = Hj(k)
     newelem%v = Hv(k)
     call insert_list_element(map(i), newelem)
   end if
enddo
end subroutine


! Gibbs sampling of the truncated multivariate normal distribution using a sparse matrix representation of the precision matrix H,
! represented in triplet form
!
! @param n number of random sample to generate by Gibbs sampling
! @param d dimension (d >= 2)
! @param mean mean vector of dimension d (d x 1)
! @param Hi,Hj,Hv are the nonzero elements of the precision matrix H (d, d): H(i, j)=v, each a vector having the same length num_nonzero
! @param num_nonzero number of nonzero elements of the precision matrix H
! @param lower lower truncation points (d x 1)
! @param upper upper truncation points (d x 1)
! @param x0 Startvektor (d x 1)
! @param burnin Number of Burn-in samples to be discarded
! @param thinning thinning factor for thinning the Markov chain
! @return return value X --> vektor (n * d) --> can be coerced into a (n x d) matrix
subroutine rtmvnorm_sparse_triplet(n, d, mean, Hi, Hj, Hv, num_nonzero, lower, upper, x0, burnin, thinning, X)

use linked_list

IMPLICIT NONE

integer :: n, d, i, j, k, ind = 0, burnin, thinning, num_nonzero

! matrix representation of concentration matrix H
integer, dimension(num_nonzero) :: Hi, Hj
double precision, dimension(num_nonzero)       :: Hv

double precision :: unifrnd, qnormr, pnormr, u, q, prob, Fa, Fb, mu_i, s2
double precision, dimension(d)    :: H_inv_ii

double precision, dimension(n*d), INTENT(INOUT) :: X
double precision, dimension(d)       :: x0, xr, mean, lower, upper, sd

! in this map we store for every row i the non-zero entries (triplets) as a linked list of matrix elements
 ! example: i=1 --> (i=1,j=1,v=0.8), (i=1,j=2,v=0.2), (i=1,j=5,v=0.3) etc.
 ! The list will not be sorted ascending in j, so we can only iterate this list...
 type(matrixrow), dimension(d) :: map
 type(matrixelem) :: elem
 type( node ), pointer :: current

! initialise R random number generator
call rndstart()
! initialise Fortran random number generator
!CALL RANDOM_SEED

! We have to reset ind each time
! If we forget this line, ind will be incremented further and then Fortran crashes!
ind  = 0

! loop through all elements and look for diagonal elements H[i,i], calculate conditional standard deviations sd(i | -i)
! List of conditional variances sd(i) can be precalculated
! Vector of conditional standard deviations sd(i | -i) = H_ii^{-1} = 1 / H[i, i] = sqrt(1 / diag(H))
! does not depend on x[-i] and can be precalculated before running the chain.
do k=1,num_nonzero
  i = Hi(k)
  j = Hj(k)

  if (i == j) then
    H_inv_ii(i) = (1.0d0 / Hv(k))  ! H^{-1}(i,i) = 1 / H(i,i)
    sd(i) = sqrt(H_inv_ii(i))      ! sd(i) is sqrt(H^{-1}(i,i))
  end if
end do

! populate map with linked lists of matrix elements H[i,j]=v and symmetric element H[j,i]=v
call populate_map(map, Hi, Hj, Hv, num_nonzero, d, .TRUE.)

! start value
xr = x0

! Actual number of samples to create:
! #burn-in-samples + n * #thinning-factor

!For all samples n times the thinning factor
do j = 1,(burnin + n * thinning)

  ! For all dimensions
  do i = 1,d
    ! s2 will represent the term H[i,-i] (x[-i] - mean[-i])
    s2 = 0

	! We avoid some n x d x d accesses to hash matrix H even for those elements that are zero...
    ! For n=30 and d=5000 this results in 30 x 5000 x 5000 = 75 million accesses to matrix H...
    ! Instead of iterating all (d-1) elements H[i,-i] we only iterate all m (m < d) NON-ZERO elements H[i,-i] which will dramatically reduce the number
    ! of hashtable accesses. This will scale as n x d x m and will be linear in d for a fixed m.
    current => map(i)%first
    do while (associated(current))
     elem = current%data
     ! sum only non-zero H[i,-i] elements in H[i,-i] (x[-i] - mean[-i])
     ! no summing for i = j elements!
      if (elem%j .ne. elem%i) then
       k = elem%j
       s2 = s2 + elem%v * (xr(k) - mean(k)) !TODO check
     end if
     current => current%next
    end do

    ! conditional mean mu[i] = E[i | -i] = mean[i] - H_ii^{-1} H[i,-i] (x[-i] - mean[-i])
    ! we only loop through all non-zero elements in H[i,-i] = all indices j .ne. i in sparse matrix representation H[i,j]=v
    mu_i       = mean(i) - H_inv_ii(i) * s2

    Fa         = pnormr(lower(i), mu_i, sd(i), 1, 0)
    Fb         = pnormr(upper(i), mu_i, sd(i), 1, 0)
    u          = unifrnd()
    !call RANDOM_NUMBER(u)
    prob       = u * (Fb - Fa) + Fa
    q          = qnormr(prob, 0.0d0, 1.0d0, 1, 0)
    xr(i)      = mu_i + sd(i) * q
    
    ! Nur f�r j > burnin samples aufzeichnen, Default ist thinning = 1
    ! bei Thinning nur jedes x-te Element nehmen
    if (j > burnin .AND. mod(j - burnin,thinning) == 0) then
      ind        = ind + 1
      X(ind)     = xr(i)
    end if
  end do
end do

 ! deallocate linked list at the end of the program and free memory
 do i=1,d
   call free_all(map(i))
   nullify(map(i)%first)                    ! "zero out" our list
   nullify(map(i)%last)
 enddo
 nullify(current)

! reset R random number generator
call rndend()
end subroutine rtmvnorm_sparse_triplet

! Gibbs sampling of the truncated multivariate normal distribution using a sparse matrix representation of the precision matrix H (d x d).
!
! Instead of using a triplet representation H(i,j)=v, we use the compressed sparse column (csc) format with 3 vectors
! Hi : integer vector of row index, length num_nonzero; starting from zero
! Hp : integer vector of pointers, length d + 1; starting from zero; non-decreasing vector
! Hv : double vector of values, length num_nonzero
!
! This format is good at accessing all non-zero elements in one column j
! (and -as in our case- for symmetric matrices also to acess all elements in one row i)
!
! To access an element H(i,j), the following steps are necessary
! j
! v = Hv(Hp(j):Hp(j+1))
! i = Hi(Hp(j):Hp(j+1))
!
! @param n number of random sample to generate by Gibbs sampling
! @param d dimension (d >= 2)
! @param mean mean vector of dimension d (d x 1)
! @param Hi,Hp,Hv are the nonzero elements of the precision matrix H (d, d): H(i, j)=v, each a vector having the same length num_nonzero
! @param num_nonzero number of nonzero elements of the precision matrix H
! @param lower lower truncation points (d x 1)
! @param upper upper truncation points (d x 1)
! @param x0 Startvektor (d x 1)
! @param burnin Number of Burn-in samples to be discarded
! @param thinning thinning factor for thinning the Markov chain
! @return return value X --> vektor (n * d) --> can be coerced into a (n x d) matrix
subroutine rtmvnorm_sparse_csc(n, d, mean, Hi, Hp, Hv, num_nonzero, lower, upper, x0, burnin, thinning, X)

IMPLICIT NONE

integer :: n, d, i, j, k, r, ind = 0, burnin, thinning, num_nonzero

! compressed sparse column (csc) matrix representation of concentration matrix H
integer, dimension(num_nonzero)   :: Hi
integer, dimension(d+1) :: Hp
double precision, dimension(num_nonzero)       :: Hv

double precision :: unifrnd, qnormr, pnormr, u, q, prob, Fa, Fb, mu_i, s2
double precision, dimension(d)    :: H_inv_ii

double precision, dimension(n*d), INTENT(INOUT) :: X
double precision, dimension(d)       :: x0, xr, mean, lower, upper, sd

! initialise R random number generator
call rndstart()

! initialise Fortran random number generator
!CALL RANDOM_SEED

! SW: I do not know why, but we have to reset ind each time!!!
! If we forget this line, ind will be incremented further and then Fortran crashes!
ind  = 0

! loop through all elements and look for diagonal elements H[i,i], calculate conditional standard deviations sd(i | -i)
! List of conditional variances sd(i) can be precalculated
! Vector of conditional standard deviations sd(i | -i) = H_ii^{-1} = 1 / H[i, i] = sqrt(1 / diag(H))
! does not depend on x[-i] and can be precalculated before running the chain.
do j=1,d
  do k=Hp(j),Hp(j+1)-1             ! k from 0..(d-1)
   i = Hi(k+1) + 1                 ! Hi is index from 0..(d-1) --> need index i=1..d

   if (i == j) then
    H_inv_ii(i) = (1.0d0 / Hv(k+1))  ! H^{-1}(i,i) = 1 / H(i,i)
    sd(i) = sqrt(H_inv_ii(i))        ! sd(i) is sqrt(H^{-1}(i,i))
   end if
  end do
end do

! start value
xr = x0

! Actual number of samples to create:
! #burn-in-samples + n * #thinning-factor

!For all samples n times the thinning factor
do j = 1,(burnin + n * thinning)

  ! For all dimensions
  do i = 1,d

    ! conditional mean mu[i] = E[i | -i] = mean[i] - H_ii^{-1} H[i,-i] (x[-i] - mean[-i])
    s2 = 0

    ! For H[i,-i] (x[-i] - mean[-i]) we need to sum only all non-zero H[i,-i] elements!
    ! since H is symmetric, we can use the column sparse compressed (csc) format and sum all H[-i,i] elements instead
    do k=Hp(i),Hp(i+1)-1                    ! loop all non-zero elements in column i, k is index 0..(d-1)
      r = Hi(k+1) + 1                       ! row index r in column i is r=1..d
      if (i .ne. r) then
        s2 = s2 + Hv(k+1) * (xr(r) - mean(r))
      end if
    end do

    mu_i       = mean(i) - H_inv_ii(i) * s2

    Fa         = pnormr(lower(i), mu_i, sd(i), 1, 0)
    Fb         = pnormr(upper(i), mu_i, sd(i), 1, 0)
    u          = unifrnd()
    !call RANDOM_NUMBER(u)
    prob       = u * (Fb - Fa) + Fa
    q          = qnormr(prob, 0.0d0, 1.0d0, 1, 0)
    xr(i)      = mu_i + sd(i) * q

    ! Only retain samples for j > burnin. Default is thinning = 1.
    ! If thinning>1 do retain only every x-th element
    if (j > burnin .AND. mod(j - burnin,thinning) == 0) then
      ind        = ind + 1
      X(ind)     = xr(i)
!      call intpr("ind=", 4, ind, 1)
!      call dblepr("X(ind)=", 7, X(ind), 1)
    end if
  end do
end do

! reset R random number generator
call rndend()
end subroutine rtmvnorm_sparse_csc


