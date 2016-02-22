#include <sys/resource.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

#define BUF_SIZE 2048

VALUE cClass;
VALUE frames_buffer[BUF_SIZE];
VALUE stack_array;
int lines_buffer[BUF_SIZE];

struct timeval tval_gc_start, tval_gc_end;
struct rusage rusage;
int sp_gc_count;

static VALUE
initialize(VALUE self)
{
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

static VALUE
get_gc_data(VALUE self)
{
    VALUE ary = rb_ary_new();
    rb_ary_push(ary, rb_time_new(tval_gc_start.tv_sec, tval_gc_start.tv_usec));
    rb_ary_push(ary, rb_time_new(tval_gc_end.tv_sec, tval_gc_end.tv_usec));
    rb_ary_push(ary, INT2NUM(sp_gc_count));
    rb_ary_push(ary, LONG2NUM(rusage.ru_maxrss));
    return ary;
}

void get_rusage_data()
{
    getrusage(RUSAGE_SELF, &rusage);
}

void mark_gc_start_time()
{
    gettimeofday(&tval_gc_start, NULL);
    sp_gc_count = rb_gc_count();
}

void mark_gc_end_time()
{
    gettimeofday(&tval_gc_end, NULL);
    sp_gc_count = rb_gc_count();
}

void Init_stack_profile()
{
    cClass = rb_define_class("StackProfile", rb_cObject);
    rb_define_method(cClass, "initialize", initialize, 0);
    rb_define_singleton_method(cClass, "getstack", getstack, 0);
    rb_define_singleton_method(cClass, "get_gc_data", get_gc_data, 0);

    VALUE mScoutApm;
    mScoutApm = rb_define_module("ScoutApm");
    Init_gc_hook(mScoutApm);
}