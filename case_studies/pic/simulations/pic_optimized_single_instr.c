#include <omp.h>  // functions omp_get_wtime, omp_get_num_threads, omp_get_thread_num

#include <stdlib.h>

#include <stdio.h>

#include <math.h>

#include "mymacros.h"

#include "mymacros.h"

#include <stdlib.h>

#include <stdbool.h>

#include <stdio.h>

#include <stdio.h>

#include <omp.h>

#include "pic_demo_aux.h"

#include "stdalign.h"

inline int MINDEX1(int N1, int i1) { return i1; }

inline int MINDEX2(int N1, int N2, int i1, int i2) { return i1 * N2 + i2; }

inline int MINDEX3(int N1, int N2, int N3, int i1, int i2, int i3) {
  return i1 * N2 * N3 + i2 * N3 + i3;
}

inline int MINDEX4(int N1, int N2, int N3, int N4, int i1, int i2, int i3,
                   int i4) {
  return i1 * N2 * N3 * N4 + i2 * N3 * N4 + i3 * N4 + i4;
}

void* CALLOC1(int N1, size_t bytes_per_item);

void* CALLOC2(int N1, int N2, size_t bytes_per_item);

void* CALLOC3(int N1, int N2, int N3, size_t bytes_per_item);

void* CALLOC4(int N1, int N2, int N3, int N4, size_t bytes_per_item);

void* MALLOC1(int N1, size_t bytes_per_item);

void* MALLOC2(int N1, int N2, size_t bytes_per_item);

void* MALLOC3(int N1, int N2, int N3, size_t bytes_per_item);

void* MALLOC4(int N1, int N2, int N3, int N4, size_t bytes_per_item);

void* MALLOC_ALIGNED1(size_t N1, size_t bytes_per_item, size_t alignment);

void* MALLOC_ALIGNED2(size_t N1, size_t N2, size_t bytes_per_item,
                      size_t alignment);

void* MALLOC_ALIGNED3(size_t N1, size_t N2, size_t N3, size_t bytes_per_item,
                      size_t alignment);

void* MALLOC_ALIGNED4(size_t N1, size_t N2, size_t N3, size_t N4,
                      size_t bytes_per_item, size_t alignment);

bool ANY_BOOL();

int ANY(int maxValue);

typedef struct {
  double x;
  double y;
  double z;
} vect;

typedef struct {
  double posX;
  double posY;
  double posZ;
  double speedX;
  double speedY;
  double speedZ;
} particle;

vect vect_add(vect v1, vect v2);

vect vect_mul(double d, vect v);

vect vect_add(vect v1, vect v2) {
  return (vect){v1.x + v2.x, v1.y + v2.y, v1.z + v2.z};
}

vect vect_mul(double d, vect v) { return (vect){d * v.x, d * v.y, d * v.z}; }



typedef struct chunk {
  struct chunk* next;
  int size;
  alignas(64) float itemsPosX[CHUNK_SIZE];
  alignas(64) float itemsPosY[CHUNK_SIZE];
  alignas(64) float itemsPosZ[CHUNK_SIZE];
  alignas(64) double itemsSpeedX[CHUNK_SIZE];
  alignas(64) double itemsSpeedY[CHUNK_SIZE];
  alignas(64) double itemsSpeedZ[CHUNK_SIZE];
} chunk;

typedef struct {
  chunk* front;
  chunk* back;
} bag;

typedef struct bag_iter {
  bool destructive;
  chunk* iter_chunk;
  int size;
  int index;
} bag_iter;

void bag_init_using(bag* b, chunk* c);

void bag_init(bag* b);

void bag_append_noinit(bag* b, bag* other);

void bag_append(bag* b, bag* other);

void bag_nullify(bag* b);

int bag_size(bag* b);

void bag_add_front_chunk(bag* b);

void bag_push_concurrent(bag* b, particle p);

void bag_push_serial(bag* b, particle p);

void bag_push(bag* b, particle p);

void bag_swap(bag* b1, bag* b2);

void bag_free(bag* b);

chunk* chunk_next(chunk* c, bool destructive);

chunk* atomic_read_chunk(chunk** p);

void atomic_write_chunk(chunk** p, chunk* v);

int atomic_increment(int* size);

chunk* chunk_alloc() {
  chunk* c;
  if (posix_memalign((void**)&c, 64, sizeof(chunk))) {
    fprintf(stderr, "chunk_alloc: posix_memalign.\n");
    exit(1);
  }
  return c;
}

void chunk_free(chunk* c) { free(c); }

chunk* bag_chunk_alloc() { return chunk_alloc(); }

void bag_chunk_free(chunk* c) { chunk_free(c); }

void bag_init_using(bag* b, chunk* c) {
  c->size = 0;
  c->next = NULL;
  b->front = c;
  b->back = c;
}

void bag_init(bag* b) {
  chunk* c = bag_chunk_alloc();
  bag_init_using(b, c);
}

void bag_append(bag* b, bag* other) {
  if (other->front) {
    b->back->next = other->front;
    b->back = other->back;
    bag_init(other);
  }
}

void bag_nullify(bag* b) {
  b->front = NULL;
  b->back = NULL;
}

int bag_size(bag* b) {
  chunk* c = b->front;
  int size = 0;
  while (c) {
    size += c->size;
    c = c->next;
  }
  return size;
}

void bag_add_front_chunk_serial(bag* b) {
  chunk* c = bag_chunk_alloc();
  c->size = 0;
  c->next = b->front;
  b->front = c;
}

void bag_add_front_chunk_concurrent(bag* b) {
  chunk* c = bag_chunk_alloc();
  c->size = 0;
  c->next = b->front;
  atomic_write_chunk(&b->front, c);
}

