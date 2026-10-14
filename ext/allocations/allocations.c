#include <ruby.h>

VALUE mScoutApm;
VALUE mInstruments;
VALUE cAllocations;

#ifdef _WIN32

#define ALLOCATIONS_ENABLED Qfalse

static VALUE
get_allocation_count(VALUE klass) {
  return ULL2NUM(0);
}

void
Init_hooks(VALUE module)
{
}

#else // _WIN32

#include <sys/resource.h> // is this needed?
#include <sys/time.h>
#include <ruby/debug.h>

#define ALLOCATIONS_ENABLED Qtrue

static __thread uint64_t endpoint_allocations;
static ID id_fiber_allocations;
static ID id_running_fiber;
static ID id_running_since;

void increment_allocations() {
  endpoint_allocations++;
}

static uint64_t
stored_count(VALUE obj, ID id)
{
  VALUE count = rb_ivar_get(obj, id);
  return NIL_P(count) ? 0 : NUM2ULL(count);
}

// The counter above is per OS thread, but a thread can interleave many fibers
// (one per request under Falcon/Async). Charge the allocations made since the
// last switch to the fiber that was running, so each fiber sees only its own.
static void
charge_running_fiber(void)
{
  VALUE thread = rb_thread_current();
  VALUE running = rb_ivar_get(thread, id_running_fiber);

  if (!NIL_P(running)) {
    uint64_t charged = stored_count(running, id_fiber_allocations) + endpoint_allocations - stored_count(thread, id_running_since);
    rb_ivar_set(running, id_fiber_allocations, ULL2NUM(charged));
  }

  rb_ivar_set(thread, id_running_fiber, rb_fiber_current());
  rb_ivar_set(thread, id_running_since, ULL2NUM(endpoint_allocations));
}

static VALUE
get_allocation_count(VALUE klass) {
  charge_running_fiber();
  return ULL2NUM(stored_count(rb_fiber_current(), id_fiber_allocations));
}

static void
fiber_switch_hook(rb_event_flag_t event, VALUE data, VALUE self, ID mid, VALUE klass)
{
  charge_running_fiber();
}

static void
tracepoint_handler(VALUE tpval, void *data)
{
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    if (rb_tracearg_event_flag(tparg) == RUBY_INTERNAL_EVENT_NEWOBJ) {
        increment_allocations();
    }
}

static VALUE
set_gc_hook(rb_event_flag_t event)
{
    VALUE tpval;
    tpval = rb_tracepoint_new(0, event, tracepoint_handler, 0);
    rb_tracepoint_enable(tpval);

    return tpval;
}

void
Init_hooks(VALUE module)
{
    id_fiber_allocations = rb_intern("__scout_apm_allocations");
    id_running_fiber = rb_intern("__scout_apm_running_fiber");
    id_running_since = rb_intern("__scout_apm_running_since");
    set_gc_hook(RUBY_INTERNAL_EVENT_NEWOBJ);
    rb_add_event_hook(fiber_switch_hook, RUBY_EVENT_FIBER_SWITCH, Qnil);
}

#endif // _WIN32

void Init_allocations()
{
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cAllocations = rb_define_class_under(mInstruments, "Allocations", rb_cObject);
    rb_define_singleton_method(cAllocations, "count", get_allocation_count, 0);
    rb_define_const(cAllocations, "ENABLED", ALLOCATIONS_ENABLED);
    Init_hooks(mScoutApm);
}
