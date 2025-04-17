#include <optitrust.h>

void pure(int n, int m, int o, int p, int q) {
  __pure();
  for (int i = 1; i < n; i++) {
    __strict();
    int a = i;
  }
  for (int i = 1; i < n; i++) {
    __strict();
    int b = i;
  }
  for (int i = 1; i < n; i++) {
    __strict();
    int c = i;
  }
  for (int i = 1; i < n; i++) {
    __strict();
    int d = i;
  }
  for (int i = 1; i < n; i++) {
    __strict();
    for (int j = 1; j < m; j++) {
      __strict();
      int x = i;
    }
  }
  for (int i = 1; i < n; i++) {
    __strict();
    for (int j = 1; j < m; j++) {
      __strict();
      int b = i;
    }
  }
  for (int i = 1; i < n; i++) {
    __strict();
    for (int j = 1; j < m; j++) {
      __strict();
      int c = i;
    }
  }
  for (int u = 0; u < o; u++) {
    __strict();
    for (int i = 1; i < n; i++) {
      __strict();
      for (int j = 0; j < m; j++) {
        __strict();
        for (int v = 0; v < p; v++) {
          __strict();
          int x = i;
          int c = i;
        }
      }
    }
    for (int i = 1; i < n; i++) {
      __strict();
      for (int j = 0; j < m; j++) {
        __strict();
        int e = j;
      }
    }
  }
  for (int i = 1; i < n; i++) {
    __strict();
    for (int j = 1; j < m; j++) {
      __strict();
      for (int k = 1; k < o; k++) {
        __strict();
        int y = i;
        int b = i;
      }
    }
  }
  for (int i = 1; i < n; i++) {
    __strict();
    for (int j = 1; j < m; j++) {
      __strict();
      for (int k = 1; k < o; k++) {
        __strict();
        int c = i;
      }
    }
  }
  for (int u = 0; u < o; u++) {
    __strict();
    int a;
    for (int v = 0; v < p; v++) {
      __strict();
      for (int i = 1; i < n; i++) {
        __strict();
        for (int j = 1; j < n; j++) {
          __strict();
          for (int k = 1; k < n; k++) {
            __strict();
            int y = i;
            int b = i;
          }
        }
      }
      for (int i = 1; i < n; i++) {
        __strict();
        for (int j = 1; j < n; j++) {
          __strict();
          for (int k = 1; k < n; k++) {
            __strict();
            int c = i;
          }
        }
      }
    }
  }
}

void seq_ro_par_rw(int m, int n, int o, int* t) {
  __modifies("t ~> Matrix3(m, n, o)");
  int x = 0;
  for (int i = 0; i < m; i++) {
    __strict();
    __sreads("&x ~> Cell");
    __xwrites(
        "for j in 0..n -> for k in 0..o -> &t[MINDEX3(m, n, o, i, j, k)] ~> "
        "Cell");
    for (int j = 0; j < n; j++) {
      __strict();
      __sreads("&x ~> Cell");
      __xwrites("for k in 0..o -> &t[MINDEX3(m, n, o, i, j, k)] ~> Cell");
      for (int k = 0; k < o; k++) {
        __strict();
        __sreads("&x ~> Cell");
        __xwrites("&t[MINDEX3(m, n, o, i, j, k)] ~> Cell");
        t[MINDEX3(m, n, o, i, j, k)] = x;
      }
    }
  }
  for (int i = 0; i < m; i++) {
    __strict();
    __xreads(
        "for j in 0..n -> for k in 0..o -> &t[MINDEX3(m, n, o, i, j, k)] ~> "
        "Cell");
    for (int j = 0; j < n; j++) {
      __strict();
      __xreads("for k in 0..o -> &t[MINDEX3(m, n, o, i, j, k)] ~> Cell");
      for (int k = 0; k < o; k++) {
        __strict();
        __xreads("&t[MINDEX3(m, n, o, i, j, k)] ~> Cell");
        int y = t[MINDEX3(m, n, o, i, j, k)];
      }
    }
  }
}

