/*
 * General idioms:
 *   - rb_* functions are attached to Ruby-accessible method calls (See Init_stacks)
 * General approach:
 *   - Because of how rb_profile_frames works, it must be called from within
 *     each thread running, rather than from a 3rd party thread.
 *   - We setup a global timer tick. The handler simply sends a thread signal
 *     to each registered thread, which causes each thread to capture its own
 *     trace
 */

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

const char *single_space = " ";

int scout_profiling_installed = 0;
int scout_profiling_running = 0;

static __thread uint64_t _skipped_in_gc;
static __thread uint64_t _skipped_in_interrupt;
static __thread uint64_t _skipped_job_registered;

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
#define INTERVAL 1500
#define MAX_TRACES 5000

VALUE interval;

#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

// Forward Declarations
static void init_thread_vars();
static void scout_profile_timer_signal_handler(int sig);
static void scout_profile_broadcast_signal_handler(int sig);
void scout_record_sample();

// #include <sys/resource.h> // is this needed?


////////////////////////////////////////////////////////////////////////////////////////
// Per-Thread variables
////////////////////////////////////////////////////////////////////////////////////////

#define FILE_LEN_MAX 200
#define KLASS_LEN_MAX 100
#define LABEL_LEN_MAX 100

struct c_traceline {
  char file[FILE_LEN_MAX];
  long file_len;
  int line;
  char klass[KLASS_LEN_MAX];
  long klass_len;
  char label[LABEL_LEN_MAX];
  long label_len;
};

struct c_trace {
  int num_tracelines;
  struct c_traceline tracelines[BUF_SIZE];
};

static __thread int _buf_i, _buf_trace_index, _buf_num_frames;
static __thread VALUE _buf_file, _buf_klass, _buf_label;
static __thread VALUE _frames_buf[BUF_SIZE];
static __thread int _lines_buf[BUF_SIZE];

static __thread struct c_trace *_traces[MAX_TRACES];
static __thread int _ok_to_sample;  // used as a mutex to control the async interrupt handler
static __thread int _start_frame_index;
static __thread int _start_trace_index;
static __thread int _cur_traces_num;
static __thread int _job_registered;

////////////////////////////////////////////////////////////////////////////////////////
// Thread Linked List
////////////////////////////////////////////////////////////////////////////////////////

/*
 * Because of how rb_profile_frames works, we need to call it from inside of each thread
 * in ScoutProf.  To do this, we have a global linked list.  Each thread needs to register itself
 * via rb_scout_add_profiled_thread()
 */

/*
 * profiled_thread is a node in the linked list of threads.
 */
struct profiled_thread
{
  pthread_t th;
  struct profiled_thread *next;
};

/*
 * head_thread: The head of the linked list
 */
struct profiled_thread *head_thread = NULL;

// Mutex around editing of the thread linked list
pthread_mutex_t profiled_threads_mutex;

/*
 * rb_scout_add_profiled_thread: adds the currently running thread to the head of the linked list
 *
 * Initializes thread locals:
 *   - ok_to_sample to false
 *   - start_frame_index and start_trace_index to 0
 *   - cur_traces_num to 0
 */