void bag_push_concurrent(bag* b, particle p) {
  chunk* c;
  int index;
  while (true) {
    c = b->front;
    index = atomic_increment(&c->size);
    if (index < CHUNK_SIZE) {
      c->itemsPosX[index] = p.posX;
      c->itemsPosY[index] = p.posY;
      c->itemsPosZ[index] = p.posZ;
      c->itemsSpeedX[index] = p.speedX;
      c->itemsSpeedY[index] = p.speedY;
      c->itemsSpeedZ[index] = p.speedZ;
      if (index == CHUNK_SIZE - 1) {
        bag_add_front_chunk_concurrent(b);
      }
      return;
    } else {
      c->size = CHUNK_SIZE;
      while (atomic_read_chunk(&b->front) == c) {
      }
    }
  }
}

void bag_push_serial(bag* b, particle p) {
  chunk* c = b->front;
  int index = c->size;
  c->size++;
  c->itemsPosX[index] = p.posX;
  c->itemsPosY[index] = p.posY;
  c->itemsPosZ[index] = p.posZ;
  c->itemsSpeedX[index] = p.speedX;
  c->itemsSpeedY[index] = p.speedY;
  c->itemsSpeedZ[index] = p.speedZ;
  if (index == CHUNK_SIZE - 1) {
    bag_add_front_chunk_serial(b);
  }
}

void bag_push(bag* b, particle p) { bag_push_serial(b, p); }

void bag_swap(bag* b1, bag* b2) {
  bag temp = *b1;
  *b1 = *b2;
  *b2 = temp;
}

chunk* chunk_next(chunk* c, bool destructive) {
  chunk* cnext = c->next;
  if (destructive) {
    bag_chunk_free(c);
  }
  return cnext;
}

void bag_free(bag* b) {
  chunk* c = b->front;
  while (c != NULL) {
    c = chunk_next(c, true);
  }
}

double areaX;

double areaY;

double areaZ;

int gridX;

int gridY;

int gridZ;

const int block = 2;

const int halfBlock = 1;

int nbThreads;

int nbCells;

double cellX;

double cellY;

double cellZ;

int nbSteps;

double stepDuration;

double averageChargeDensity;

double averageMassDensity;

double particleCharge;

double particleMass;

int nbParticles;

char sim_distrib;

double* params;

double* speed_params;

int seed;

double*** rho;

double*** Ex;

double*** Ey;

double*** Ez;

vect* field;

alignas(64) double* deposit;

bag* bagsCur;

void addParticle(double x, double y, double z, double vx, double vy, double vz);

int cellOfCoord(int i, int j, int k);

void allocateStructures();

void allocateStructuresForPoissonSolver();

void deallocateStructures();

void deallocateStructuresForPoissonSolver();

inline int int_of_double(double a) { return (int)a - (a < 0.); }

inline int wrap(int gridSize, int a) {
  return (a % gridSize + gridSize) % gridSize;
}

const int nbCorners = 8;

inline int cellOfCoord(int i, int j, int k) {
  return MINDEX3(gridX, gridY, gridZ, i, j, k);
}

int idCellOfPos(vect pos) {
  const int iX = int_of_double(pos.x / cellX);
  const int iY = int_of_double(pos.y / cellY);
  const int iZ = int_of_double(pos.z / cellZ);
  return cellOfCoord(iX, iY, iZ);
}

double fwrap(double gridWidth, double x) {
  const double r = fmod(x, gridWidth);
  if (r >= 0) {
    return r;
  } else {
    return r + gridWidth;
  }
}

inline double relativePosX(double x) {
  const int iX = int_of_double(x / cellX);
  return (x - iX * cellX) / cellX;
}

inline double relativePosY(double y) {
  const int iY = int_of_double(y / cellY);
  return (y - iY * cellY) / cellY;
}

inline double relativePosZ(double z) {
  const int iZ = int_of_double(z / cellZ);
  return (z - iZ * cellZ) / cellZ;
}

typedef struct {
  int iX;
  int iY;
  int iZ;
} coord;

inline coord coordOfCell(int idCell) {
  const int iZ = idCell % gridZ;
  const int iXY = idCell / gridZ;
  const int iY = iXY % gridY;
  const int iX = iXY / gridY;
  return (coord){iX, iY, iZ};
}

typedef struct { int v[8]; } int_nbCorners;

typedef struct { double v[8]; } double_nbCorners;

typedef struct { vect v[8]; } vect_nbCorners;

int_nbCorners indicesOfCorners(int idCell) {
  const coord coord = coordOfCell(idCell);
  const int x = coord.iX;
  const int y = coord.iY;
  const int z = coord.iZ;
  const int x2 = wrap(gridX, x + 1);
  const int y2 = wrap(gridY, y + 1);
  const int z2 = wrap(gridZ, z + 1);
  return (int_nbCorners){{cellOfCoord(x, y, z), cellOfCoord(x, y, z2),
                          cellOfCoord(x, y2, z), cellOfCoord(x, y2, z2),
                          cellOfCoord(x2, y, z), cellOfCoord(x2, y, z2),
                          cellOfCoord(x2, y2, z), cellOfCoord(x2, y2, z2)}};
}

void accumulateChargeAtCorners(double* deposit, int idCell,
                               double_nbCorners charges) {
  const int_nbCorners indices = indicesOfCorners(idCell);
  for (int idCorner = 0; idCorner < nbCorners; idCorner++) {
    deposit[MINDEX1(nbCells, indices.v[idCorner])] += charges.v[idCorner];
  }
}

alignas(64) const double coefX[8] = {1., 1., 1., 1., 0., 0., 0., 0.};

alignas(64) const double signX[8] = {-1., -1., -1., -1., 1., 1., 1., 1.};

alignas(64) const double coefY[8] = {1., 1., 0., 0., 1., 1., 0., 0.};

alignas(64) const double signY[8] = {-1., -1., 1., 1., -1., -1., 1., 1.};

alignas(64) const double coefZ[8] = {1., 0., 1., 0., 1., 0., 1., 0.};

