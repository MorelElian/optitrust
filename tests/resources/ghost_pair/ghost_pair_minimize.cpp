#include <optitrust.h>

int main() {
  __pure();

  int x = 0;

  int* const A = CALLOC1(int, 10);
  __GHOST_BEGIN(focusA, matrix1_ro_focus, "A, 0");
  x += 1;
  x += A[MINDEX1(10, 0)];
  x += 1;
  __GHOST_END(focusA);
  __GHOST_BEGIN(focusA2, matrix1_ro_focus, "A, 0");
  x += 1;
  __GHOST_END(focusA2);
  free(A);

  int* const B = CALLOC2(int, 8, 6);
  __GHOST_BEGIN(focusBi, group_focus, "i := 1");
  x += 2;
  __GHOST_BEGIN(focusBj, group_focus, "i := 2");
  x += 1;
  x += B[MINDEX2(8, 6, 1, 2)];
  x += 1;
  __GHOST_END(focusBj);
  x += 2;
  __GHOST_END(focusBi);

  __GHOST_BEGIN(focusRoBi, group_ro_focus, "i := 1");
  __GHOST_BEGIN(focusRoBj, group_ro_focus, "i := 2");
  x += 1;
  x += B[MINDEX2(8, 6, 1, 2)];
  x += 1;
  __GHOST_END(focusRoBj);
  __GHOST_END(focusRoBi);

  free(B);
}
