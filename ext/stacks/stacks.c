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
#define MAX_TRACES 4000

//#define INTERVAL 5000 // in microseconds
#define NANO_SECOND_MULTIPLIER  1000000  // 1 millisecond = 1,000,000 Nanoseconds
const long INTERVAL = 1 * NANO_SECOND_MULTIPLIER; // milliseconds * NANO_SECOND_MULTIPLIER

VALUE interval;

#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

// Forward Declarations
static void init_thread_vars();
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
  int _lines_buf[BUF_SIZE];
  VALUE _frames_buf[BUF_SIZE];
};

static __thread int _buf_i, _buf_trace_index, _buf_num_frames;

static __thread struct c_trace *_traces;
static __thread int _ok_to_sample;  // used as a mutex to control the async interrupt handler
static __thread int _start_frame_index;
static __thread int _start_trace_index;
static __thread int _cur_traces_num;

static int _job_registered;

static __thread VALUE gc_hook;

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


// Background controller thread ID
pthread_t btid;


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
  struct profiled_thread *thr;
  init_thread_vars();

  pthread_mutex_lock(&profiled_threads_mutex);

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

static void
scout_signal_threads_to_profile()
{
    struct profiled_thread *ptr, *next;
    ptr = head_thread;
    next = NULL;
    while(ptr != NULL) {
      if (pthread_kill(ptr->th, SIGVTALRM) == ESRCH) { // Send signal to the specific thread. If ESRCH is returned, remove the dead thread
        next = ptr->next;
        //remove_profiled_thread(ptr->th);
        ptr = next;
      } else {
        ptr = ptr->next;
      }
    }
    _job_registered = 0;
}

// Should we block signals to this thread?
void *
background_worker()
{
  int clock_result, register_result, prio_result;
  struct timespec clock_remaining;
  struct timespec sleep_time = {.tv_sec = 0, .tv_nsec = INTERVAL};

  prio_result = pthread_setschedprio(pthread_self(), (int)20);
  if (prio_result == 0) {
    fprintf(stderr, "Set proprity for background thread successfully!\n");
  } else {
    fprintf(stderr, "Failed to set background thread priority! Error: %d\n", prio_result);
  }

  while (1) {
    //check to see if we should change values, exit, etc
    SNOOZE:
    clock_result = clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep_time, &clock_remaining);
    if (clock_result == 0) {
      if (rb_during_gc()) {
        //_skipped_in_gc++;
      } else {
        register_result = rb_postponed_job_register_one(0, scout_signal_threads_to_profile, 0);
        if ((register_result == 1) || (register_result == 2)) {
          _job_registered = 1;
        } else {
          fprintf(stderr, "Error: job was not registered! Result: %d\n", register_result);
        }
      }
    } else if (clock_result == EINTR) {
      fprintf(stderr, "Clock was interrupted!\n");
      sleep_time = clock_remaining;
      goto SNOOZE;
    } else {
      fprintf(stderr, "Error: nanosleep returned value : %d\n", clock_result);
    }
  }
}

/* rb_scout_start_profiling: Installs the global timer
 */
static VALUE
rb_scout_start_profiling(VALUE self)
{
  if (scout_profiling_running) {
    return Qtrue;
  }

  rb_warn("Starting Profiling");
  scout_profiling_running = 1;

  // VALUE must be returned, just return nil
  return Qnil;
}

/* rb_scout_stop_profiling: Removes the global timer
 */
static VALUE
rb_scout_stop_profiling(VALUE self)
{
  return Qnil;
}

/* rb_scout_uninstall_profiling: removes global timer, and removes global SIGALRM handler
 */
static VALUE
rb_scout_uninstall_profiling(VALUE self)
{
  return Qnil;
}

