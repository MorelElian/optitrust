int f(int x) {
  if (x > 0) {
    return x;
  } else {
    return -x;
  }
}

void f_dps(int x, int* res) {
  if (x > 0) {
    *res = x;
  } else {
    *res = -x;
  }
}
