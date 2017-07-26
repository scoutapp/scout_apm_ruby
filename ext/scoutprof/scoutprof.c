/*
 * Ruby lib
 */
#include <ruby/ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>
#include <ruby/io.h>
#include <ruby/intern.h>

/*
 * Std lib
 */
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>

#define MAX_TRACES 100000

VALUE mScoutApm;
VALUE mInstruments;
VALUE cScoutprof;
VALUE cTrace;

ID symTraces;

typedef struct c_trace {
  int num_tracelines;
  int lines_buf[2];
  VALUE frames_buf[2];
} trace_t;

typedef struct c_scoutprof {
  int num_traces;
} scoutprof_t;

static void
rb_scout_trace_mark(trace_t *trace)
{
  int i;
  for (i = 0; i < trace->num_tracelines; i++){
    //rb_gc_mark(trace->frames_buf[i]);
  }
}

static VALUE
rb_scout_scoutprof_alloc(VALUE self)
{
  scoutprof_t scoutprof;
  return Data_Wrap_Struct(self, NULL, NULL, &scoutprof);
}

static VALUE
rb_scout_trace_alloc(VALUE self)
{
  trace_t trace;
  return Data_Wrap_Struct(self, rb_scout_trace_mark, NULL, &trace);
}

static VALUE
rb_scout_scoutprof_initialize(VALUE self)
{
  rb_iv_set(self, "@traces", rb_ary_new2(MAX_TRACES));
  return self;
}

static VALUE
rb_scout_trace_initialize(VALUE self)
{
  return self;
}

static VALUE
rb_scout_scoutprof_record(VALUE self)
{
  int cur_num_traces, lines_read;
  scoutprof_t *scoutprof;
  trace_t trace;
  VALUE traces_ivar;
  VALUE rbTrace;

  Data_Get_Struct(self, scoutprof_t, scoutprof);

  cur_num_traces = scoutprof->num_traces;
  if (scoutprof->num_traces < MAX_TRACES) {
    lines_read = rb_profile_frames(0, 2, &(trace.frames_buf), &(trace.lines_buf));
    if (lines_read > 0) {
      traces_ivar = rb_iv_get(self, "@traces");
      trace.num_tracelines = lines_read;
      rbTrace = Data_Wrap_Struct(cTrace, rb_scout_trace_mark, NULL, &trace);
      rb_ary_push(traces_ivar, rbTrace);
      scoutprof->num_traces = cur_num_traces + 1;
      return Qtrue;
    }
  }
  return Qnil;
}

void Init_scoutprof()
{
  mScoutApm = rb_define_module("ScoutApm");
  mInstruments = rb_define_module_under(mScoutApm, "Instruments");
  cScoutprof = rb_define_class_under(mInstruments, "Scoutprof", rb_cObject);
  cTrace = rb_define_class_under(cScoutprof, "Trace", rb_cObject);

  symTraces = rb_intern("traces");

  rb_warning("Initializing Real ScoutProf Native Extension");

  rb_define_alloc_func(cScoutprof, rb_scout_scoutprof_alloc);
  rb_define_method(cScoutprof, "initialize", rb_scout_scoutprof_initialize, 0);
  rb_define_method(cScoutprof, "record", rb_scout_scoutprof_record, 0);

  rb_define_alloc_func(cTrace, rb_scout_trace_alloc);
  rb_define_method(cTrace, "initialize", rb_scout_trace_initialize, 0);

  rb_define_const(cScoutprof, "ENABLED", Qtrue);
  rb_warning("Finished Initializing Real ScoutProf Native Extension");
}