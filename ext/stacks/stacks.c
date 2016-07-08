#include <ruby/ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>
#include <ruby/io.h>
#include <ruby/intern.h>
#include <signal.h>
#include <sys/time.h>
#include <errno.h>
#include <pthread.h>
#include <semaphore.h>


int scout_profiling_installed = 0;
int scout_profiling_running = 0;

ID sym_ScoutApm;
ID sym_Stacks;
ID sym_collect;
ID sym_scrub_bang;
VALUE ScoutApm;
VALUE Stacks;

rb_encoding *enc_UTF8;

VALUE mScoutApm;
VALUE mInstruments;
VALUE cStacks;

#define BUF_SIZE 512
#define INTERVAL 5000
#define MAX_TRACES 3000

VALUE interval;

#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

#include <sys/resource.h> // is this needed?
#include <sys/time.h>
#include <ruby/debug.h>

struct profiled_thread
{
  pthread_t th;
  struct profiled_thread *next;
};

struct c_traceline {
  char *file;
  long file_len;
  int line;
  char *klass;
  long klass_len;
  char *label;
  long label_len;
};

struct c_trace {
  int num_tracelines;
  struct c_traceline tracelines[BUF_SIZE];
};

struct frames_and_lines
{
  int num_frames;
  VALUE frames[BUF_SIZE];
  int lines[BUF_SIZE];
};

static __thread struct c_trace _traces[MAX_TRACES]; // perhaps make this a pointer to malloc'ed data - this can be a large structure
static __thread int _ok_to_sample;  // used as a mutex to control the async interrupt handler
static __thread int _start_frame_index;
static __thread int _start_trace_index;
static __thread int _cur_traces_num;
static __thread struct frames_and_lines _frames_lines_buf; // perhaps make this a pointer to malloc'ed data - this can be a large structure

// Profiled threads are joined as a linked list
pthread_mutex_t profiled_threads_mutex;
pthread_mutexattr_t profiled_threads_mutex_attr;
struct profiled_thread *head_thread = NULL;

static VALUE rb_scout_add_profiled_thread(VALUE self)
{
  struct profiled_thread *thr;
  _ok_to_sample = 0;
  _start_frame_index = 0;
  _start_trace_index = 0;
  _cur_traces_num = 0;
  pthread_mutex_lock(&profiled_threads_mutex);
  thr = (struct profiled_thread *) malloc(sizeof(struct profiled_thread ));
  thr->th = pthread_self();
  thr->next = NULL;
  if (head_thread == NULL) {
    head_thread = thr;
  } else {
    thr->next = head_thread;
    head_thread = thr; // now we're head_thread
  }
  pthread_mutex_unlock(&profiled_threads_mutex);
  return Qtrue;
}

static int remove_profiled_thread(pthread_t th)
{
  struct profiled_thread *ptr = head_thread;
  struct profiled_thread *prev = NULL;
  pthread_mutex_lock(&profiled_threads_mutex);
  while(ptr != NULL) {
    if (pthread_equal(th, ptr->th)) {
      if (head_thread == ptr) { // we're the head_thread
        if (head_thread->next == NULL) { // we're also the last
          head_thread = NULL;
          free(ptr);
          ptr = NULL;
        } else { // Just the head, not the last. Reassign head_thread to next
          head_thread = ptr->next;
          free(ptr);
          ptr = NULL;
        } // if head_thread->next == NULL
      } else if (ptr->next == NULL) { // we're the last thread, but not the head_thread
        prev->next = NULL;
        free(ptr);
        ptr = NULL;
      } else { // we're not the head_thread or last thread
        prev->next = ptr->next; // cut ptr out of the linked list
        free(ptr);
        ptr = NULL;
      }
    } else { // pthread_equal()
      ptr = ptr->next;
    }
  } // while (ptr != NULL)
  pthread_mutex_unlock(&profiled_threads_mutex);
  return 0;
}

static VALUE rb_scout_remove_profiled_thread(VALUE self)
{
  _ok_to_sample = 0;
  remove_profiled_thread(pthread_self());
  return Qtrue;
}

