#include <optitrust.h>

int main() {
  const int N0 = 1;
  int* const a = (int*)calloc(MSIZE1(N0), sizeof(int));
  int* const b = (int*)malloc(MSIZE1(N0) * sizeof(int));
  for (int i1 = 0; i1 < N0; i1++) {
    b[MINDEX1(N0, i1)] = a[MINDEX1(N0, i1)];
  }
  for (int i = 0; i < 10; i++) {
    b[MINDEX1(N0, i)];
  }
  for (int i1 = 0; i1 < N0; i1++) {
    a[MINDEX1(N0, i1)] = b[MINDEX1(N0, i1)];
  }
  free(b);
}
