#include <optitrust.h>

void parallel(int* t, int* u, int n) {
  __modifies(
    "for i in 1..n -> &t[i] ~> Cell,"
    "for i in 1..n -> &u[i] ~> Cell");

  for (int i = 1; i < n; i++) {
    __xmodifies(
      "&t[i] ~> Cell,"
      "&u[i] ~> Cell");
    int a = i;
    t[i] += a;
  }
  for (int i = 1; i < n; i++) {
    __xmodifies(
      "&t[i] ~> Cell,"
      "&u[i] ~> Cell");
    int b = i;
    u[i] += b + t[i];
    int c = i;
    u[i] += c;
  }

  for (int i = 0; (i < 5); i++) {
    __strict();
    int y = i;
  }
  for (int i = 0; (i < 5); i++) {
    __strict();
    int z = i;
  }

  for (int i = 0; i < 3; i++) {
    __strict();
    int* const m1 = MALLOC1(int, 5);
    free(m1);
  }
  for (int i = 0; i < 3; i++) {
    int* const m2 = MALLOC1(int, 5);
    free(m2);
  }
}

void uninit(int* t, int* u, int n) {
  __writes("for i in 1..n -> &t[i] ~> Cell");

  int x = 0;
  for (int i = 1; i < n; i++) {
    __strict();
    __xwrites("&t[i] ~> Cell");
    t[i] = i;
  }
  for (int i = 1; i < n; i++) {
    __strict();
    __smodifies("&x ~> Cell");
    __xmodifies("&t[i] ~> Cell");
    x += t[i];
  }
}
/*
void uninit_ro(int* t, int* u, int n) {
  __writes("for i in 1..n -> &t[i] ~> Cell");

  int x = 0;
  for (int i = 1; i < n; i++) {
    __xwrites("&t[i] ~> Cell");
    t[i] = i;
  }
  for (int i = 1; i < n; i++) {
    __smodifies("&x ~> Cell");
    __sreads("for i in 1..n -> &t[i] ~> Cell");

    __GHOST_BEGIN(tf, ro_group_focus, "i := i");
    x += t[i];
    __GHOST_END(tf);
  }
}
*/
void commute() {
  __pure();
  int x = 0;
  int y = 0;
  for (int i = 0; i < 5; i++) {
    __strict();
    __smodifies("&x ~> Cell");
    x++;
  }
  for (int i = 0; i < 5; i++) {
    __strict();
    __smodifies("&y ~> Cell");
    y++;
  }
  int z = 2;
  for (int j = 0; j < 5; j++) {
    __strict();
    __smodifies("&x ~> Cell");
    __sreads("&z ~> Cell");
    x += z;
  }
  for (int j = 0; j < 5; j++) {
    __strict();
    __smodifies("&y ~> Cell");
    __sreads("&z ~> Cell");
    y += z;
  }
  for (int k1 = 0; k1 < 5; k1++) {
    __strict();
    __smodifies("&x ~> Cell");
    x += 1;
  }
  for (int k1 = 0; k1 < 5; k1++) {
    __strict();
    __smodifies("&y ~> Cell");
    for (int k2 = 0; k2 < 5; k2++) {
      __strict();
      __smodifies("&y ~> Cell");
      y += 1;
    }
  }
  for (int k1 = 0; k1 < 5; k1++) {
    __strict();
    __smodifies("&z ~> Cell");
    z += 1;
  }
}


void excl_ros(int* t, int n) {
  __reads("for i in 1..n -> &t[i] ~> Cell");

  int x = 0;
  int y = 0;
  for (int i = 1; i < n; i++) {
    __strict();
    __smodifies("&y ~> Cell");
    __xreads("&t[i] ~> Cell");
    y += t[i];
  }
  for (int i = 1; i < n; i++) {
    __strict();
    __smodifies("&x ~> Cell");
    __xreads("&t[i] ~> Cell");
    x += t[i];
  }
}

void wrong_rw_rw() {
  __pure();

  int x = 0;
  for (int i = 0; i < 4; i++) {
    __strict();
    __smodifies("&x ~> Cell");
    x++;
  }
  for (int i = 0; i < 4; i++) {
    __strict();
    __smodifies("&x ~> Cell");
    x++;
  }
}

void wrong_rw_ro() {
  __pure();

  int x = 0;
  int y = 0;
  for (int i = 0; i < 4; i++) {
    __strict();
    __smodifies("&x ~> Cell");
    x++;
  }
  for (int i = 0; i < 4; i++) {
    __strict();
    __sreads("&x ~> Cell");
    __smodifies("&y ~> Cell");
    y += x;
  }
}

void wrong_ro_rw() {
  __pure();

  int x = 0;
  int y = 0;
  for (int i = 0; i < 4; i++) {
    __strict();
    __sreads("&x ~> Cell");
    __smodifies("&y ~> Cell");
    y += x;
  }
  for (int i = 0; i < 4; i++) {
    __strict();
    __smodifies("&x ~> Cell");
    x++;
  }
}

/* LATER:
void ghosts() {
  __pure();

  int x = 0;
  const __ghost_fn __ghost_pair_1 =
      __ghost_begin(ro_fork_group, "H := &x ~> Cell, r := 0..5");
  for (int i = 0; i < 5; i++) {
    __strict();
    __xreads("&x ~> Cell");
    __ghost(ro_fork_group, "H := &x ~> Cell, r := 0..5");
    for (int k = 0; k < 5; k++) {
      __strict();
      __sreads("for j in 0..5 -> &x ~> Cell");
      for (int j = 0; j < 5; j++) {
        __strict();
        __xreads("&x ~> Cell");
        x + 1;
      }
    }
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
  }
  __ghost_end(__ghost_pair_1);
}

void double_ghosts() {
  __pure();

  int x = 0;
  const __ghost_fn __ghost_pair_1 =
      __ghost_begin(ro_fork_group, "H := &x ~> Cell, r := 0..5");
  for (int i = 0; i < 5; i++) {
    __strict();
    __xreads("&x ~> Cell");
    __ghost(ro_fork_group, "H := &x ~> Cell, r := 0..5");
    __ghost(ro_fork_group, "H := &x ~> Cell, r := 0..5");
    for (int k = 0; k < 5; k++) {
      __strict();
      __sreads("for j in 0..5 -> &x ~> Cell");
      for (int j = 0; j < 5; j++) {
        __strict();
        __xreads("&x ~> Cell");
        x + 1;
      }
    }
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
  }
  __ghost_end(__ghost_pair_1);
}
*/
