#include <sys/resource.h>
#include <sys/time.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

#define NUM_GC_EVENTS 40

VALUE mScoutApm;
VALUE cStackProfile;

VALUE sym_start_time;
VALUE sym_end_time;
VALUE sym_start_gc_count;
VALUE sym_end_gc_count;
VALUE sym_start_max_rss;
VALUE sym_end_max_rss;

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
    //fprintf(stderr, "stackprofile gc_start: start_time: %d %0.6f, start_gc_count: %d, start_rusage: %d\n", evnt->tval_gc_start.tv_sec, (float)evnt->tval_gc_start.tv_usec, evnt->start_gc_count, evnt->start_rusage.ru_maxrss);
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
    //fprintf(stderr, "stackprofile gc_end: end_time: %d %0.6f, end_gc_count: %d, end_rusage: %d\n", evnt->tval_gc_end.tv_sec, (float)evnt->tval_gc_end.tv_usec, evnt->end_gc_count, evnt->end_rusage.ru_maxrss);
}

int is_gc_event_valid(struct gc_event *evnt) {
    if ( (evnt->start_gc_count > 0) && (evnt->start_gc_count == evnt->end_gc_count) ) {
        return 1;
    }
    return 0;
}

int check_times_overlap(struct gc_event* evnt, VALUE val_start_time, VALUE val_end_time) {
    struct timeval gc_start_time, gc_end_time;
    struct timeval start_time, end_time;

    gc_start_time = evnt->tval_gc_start;
    gc_end_time = evnt->tval_gc_end;
    start_time = rb_time_timeval(val_start_time);
    end_time = rb_time_timeval(val_end_time);

    if ( (timercmp(&start_time, &gc_start_time, >) && timercmp(&end_time, &gc_start_time, >) && timercmp(&end_time, &gc_end_time, <)) ||
         (timercmp(&start_time, &gc_start_time, >) && timercmp(&start_time, &gc_end_time, <) && timercmp(&end_time, &gc_end_time, >)) ||
         (timercmp(&start_time, &gc_start_time, <) && timercmp(&end_time, &gc_end_time, >)) ||
         (timercmp(&start_time, &gc_start_time, <) && timercmp(&end_time, &gc_start_time, >) && timercmp(&end_time, &gc_end_time, <)) )
        return 1;
    return 0;
}

static VALUE
gc_event_datas_for(VALUE self, VALUE start_time, VALUE end_time)
{
    int i;
    VALUE event_array = rb_ary_new();

    for (i = 0; i < NUM_GC_EVENTS; i = i + 1) {
        struct gc_event* evnt;
        evnt = &gc_event_array[i];

        if ( is_gc_event_valid(evnt) && check_times_overlap(evnt, start_time, end_time)) {
            VALUE hsh = rb_hash_new();
            rb_hash_aset(hsh, sym_start_time, rb_time_new(evnt->tval_gc_start.tv_sec, evnt->tval_gc_start.tv_usec));
            rb_hash_aset(hsh, sym_end_time, rb_time_new(evnt->tval_gc_end.tv_sec, evnt->tval_gc_end.tv_usec));
            rb_hash_aset(hsh, sym_start_gc_count, INT2NUM(evnt->start_gc_count));
            rb_hash_aset(hsh, sym_end_gc_count, INT2NUM(evnt->end_gc_count));
            rb_hash_aset(hsh, sym_start_max_rss, LONG2NUM(evnt->start_rusage.ru_maxrss));
            rb_hash_aset(hsh, sym_end_max_rss, LONG2NUM(evnt->end_rusage.ru_maxrss));

            rb_ary_push(event_array, hsh);

            // Debug printer
            //fprintf(stderr, "stackprofile print_gc_event: start_time: %d %0.6f, start_gc_count: %d, start_rusage: %d, end_time: %d %0.6f, end_gc_count: %d, end_rusage: %d\n", evnt->tval_gc_start.tv_sec, (float)evnt->tval_gc_start.tv_usec, evnt->start_gc_count, evnt->start_rusage.ru_maxrss, evnt->tval_gc_end.tv_sec, (float)evnt->tval_gc_end.tv_usec, evnt->end_gc_count, evnt->end_rusage.ru_maxrss);
        }
    }
    return event_array;
}

void Init_stack_profile()
{
    sym_start_time = ID2SYM(rb_intern("start_time"));
    sym_end_time = ID2SYM(rb_intern("end_time"));
    sym_start_gc_count = ID2SYM(rb_intern("start_gc_count"));
    sym_end_gc_count = ID2SYM(rb_intern("end_gc_count"));
    sym_start_max_rss = ID2SYM(rb_intern("start_max_rss"));
    sym_end_max_rss = ID2SYM(rb_intern("end_max_rss"));

    mScoutApm = rb_define_module("ScoutApm");
    cStackProfile = rb_define_class_under(mScoutApm, "StackProfile", rb_cObject);
    rb_define_singleton_method(cStackProfile, "gc_event_datas_for", gc_event_datas_for, 2);

    Init_gc_hook(mScoutApm);
}