static VALUE rb_scout_add_profiled_thread(VALUE self)
{
  int i;
  struct profiled_thread *thr;
  init_thread_vars();

  pthread_mutex_lock(&profiled_threads_mutex);

  for (i = 0; i < MAX_TRACES; i++) {
    _traces[i] = malloc(sizeof(struct c_trace));
  }
  //fprintf(stderr, "Done mallocing\n");

  thr = (struct profiled_thread *) malloc(sizeof(struct profiled_thread));
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

/*
 * remove_profiled_thread: removes a thread from the linked list.
 * if the linked list is empty, this is a noop
 */
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

/* rb_scout_remove_profiled_thread: removes a thread from the linked list
 *
 * Turns off _ok_to_sample, then proxies to remove_profiled_thread
 */
static VALUE rb_scout_remove_profiled_thread(VALUE self)
{
  _ok_to_sample = 0;
  remove_profiled_thread(pthread_self());
  return Qtrue;
}

////////////////////////////////////////////////////////////////////////////////////////
// Global timer
////////////////////////////////////////////////////////////////////////////////////////

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

/*
 * scout_profile_timer_signal_handler: The signal handler that reacts to the global SIGALRM
 *
 * Notifies all threads with SIGVTALRM
 */
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


/* rb_scout_start_profiling: Installs the global timer
 */
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

/* rb_scout_stop_profiling: Removes the global timer
 */
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

/* rb_scout_uninstall_profiling: removes global timer, and removes global SIGALRM handler
 */
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


////////////////////////////////////////////////////////////////////////////////////////
// Per-Thread Handler
////////////////////////////////////////////////////////////////////////////////////////


static void
init_thread_vars()
{
  _ok_to_sample = 0;
  _start_frame_index = 0;
  _start_trace_index = 0;
  _cur_traces_num = 0;
  _job_registered = 0;
  return;
}

/* scout_profile_job_handler: 
 *
 * TODO: why the indirection? Could we call scout_record_sample() directly instead?
 */
static void
scout_profile_job_handler(void *data)
{
  scout_record_sample();
  _job_registered = 0;
}

/* scout_profile_broadcast_signal_handler: Signal handler for each thread. 
 *
 * proxies off to scout_profile_job_handler via Ruby's rb_postponed_job_register
 */
static void
scout_profile_broadcast_signal_handler(int sig)
{
  static int in_signal_handler = 0;

  if (in_signal_handler) {
    _skipped_in_interrupt++;
    return;
  }

  if (_job_registered) {
    _skipped_job_registered++;
    return;
  }

  if (!_ok_to_sample) return;

  in_signal_handler++;
  if (rb_during_gc()) {
    _skipped_in_gc++;
  } else {
    if (rb_postponed_job_register(0, scout_profile_job_handler, 0) == 1) {
      _job_registered = 1;
    }
  }
  in_signal_handler--;
}

static long
scout_string_copy(VALUE src_string, char *dest_buffer, long dest_len , long *length_buffer)
{
  long copy_len, src_len;
  if (TYPE(src_string) != T_STRING) {
    *dest_buffer = *single_space;
    *length_buffer = (long)1;
    return -1;
  }
  src_len = RSTRING_LEN(src_string);
  if ( src_len < dest_len ) {
    copy_len = src_len;
  } else {
    copy_len = dest_len;
  }
  memcpy(dest_buffer, RSTRING_PTR(src_string), (size_t)copy_len);
  *length_buffer = copy_len;
  return copy_len;
}

/*
 * scout_record_sample: Defered function run from the per-thread handler
 *
 * Note: that this is called from *EVERY PROFILED THREAD FOR EACH CLOCK TICK
 *       INTERVAL*, so the performance of this method is crucial.
 *
 *  A fair bit of code, but fairly simple logic:
 *   * bail out early if we have sampling off
 *   * bail out early if GC is running
 *   * bail out early if we've filled the traces buffer
 *   * run rb_profile_frames
 *   * extract various info from the frames, and store it in _traces
 */
void
scout_record_sample()
{
  if (!_ok_to_sample) return;
  if (rb_during_gc()) {
    _skipped_in_gc++;
    return;
  }
  _buf_trace_index = _cur_traces_num;
  if (_cur_traces_num < MAX_TRACES) {
    //fprintf(stderr, "SAMPLING\n\n");
    _buf_num_frames = rb_profile_frames(0, sizeof(_frames_buf) / sizeof(VALUE), _frames_buf, _lines_buf);

    //fprintf(stderr, "\n\nBuf liunes is: %d\n\n", _buf_num_frames);

    if (_buf_num_frames > 0) {
      _traces[_buf_trace_index]->num_tracelines = _buf_num_frames;
      //fprintf(stderr, "\n\nNum tracelins is: %d\n\n", _traces[_buf_trace_index]->num_tracelines);

      for (_buf_i = 0; _buf_i < _buf_num_frames; _buf_i++) {

        // Extract File
        _buf_file = rb_profile_frame_absolute_path(_frames_buf[_buf_i]);
        scout_string_copy(_buf_file, &_traces[_buf_trace_index]->tracelines[_buf_i].file[0], (long)FILE_LEN_MAX, &_traces[_buf_trace_index]->tracelines[_buf_i].file_len);

        // Extract Line number
        _traces[_buf_trace_index]->tracelines[_buf_i].line  = _lines_buf[_buf_i];

        // Extract Class
        _buf_klass = rb_profile_frame_classpath(_frames_buf[_buf_i]);
        scout_string_copy(_buf_klass, &_traces[_buf_trace_index]->tracelines[_buf_i].klass[0], (long)KLASS_LEN_MAX, &_traces[_buf_trace_index]->tracelines[_buf_i].klass_len);

        // Extract Method
        _buf_label = rb_profile_frame_label(_frames_buf[_buf_i]);
        scout_string_copy(_buf_label, &_traces[_buf_trace_index]->tracelines[_buf_i].label[0], (long)LABEL_LEN_MAX, &_traces[_buf_trace_index]->tracelines[_buf_i].label_len);
      }
      _cur_traces_num++;
    }
  }
}

/* rb_scout_profile_frames: retreive the traces for the layer that is exiting
 *
 * Note: Calls to this must have already stopped sampling
 */
static VALUE rb_scout_profile_frames(VALUE self)
{
  int i, n;
  VALUE traces, trace, trace_line, scrub_replace;

  scrub_replace = rb_str_new2("");

  traces = rb_ary_new2(0); //_cur_traces_num - _start_trace_index);

  //fprintf(stderr, "OK to TRACE is: %d\n", _ok_to_sample);
  //fprintf(stderr, "TOTAL TRACES COUNT: %d\n", _cur_traces_num);
  if (_cur_traces_num - _start_trace_index > 0) {
    //fprintf(stderr, "CUR TRACES: %d\n", _cur_traces_num);
    //fprintf(stderr, "START TRACE IDX: %d\n", _start_trace_index);
    //fprintf(stderr, "TRACES COUNT: %d\n", _cur_traces_num - _start_trace_index);
    for(i = _start_trace_index; i < _cur_traces_num; i++) {
      //fprintf(stderr, "TRACELINES COUNT: %d\n", _traces[i]->num_tracelines);
      if (_traces[i]->num_tracelines > 0) {
        trace = rb_ary_new2(0);
        for(n = 0; n < _traces[i]->num_tracelines; n++) {
          //fprintf(stderr, ".");
          trace_line = rb_ary_new2(4);
          rb_ary_store(trace_line, 0, rb_funcall(rb_enc_str_new(&_traces[i]->tracelines[n].file[0], _traces[i]->tracelines[n].file_len, enc_UTF8), sym_scrub_bang, 1, scrub_replace));
          rb_ary_store(trace_line, 1, INT2FIX(_traces[i]->tracelines[n].line));
          rb_ary_store(trace_line, 2, rb_funcall(rb_enc_str_new(&_traces[i]->tracelines[n].klass[0], _traces[i]->tracelines[n].klass_len, enc_UTF8), sym_scrub_bang, 1, scrub_replace));
          rb_ary_store(trace_line, 3, rb_funcall(rb_enc_str_new(&_traces[i]->tracelines[n].label[0], _traces[i]->tracelines[n].label_len, enc_UTF8), sym_scrub_bang, 1, scrub_replace));
          rb_ary_push(trace, trace_line);
        }
        rb_ary_push(traces, trace);
      }
    }
  }
  _cur_traces_num = _start_trace_index;
  return traces;
}



/*****************************************************/
/* Control code */
/*****************************************************/

/* Per thread start sampling */
static VALUE
rb_scout_start_sampling(VALUE self)
{
  _ok_to_sample = 1;
  return Qtrue;
}

/* Per thread stop sampling */
static VALUE
rb_scout_stop_sampling(VALUE self, VALUE reset)
{
  _ok_to_sample = 0;
  // TODO: I think this can be (reset == Qtrue)
  if (TYPE(reset) == T_TRUE) {
    //fprintf(stderr, "Skipped - GC: %lld - Interrupt: %lld - Job Registered %lld\n", _skipped_in_gc, _skipped_in_interrupt, _skipped_job_registered);
    _cur_traces_num = 0;
    _skipped_job_registered = 0;
    _skipped_in_gc = 0;
    _skipped_in_interrupt = 0;
  }
  return Qtrue;
}

// rb_scout_update_indexes: Called when each layer starts or something
static VALUE
rb_scout_update_indexes(VALUE self, VALUE frame_index, VALUE trace_index)
{
  _start_trace_index = NUM2INT(trace_index);
  _start_frame_index = NUM2INT(frame_index);
  return Qtrue;
}


// rb_scout_current_trace_index: Get the current top of the trace stack
static VALUE
rb_scout_current_trace_index(VALUE self)
{
  return INT2NUM(_cur_traces_num);
}

// Gem Init. Set up constants, attach methods
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

