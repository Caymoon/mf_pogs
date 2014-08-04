#ifndef SINKHORN_KNOPP_HPP_
#define SINKHORN_KNOPP_HPP_

#include <thrust/device_vector.h>
#include <thrust/functional.h>
#include <thrust/transform.h>

#include <algorithm>

#include "_interface_defs.h"
#include "cml/cml_blas.cuh"
#include "cml/cml_matrix.cuh"
#include "cml/cml_vector.cuh"

// x -> |x|
template <typename T>
struct AbsF : thrust::unary_function<T, T> {
  __device__ T operator()(T x) { return fabs(x); }
};

// x -> 1 / x
template <typename T>
struct ReciprF : thrust::unary_function<T, T> {
  __device__ T operator()(T x) { return static_cast<T>(1) / x; }
};

// Sinkhorn Knopp algorithm for matrix equilibration.
// The following approx. holds: diag(d) * Ai * e =  1, diag(e) * Ai' * d = 1
// Output matrix is generated as: Ao = diag(d) * Ai * diag(e),
// template <typename T>
// void SinkhornKnopp(cublasHandle_t handle, const T *Ai, cml::matrix<T> *Ao,
//                    cml::vector<T> *d, cml::vector<T> *e) {
//   unsigned int kNumItr = 10;
//   cml::matrix_memcpy(Ao, Ai);
//   cml::vector_set_all(d, static_cast<T>(1));
// 
//   // A := |A| -- elementwise
//   thrust::transform(thrust::device_pointer_cast(Ao->data),
//       thrust::device_pointer_cast(Ao->data + Ao->size2 * Ao->tda),
//       thrust::device_pointer_cast(Ao->data), AbsF<T>());
// 
//   // e := 1 ./ A' * d; d := 1 ./ A * e; -- k times.
//   for (unsigned int k = 0; k < kNumItr; ++k) {
//     cml::blas_gemv(handle, CUBLAS_OP_T, static_cast<T>(1), Ao, d,
//         static_cast<T>(0), e);
// 
//     thrust::transform(thrust::device_pointer_cast(e->data),
//         thrust::device_pointer_cast(e->data + e->size),
//         thrust::device_pointer_cast(e->data), ReciprF<T>());
// 
//     cml::blas_gemv(handle, CUBLAS_OP_N, static_cast<T>(1), Ao, e,
//         static_cast<T>(0), d);
//     thrust::transform(thrust::device_pointer_cast(d->data),
//         thrust::device_pointer_cast(d->data + d->size),
//         thrust::device_pointer_cast(d->data), ReciprF<T>());
// 
//     T nrm_d = cml::blas_nrm2(handle, d) / sqrt(static_cast<T>(d->size));
//     T nrm_e = cml::blas_nrm2(handle, e) / sqrt(static_cast<T>(e->size));
//     T scale = sqrt(nrm_e / nrm_d);
//     cml::blas_scal(handle, scale, d);
//     cml::blas_scal(handle, static_cast<T>(1) / scale, e);
//   }
// 
//   // A := D * A * E
//   T* de = new T[std::max(Ao->size1, Ao->size2)];
//   cml::vector_memcpy(de, d);
//   cml::matrix_memcpy(Ao, Ai);
//   for (unsigned int i = 0; i < Ao->size1; ++i) {
//     cml::vector<T> v = cml::matrix_row(Ao, i);
//     cml::blas_scal(handle, de[i], &v);
//   }
//   cml::vector_memcpy(de, e);
//   for (unsigned int j = 0; j < Ao->size2; ++j) {
//     cml::vector<T> v = cml::matrix_column(Ao, j);
//     cml::blas_scal(handle, de[j], &v);
//   }
//   delete [] de;
// }

template <typename T, CBLAS_ORDER O>
int Equilibrate(T *A, cml::vector<T> *d, cml::vector<T> *e) {
  int err = 0;
  T *dpr = new T[d->size], *epr = new T[e->size];
  if (d->size < e->size) {
    for (unsigned int i = 0; i < d->size; ++i)
      dpr[i] = 0;
    for (unsigned int j = 0; j < e->size; ++j)
      epr[j] = 1;
    if (O == CblasColMajor)
      for (unsigned int j = 0; j < e->size; ++j)
#pragma omp parallel for
        for (unsigned int i = 0; i < d->size; ++i)
          dpr[i] += std::fabs(A[i + j * d->size]);
    else
#pragma omp parallel for
      for (unsigned int i = 0; i < d->size; ++i)
        for (unsigned int j = 0; j < e->size; ++j)
          dpr[i] += std::fabs(A[i * e->size + j]);
    for (unsigned int i = 0; i < d->size; ++i) {
      err += dpr[i] == 0;
      dpr[i] = 1 / dpr[i];
    }
  } else {
    for (unsigned int i = 0; i < d->size; ++i)
      dpr[i] = 1;
    for (unsigned int j = 0; j < e->size; ++j)
      epr[j] = 0;
    if (O == CblasColMajor)
#pragma omp parallel for
      for (unsigned int j = 0; j < e->size; ++j)
        for (unsigned int i = 0; i < d->size; ++i)
          epr[j] += std::fabs(A[i + j * d->size]);
    else
      for (unsigned int i = 0; i < d->size; ++i)
#pragma omp parallel for
        for (unsigned int j = 0; j < e->size; ++j)
          epr[j] += std::fabs(A[i * e->size + j]);
    for (unsigned int j = 0; j < e->size; ++j) {
      err += epr[j] == 0;
      epr[j] = 1 / epr[j];
    }
  }
  if (O == CblasColMajor)
#pragma omp parallel for
    for (unsigned int j = 0; j < e->size; ++j)
      for (unsigned int i = 0; i < d->size; ++i)
        A[i + j * d->size] *= epr[j] * dpr[i];
  else
#pragma omp parallel for
    for (unsigned int i = 0; i < d->size; ++i)
      for (unsigned int j = 0; j < e->size; ++j)
        A[i * e->size + j] *= epr[j] * dpr[i];
  cml::vector_memcpy(d, dpr);
  cml::vector_memcpy(e, epr);
  delete [] dpr;
  delete [] epr;
  if (err)
    Printf("Error: Zero column/row in A\n");
  return err;
}

#endif  // SINKHORN_KNOPP_HPP_

