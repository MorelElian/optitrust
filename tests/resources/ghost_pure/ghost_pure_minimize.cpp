#include <optitrust.h>

__GHOST(trivial_init) {
  __requires("k: int");
  __ensures("k = k");
  __admitted();
}

__GHOST(trivial_change) {
  __requires("k: int, old_k: int, old_k = old_k");
  __ensures("k = k");
  __admitted();
}

void req_triv(int k) {
  __requires("k = k");
}

void f() {
  __pure();

  const int k = 0;
  k+1;
  __ghost(trivial_init, "k");
  k+2;
  __ghost(trivial_change, "k+3");
  __ghost(trivial_change, "k+4");
  req_triv(k+3);
  req_triv(k+4);
  __ghost(trivial_change, "k+5");
}

void g() {
  __pure();
  for (int i = 0; i < 100; ++i) {
    __xensures("i = i");
    __ghost(trivial_init, "i");
    __ghost(trivial_init, "i*2");
    __ghost(trivial_init, "i+12");
    __ghost(trivial_change, "i*3, i*2");
    req_triv(i+12);
  }
}

void must_be_zero(int i) {
  __requires("i = 0");
}

void must_be_zero_ens(int i) {
  __requires("i = 0");
  __ensures("i * 1 = 0");
  __admitted();
}

void h(int i, int j) {
  __requires("i = j");
  if (j == 0) {
    __ghost(assert_alias, "j, 0");
    __ghost(assert_alias, "j, 0");
    must_be_zero(i);
    __ghost(assert_alias, "j, 0");
  }
}

void h2(int i, int j) {
  __requires("i = j");
  if (j == 0) {
    __ghost(assert_alias, "j, 0");
    __ghost(assert_alias, "j, 0");
    must_be_zero_ens(i);
    __ghost(assert_alias, "j, 0");
    must_be_zero(i * 1);
  }
}
