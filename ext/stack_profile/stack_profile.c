#include <sys/resource.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

#define BUF_SIZE 2048

#define NUM_GC_EVENTS 40

VALUE mScoutApm;
VALUE cStackProfile;

// All of the data tracked from start to end of a single gc cycle
struct gc_event {
    int start_gc_count;
    int end_gc_count;
    struct timeval tval_gc_start;
    struct timeval tval_gc_end;
    struct rusage start_rusage;
    struct rusage end_rusage;
};

// Array of gc_event structs
struct gc_event gc_event_array[NUM_GC_EVENTS];
int gc_event_count;

void record_gc_start_data()
{
    struct gc_event* evnt;

    // Avoid integer overflow, reset the counter when it hits NUM_GC_EVENTS - 1
    gc_event_count = gc_event_count == (NUM_GC_EVENTS - 1) ? 0 : gc_event_count + 1;

    evnt = &gc_event_array[gc_event_count];

    // Reset end_gc_count to 0 so we know the end data is not valid yet
    evnt->end_gc_count = 0;

    // Collect the event start data
    gettimeofday(&evnt->tval_gc_start, NULL);
    evnt->start_gc_count = rb_gc_count();
    getrusage(RUSAGE_SELF, &evnt->start_rusage);

    // Debug printer
    fprintf(stderr, "stackprofile gc_start: start_time: %d %0.6f, start_gc_count: %d, start_rusage: %d\n", evnt->tval_gc_start.tv_sec, (float)evnt->tval_gc_start.tv_usec, evnt->start_gc_count, evnt->start_rusage.ru_maxrss);
}

void record_gc_end_data()
{
    struct gc_event* evnt;
    evnt = &gc_event_array[gc_event_count];

    // Collect the event end data
    gettimeofday(&evnt->tval_gc_end, NULL);
    evnt->end_gc_count = rb_gc_count();
    getrusage(RUSAGE_SELF, &evnt->end_rusage);

    // Debug printer
    fprintf(stderr, "stackprofile gc_end: end_time: %d %0.6f, end_gc_count: %d, end_rusage: %d\n", evnt->tval_gc_end.tv_sec, (float)evnt->tval_gc_end.tv_usec, evnt->end_gc_count, evnt->end_rusage.ru_maxrss);
}

static VALUE
gc_event_datas(VALUE self)
{
    int i;
    VALUE event_array = rb_ary_new();

    for (i = 0; i < NUM_GC_EVENTS; i = i + 1) {
        struct gc_event* evnt;
        evnt = &gc_event_array[i];

        VALUE hsh = rb_hash_new();
        rb_hash_aset(hsh, ID2SYM(rb_intern("start_time")), rb_time_new(evnt->tval_gc_start.tv_sec, evnt->tval_gc_start.tv_usec));
        rb_hash_aset(hsh, ID2SYM(rb_intern("end_time")), rb_time_new(evnt->tval_gc_end.tv_sec, evnt->tval_gc_end.tv_usec));
        rb_hash_aset(hsh, ID2SYM(rb_intern("start_gc_count")), INT2NUM(evnt->start_gc_count));
        rb_hash_aset(hsh, ID2SYM(rb_intern("end_gc_count")), INT2NUM(evnt->end_gc_count));
        rb_hash_aset(hsh, ID2SYM(rb_intern("start_max_rss")), LONG2NUM(evnt->start_rusage.ru_maxrss));
        rb_hash_aset(hsh, ID2SYM(rb_intern("end_max_rss")), LONG2NUM(evnt->end_rusage.ru_maxrss));

        rb_ary_push(event_array, hsh);

        // Debug printer
        //fprintf(stderr, "stackprofile print_gc_event: start_time: %d %0.6f, start_gc_count: %d, start_rusage: %d, end_time: %d %0.6f, end_gc_count: %d, end_rusage: %d\n", evnt->tval_gc_start.tv_sec, (float)evnt->tval_gc_start.tv_usec, evnt->start_gc_count, evnt->start_rusage.ru_maxrss, evnt->tval_gc_end.tv_sec, (float)evnt->tval_gc_end.tv_usec, evnt->end_gc_count, evnt->end_rusage.ru_maxrss);

    }
    return event_array;
}

void Init_stack_profile()
{
    mScoutApm = rb_define_module("ScoutApm");
    cStackProfile = rb_define_class_under(mScoutApm, "StackProfile", rb_cObject);
    rb_define_singleton_method(cStackProfile, "gc_event_datas", gc_event_datas, 0);

    Init_gc_hook(mScoutApm);
}