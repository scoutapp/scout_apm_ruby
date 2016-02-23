#include <sys/resource.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

#define BUF_SIZE 2048

#define NUM_GC_EVENTS 10

VALUE mScoutApm;
VALUE cStackProfile;
VALUE frames_buffer[BUF_SIZE];
VALUE stack_array;
int lines_buffer[BUF_SIZE];

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

static VALUE
initialize(VALUE self)
{
    rb_iv_set(self, "@gc_data", Qnil);
    return self;
}

static VALUE
getstack(VALUE rb_self)
{

    int num, i;

    num = rb_profile_frames(0, sizeof(frames_buffer) / sizeof(VALUE), frames_buffer, lines_buffer);

    stack_array = rb_ary_new();
    for(i = 0; i < num; i = i + 1) {
        rb_ary_push(stack_array, rb_profile_frame_full_label(frames_buffer[i]));
    }

    return stack_array;
}

//static VALUE
//load_gc_data(VALUE self)
//{
//    VALUE hsh = rb_hash_new();
//    rb_hash_aset(hsh, ID2SYM(rb_intern("start_time")), rb_time_new(tval_gc_start.tv_sec, tval_gc_start.tv_usec));
//    rb_hash_aset(hsh, ID2SYM(rb_intern("end_time")), rb_time_new(tval_gc_end.tv_sec, tval_gc_end.tv_usec));

//    rb_hash_aset(hsh, ID2SYM(rb_intern("start_gc_count")), INT2NUM(start_gc_count));
//    rb_hash_aset(hsh, ID2SYM(rb_intern("end_gc_count")), INT2NUM(end_gc_count));

//    rb_hash_aset(hsh, ID2SYM(rb_intern("start_max_rss")), LONG2NUM(start_rusage.ru_maxrss));
//    rb_hash_aset(hsh, ID2SYM(rb_intern("end_max_rss")), LONG2NUM(end_rusage.ru_maxrss));

//    return rb_iv_set(self, "@gc_data", hsh);
//}

void record_gc_start_data()
{
    struct gc_event* evnt;

    gc_event_count = gc_event_count + 1;
    evnt = &gc_event_array[gc_event_count % NUM_GC_EVENTS];

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
    evnt = &gc_event_array[gc_event_count % NUM_GC_EVENTS];

    // Collect the event end data
    gettimeofday(&evnt->tval_gc_end, NULL);
    evnt->end_gc_count = rb_gc_count();
    getrusage(RUSAGE_SELF, &evnt->end_rusage);

    // Debug printer
    fprintf(stderr, "stackprofile gc_end: end_time: %d %0.6f, end_gc_count: %d, end_rusage: %d\n", evnt->tval_gc_end.tv_sec, (float)evnt->tval_gc_end.tv_usec, evnt->end_gc_count, evnt->end_rusage.ru_maxrss);
}

void Init_stack_profile()
{
    mScoutApm = rb_define_module("ScoutApm");
    cStackProfile = rb_define_class_under(mScoutApm, "StackProfile", rb_cObject);
    rb_define_method(cStackProfile, "initialize", initialize, 0);
    rb_define_singleton_method(cStackProfile, "getstack", getstack, 0);
    //rb_define_method(cStackProfile, "load_gc_data", load_gc_data, 0);
    rb_cv_set(cStackProfile, "@@gc_event_array", rb_ary_new());

    Init_gc_hook(mScoutApm);
}