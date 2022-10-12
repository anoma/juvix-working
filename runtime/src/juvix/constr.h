#ifndef JUVIX_CONSTR_H
#define JUVIX_CONSTR_H

#include <juvix/mem/alloc.h>
#include <juvix/object.h>

#define ALLOC_CONSTR_UNBOXED(var, uid) \
    do {                               \
        var = make_header(uid, 0);     \
    } while (0)

#define ALLOC_CONSTR_BOXED(var, uid, nfields, SAVE, RESTORE)  \
    do {                                                      \
        ALLOC((word_t *)(var), (nfields) + 1, SAVE, RESTORE); \
        SET_FIELD(var, 0, make_header(uid, nfields));         \
    } while (0)

#define ALLOC_CONSTR_PAIR(var, SAVE, RESTORE) \
    ALLOC((word_t *)(var), 2, SAVE, RESTORE)

#define FST(var) FIELD(var, 0)
#define SND(var) FIELD(var, 1)

#define CONSTR_ARG(var, n) FIELD(var, (n) + 1)

static inline word_t *get_constr_args(word_t x) { return (word_t *)x + 1; }

#endif
