#include "ruby/ruby.h"
#include "ruby/debug.h"

static VALUE
invoke_proc_begin(VALUE proc)
{
    return rb_proc_call(proc, rb_ary_new());
}

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

static VALUE
set_after_gc_start()
{
    return set_gc_hook(RUBY_INTERNAL_EVENT_GC_START);
}

static VALUE
set_after_gc_end()
{
    return set_gc_hook(RUBY_INTERNAL_EVENT_GC_END_SWEEP);
}

void
Init_gc_hook(VALUE module)
{
    set_after_gc_start();
    set_after_gc_end();
    // rb_define_module_function(module, "after_gc_start_hook=", set_after_gc_start, 1);
    // rb_define_module_function(module, "after_gc_end_hook=", set_after_gc_end, 1);
}
