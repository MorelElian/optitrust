int f(int x) { return x + 1; }

int g(int x, int y, int z, int w) {
  int p = x + x + y + z + w;
  return p + p;
}

int h(int x) { return x - 1; }

int m(int x, int y) { return x - y; }

int main() {
  int u = 1;
  int v = 2;
  int w = 3;
  const int a = h(4);
  const int b = m(v, 2);
  int p = a + a + u + b + (w + 1);

  int t = f(p + p);
  return 0;
}