alignas(64) const double signZ[8] = {-1., 1., -1., 1., -1., 1., -1., 1.};

double_nbCorners cornerInterpolationCoeff(vect pos) {
  const int iX = int_of_double(pos.x / cellX);
  const double rX = (pos.x - iX * cellX) / cellX;
  const int iY = int_of_double(pos.y / cellY);
  const double rY = (pos.y - iY * cellY) / cellY;
  const int iZ = int_of_double(pos.z / cellZ);
  const double rZ = (pos.z - iZ * cellZ) / cellZ;
  double_nbCorners r;
  for (int idCorner = 0; idCorner < nbCorners; idCorner++) {
    r.v[idCorner] = (coefX[idCorner] + signX[idCorner] * rX) *
                    (coefY[idCorner] + signY[idCorner] * rY) *
                    (coefZ[idCorner] + signZ[idCorner] * rZ);
  }
  return r;
}

void computeRhoFromDeposit() {
  const double factor = averageChargeDensity * nbCells / nbParticles;
  for (int i = 0; i < gridX; i++) {
    for (int j = 0; j < gridY; j++) {
      for (int k = 0; k < gridZ; k++) {
        rho[i][j][k] = factor * deposit[MINDEX1(nbCells, cellOfCoord(i, j, k))];
      }
    }
  }
}

void resetDeposit() {
  for (int idCell = 0; idCell < nbCells; idCell++) {
    deposit[MINDEX1(nbCells, idCell)] = 0;
  }
}

void updateFieldUsingDeposit() {
  computeRhoFromDeposit();
  computeFieldFromRho();
  resetDeposit();
}

alignas(64) double* depositCorners;

alignas(64) double* depositThreadCorners;

bag* bagsNexts;

void allocateStructures() {
  allocateStructuresForPoissonSolver();
  deposit = (double*)MALLOC_ALIGNED1(nbCells, sizeof(double), 64);
  depositCorners =
      (double*)MALLOC_ALIGNED2(nbCells, nbCorners, sizeof(double), 64);
  depositThreadCorners = (double*)MALLOC_ALIGNED3(nbThreads, nbCells, nbCorners,
                                                  sizeof(double), 64);
  field = (vect*)malloc(nbCells * sizeof(vect));
  bagsCur = (bag*)malloc(nbCells * sizeof(bag));
  bagsNexts = (bag*)MALLOC_ALIGNED2(nbCells, 2, sizeof(bag), 64);
  for (int idCell = 0; idCell < nbCells; idCell++) {
    for (int bagsKind = 0; bagsKind < 2; bagsKind++) {
      bag_init(&bagsNexts[MINDEX2(nbCells, 2, idCell, bagsKind)]);
    }
  }
  for (int idCell = 0; idCell < nbCells; idCell++) {
    bag_init(&bagsCur[idCell]);
  }
}

void deallocateStructures() {
  deallocateStructuresForPoissonSolver();
  for (int idCell = 0; idCell < nbCells; idCell++) {
    bag_free(&bagsCur[idCell]);
  }
  for (int idCell = 0; idCell < nbCells; idCell++) {
    for (int bagsKind = 0; bagsKind < 2; bagsKind++) {
      bag_free(&bagsNexts[MINDEX2(nbCells, 2, idCell, bagsKind)]);
    }
  }
  free(bagsNexts);
  free(depositThreadCorners);
  free(depositCorners);
  free(bagsCur);
  free(field);
}

void computeConstants() {
  nbCells = gridX * gridY * gridZ;
  cellX = areaX / gridX;
  cellY = areaY / gridY;
  cellZ = areaZ / gridZ;
  const double cellVolume = cellX * cellY * cellZ;
  const double totalVolume = nbCells * cellVolume;
  const double totalCharge = averageChargeDensity * totalVolume;
  const double totalMass = averageMassDensity * totalVolume;
  particleCharge = totalCharge / nbParticles;
  particleMass = totalMass / nbParticles;
}

void addParticle(double x, double y, double z, double vx, double vy,
                 double vz) {
  vect pos = {x, y, z};
  vect speed = {vx, vy, vz};
  const int idCell = idCellOfPos(pos);
  const coord co = coordOfCell(idCell);
  particle p;
  p.posX = pos.x / cellX - co.iX;
  p.posY = pos.y / cellY - co.iY;
  p.posZ = pos.z / cellZ - co.iZ;
  p.speedX = speed.x / (cellX / stepDuration);
  p.speedY = speed.y / (cellY / stepDuration);
  p.speedZ = speed.z / (cellZ / stepDuration);
  bag_push(&bagsCur[idCell], p);
  double_nbCorners contribs = cornerInterpolationCoeff(pos);
  accumulateChargeAtCorners(deposit, idCell, contribs);
}

