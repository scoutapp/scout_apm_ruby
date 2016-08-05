/////////////////////////////////////////////////////////////////////////////////
// ATOMIC DEFS
//
// GCC added C11 atomics in 4.9, which is after ubuntu 14.04's version. Provide
// typedefs around what we really use to allow compatibility
//
/////////////////////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////////////////////
// Build system MUST set either SCOUT_USE_OLD_ATOMICS or SCOUT_USE_NEW_ATOMICS,
// but not both
/////////////////////////////////////////////////////////////////////////////////


#ifdef SCOUT_USE_OLD_ATOMICS

typedef bool atomic_bool_t;
typedef uint16_t atomic_uint16_t;
typedef uint32_t atomic_uint32_t;

// Function which abuses compare&swap to set the value to what you want.
void scout_macro_fn_atomic_store_bool(bool* p_ai, bool val)
{
  bool ai_was;
  ai_was = *p_ai;

  do {
    ai_was = __sync_val_compare_and_swap (p_ai, ai_was, val);
  } while (ai_was != *p_ai);
}

// Function which abuses compare&swap to set the value to what you want.
void scout_macro_fn_atomic_store_int16(atomic_uint16_t* p_ai, atomic_uint16_t val)
{
  atomic_uint16_t ai_was;
  ai_was = *p_ai;

  do {
    ai_was = __sync_val_compare_and_swap (p_ai, ai_was, val);
  } while (ai_was != *p_ai);
}

// Function which abuses compare&swap to set the value to what you want.
void scout_macro_fn_atomic_store_int32(atomic_uint32_t* p_ai, atomic_uint32_t val)
{
  atomic_uint32_t ai_was;
  ai_was = *p_ai;

  do {
    ai_was = __sync_val_compare_and_swap (p_ai, ai_was, val);
  } while (ai_was != *p_ai);
}


#define ATOMIC_STORE_BOOL(var, value) scout_macro_fn_atomic_store_bool(var, value)
#define ATOMIC_STORE_INT16(var, value) scout_macro_fn_atomic_store_int16(var, value)
#define ATOMIC_STORE_INT32(var, value) scout_macro_fn_atomic_store_int32(var, value)
#define ATOMIC_LOAD(var) __sync_fetch_and_add((var),0)
#define ATOMIC_ADD(var, value) __sync_fetch_and_add((var), value)
#define ATOMIC_INIT(value) value

#endif


/////////////////////////////////////////////////////////////////////////////////


#ifdef SCOUT_USE_NEW_ATOMICS

// We have c11 atomics
#include <stdatomic.h>
#define ATOMIC_STORE_BOOL(var, value) atomic_store(var, value)
#define ATOMIC_STORE_INT16(var, value) atomic_store(var, value)
#define ATOMIC_STORE_INT32(var, value) atomic_store(var, value)
#define ATOMIC_LOAD(var) atomic_load(var)
#define ATOMIC_ADD(var, value) atomic_fetch_add(var, value)
#define ATOMIC_INIT(value) ATOMIC_VAR_INIT(value)

typedef atomic_bool atomic_bool_t;
typedef atomic_uint_fast16_t atomic_uint16_t;
typedef atomic_uint_fast32_t atomic_uint32_t;

#endif


