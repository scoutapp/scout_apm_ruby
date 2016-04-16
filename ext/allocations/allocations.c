#include <sys/resource.h> // is this needed?
#include <sys/time.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

VALUE mScoutApm;
VALUE mInstruments;
VALUE cAllocations;

static __thread uint64_t endpoint_allocations;
void increment_allocations() {
  endpoint_allocations++;
}

static VALUE
get_allocation_count() {
  return ULL2NUM(endpoint_allocations);
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
    // TODO - need to prevent applying the same tracepoint multiple times?
    tpval = rb_tracepoint_new(0, event, tracepoint_handler, 0);
    rb_tracepoint_enable(tpval);

    return tpval;
}

void
Init_hooks(VALUE module)
{
    set_gc_hook(RUBY_INTERNAL_EVENT_NEWOBJ);
}

void Init_allocations()
{
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cAllocations = rb_define_class_under(mInstruments, "Allocations", rb_cObject);
    rb_define_singleton_method(cAllocations, "count", get_allocation_count, 0);

    Init_hooks(mScoutApm);
}