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

//scout_profile_signal_handler(int sig, siginfo_t *sinfo, void *ucontext)
static void
scout_profile_signal_handler(int sig)
{
  if (rb_during_gc()) {
    // _stackprof.during_gc++, _stackprof.overall_samples++;
  } else {
    rb_postponed_job_register_one(0, scout_profile_job_handler, 0);
  }
}

static VALUE
scout_install_profiling(VALUE module)
{
  struct sigaction new_action, old_action;
  interval = INT2FIX(INTERVAL);

  // Useful docs on signal handling:
  //   http://www.gnu.org/software/libc/manual/html_node/Signal-Handling.html#Signal-Handling
  //
  // This seciton of code sets up a new signal handler
  //
  // SA_RESTART means to continue any primitive lib functions that were aborted
  // when the timer fired. So an open() call that we interrupt will still
  // happen, rather than returning an error where it was called (perhaps
  // breaking poorly written code in other places that didn't think to check).
  new_action.sa_handler = scout_profile_signal_handler;
  new_action.sa_flags = SA_RESTART;
  sigemptyset(&new_action.sa_mask);
  sigaction(SIGALRM, &new_action, &old_action);

  // VALUE must be returned, just return nil
  return Qnil;
}

static VALUE
scout_start_profiling(VALUE module)
{
  rb_warn("Starting Profiling")
  struct itimerval timer;

  // This section of code sets up a timer that sends SIGALRM every <INTERVAL>
  // amount of time
  //
  // First Check for an existing timer
  struct itimerval testTimer;
  int getResult = getitimer(ITIMER_REAL, &testTimer);
  if (getResult != 0) {
    rb_warn("Failed in call to getitimer: %d", getResult);
  }

  if (testTimer.it_value.tv_sec != 0 && testTimer.it_value.tv_usec != 0) {
    rb_warn("Timer appears to already exist before setting Scout's");
  }

  // Then make the timer
  timer.it_interval.tv_sec = 0;
  timer.it_interval.tv_usec = NUM2INT(interval);
  timer.it_value = timer.it_interval;
  setitimer(ITIMER_REAL, &timer, 0);

  // VALUE must be returned, just return nil
  return Qnil;
}

static VALUE
scout_stop_profiling(VALUE module)
{
  rb_warn("Stopping Profiling")
  // Wipe timer
  struct itimerval timer;
  timer.it_interval.tv_sec = 0;
  timer.it_interval.tv_usec = 0;
  timer.it_value = timer.it_interval;
  setitimer(ITIMER_REAL, &timer, 0);

  return Qnil;
}

static VALUE
scout_uninstall_profiling(VALUE module)
{
  // Wipe timer
  struct itimerval timer;
  timer.it_interval.tv_sec = 0;
  timer.it_interval.tv_usec = 0;
  timer.it_value = timer.it_interval;
  setitimer(ITIMER_REAL, &timer, 0);

  // Clear signal handler for ALRM. Do this after the timer is reset
  signal(SIGALRM, SIG_DFL);

  return Qnil;
}

void Init_stacks()
{
    rb_warn("Init_stacks");
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cStacks = rb_define_class_under(mInstruments, "Stacks", rb_cObject);

    // Installs/uninstalls the signal handler.
    rb_define_singleton_method(cStacks, "install", scout_install_profiling, 0);
    rb_define_singleton_method(cStacks, "uninstall", scout_uninstall_profiling, 0);

    // Starts/removes the timer tick, leaving the sighandler.
    rb_define_singleton_method(cStacks, "start", scout_start_profiling, 0);
    rb_define_singleton_method(cStacks, "stop", scout_stop_profiling, 0);

    rb_define_const(cStacks, "ENABLED", Qtrue);
    rb_warn("Finished Init_stacks");
}

#else

void scout_install_profiling(VALUE module)
{
  return Qnil;
}

void scout_uninstall_profiling(VALUE module)
{
  return Qnil;
}

void scout_start_profiling(VALUE module)
{
  return Qnil;
}

void scout_stop_profiling(VALUE module)
{
  return Qnil;
}

void Init_stacks()
{
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cStacks = rb_define_class_under(mInstruments, "Stacks", rb_cObject);

    // Installs/uninstalls the signal handler.
    rb_define_singleton_method(cStacks, "install", scout_install_profiling, 0);
    rb_define_singleton_method(cStacks, "uninstall", scout_uninstall_profiling, 0);

    // Starts/removes the timer tick, leaving the sighandler.
    rb_define_singleton_method(cStacks, "start", scout_start_profiling, 0);
    rb_define_singleton_method(cStacks, "stop", scout_stop_profiling, 0);

    rb_define_const(cStacks, "ENABLED", Qfalse);
}

#endif //#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