// Note that this is called from *EVERY PROFILED THREAD FOR EACH CLOCK TICK INTERVAL*, so the performance of this method is crucial.
void
scout_record_sample()
{
  int i, trace_index;
  VALUE file, klass, label;
  if (!_ok_to_sample || rb_during_gc()) {
    return;
  }
  trace_index = _cur_traces_num;
  if (_ok_to_sample && (_cur_traces_num < MAX_TRACES)) {
    _frames_lines_buf.num_frames = rb_profile_frames(0, sizeof(_frames_lines_buf.frames) / sizeof(VALUE), _frames_lines_buf.frames, _frames_lines_buf.lines);

    if (_frames_lines_buf.num_frames - _start_frame_index > 0) {
      _traces[trace_index].num_tracelines = _frames_lines_buf.num_frames - _start_frame_index;

      for (i = _start_frame_index; i < _frames_lines_buf.num_frames; i++) {

        file = rb_profile_frame_absolute_path(_frames_lines_buf.frames[i]);
        if (TYPE(file) == T_STRING) {
          _traces[trace_index].tracelines[i].file  = StringValuePtr(file);
          _traces[trace_index].tracelines[i].file_len  = RSTRING_LEN(file);
        } else {
          _traces[trace_index].tracelines[i].file  = " ";
          _traces[trace_index].tracelines[i].file_len  = (long)1;
        }

        _traces[trace_index].tracelines[i].line  = _frames_lines_buf.lines[i];

        klass = rb_profile_frame_classpath(_frames_lines_buf.frames[i]);
        //if (TYPE(klass) == T_STRING) {
        //  _traces[trace_index].tracelines[i].klass = StringValuePtr(klass);
        //  _traces[trace_index].tracelines[i].klass_len = RSTRING_LEN(klass);
        //} else {
          _traces[trace_index].tracelines[i].klass = " ";
          _traces[trace_index].tracelines[i].klass_len = (long)1;
        //}

        label = rb_profile_frame_label(_frames_lines_buf.frames[i]);
        if (TYPE(label) == T_STRING) {
          _traces[trace_index].tracelines[i].label = StringValuePtr(label);
          _traces[trace_index].tracelines[i].label_len = RSTRING_LEN(label);
        } else {
          _traces[trace_index].tracelines[i].label = " ";
          _traces[trace_index].tracelines[i].label_len = (long)1;
        }
      }
      _cur_traces_num++;
    }
  }
}