void ghost_scope(int m, int n) {
  __pure();
  int x = 0;
  for (int i = 0; i < m; i++) {
    __strict();
    __sreads("&x ~> Cell");
    const __ghost_fn xfg =
        __ghost_begin(ro_fork_group, "H := &x ~> Cell, r := 0..n");
    for (int j = 0; j < n; j++) {
      __strict();
      __xreads("&x ~> Cell");
      int y = x;
    }
    __ghost_end(xfg);
  }
  for (int i = 0; i < m; i++) {
    __strict();
    __sreads("&x ~> Cell");
    const __ghost_fn __ghost_pair_1 =
        __ghost_begin(ro_fork_group, "H := &x ~> Cell, r := 0..n");
    for (int j = 0; j < n; j++) {
      __strict();
      __xreads("&x ~> Cell");
      int z = x;
    }
    __ghost_end(__ghost_pair_1);
  }
}

__ghost_ret ensures_pure() {
  __requires("n: int");
  __ensures("__is_true(n == n)");
  __admitted();
}

void requires_pure(int n) { __requires("__is_true(n == n)"); }

void ensures_not_ghost(int n) {
  __ensures("__is_true(n == n)");
  __ghost(ensures_pure, "n := n");
}

void ghost_pure(int m, int n) {
  __pure();
  for (int i = 0; i < m; i++) {
    __strict();
    __xensures("__is_true(5 == 5)");
    __xensures("__is_true(6 == 6)");
    ensures_not_ghost(5);
    ensures_not_ghost(6);
    ensures_not_ghost(7);
    __ghost(ensures_pure, "n := 1", "#_1 <- #212");
    requires_pure(1);
    __ghost(ensures_pure, "n := 3", "#_2 <- #212");
    requires_pure(3);
  }
  for (int i = 0; i < m; i++) {
    __strict();
    __xrequires("__is_true(5 == 5)");
    __xrequires("__is_true(6 == 6)");
    __xensures("__is_true(6 == 6)");
  split:
    __ghost(ensures_pure, "n := 2");
    requires_pure(2);
    __ghost(ensures_pure, "n := 3", "#_3 <- #212");
    requires_pure(3);
    __ghost(ensures_pure, "n := 4", "#_4 <- #212");
    requires_pure(4);
    requires_pure(5);
    requires_pure(6);
  }
}

void edges() {
  for (int i = 0; i < 5; i++) {
    int x = i;
    x++;
  }
}

void specialize_one_fork() {
  __pure();
  int x = 0;
  const __ghost_fn fork_out =
      __ghost_begin(ro_fork_group, "H := &x ~> Cell, r := 0..7");
  for (int i = 0; i < 7; i++) {
    __strict();
    __requires("#_1: _Fraction");
    __xconsumes("_RO(#_1, &x ~> Cell)");
    __xproduces(
        "_RO(#_1 / 2 / range_count(0..5), for #_2 in 0..5 -> &x ~> Cell)");
    __xproduces("_RO(#_1 / 2, &x ~> Cell)");
    __ghost(ro_split2, "f := #_1, H := &x ~> Cell");
    __ghost(ro_fork_group, "f := #_1 / 2, H := &x ~> Cell, r := 0..5");
  }
  for (int i = 0; i < 7; i++) {
    __strict();
    __requires("#_1: _Fraction");
    __xconsumes(
        "_RO(#_1 / 2 / range_count(0..5), for #_2 in 0..5 -> &x ~> Cell)");
    __xconsumes("_RO(#_1 / 2, &x ~> Cell)");
    __xproduces("_RO(#_1, &x ~> Cell)");
    __ghost(ro_allow_join2, "f := #_1, H := &x ~> Cell");
    for (int j = 0; j < 5; j++) {
      __strict();
      __xreads("&x ~> Cell");
      x + 1;
    }
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
  }
  __ghost_end(fork_out);
}