static VALUE
rb_scout_install_profiling(VALUE self)
{
  struct sigaction new_vtaction, old_vtaction;

  // We can only install once. If uninstall is called, we will NOT be able to call install again.
  // Instead, stop/start should be used to temporarily disable all ScoutProf sampling.
  if (scout_profiling_installed) {
    return Qfalse;
  }

  pthread_create(&btid, NULL, background_worker, NULL);

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

////////////////////////////////////////////////////////////////////////////////////////
// Per-Thread Handler
////////////////////////////////////////////////////////////////////////////////////////

static void
scoutprof_gc_mark(void *data)
{
  int i, n;
  for (i = 0; i < _cur_traces_num; i++) {
    for (n = 0; n < _traces[i].num_tracelines; n++) {
      //fprintf(stderr, "GC MARK _cur_traces_num = %d, i = %d, num_tracelines = %d, n = %d\n", _cur_traces_num, i, _traces[i].num_tracelines, n);
      //fprintf(stderr, "GC MARK _cur_traces_num = %d, i = %d, num_tracelines = %d, n = %d\n", _cur_traces_num, i, _traces[i].num_tracelines, n);
      rb_gc_mark(_traces[i]._frames_buf[n]);
    }
  }
}

static void
init_thread_vars()
{
  int i;
  _ok_to_sample = 0;
  _start_frame_index = 0;
  _start_trace_index = 0;
  _cur_traces_num = 0;

  _traces = ALLOC_N(struct c_trace, MAX_TRACES); // TODO Check return

  gc_hook = Data_Wrap_Struct(rb_cObject, &scoutprof_gc_mark, NULL, &_traces);
  rb_global_variable(&gc_hook);

  return;
}

/* scout_profile_broadcast_signal_handler: Signal handler for each thread. 
 *
 * proxies off to scout_profile_job_handler via Ruby's rb_postponed_job_register
 */
static void
scout_profile_broadcast_signal_handler(int sig)
{
  static __thread int in_signal_handler = 0;

  if (in_signal_handler) {
    fprintf(stderr, "IN SIGNAL HANDLER!? Value: %d\n", in_signal_handler);
    return;
  }

  if (!_ok_to_sample) return;

  in_signal_handler++;
  if (rb_during_gc()) {
    //_skipped_in_gc++;
  } else {
    scout_record_sample();
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
    return;
  }
  _buf_trace_index = _cur_traces_num;
  if (_cur_traces_num < MAX_TRACES) {
    //fprintf(stderr, "SAMPLING\n\n");
    _buf_num_frames = rb_profile_frames(0, sizeof(_traces[_buf_trace_index]._frames_buf) / sizeof(VALUE), _traces[_buf_trace_index]._frames_buf, _traces[_buf_trace_index]._lines_buf);

    //fprintf(stderr, "\n\nBuf liunes is: %d\n\n", _buf_num_frames);
    if (_buf_num_frames > 0) {
      _traces[_buf_trace_index].num_tracelines = _buf_num_frames;
      //fprintf(stderr, "\n\nNum tracelins is: %d\n\n", _traces[_buf_trace_index].num_tracelines);
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
  int i, n, line;
  VALUE file, klass, label;
  VALUE traces, trace, trace_line;

  traces = rb_ary_new2(0); //_cur_traces_num - _start_trace_index);

  //fprintf(stderr, "OK to TRACE is: %d\n", _ok_to_sample);
  //fprintf(stderr, "TOTAL TRACES COUNT: %d\n", _cur_traces_num);
  if (_cur_traces_num - _start_trace_index > 0) {
    fprintf(stderr, "CUR TRACES: %d\n", _cur_traces_num);
    fprintf(stderr, "START TRACE IDX: %d\n", _start_trace_index);
    fprintf(stderr, "TRACES COUNT: %d\n", _cur_traces_num - _start_trace_index);
    for(i = _start_trace_index; i < _cur_traces_num; i++) {
      //fprintf(stderr, "TRACELINES COUNT: %d\n", _traces[i].num_tracelines);
      if (_traces[i].num_tracelines > 0) {
        trace = rb_ary_new2(0);
        for(n = 0; n < _traces[i].num_tracelines; n++) {
          //fprintf(stderr, "PROFILE _cur_traces_num = %d, i = %d, num_tracelines = %d, n = %d\n", _cur_traces_num, i, _traces[i].num_tracelines, n);
          // Extract File
          file = rb_profile_frame_absolute_path(_traces[i]._frames_buf[n]);


          // Extract Class
          klass = rb_profile_frame_classpath(_traces[i]._frames_buf[n]);

          // Extract Method
          label = rb_profile_frame_label(_traces[i]._frames_buf[n]);

          //fprintf(stderr, ".");
          trace_line = rb_ary_new2(4);
          rb_ary_store(trace_line, 0, file);
          rb_ary_store(trace_line, 1, INT2FIX(_traces[i]._lines_buf[n]));
          rb_ary_store(trace_line, 2, klass);
          rb_ary_store(trace_line, 3, label);
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

