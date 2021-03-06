## #####################
##  stocks
## #####################
library(quantmod)
library(plyr)
library(bmgarch)
library(bayesplot)

##########
# Stocks #
##########

getSymbols("TWTR")
TWTR$TWTR.Open[1:10]

TWTR$wday <- .indexwday( TWTR )
TWTR$mday <- ifelse( TWTR$wday == 1, 1, 0)

getSymbols("FB")
FB$FB.Open[1:10]
FB$wday <- .indexwday( FB )
FB$mday <- ifelse( FB$wday == 1, 1, 0)


getSymbols("GOOG")
GOOG$GOOG.Open[1:10]
GOOG$wday <- .indexwday( GOOG )
GOOG$mday <- ifelse( GOOG$wday == 1, 1, 0)


upper <- max(dim(cbind(FB$FB.Open,  TWTR$TWTR.Open,  GOOG$GOOG.Open)))
lower <- upper-100
leaveout <- 0
r2 <- cbind(FB$FB.Open, TWTR$TWTR.Open, GOOG$GOOG.Open)[lower:(upper-leaveout),] ## remove the last leaveout days

################
## BEKK       ##
################
## Forecasting

# If not using arma.
rlag <- scale( diff(r2, lag = 1,  log = FALSE )[-1, ]  )
colnames(rlag ) <- colnames(r2 )

# If using arma
sr2 <- scale(r2 )
sr2
r2

fit <- bmgarch(r2,
               iterations = 1000,
               P = 1, Q = 1,
               meanstructure = "arma",
               standardize_data = TRUE,
               parameterization = 'DCC',
               xH = NULL,
               adapt_delta=0.85)
system("notify-send 'Done sampling' " )
summary(fit )

plot(fit, type = 'ccor' )

forecast(fit, ahead = 3 ,  type = "cor")

fit.constant <- bmgarch(rlag[,1:2],
                        iterations = 800,
                        P = 1, Q = 1,
                        meanstructure = "constant",
                        standardize_data = FALSE,
                        parameterization = "BEKK",
                        xH = NULL,
                        adapt_delta = .80)
system("notify-send 'Done sampling' " )
summary(fit.constant)
mcmc_parcoord(as.array(fit.constant$model_fit, pars = c("A","B","Cnst")), np = nuts_params(fit.constant$model_fit))

############
# Sim data #
############
sim.bekk <- function(N,C,A,B, phi = NULL, theta = NULL) {
    if(ncol(C) != nrow(C)){
        stop("C must be symmetric, square, PD.")
    }
    if(ncol(A) != nrow(A)){
        stop("A must be square.")
    }
    if(ncol(B) != nrow(B)){
        stop("B must be square.")
    }
    nt <- ncol(C)

    y <- array(0, dim = c(N, nt))
    y[1,] <- rnorm(nt, 0, sqrt(diag(C)))

    H <- array(0, dim = c(nt, nt, N))
    H[,,1] <- C

    for(i in 2:N) {
        H[,,i] <- C + t(A) %*% (t(y[i - 1,, drop = FALSE]) %*% y[i - 1,,drop = FALSE]) %*% A + t(B) %*% H[,,i-1] %*% B
        y[i,] <- MASS::mvrnorm(1, rep(0, nt), H[,,i])
    }

    if (!is.null(phi) & !is.null(theta)) {
        ## Assume phi0 (intercept) is zero.
        if (ncol(phi) != nrow(phi)) {
            stop("phi must be square [nt, nt].")
        }
        if (ncol(theta) != nrow(theta)) {
            stop("theta must be square [nt, nt].")
        }
        if (ncol(phi) != nt) {
            stop("phi must be square [nt, nt].")
        }
        if (ncol(theta) != nt) {
            stop("theta must be square [nt, nt].")
        }
        mu <- array(0, dim = c(N, nt))
        mu[1,] <- 0
        for(i in 2:N) {
            mu[i,] <- 10 + y[i - 1, , drop = FALSE] %*% phi + (y[i - 1, ,drop = FALSE] - mu[i - 1,,drop = FALSE])%*%theta
            y[i,] <- y[i,,drop = FALSE] + mu[i,,drop = FALSE]
        }
        ## y <- mu + y
    }

    return(y)
}

set.seed(13)

# nt = 2
N <-  200
C <-  matrix( c(1,  .3,  .3,  1 ) ,  ncol = 2)

A <-  matrix( c(.43,  -.07,  0.03,  .53 ) ,  ncol = 2, byrow = TRUE)
A <-  matrix( c(.34,  -.43,  -.35,  .16 ) ,  ncol = 2, byrow = TRUE)

B <-  matrix( c(.85,  -.11,  0.09,  .57 ) ,  ncol = 2, byrow = TRUE)
B <-  matrix(c(.81, -.23, .63, .31), ncol =  2, byrow = TRUE)

# nt = 3
set.seed(13)
N <- 100
nt <- 3
C_sd <- diag(rep(2, 3))
C <- C_sd %*% rethinking::rlkjcorr(1,3, 5) %*% C_sd
A <- matrix(runif(nt^2, -.5, .5), ncol=nt)
B <- matrix(runif(nt^2, -.5, .5), ncol=nt)

# ARMA(1,1)
phi <- matrix(runif(nt^2, -.5, .5), ncol = nt)
theta <- matrix(runif(nt^2, -.5, .5), ncol = nt)
phi <- matrix(0, ncol = nt, nrow = nt)
theta <- matrix(0, ncol = nt, nrow = nt)
diag(phi) <- rep(.8, nt)
diag(theta) <- rep(.5, nt)

y <- sim.bekk(N, C, A, B, phi = NULL, theta =  NULL)

fit <- bmgarch(y,
                iterations = 1000,
                P = 1, Q = 1,
                meanstructure = "constant",
                standardize_data = FALSE,
                parameterization = "pdBEKK",
                distribution = "Gaussian",
                xH = NULL,
                adapt_delta = .95)
system("notify-send 'Done sampling' " )
summary(fit)

mcmc_trace(as.array(fit$model_fit, pars = c("A","B","Cnst")))
mcmc_dens_overlay(as.array(fit$model_fit, pars = c("A","B","Cnst")))
mcmc_parcoord(as.array(fit$model_fit, pars = c("A","B","Cnst","beta0","beta1","phi","theta")), np = nuts_params(fit$model_fit))