// Calls to this must have already stopped sampling
static VALUE rb_scout_profile_frames(VALUE self)
{
  int i, n;
  VALUE traces, trace, trace_line, scrub_replace;

  scrub_replace = rb_str_new2("");

  traces = rb_ary_new2(0); //_cur_traces_num - _start_trace_index);

  fprintf(stderr, "TOTAL TRACES COUNT: %d\n", _cur_traces_num);
  if (_cur_traces_num - _start_trace_index > 0) {
    fprintf(stderr, "TRACES COUNT: %d\n", _cur_traces_num - _start_trace_index);
    for(i = _start_trace_index; i < _cur_traces_num; i++) {
      fprintf(stderr, "TRACELINES COUNT: %d\n", _traces[i].num_tracelines);
      if (_traces[i].num_tracelines > 0) {
        trace = rb_ary_new2(_traces[i].num_tracelines);
        for(n = 0; n < _traces[i].num_tracelines; n++) {
          //fprintf(stderr, ".");
          trace_line = rb_ary_new2(4);
          rb_ary_store(trace_line, 0, rb_funcall(rb_enc_str_new(_traces[i].tracelines[n].file, _traces[i].tracelines[n].file_len, enc_UTF8), sym_scrub_bang, 1, scrub_replace));
          rb_ary_store(trace_line, 1, INT2FIX(_traces[i].tracelines[n].line));
          rb_ary_store(trace_line, 2, rb_funcall(rb_enc_str_new(_traces[i].tracelines[n].klass, _traces[i].tracelines[n].klass_len, enc_UTF8), sym_scrub_bang, 1, scrub_replace));
          rb_ary_store(trace_line, 3, rb_funcall(rb_enc_str_new(_traces[i].tracelines[n].label, _traces[i].tracelines[n].label_len, enc_UTF8), sym_scrub_bang, 1, scrub_replace));
          rb_ary_push(trace, trace_line);
        }
        rb_ary_push(traces, trace);
      }
    }
  }
  _cur_traces_num = _start_trace_index;
  return traces;
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
scout_profile_broadcast_signal_handler(int sig)
{
  if (rb_during_gc()) {
    // _stackprof.during_gc++, _stackprof.overall_samples++;
  } else {
    rb_postponed_job_register(0, scout_profile_job_handler, 0);
  }
}

//scout_profile_signal_handler(int sig, siginfo_t *sinfo, void *ucontext)
static void
scout_profile_timer_signal_handler(int sig)
{
    struct profiled_thread *ptr, *next;
    ptr = head_thread;
    next = NULL;
    while(ptr != NULL) {
      if (pthread_kill(ptr->th, SIGVTALRM) == ESRCH) { // Send signal to the specific thread. If ESRCH is returned, remove the dead thread
        next = ptr->next;
        remove_profiled_thread(ptr->th);
        ptr = next;
      } else {
        ptr = ptr->next;
      }
    }
}

static VALUE
rb_scout_install_profiling(VALUE self)
{
  struct sigaction new_action, old_action;
  struct sigaction new_vtaction, old_vtaction;
  interval = INT2FIX(INTERVAL);

  // We can only install once. If uninstall is called, we will NOT be able to call install again.
  // Instead, stop/start should be used to temporarily disable all ScoutProf sampling.
  if (scout_profiling_installed) {
    return Qfalse;
  }

  // Useful docs on signal handling:
  //   http://www.gnu.org/software/libc/manual/html_node/Signal-Handling.html#Signal-Handling
  //
  // This seciton of code sets up a new signal handler
  //
  // SA_RESTART means to continue any primitive lib functions that were aborted
  // when the timer fired. So an open() call that we interrupt will still
  // happen, rather than returning an error where it was called (perhaps
  // breaking poorly written code in other places that didn't think to check).
  new_action.sa_handler = scout_profile_timer_signal_handler;
  new_action.sa_flags = SA_RESTART;
  sigemptyset(&new_action.sa_mask);
  sigaction(SIGALRM, &new_action, &old_action);


  // Also set up an interrupt handler for when we broadcast an alarm
  new_vtaction.sa_handler = scout_profile_broadcast_signal_handler;
  new_vtaction.sa_flags = SA_RESTART;
  sigemptyset(&new_vtaction.sa_mask);
  sigaction(SIGVTALRM, &new_vtaction, &old_vtaction);

  rb_define_const(cStacks, "INSTALLED", Qtrue);
  scout_profiling_installed = 1;

  // VALUE must be returned, just return nil
  return Qnil;
}

static VALUE
rb_scout_start_profiling(VALUE self)
{
  struct itimerval timer;
  struct itimerval testTimer;
  int getResult;

  if (scout_profiling_running) {
    return Qtrue;
  }

  rb_warn("Starting Profiling");

  // This section of code sets up a timer that sends SIGALRM every <INTERVAL>
  // amount of time
  //
  // First Check for an existing timer
  getResult = getitimer(ITIMER_REAL, &testTimer);
  if (getResult != 0) {
    rb_warn("Failed in call to getitimer: %d", getResult);
  }

  if (testTimer.it_value.tv_sec != 0 && testTimer.it_value.tv_usec != 0) {
    rb_warn("Timer appears to already exist before setting Scout's");
  }

  // Then make the timer
  timer.it_interval.tv_sec = 0;
  timer.it_interval.tv_usec = INTERVAL; //FIX2INT(interval);
  timer.it_value = timer.it_interval;
  setitimer(ITIMER_REAL, &timer, 0);
  scout_profiling_running = 1;

  // VALUE must be returned, just return nil
  return Qnil;
}

static VALUE
rb_scout_stop_profiling(VALUE self)
{
  // Wipe timer
  struct itimerval timer;

  if (!scout_profiling_running) {
    return Qtrue;
  }

  timer.it_interval.tv_sec = 0;
  timer.it_interval.tv_usec = 0;
  timer.it_value = timer.it_interval;
  setitimer(ITIMER_REAL, &timer, 0);
  scout_profiling_running = 0;

  return Qnil;
}

static VALUE
rb_scout_uninstall_profiling(VALUE self)
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

static VALUE
rb_scout_start_sampling(VALUE self)
{
  _ok_to_sample = 1;
  return Qtrue;
}

static VALUE
rb_scout_stop_sampling(VALUE self, VALUE reset)
{
  _ok_to_sample = 0;
  if (TYPE(reset) == T_TRUE) {
    _cur_traces_num = 0;
  }
  return Qtrue;
}

static VALUE
rb_scout_update_indexes(VALUE self, VALUE frame_index, VALUE trace_index)
{
  _start_trace_index = NUM2INT(trace_index);
  _start_frame_index = NUM2INT(frame_index);
  return Qtrue;
}

static VALUE
rb_scout_current_trace_index(VALUE self)
{
  return INT2NUM(_cur_traces_num);
}

void Init_stacks()
{
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cStacks = rb_define_class_under(mInstruments, "Stacks", rb_cObject);

    sym_ScoutApm = rb_intern("ScoutApm");
    sym_Stacks = rb_intern("Stacks");
    sym_collect = rb_intern("collect");

    sym_scrub_bang = rb_intern("scrub!");
    enc_UTF8 = rb_enc_find("UTF-8");

    ScoutApm = rb_const_get(rb_cObject, sym_ScoutApm);
    Stacks = rb_const_get(ScoutApm, sym_Stacks);
    rb_warn("Init_stacks");

    // Installs/uninstalls the signal handler.
    rb_define_singleton_method(cStacks, "install", rb_scout_install_profiling, 0);
    rb_define_singleton_method(cStacks, "uninstall", rb_scout_uninstall_profiling, 0);

    // Starts/removes the timer tick, leaving the sighandler.
    rb_define_singleton_method(cStacks, "start", rb_scout_start_profiling, 0);
    rb_define_singleton_method(cStacks, "stop", rb_scout_stop_profiling, 0);

    rb_define_singleton_method(cStacks, "add_profiled_thread", rb_scout_add_profiled_thread, 0);
    rb_define_singleton_method(cStacks, "remove_profiled_thread", rb_scout_remove_profiled_thread, 0);
    rb_define_singleton_method(cStacks, "profile_frames", rb_scout_profile_frames, 0);
    rb_define_singleton_method(cStacks, "start_sampling", rb_scout_start_sampling, 0);
    rb_define_singleton_method(cStacks, "stop_sampling", rb_scout_stop_sampling, 1);
    rb_define_singleton_method(cStacks, "update_indexes", rb_scout_update_indexes, 2);
    rb_define_singleton_method(cStacks, "current_trace_index", rb_scout_current_trace_index, 0);

    rb_define_const(cStacks, "ENABLED", Qtrue);
    rb_warn("Finished Initializing ScoutProf Native Extension");
}

#else

void rb_scout_add_profiled_thread(VALUE module)
{
  return Qnil;
}

void rb_scout_remove_profiled_thread(VALUE module)
{
  return Qnil;
}

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
    rb_define_singleton_method(cStacks, "install", rb_scout_install_profiling, 0);
    rb_define_singleton_method(cStacks, "uninstall", rb_scout_uninstall_profiling, 0);

    // Starts/removes the timer tick, leaving the sighandler.
    rb_define_singleton_method(cStacks, "start", rb_scout_start_profiling, 0);
    rb_define_singleton_method(cStacks, "stop", rb_scout_stop_profiling, 0);

    rb_define_singleton_method(cStacks, "add_profiled_thread", rb_scout_add_profiled_thread, 0);
    rb_define_singleton_method(cStacks, "remove_profiled_thread", rb_scout_remove_profiled_thread, 0);

    rb_define_const(cStacks, "ENABLED", Qfalse);
    rb_define_const(cStacks, "INSTALLED", Qfalse);
}

#endif //#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

