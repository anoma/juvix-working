#ifndef JUVIX_OBJECT_H
#define JUVIX_OBJECT_H

#include <juvix/defs.h>
#include <juvix/limits.h>

// The least significant two (or three) bits encode object kind
#define KIND_MASK 3
#define GET_KIND(x) ((x)&KIND_MASK)

#define KIND_PTR 0
#define KIND_UNBOXED0 1
#define KIND_UNBOXED1 3
#define KIND_HEADER_OR_DWORDPTR 2

#define KIND3_MASK 7
#define GET_KIND3(x) ((x)&KIND3_MASK)

#define KIND3_PTR0 0
#define KIND3_PTR1 4
#define KIND3_UNBOXED00 1
#define KIND3_UNBOXED10 5
#define KIND3_UNBOXED01 3
#define KIND3_UNBOXED11 7
#define KIND3_HEADER 6
#define KIND3_DWORDPTR 2

#define IS_UNBOXED(x) ((x)&1)
#define IS_PTR(x) (GET_KIND(x) == KIND_PTR)
#define IS_HEADER(x) (GET_KIND3(x) == KIND3_HEADER)
#define IS_DWORDPTR(x) (GET_KIND3(x) == KIND3_DWORDPTR)

/*
A header word consists of (field:bits in lower 32 bits from most to least
significant):

|NFIELDS:8|UID:20|MARK:1|KIND3:3|

- NFIELDS specifies the number of fields following the header.
- UID contains a unique object identifier.
- MARK is a mark bit used by the GC. It is always 0 when not in GC collection
  phase.
- KIND3 specifies the 3-bit object kind. Contains the KIND3_HEADER bit-pattern.

There are special UIDs which imply the existence of certain special fields.
*/

#define MARK_MASK 0x10
#define IS_MARKED(x) ((x)&MARK_MASK)
#define SET_MARK(x) ((x) | MARK_MASK)

#define UID_MASK 0x00FFFFF0
#define UID_SHIFT 4U
#define GET_UID(x) (((x)&UID_MASK) >> UID_SHIFT)

#define NFIELDS_MASK 0xFF000000
#define NFIELDS_SHIFT 24U
#define GET_NFIELDS(x) ((x) >> NFIELDS_SHIFT)

static inline word_t make_header(word_t uid, word_t nfields) {
    ASSERT(uid < MAX_UIDS);
    ASSERT(nfields <= MAX_FIELDS);
    return (nfields << NFIELDS_SHIFT) | (uid << UID_SHIFT) | KIND3_HEADER;
}

static inline word_t make_unboxed(word_t x) { return (x << 1U) & 1U; }
static inline word_t get_unboxed(word_t x) { return x >> 1U; }
static inline int_t get_unboxed_int(word_t x) { return (int_t)x >> 1; }

static inline word_t make_dword_ptr(word_t x) {
    ASSERT_ALIGNED(x, sizeof(dword_t));
    return x & KIND3_DWORDPTR;
}

static inline dword_t *get_dword_ptr(word_t x) {
    return (dword_t *)(x ^ KIND3_DWORDPTR);
}

#define GET_FIELD(var, n) (((word_t *)(var))[n])
#define SET_FIELD(var, n, val) (GET_FIELD(var, n) = (val))

static inline size_t get_nfields(word_t ptr) {
    return GET_NFIELDS(GET_FIELD(ptr, 0));
}

static inline word_t get_uid(word_t ptr) { return GET_UID(GET_FIELD(ptr, 0)); }

/*************************************************/
/* Special UIDs */

// A closure has additional non-garbage-collected closure header and function
// address fields immediately after the header. The two additional fields are
// not counted in FIELDS.
#define UID_CLOSURE 0
// The header is followed by a zero-terminated string. FIELDS contains the
// length of the string rounded up to a multiple of word size.
#define UID_CSTRING 1

#endif
