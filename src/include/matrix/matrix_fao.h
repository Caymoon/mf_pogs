#ifndef MATRIX_MATRIX_FAO_H_
#define MATRIX_MATRIX_FAO_H_

namespace pogs {

template <typename T>
class MatrixFAO : public Matrix<T> {
 private:
  void *_info;
  // gsl::vector<T> _dag_output;
  // gsl::vector<T> _dag_input;
  size_t _m;
  size_t _n;
  void (*_Amul)(void *);
  void (*_ATmul)(void *);
  void * _dag;
  // gsl::vector<T> _d;
  // gsl::vector<T> _e;
  bool _done_equil;
  const size_t _samples, _equil_steps;

 public:
  // Constructor (only sets variables)
  MatrixFAO(T *dag_output, size_t m, T *dag_input, size_t n,
            void (*Amul)(void *), void (*ATmul)(void *),
            void *dag, size_t samples, size_t equil_steps);
  ~MatrixFAO();

  // Initialize matrix, call this before any other methods.
  int Init();

  // Method to equilibrate.
  int Equil(T *d, T *e,
            const std::function<void(T*)> &constrain_d,
            const std::function<void(T*)> &constrain_e);

  // Method to multiply by A and A^T.
  int Mul(char trans, T alpha, const T *x, T beta, T *y) const;
};

}  // namespace pogs

#endif  // MATRIX_MATRIX_FAO_H_

