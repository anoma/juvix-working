#ifndef BOOL_H_
#define BOOL_H_

#include <stdbool.h>

typedef bool prim_bool;

#define prim_true true
#define prim_false false

bool is_prim_true(prim_bool b) {
    return b == prim_true;
}

bool is_prim_false(prim_bool b) {
    return b == prim_false;
}

#endif // BOOL_H_
