#include <ruby/ruby.h>
#include <ruby/debug.h>

#define BUF_SIZE 2048

VALUE cClass;
VALUE frames_buffer[BUF_SIZE];
VALUE stack_array;
int lines_buffer[BUF_SIZE];

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

void Init_stack_profile()
{
    cClass = rb_define_class("StackProfile", rb_cObject);
    rb_define_method(cClass, "initialize", initialize, 0);
    rb_define_singleton_method(cClass, "getstack", getstack, 0);

    VALUE mScoutApm;
    mScoutApm = rb_define_module("ScoutApm");
    Init_gc_hook(mScoutApm);
}