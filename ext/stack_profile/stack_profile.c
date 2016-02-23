#include <sys/resource.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

#define BUF_SIZE 2048

VALUE mScoutApm;
VALUE cStackProfile;
VALUE frames_buffer[BUF_SIZE];
VALUE stack_array;
int lines_buffer[BUF_SIZE];

struct timeval tval_gc_start, tval_gc_end;
struct rusage start_rusage, end_rusage;
int start_gc_count, end_gc_count;

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

static VALUE
load_gc_data(VALUE self)
{
    VALUE hsh = rb_hash_new();
    rb_hash_aset(hsh, ID2SYM(rb_intern("start_time")), rb_time_new(tval_gc_start.tv_sec, tval_gc_start.tv_usec));
    rb_hash_aset(hsh, ID2SYM(rb_intern("end_time")), rb_time_new(tval_gc_end.tv_sec, tval_gc_end.tv_usec));

    rb_hash_aset(hsh, ID2SYM(rb_intern("start_gc_count")), INT2NUM(start_gc_count));
    rb_hash_aset(hsh, ID2SYM(rb_intern("end_gc_count")), INT2NUM(end_gc_count));

    rb_hash_aset(hsh, ID2SYM(rb_intern("start_max_rss")), LONG2NUM(start_rusage.ru_maxrss));
    rb_hash_aset(hsh, ID2SYM(rb_intern("end_max_rss")), LONG2NUM(end_rusage.ru_maxrss));

    return rb_iv_set(self, "@gc_data", hsh);
}

void record_gc_start_data()
{
    gettimeofday(&tval_gc_start, NULL);
    start_gc_count = rb_gc_count();
    getrusage(RUSAGE_SELF, &start_rusage);
}

void record_gc_end_data()
{
    gettimeofday(&tval_gc_end, NULL);
    end_gc_count = rb_gc_count();
    getrusage(RUSAGE_SELF, &end_rusage);
}

void Init_stack_profile()
{
    mScoutApm = rb_define_module("ScoutApm");
    cStackProfile = rb_define_class_under(mScoutApm, "StackProfile", rb_cObject);
    rb_define_method(cStackProfile, "initialize", initialize, 0);
    rb_define_singleton_method(cStackProfile, "getstack", getstack, 0);
    rb_define_method(cStackProfile, "load_gc_data", load_gc_data, 0);

    Init_gc_hook(mScoutApm);
}