void specialize_two_forks() {
  __pure();
  int x = 0;
  const __ghost_fn fork_out =
      __ghost_begin(ro_fork_group, "H := &x ~> Cell, r := 0..7");
  for (int i = 0; i < 7; i++) {
    __strict();
    __requires("#_1: _Fraction");
    __xconsumes("_RO(#_1, &x ~> Cell)");
    __xproduces(
        "_RO(#_1 / 3 / range_count(0..5), for #_2 in 0..5 -> &x ~> Cell)");
    __xproduces(
        "_RO(#_1 / 3 / range_count(0..5), for #_3 in 0..5 -> &x ~> Cell)");
    __xproduces("_RO(#_1 / 3, &x ~> Cell)");
    __ghost(ro_split3, "f := #_1, H := &x ~> Cell");
    __ghost(ro_fork_group, "f := #_1 / 3, H := &x ~> Cell, r := 0..5");
    __ghost(ro_fork_group, "f := #_1 / 3, H := &x ~> Cell, r := 0..5");
  }
  for (int i = 0; i < 7; i++) {
    __strict();
    __requires("#_1: _Fraction");
    __xconsumes(
        "_RO(#_1 / 3 / range_count(0..5), for #_2 in 0..5 -> &x ~> Cell)");
    __xconsumes(
        "_RO(#_1 / 3 / range_count(0..5), for #_3 in 0..5 -> &x ~> Cell)");
    __xconsumes("_RO(#_1 / 3, &x ~> Cell)");
    __xproduces("_RO(#_1, &x ~> Cell)");
    __ghost(ro_allow_join3, "f := #_1, H := &x ~> Cell");
    for (int j = 0; j < 5; j++) {
      __strict();
      __xreads("&x ~> Cell");
      x + 1;
    }
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
  }
  __ghost_end(fork_out);
}

void specialize_two_forks_twice() {
  __pure();
  int x = 0;
  const __ghost_fn fork_out =
      __ghost_begin(ro_fork_group, "H := &x ~> Cell, r := 0..7");
  for (int i = 0; i < 7; i++) {
    __strict();
    __requires("#_1: _Fraction");
    __xconsumes("_RO(#_1, &x ~> Cell)");
    __xproduces(
        "_RO(#_1 / 2 / 2 / range_count(0..5), for #_2 in 0..5 -> &x ~> Cell)");
    __xproduces(
        "_RO(#_1 / 2 / range_count(0..5), for #_3 in 0..5 -> &x ~> Cell)");
    __xproduces("_RO(#_1 / 2 / 2, &x ~> Cell)");
    __ghost(ro_split2, "f := #_1, H := &x ~> Cell");
    __ghost(ro_split2, "f := #_1 / 2, H := &x ~> Cell");
    __ghost(ro_fork_group, "f := #_1 / 2, H := &x ~> Cell, r := 0..5");
    __ghost(ro_fork_group, "f := #_1 / 2 / 2, H := &x ~> Cell, r := 0..5");
  }
  for (int i = 0; i < 7; i++) {
    __strict();
    __requires("#_1: _Fraction");
    __xconsumes(
        "_RO(#_1 / 2 / 2 / range_count(0..5), for #_2 in 0..5 -> &x ~> Cell)");
    __xconsumes("_RO(#_1 / 2 / 2, &x ~> Cell)");
    __xproduces("_RO(#_1 / 2, &x ~> Cell)");
    __ghost(ro_allow_join2, "f := #_1 / 2, H := &x ~> Cell");
    for (int j = 0; j < 5; j++) {
      __strict();
      __xreads("&x ~> Cell");
      x + 1;
    }
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
  }
  for (int i = 0; i < 7; i++) {
    __strict();
    __requires("#_1: _Fraction");
    __xconsumes("_RO(#_1 / 2, &x ~> Cell)");
    __xconsumes(
        "_RO(#_1 / 2 / range_count(0..5), for j in 0..5 -> &x ~> Cell)");
    __xproduces("_RO(#_1, &x ~> Cell)");
    __ghost(ro_allow_join2, "f := #_1, H := &x ~> Cell");
    __ghost(ro_join_group, "H := &x ~> Cell, r := 0..5");
  }
  __ghost_end(fork_out);
}
