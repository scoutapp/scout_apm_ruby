#include <ruby/ruby.h>
#include <ruby/debug.h>

#define BUF_SIZE 2048

VALUE cClass;
VALUE frames_buffer[BUF_SIZE];
VALUE stack_array;
int lines_buffer[BUF_SIZE];

struct timeval tval_gc_start, tval_gc_end;

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
get_gc_times(VALUE self)
{
    VALUE ary = rb_ary_new();
    rb_ary_push(ary, rb_time_new(tval_gc_start.tv_sec, tval_gc_start.tv_usec));
    rb_ary_push(ary, rb_time_new(tval_gc_end.tv_sec, tval_gc_end.tv_usec));
    return ary;
}

void mark_gc_start_time()
{
    gettimeofday(&tval_gc_start, NULL);
}

void mark_gc_end_time()
{
    gettimeofday(&tval_gc_end, NULL);
}

void Init_stack_profile()
{
    cClass = rb_define_class("StackProfile", rb_cObject);
    rb_define_method(cClass, "initialize", initialize, 0);
    rb_define_singleton_method(cClass, "getstack", getstack, 0);
    rb_define_singleton_method(cClass, "get_gc_times", get_gc_times, 0);

    VALUE mScoutApm;
    mScoutApm = rb_define_module("ScoutApm");
    Init_gc_hook(mScoutApm);
}