void stepLeapFrog() {
  updateFieldUsingDeposit();
  const double negHalfStepDuration = -0.5 * stepDuration;
  const double factorC =
      particleCharge * (stepDuration * stepDuration) / particleMass;
  const double factorX = factorC / cellX;
  const double factorY = factorC / cellY;
  const double factorZ = factorC / cellZ;
#pragma omp parallel for
  for (int idCell = 0; idCell < nbCells; idCell++) {
    bag* b = &bagsCur[idCell];
    const int_nbCorners indices = indicesOfCorners(idCell);
    vect_nbCorners field_at_corners;
    for (int idCorner = 0; idCorner < nbCorners; idCorner++) {
      field_at_corners.v[idCorner].x = field[indices.v[idCorner]].x * factorX;
      field_at_corners.v[idCorner].y = field[indices.v[idCorner]].y * factorY;
      field_at_corners.v[idCorner].z = field[indices.v[idCorner]].z * factorZ;
    }
    for (chunk* c = b->front; c != NULL; c = chunk_next(c, false)) {
      const int nb = c->size;
#pragma omp simd
      for (int i = 0; i < nb; i++) {
        double_nbCorners coeffs;
        c->itemsSpeedX[i] = c->itemsSpeedX[i] +
                            negHalfStepDuration * particleCharge /
                                particleMass *
                                ((coefX[0] + signX[0] * c->itemsPosX[i]) *
                                     (coefY[0] + signY[0] * c->itemsPosY[i]) *
                                     (coefZ[0] + signZ[0] * c->itemsPosZ[i]) *
                                     field_at_corners.v[0].x +
                                 (coefX[1] + signX[1] * c->itemsPosX[i]) *
                                     (coefY[1] + signY[1] * c->itemsPosY[i]) *
                                     (coefZ[1] + signZ[1] * c->itemsPosZ[i]) *
                                     field_at_corners.v[1].x +
                                 (coefX[2] + signX[2] * c->itemsPosX[i]) *
                                     (coefY[2] + signY[2] * c->itemsPosY[i]) *
                                     (coefZ[2] + signZ[2] * c->itemsPosZ[i]) *
                                     field_at_corners.v[2].x +
                                 (coefX[3] + signX[3] * c->itemsPosX[i]) *
                                     (coefY[3] + signY[3] * c->itemsPosY[i]) *
                                     (coefZ[3] + signZ[3] * c->itemsPosZ[i]) *
                                     field_at_corners.v[3].x +
                                 (coefX[4] + signX[4] * c->itemsPosX[i]) *
                                     (coefY[4] + signY[4] * c->itemsPosY[i]) *
                                     (coefZ[4] + signZ[4] * c->itemsPosZ[i]) *
                                     field_at_corners.v[4].x +
                                 (coefX[5] + signX[5] * c->itemsPosX[i]) *
                                     (coefY[5] + signY[5] * c->itemsPosY[i]) *
                                     (coefZ[5] + signZ[5] * c->itemsPosZ[i]) *
                                     field_at_corners.v[5].x +
                                 (coefX[6] + signX[6] * c->itemsPosX[i]) *
                                     (coefY[6] + signY[6] * c->itemsPosY[i]) *
                                     (coefZ[6] + signZ[6] * c->itemsPosZ[i]) *
                                     field_at_corners.v[6].x +
                                 (coefX[7] + signX[7] * c->itemsPosX[i]) *
                                     (coefY[7] + signY[7] * c->itemsPosY[i]) *
                                     (coefZ[7] + signZ[7] * c->itemsPosZ[i]) *
                                     field_at_corners.v[7].x) /
                                factorX * stepDuration / cellX;
        c->itemsSpeedY[i] = c->itemsSpeedY[i] +
                            negHalfStepDuration * particleCharge /
                                particleMass *
                                ((coefX[0] + signX[0] * c->itemsPosX[i]) *
                                     (coefY[0] + signY[0] * c->itemsPosY[i]) *
                                     (coefZ[0] + signZ[0] * c->itemsPosZ[i]) *
                                     field_at_corners.v[0].y +
                                 (coefX[1] + signX[1] * c->itemsPosX[i]) *
                                     (coefY[1] + signY[1] * c->itemsPosY[i]) *
                                     (coefZ[1] + signZ[1] * c->itemsPosZ[i]) *
                                     field_at_corners.v[1].y +
                                 (coefX[2] + signX[2] * c->itemsPosX[i]) *
                                     (coefY[2] + signY[2] * c->itemsPosY[i]) *
                                     (coefZ[2] + signZ[2] * c->itemsPosZ[i]) *
                                     field_at_corners.v[2].y +
                                 (coefX[3] + signX[3] * c->itemsPosX[i]) *
                                     (coefY[3] + signY[3] * c->itemsPosY[i]) *
                                     (coefZ[3] + signZ[3] * c->itemsPosZ[i]) *
                                     field_at_corners.v[3].y +
                                 (coefX[4] + signX[4] * c->itemsPosX[i]) *
                                     (coefY[4] + signY[4] * c->itemsPosY[i]) *
                                     (coefZ[4] + signZ[4] * c->itemsPosZ[i]) *
                                     field_at_corners.v[4].y +
                                 (coefX[5] + signX[5] * c->itemsPosX[i]) *
                                     (coefY[5] + signY[5] * c->itemsPosY[i]) *
                                     (coefZ[5] + signZ[5] * c->itemsPosZ[i]) *
                                     field_at_corners.v[5].y +
                                 (coefX[6] + signX[6] * c->itemsPosX[i]) *
                                     (coefY[6] + signY[6] * c->itemsPosY[i]) *
                                     (coefZ[6] + signZ[6] * c->itemsPosZ[i]) *
                                     field_at_corners.v[6].y +
                                 (coefX[7] + signX[7] * c->itemsPosX[i]) *
                                     (coefY[7] + signY[7] * c->itemsPosY[i]) *
                                     (coefZ[7] + signZ[7] * c->itemsPosZ[i]) *
                                     field_at_corners.v[7].y) /
                                factorY * stepDuration / cellY;
        c->itemsSpeedZ[i] = c->itemsSpeedZ[i] +
                            negHalfStepDuration * particleCharge /
                                particleMass *
                                ((coefX[0] + signX[0] * c->itemsPosX[i]) *
                                     (coefY[0] + signY[0] * c->itemsPosY[i]) *
                                     (coefZ[0] + signZ[0] * c->itemsPosZ[i]) *
                                     field_at_corners.v[0].z +
                                 (coefX[1] + signX[1] * c->itemsPosX[i]) *
                                     (coefY[1] + signY[1] * c->itemsPosY[i]) *
                                     (coefZ[1] + signZ[1] * c->itemsPosZ[i]) *
                                     field_at_corners.v[1].z +
                                 (coefX[2] + signX[2] * c->itemsPosX[i]) *
                                     (coefY[2] + signY[2] * c->itemsPosY[i]) *
                                     (coefZ[2] + signZ[2] * c->itemsPosZ[i]) *
                                     field_at_corners.v[2].z +
                                 (coefX[3] + signX[3] * c->itemsPosX[i]) *
                                     (coefY[3] + signY[3] * c->itemsPosY[i]) *
                                     (coefZ[3] + signZ[3] * c->itemsPosZ[i]) *
                                     field_at_corners.v[3].z +
                                 (coefX[4] + signX[4] * c->itemsPosX[i]) *
                                     (coefY[4] + signY[4] * c->itemsPosY[i]) *
                                     (coefZ[4] + signZ[4] * c->itemsPosZ[i]) *
                                     field_at_corners.v[4].z +
                                 (coefX[5] + signX[5] * c->itemsPosX[i]) *
                                     (coefY[5] + signY[5] * c->itemsPosY[i]) *
                                     (coefZ[5] + signZ[5] * c->itemsPosZ[i]) *
                                     field_at_corners.v[5].z +
                                 (coefX[6] + signX[6] * c->itemsPosX[i]) *
                                     (coefY[6] + signY[6] * c->itemsPosY[i]) *
                                     (coefZ[6] + signZ[6] * c->itemsPosZ[i]) *
                                     field_at_corners.v[6].z +
                                 (coefX[7] + signX[7] * c->itemsPosX[i]) *
                                     (coefY[7] + signY[7] * c->itemsPosY[i]) *
                                     (coefZ[7] + signZ[7] * c->itemsPosZ[i]) *
                                     field_at_corners.v[7].z) /
                                factorZ * stepDuration / cellZ;
      }
    }
  }
}

