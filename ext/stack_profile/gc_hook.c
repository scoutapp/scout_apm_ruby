#include "ruby/ruby.h"
#include "ruby/debug.h"

static void
gc_start_end_i(VALUE tpval, void *data)
{
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    if (rb_tracearg_event_flag(tparg) == RUBY_INTERNAL_EVENT_GC_START) {
        record_gc_start_data();
    } else {
        record_gc_end_data();
    }
}

static VALUE
set_gc_hook(rb_event_flag_t event)
{
    VALUE tpval;
    // TODO - need to prevent applying the same tracepoint multiple times?
    tpval = rb_tracepoint_new(0, event, gc_start_end_i, 0);
    rb_tracepoint_enable(tpval);

    return tpval;
}

void
Init_gc_hook(VALUE module)
{
    set_gc_hook(RUBY_INTERNAL_EVENT_GC_START);
    set_gc_hook(RUBY_INTERNAL_EVENT_GC_END_SWEEP);
}
