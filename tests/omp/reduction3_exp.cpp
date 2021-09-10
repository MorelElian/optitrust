#include <stdio.h>

int main() {
  int a;
#pragma omp parallel shared(a) private(i)
  {
#pragma omp master
    a = 0;
#pragma omp for reduction(+ : a)
    for (int i = 0; (i < 10); i++) {
      a += i;
    }
#pragma omp single
    printf("Sum is %d\n", a);
  }
  return 0;
}