double fwrapInt(int m, double v) {
  const int q = int_of_double(v);
  const double r = v - q;
  const int j = wrap(m, q);
  return j + r;
}

int bij(int nbCells, int nbCorners, int idCell, int idCorner) {
  coord coord = coordOfCell(idCell);
  int iX = coord.iX;
  int iY = coord.iY;
  int iZ = coord.iZ;
  int res[8] = {cellOfCoord(iX, iY, iZ),
                cellOfCoord(iX, iY, wrap(gridZ, iZ - 1)),
                cellOfCoord(iX, wrap(gridY, iY - 1), iZ),
                cellOfCoord(iX, wrap(gridY, iY - 1), wrap(gridZ, iZ - 1)),
                cellOfCoord(wrap(gridX, iX - 1), iY, iZ),
                cellOfCoord(wrap(gridX, iX - 1), iY, wrap(gridZ, iZ - 1)),
                cellOfCoord(wrap(gridX, iX - 1), wrap(gridY, iY - 1), iZ),
                cellOfCoord(wrap(gridX, iX - 1), wrap(gridY, iY - 1),
                            wrap(gridZ, iZ - 1))};
  return MINDEX2(nbCells, nbCorners, res[idCorner], idCorner);
}

const int PRIVATE = 0;

const int SHARED = 1;

//===========================================================================
#ifdef ANALYZEPERF
#define MAXNBTHREADS 40
#define CONTRIBPADDING 32 // must be twice more than the largest key used
#define CONTRIBSIZE (MAXNBTHREADS*CONTRIBPADDING)
double contrib[CONTRIBSIZE];
void contrib_reset() {
  for (int i = 0; i < CONTRIBSIZE; i++) {
    contrib[i] = 0.0;
  }
}
void contrib_report(double total, int nbReports) {
  /*for (int idThread = 0; idThread < 2; idThread++) {
    for (int key = 0; key < nbReports; key++) {
      printf("ANALYSEPERF:contrib[thread=%d][key=%d] = %.3lf\n", idThread, key, contrib[idThread * CONTRIBPADDING + key]);
    }
  }*/
  // collapse all contributions on thread 0
  for (int idThread = 1; idThread < MAXNBTHREADS; idThread++) {
    for (int key = 0; key < CONTRIBPADDING; key++) {
      contrib[key] += contrib[idThread * CONTRIBPADDING + key];
    }
  }
  double totalValues = 0.0;
  double totalPercent = 0.0;
  for (int key = 0; key < nbReports; key++) {
    double value = contrib[key];
    double percent = 100. * value / total;
    totalValues += value;
    totalPercent += percent;
    if (value != 0.0) {
      printf("ANALYSEPERF:contrib[%d] = %.3lf\t %.1lf%%\n", key, value, percent);
    }
  }
  printf("ANALYZEPERF:total = %.3lf\t %.1lf%%\n", totalValues, totalPercent);
}
#define CONTRIB_TIME(idThread, key, value) contrib[idThread * CONTRIBPADDING + key] += value;
#else
#define CONTRIB_TIME(idThread, key, value)
#endif
#define CONTRIB_PRE 0
#define CONTRIB_FIELD 1
#define CONTRIB_SPEED_LOOP 2
#define CONTRIB_POS_LOOP 3
#define CONTRIB_PUSH_LOOP 4
#define CONTRIB_REDUCE 5
#define CONTRIB_POISSON 6
#define CONTRIB_STEP1 7
#define CONTRIB_STEP2 8
#define CONTRIB_STEP3 9
#define CONTRIB_NONATOMIC_PUSH 10
#define CONTRIB_ATOMIC_PUSH 11

//===========================================================================

