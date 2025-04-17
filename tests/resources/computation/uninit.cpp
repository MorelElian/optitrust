#include "../../../include/optitrust.h"

/* TODO:
void init_fst_iter() {
  __pure();

  int x;
  for (int i = 0; i < 5; i++) {
    if (x == 0) {
      x = 0;
    }
    x++;
  }
  x++;
}

void init_fst_iter2(int n) {
  __pure();

  int x;
  if (n == 0) {
    x = 1;
  }
  for (int i = 0; i < n; i++) {
    if (x == 0) {
      x = 2;
    }
    x++;
  }
  x++;
}

void init_cond(bool c) {
  int x;
  if (c) {
    x = 3;
  } else {
    x = 4;
  }
  x++;
}
*/
void init_var_evry_iter() {
  int x;
  for (int i = 0; i < 5; i++) {
    __strict();
    __smodifies("x ~> UninitCell");
    x = 5;
    x++;
  }
}

void init_arr_evry_iter() {
  int* const x = MALLOC1(int, 3);
  for (int i = 0; i < 6; i++) {
    __strict();
    __smodifies("for j in 0..3 -> &x[j] ~> UninitCell");
    for (int j = 0; j < 3; j++) {
      __strict();
      __xconsumes("&x[j] ~> UninitCell");
      __xproduces("&x[j] ~> Cell");
      x[j] = 0;
    }
    for (int j = 0; j < 3; j++) {
      __strict();
      __xmodifies("&x[j] ~> Cell");
      x[j]++;
    }
  }
  free(x);
}
