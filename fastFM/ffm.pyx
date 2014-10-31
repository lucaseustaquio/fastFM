# sample.pyx
# Import the low-level C declarations
cimport cffm
from  cffm cimport cs_di, ffm_param
# Import some functionality from Python and the C stdlib
from cpython.pycapsule cimport *

from libc.stdlib cimport malloc, free
from scipy.sparse import csc_matrix
cimport numpy as np
import numpy as np
# Destructor for cleaning up CsMatrix objects
cdef del_CsMatrix(object obj):
    pt = <cffm.cs_di *> PyCapsule_GetPointer(obj,"CsMatrix")
    free(<void *> pt)

# Create a CsMatrix object and return as a capsule
def CsMatrix(X not None):
    cdef cffm.cs_di *p
    p = <cffm.cs_di *> malloc(sizeof(cffm.cs_di))
    if p == NULL:
        raise MemoryError("No memory to make a Point")

    cdef int i
    cdef np.ndarray[int, ndim=1, mode = 'c'] indptr = X.indptr
    cdef np.ndarray[int, ndim=1, mode = 'c'] indices = X.indices
    cdef np.ndarray[double, ndim=1, mode = 'c'] data = X.data

    # Put the scipy data into the CSparse struct. This is just copying some
    # pointers.
    p.nzmax = X.data.shape[0]
    p.m = X.shape[0]
    p.n = X.shape[1]
    p.p = &indptr[0]
    p.i = &indices[0]
    p.x = &data[0]
    p.nz = -1 # to indicate CSC format
    return PyCapsule_New(<void *>p,"CsMatrix",<PyCapsule_Destructor>del_CsMatrix)

# Destructor for cleaning up FFMParam objects
cdef del_FFMParam(object obj):
    pt = <cffm.ffm_param *> PyCapsule_GetPointer(obj,"FFMParam")
    free(<void *> pt)

# Create a FFMParam object and return as a capsule
def FFMParam(fm):
    map_flags = {'classification': 10,
                 'regression': 20,
                 'ranking': 30}
    cdef cffm.ffm_param *p
    p = <cffm.ffm_param *> malloc(sizeof(cffm.ffm_param))
    if p == NULL:
        raise MemoryError("No memory to make a FFMParam")
    p.n_iter = fm.max_iter
    p.k = fm.rank_pair
    p.init_sigma = fm.init_stdev
    p.stepsize = fm.step_size
    p.TASK = map_flags[fm.task]
    p.rng_seed = fm.random_state
    p.lambda_w = fm.lambda_w
    p.lambda_V = fm.lambda_V
    return PyCapsule_New(<void *>p,"FFMParam",<PyCapsule_Destructor>del_FFMParam)

def ffm_predict(double w_0, double[:] w,
        np.ndarray[np.float64_t, ndim = 2] V, X):
    assert X.shape[1] == len(w)
    assert X.shape[1] == V.shape[1]
    X_ = CsMatrix(X)
    k = V.shape[0]
    pt_X = <cffm.cs_di *> PyCapsule_GetPointer(X_,"CsMatrix")
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] y =\
         np.zeros(X.shape[0], dtype=np.float64)
    cffm.ffm_predict(&w_0, &w[0], <double *> V.data, pt_X, &y[0], k)
    return y

def ffm_als_fit(fm, X, double[:] y):
    assert fm.solver == 'als'
    assert X.shape[0] == len(y) # test shapes
    n_features = X.shape[1]
    X_ = CsMatrix(X)
    pt_X = <cffm.cs_di *> PyCapsule_GetPointer(X_,"CsMatrix")
    param = FFMParam(fm)
    pt_param = <cffm.ffm_param *> PyCapsule_GetPointer(param,"FFMParam")
    #allocate the coefs
    cdef double w_0 = 0
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] w =\
         np.zeros(n_features, dtype=np.float64)
    cdef np.ndarray[np.float64_t, ndim=2, mode='c'] V =\
         np.zeros((fm.rank_pair, n_features), dtype=np.float64)

    cffm.ffm_als_fit(&w_0, <double *> w.data, <double *> V.data, pt_X, &y[0],
            pt_param)
    return w_0, w, V


def ffm_sgd_fit(fm, X, double[:] y):
    assert fm.solver == 'sgd'
    assert X.shape[1] == len(y) # test shapes
    n_features = X.shape[0]
    X_ = CsMatrix(X)
    pt_X = <cffm.cs_di *> PyCapsule_GetPointer(X_,"CsMatrix")
    param = FFMParam(fm)
    pt_param = <cffm.ffm_param *> PyCapsule_GetPointer(param,"FFMParam")
    #allocate the coefs
    cdef double w_0 = 0
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] w =\
         np.zeros(n_features, dtype=np.float64)
    cdef np.ndarray[np.float64_t, ndim=2, mode='c'] V =\
         np.zeros((fm.rank_pair, n_features), dtype=np.float64)

    cffm.ffm_sgd_fit(&w_0, <double *> w.data, <double *> V.data, pt_X, &y[0],
            pt_param)
    return w_0, w, V


def ffm_fit_sgd_bpr(fm, X, np.ndarray[np.float64_t, ndim=2, mode='c'] pairs):
    n_features = X.shape[0]
    X_ = CsMatrix(X)
    pt_X = <cffm.cs_di *> PyCapsule_GetPointer(X_,"CsMatrix")
    param = FFMParam(fm)
    pt_param = <cffm.ffm_param *> PyCapsule_GetPointer(param,"FFMParam")

    #allocate the coefs
    cdef double w_0 = 0
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] w =\
         np.zeros(n_features, dtype=np.float64)
    cdef np.ndarray[np.float64_t, ndim=2, mode='c'] V =\
         np.zeros((fm.rank_pair, n_features), dtype=np.float64)

    cffm.ffm_sgd_bpr_fit(&w_0, <double *> w.data, <double *> V.data, pt_X,
            <double *>  pairs.data, pairs.shape[0], pt_param)
    return w_0, w, V

def ffm_mcmc_fit_predict(fm, X_train, X_test, double[:] y):
    assert X_train.shape[0] == len(y)
    assert X_train.shape[1] == X_test.shape[1]
    param = FFMParam(fm)
    pt_param = <cffm.ffm_param *> PyCapsule_GetPointer(param,"FFMParam")
    X_train_ = CsMatrix(X_train)
    pt_X_train = <cffm.cs_di *> PyCapsule_GetPointer(X_train_,"CsMatrix")
    X_test_ = CsMatrix(X_test)
    pt_X_test = <cffm.cs_di *> PyCapsule_GetPointer(X_test_,"CsMatrix")

    #allocate the coefs
    cdef double w_0 = 0
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] w =\
         np.zeros(X_train.shape[1], dtype=np.float64)
    cdef np.ndarray[np.float64_t, ndim=2, mode='c'] V =\
         np.zeros((fm.rank_pair, X_train.shape[1]), dtype=np.float64)

    # allocate the results vector
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] y_pred =\
         np.zeros(X_test.shape[0], dtype=np.float64)

    cffm.ffm_mcmc_fit_predict(&w_0, <double *> w.data, <double *> V.data,
            pt_X_train, pt_X_test, &y[0], <double *> y_pred.data, pt_param)
    return (w_0, w, V), y_pred

def cs_norm(X):
    X = CsMatrix(X)
    pt = <cffm.cs_di *> PyCapsule_GetPointer(X,"CsMatrix")
    return cffm.cs_di_norm(pt)