void step() {
  double contrib_time_00 = omp_get_wtime();
  double contrib_time_8 = omp_get_wtime();
  const double factorC =
      particleCharge * (stepDuration * stepDuration) / particleMass;
  const double factorX =
      particleCharge * (stepDuration * stepDuration) / particleMass / cellX;
  const double factorY =
      particleCharge * (stepDuration * stepDuration) / particleMass / cellY;
  const double factorZ =
      particleCharge * (stepDuration * stepDuration) / particleMass / cellZ;
#pragma omp parallel for
  for (int idCell = 0; idCell < nbCells; idCell++) {
    for (int idCorner = 0; idCorner < nbCorners; idCorner++) {
      for (int idThread = 0; idThread < nbThreads; idThread++) {
        depositThreadCorners[MINDEX3(nbThreads, nbCells, nbCorners, idThread,
                                     idCell, idCorner)] = 0.;
      }
    }
  }
  double contrib_time_9 = omp_get_wtime();
  CONTRIB_TIME(0, CONTRIB_PRE, (contrib_time_9 - contrib_time_8) * nbThreads);
core:
  for (int cX = 0; cX < 2; cX++) {
    for (int cY = 0; cY < 2; cY++) {
      for (int cZ = 0; cZ < 2; cZ++) {
#pragma omp parallel for collapse(3)
        for (int bX = cX * block; bX < gridX; bX += 2 * block) {
          for (int bY = cY * block; bY < gridY; bY += 2 * block) {
            for (int bZ = cZ * block; bZ < gridZ; bZ += 2 * block) {
              const int idThread = omp_get_thread_num();
              for (int iX = bX; iX < bX + block; iX++) {
                for (int iY = bY; iY < bY + block; iY++) {
                  for (int iZ = bZ; iZ < bZ + block; iZ++) {
                    double contrib_time_10 = omp_get_wtime();
                    const int idCell = (iX * gridY + iY) * gridZ + iZ;
                    const int_nbCorners indices = indicesOfCorners(idCell);
                    vect_nbCorners field_at_corners;
                    for (int idCorner = 0; idCorner < nbCorners; idCorner++) {
                      field_at_corners.v[idCorner].x =
                          field[indices.v[idCorner]].x * factorX;
                      field_at_corners.v[idCorner].y =
                          field[indices.v[idCorner]].y * factorY;
                      field_at_corners.v[idCorner].z =
                          field[indices.v[idCorner]].z * factorZ;
                    }
                    double contrib_time_11 = omp_get_wtime();
                    CONTRIB_TIME(idThread, CONTRIB_FIELD, (contrib_time_11 - contrib_time_10));
                    bag* b = &bagsCur[idCell];
                    for (chunk* c = b->front; c != NULL;
                         c = chunk_next(c, true)) {
                      const int nb = c->size;
                      alignas(64) int idCell2_step[CHUNK_SIZE];
                      double contrib_time_0 = omp_get_wtime();
#pragma omp simd
                      for (int i = 0; i < nb; i++) {
                        double_nbCorners coeffs;
                        c->itemsSpeedX[i] +=
                            (coefX[0] + signX[0] * c->itemsPosX[i]) *
                                (coefY[0] + signY[0] * c->itemsPosY[i]) *
                                (coefZ[0] + signZ[0] * c->itemsPosZ[i]) *
                                field_at_corners.v[0].x +
                            (coefX[1] + signX[1] * c->itemsPosX[i]) *
                                (coefY[1] + signY[1] * c->itemsPosY[i]) *
                                (coefZ[1] + signZ[1] * c->itemsPosZ[i]) *
                                field_at_corners.v[1].x +
                            (coefX[2] + signX[2] * c->itemsPosX[i]) *
                                (coefY[2] + signY[2] * c->itemsPosY[i]) *
                                (coefZ[2] + signZ[2] * c->itemsPosZ[i]) *
                                field_at_corners.v[2].x +
                            (coefX[3] + signX[3] * c->itemsPosX[i]) *
                                (coefY[3] + signY[3] * c->itemsPosY[i]) *
                                (coefZ[3] + signZ[3] * c->itemsPosZ[i]) *
                                field_at_corners.v[3].x +
                            (coefX[4] + signX[4] * c->itemsPosX[i]) *
                                (coefY[4] + signY[4] * c->itemsPosY[i]) *
                                (coefZ[4] + signZ[4] * c->itemsPosZ[i]) *
                                field_at_corners.v[4].x +
                            (coefX[5] + signX[5] * c->itemsPosX[i]) *
                                (coefY[5] + signY[5] * c->itemsPosY[i]) *
                                (coefZ[5] + signZ[5] * c->itemsPosZ[i]) *
                                field_at_corners.v[5].x +
                            (coefX[6] + signX[6] * c->itemsPosX[i]) *
                                (coefY[6] + signY[6] * c->itemsPosY[i]) *
                                (coefZ[6] + signZ[6] * c->itemsPosZ[i]) *
                                field_at_corners.v[6].x +
                            (coefX[7] + signX[7] * c->itemsPosX[i]) *
                                (coefY[7] + signY[7] * c->itemsPosY[i]) *
                                (coefZ[7] + signZ[7] * c->itemsPosZ[i]) *
                                field_at_corners.v[7].x;
                        c->itemsSpeedY[i] +=
                            (coefX[0] + signX[0] * c->itemsPosX[i]) *
                                (coefY[0] + signY[0] * c->itemsPosY[i]) *
                                (coefZ[0] + signZ[0] * c->itemsPosZ[i]) *
                                field_at_corners.v[0].y +
                            (coefX[1] + signX[1] * c->itemsPosX[i]) *
                                (coefY[1] + signY[1] * c->itemsPosY[i]) *
                                (coefZ[1] + signZ[1] * c->itemsPosZ[i]) *
                                field_at_corners.v[1].y +
                            (coefX[2] + signX[2] * c->itemsPosX[i]) *
                                (coefY[2] + signY[2] * c->itemsPosY[i]) *
                                (coefZ[2] + signZ[2] * c->itemsPosZ[i]) *
                                field_at_corners.v[2].y +
                            (coefX[3] + signX[3] * c->itemsPosX[i]) *
                                (coefY[3] + signY[3] * c->itemsPosY[i]) *
                                (coefZ[3] + signZ[3] * c->itemsPosZ[i]) *
                                field_at_corners.v[3].y +
                            (coefX[4] + signX[4] * c->itemsPosX[i]) *
                                (coefY[4] + signY[4] * c->itemsPosY[i]) *
                                (coefZ[4] + signZ[4] * c->itemsPosZ[i]) *
                                field_at_corners.v[4].y +
                            (coefX[5] + signX[5] * c->itemsPosX[i]) *
                                (coefY[5] + signY[5] * c->itemsPosY[i]) *
                                (coefZ[5] + signZ[5] * c->itemsPosZ[i]) *
                                field_at_corners.v[5].y +
                            (coefX[6] + signX[6] * c->itemsPosX[i]) *
                                (coefY[6] + signY[6] * c->itemsPosY[i]) *
                                (coefZ[6] + signZ[6] * c->itemsPosZ[i]) *
                                field_at_corners.v[6].y +
                            (coefX[7] + signX[7] * c->itemsPosX[i]) *
                                (coefY[7] + signY[7] * c->itemsPosY[i]) *
                                (coefZ[7] + signZ[7] * c->itemsPosZ[i]) *
                                field_at_corners.v[7].y;
                        c->itemsSpeedZ[i] +=
                            (coefX[0] + signX[0] * c->itemsPosX[i]) *
                                (coefY[0] + signY[0] * c->itemsPosY[i]) *
                                (coefZ[0] + signZ[0] * c->itemsPosZ[i]) *
                                field_at_corners.v[0].z +
                            (coefX[1] + signX[1] * c->itemsPosX[i]) *
                                (coefY[1] + signY[1] * c->itemsPosY[i]) *
                                (coefZ[1] + signZ[1] * c->itemsPosZ[i]) *
                                field_at_corners.v[1].z +
                            (coefX[2] + signX[2] * c->itemsPosX[i]) *
                                (coefY[2] + signY[2] * c->itemsPosY[i]) *
                                (coefZ[2] + signZ[2] * c->itemsPosZ[i]) *
                                field_at_corners.v[2].z +
                            (coefX[3] + signX[3] * c->itemsPosX[i]) *
                                (coefY[3] + signY[3] * c->itemsPosY[i]) *
                                (coefZ[3] + signZ[3] * c->itemsPosZ[i]) *
                                field_at_corners.v[3].z +
                            (coefX[4] + signX[4] * c->itemsPosX[i]) *
                                (coefY[4] + signY[4] * c->itemsPosY[i]) *
                                (coefZ[4] + signZ[4] * c->itemsPosZ[i]) *
                                field_at_corners.v[4].z +
                            (coefX[5] + signX[5] * c->itemsPosX[i]) *
                                (coefY[5] + signY[5] * c->itemsPosY[i]) *
                                (coefZ[5] + signZ[5] * c->itemsPosZ[i]) *
                                field_at_corners.v[5].z +
                            (coefX[6] + signX[6] * c->itemsPosX[i]) *
                                (coefY[6] + signY[6] * c->itemsPosY[i]) *
                                (coefZ[6] + signZ[6] * c->itemsPosZ[i]) *
                                field_at_corners.v[6].z +
                            (coefX[7] + signX[7] * c->itemsPosX[i]) *
                                (coefY[7] + signY[7] * c->itemsPosY[i]) *
                                (coefZ[7] + signZ[7] * c->itemsPosZ[i]) *
                                field_at_corners.v[7].z;
                      }
                      double contrib_time_1 = omp_get_wtime();
#pragma omp simd
                      for (int i = 0; i < nb; i++) {
                        const double pX =
                            c->itemsPosX[i] + iX + c->itemsSpeedX[i];
                        const double pY =
                            c->itemsPosY[i] + iY + c->itemsSpeedY[i];
                        const double pZ =
                            c->itemsPosZ[i] + iZ + c->itemsSpeedZ[i];
                        const int qX = int_of_double(pX);
                        const double rX = pX - qX;
                        const int iX2 = qX & gridX + -1;
                        const int qY = int_of_double(pY);
                        const double rY = pY - qY;
                        const int iY2 = qY & gridY + -1;
                        const int qZ = int_of_double(pZ);
                        const double rZ = pZ - qZ;
                        const int iZ2 = qZ & gridZ + -1;
                        idCell2_step[i] =
                            MINDEX3(gridX, gridY, gridZ, iX2, iY2, iZ2);
                        c->itemsPosX[i] = (float)rX;
                        c->itemsPosY[i] = (float)rY;
                        c->itemsPosZ[i] = (float)rZ;
                      }
                      double contrib_time_2 = omp_get_wtime();
                      for (int i = 0; i < nb; i++) {
                        particle p2;
                        p2.posX = c->itemsPosX[i];
                        p2.posY = c->itemsPosY[i];
                        p2.posZ = c->itemsPosZ[i];
                        p2.speedX = c->itemsSpeedX[i];
                        p2.speedY = c->itemsSpeedY[i];
                        p2.speedZ = c->itemsSpeedZ[i];
                        const coord co = coordOfCell(idCell2_step[i]);
                        const bool isDistFromBlockLessThanHalfABlock =
                            co.iX >= bX - halfBlock &&
                                co.iX < bX + block + halfBlock ||
                            bX == 0 && co.iX >= gridX - halfBlock ||
                            bX == gridX - block && co.iX < halfBlock &&
                                (co.iY >= bY - halfBlock &&
                                 co.iY < bY + block + halfBlock) ||
                            bY == 0 && co.iY >= gridY - halfBlock ||
                            bY == gridY - block && co.iY < halfBlock &&
                                (co.iZ >= bZ - halfBlock &&
                                 co.iZ < bZ + block + halfBlock) ||
                            bZ == 0 && co.iZ >= gridZ - halfBlock ||
                            bZ == gridZ - block && co.iZ < halfBlock;
                        if (isDistFromBlockLessThanHalfABlock) {
                          CONTRIB_TIME(idThread, CONTRIB_NONATOMIC_PUSH, 1.0);
                          bag_push_serial(
                              &bagsNexts[MINDEX2(nbCells, 2, idCell2_step[i],
                                                 PRIVATE)],
                              p2);
                        } else {
                          CONTRIB_TIME(idThread, CONTRIB_ATOMIC_PUSH, 1.0);
                          bag_push_concurrent(
                              &bagsNexts[MINDEX2(nbCells, 2, idCell2_step[i],
                                                 SHARED)],
                              p2);
                        }
#pragma omp simd aligned(coefX, coefY, coefZ, signX, signY, signZ : 64)
                        for (int idCorner = 0; idCorner < nbCorners;
                             idCorner++) {
                          depositThreadCorners[MINDEX3(
                              nbThreads, nbCells, nbCorners, idThread,
                              idCell2_step[i], idCorner)] +=
                              (coefX[idCorner] +
                               signX[idCorner] * c->itemsPosX[i]) *
                              (coefY[idCorner] +
                               signY[idCorner] * c->itemsPosY[i]) *
                              (coefZ[idCorner] +
                               signZ[idCorner] * c->itemsPosZ[i]);
                        }
                      }
                      double contrib_time_3 = omp_get_wtime();
                      CONTRIB_TIME(idThread, CONTRIB_SPEED_LOOP, contrib_time_1 - contrib_time_0);
                      CONTRIB_TIME(idThread, CONTRIB_POS_LOOP, contrib_time_2 - contrib_time_1);
                      CONTRIB_TIME(idThread, CONTRIB_PUSH_LOOP, contrib_time_3 - contrib_time_2);
                    }
                    bag_init(b);
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  double contrib_time_01 = omp_get_wtime();

  double contrib_time_4 = omp_get_wtime();
#pragma omp parallel for
  for (int idCell = 0; idCell < nbCells; idCell++) {
    for (int bagsKind = 0; bagsKind < 2; bagsKind++) {
      bag_append(&bagsCur[MINDEX1(nbCells, idCell)],
                 &bagsNexts[MINDEX2(nbCells, 2, idCell, bagsKind)]);
    }
#pragma omp simd
    for (int idCorner = 0; idCorner < nbCorners; idCorner++) {
      depositCorners[idCell * nbCorners + idCorner] =
          depositThreadCorners[0 * nbCells * nbCorners + idCell * nbCorners +
                               idCorner];
    }
    for (int idThread = 1; idThread < nbThreads; idThread++) {
#pragma omp simd
      for (int idCorner = 0; idCorner < nbCorners; idCorner++)
        depositCorners[idCell * nbCorners + idCorner] +=
            depositThreadCorners[idThread * nbCells * nbCorners +
                                 idCell * nbCorners + idCorner];
    }
  }
#pragma omp parallel for
  for (int idCell = 0; idCell < nbCells; idCell++) {
    double sum = 0.;
    for (int idCorner = 0; idCorner < nbCorners; idCorner++) {
      sum += depositCorners[bij(nbCells, nbCorners, idCell, idCorner)];
    }
    deposit[MINDEX1(nbCells, idCell)] = sum;
  }
  double contrib_time_5 = omp_get_wtime();
  CONTRIB_TIME(0, CONTRIB_REDUCE, nbThreads * (contrib_time_5 - contrib_time_4));

  double contrib_time_02 = omp_get_wtime();

  double contrib_time_6 = omp_get_wtime();
  updateFieldUsingDeposit();
  double contrib_time_7 = omp_get_wtime();
  CONTRIB_TIME(0, CONTRIB_POISSON, nbThreads * (contrib_time_7 - contrib_time_6));
  double contrib_time_03 = omp_get_wtime();
  CONTRIB_TIME(0, CONTRIB_STEP1, nbThreads * (contrib_time_01 - contrib_time_00));
  CONTRIB_TIME(0, CONTRIB_STEP2, nbThreads * (contrib_time_02 - contrib_time_01));
  CONTRIB_TIME(0, CONTRIB_STEP3, nbThreads * (contrib_time_03 - contrib_time_02));
}

//#include <time.h>
//#include <sys/time.h>

int main(int argc, char** argv) {
#pragma omp parallel
  {
#pragma omp single
    nbThreads = omp_get_num_threads();
  }
  loadParameters(argc, argv);
  computeConstants();
  allocateStructures();
  resetDeposit();
  createParticles();
  stepLeapFrog();
#ifdef ANALYZEPERF
    contrib_reset();
#endif
/*
    struct timeval begin, end;
    gettimeofday(&begin, 0);

  clock_t start = clock();*/

  double timeStart = omp_get_wtime();
  double nextReport = timeStart + 1.;
  for (int idStep = 0; idStep < nbSteps; idStep++) {
    if (omp_get_wtime() > nextReport) {
      nextReport += 1.;
      printf("Step %d\n", idStep);
    }
    step();
  }
  /*
  double timeTotal2 = ((double) (clock() - start)) / CLOCKS_PER_SEC;

  // Stop measuring time and calculate the elapsed time
  gettimeofday(&end, 0);
  long seconds = end.tv_sec - begin.tv_sec;
  long microseconds = end.tv_usec - begin.tv_usec;
  double timeTotal3 = seconds + microseconds*1e-6;
*/

  double timeTotal = (double)(omp_get_wtime() - timeStart);
  printf("Exectime: %.3f sec\n", timeTotal);
  printf("ParticlesMoved: %.1f billion particles\n",
         (double)nbParticles * nbSteps / 1000 / 1000 / 1000);
  printf("Throughput: %.1f million particles/sec\n",
         (double)nbParticles * nbSteps / timeTotal / 1000 / 1000);
#ifdef ANALYZEPERF
  /*
   printf("Exectime2(scaling issue of CLOCKS_PER_SEC): %.3f sec\n", timeTotal2);
   printf("Exectime3: %.3f sec\n", timeTotal3);
   */
   contrib_report(timeTotal * nbThreads, CONTRIB_NONATOMIC_PUSH);
#endif
  deallocateStructures();
  free(deposit);
}
