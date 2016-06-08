#include <ruby/ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>
#include <ruby/io.h>
#include <ruby/intern.h>
#include <signal.h>
#include <sys/time.h>
#include <pthread.h>


VALUE mScoutApm;
VALUE mInstruments;
VALUE cStacks;


#define BUF_SIZE 2048
#define INTERVAL 10000
VALUE frames_buffer[BUF_SIZE];
int lines_buffer[BUF_SIZE];

VALUE interval;

#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

#include <sys/resource.h> // is this needed?
#include <sys/time.h>
#include <ruby/debug.h>


// Called every single time a tick happens.
// Goal is to collect the backtrace, and shuffle it off back to ruby-land for further analysis
//
// NOTE: This runs inside of a signal handler, which limits the work you can do
// here, or when calling back to rubyland
void
scout_record_sample()
{
  // Get frames
  int num;
  num = rb_profile_frames(0, sizeof(frames_buffer) / sizeof(VALUE), frames_buffer, lines_buffer);

  // Lookup the classes
  ID sym_ScoutApm = rb_intern("ScoutApm");
  ID sym_Stacks = rb_intern("Stacks");
  ID sym_StackTrace = rb_intern("StackTrace");
  ID sym_collect = rb_intern("collect");
  ID sym_add = rb_intern("add");
  VALUE ScoutApm = rb_const_get(rb_cObject, sym_ScoutApm);
  VALUE Stacks = rb_const_get(ScoutApm, sym_Stacks);
  VALUE StackTrace = rb_const_get(ScoutApm, sym_StackTrace);

  // Initialize a Trace object
  VALUE trace_args[1];
  trace_args[0] = INT2FIX(num);
  VALUE trace = rb_class_new_instance(1, trace_args, StackTrace);

  // Populate the trace object
  int i;
  for (i = 0; i < num; i++) {
    VALUE frame = frames_buffer[i];
    VALUE file  = rb_profile_frame_absolute_path(frame);
    VALUE label = rb_profile_frame_label(frame);
    VALUE klass = rb_profile_frame_classpath(frame);
    VALUE line  = INT2FIX(lines_buffer[i]);
    rb_funcall(trace, sym_add, 4, file, line, label, klass);
  }

  // Store the Trace object
  rb_funcall(Stacks, sym_collect, 1, trace);
}


static void
scout_profile_job_handler(void *data)
{
  static int in_signal_handler = 0;
  if (in_signal_handler) return;

  in_signal_handler++;
  scout_record_sample();
  in_signal_handler--;
}

static void
scout_profile_signal_handler(int sig, siginfo_t *sinfo, void *ucontext)
{
  if (rb_during_gc()) {
    // _stackprof.during_gc++, _stackprof.overall_samples++;
  } else {
    rb_postponed_job_register_one(0, scout_profile_job_handler, 0);
  }
}

void
Init_stack_hooks(VALUE module)
{
  struct sigaction sa;
  struct itimerval timer;
  interval = INT2FIX(INTERVAL);

  sa.sa_sigaction = scout_profile_signal_handler;
  sa.sa_flags = SA_RESTART | SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGALRM, &sa, NULL);

  timer.it_interval.tv_sec = 0;
  timer.it_interval.tv_usec = NUM2INT(interval);
  timer.it_value = timer.it_interval;
  setitimer(ITIMER_REAL, &timer, 0);

}

void Init_stacks()
{
    rb_warn("Init_stacks");
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cStacks = rb_define_class_under(mInstruments, "Stacks", rb_cObject);
    rb_define_const(cStacks, "ENABLED", Qtrue);
    Init_stack_hooks(cStacks);
    rb_warn("Finished Init_stacks");
}

#else

void
Init_hooks(VALUE module)
{
}

void Init_stacks()
{
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cStacks = rb_define_class_under(mInstruments, "Stacks", rb_cObject);
    rb_define_const(cStacks, "ENABLED", Qfalse);
}

#endif //#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

