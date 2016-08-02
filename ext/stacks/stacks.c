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
#include <semaphore.h>
#include <setjmp.h>
#include <signal.h>
#include <stdbool.h>
#include <sys/time.h>

/////////////////////////////////////////////////////////////////////////////////
// ATOMIC DEFS
//
// GCC added C11 atomics in 4.9, which is after ubuntu 14.04's version. Provide
// typedefs around what we really use to allow compatibility
/////////////////////////////////////////////////////////////////////////////////

// TODO: Check for GCC 4.9+, where C11 atomics were implemented
#if 1

// We have c11 atomics
#include <stdatomic.h>
#define ATOMIC_STORE_BOOL(var, value) atomic_store(var, value)
#define ATOMIC_STORE_INT16(var, value) atomic_store(var, value)
#define ATOMIC_STORE_INT32(var, value) atomic_store(var, value)
#define ATOMIC_LOAD(var) atomic_load(var)
#define ATOMIC_ADD(var, value) atomic_fetch_add(var, value)
#define ATOMIC_INIT(value) ATOMIC_VAR_INIT(value)

typedef atomic_bool atomic_bool_t;
typedef atomic_uint_fast16_t atomic_uint16_t;
typedef atomic_uint_fast32_t atomic_uint32_t;

#else

typedef bool atomic_bool_t;
typedef uint16_t atomic_uint16_t;
typedef uint32_t atomic_uint32_t;

// Function which abuses compare&swap to set the value to what you want.
void scout_macro_fn_atomic_store_bool(bool* p_ai, bool val)
{
  bool ai_was;
  ai_was = *p_ai;

  do {
    ai_was = __sync_val_compare_and_swap (p_ai, ai_was, val);
  } while (ai_was != *p_ai);
}

// Function which abuses compare&swap to set the value to what you want.
void scout_macro_fn_atomic_store_int16(atomic_uint16_t* p_ai, atomic_uint16_t val)
{
  atomic_uint16_t ai_was;
  ai_was = *p_ai;

  do {
    ai_was = __sync_val_compare_and_swap (p_ai, ai_was, val);
  } while (ai_was != *p_ai);
}

// Function which abuses compare&swap to set the value to what you want.
void scout_macro_fn_atomic_store_int32(atomic_uint32_t* p_ai, atomic_uint32_t val)
{
  atomic_uint32_t ai_was;
  ai_was = *p_ai;

  do {
    ai_was = __sync_val_compare_and_swap (p_ai, ai_was, val);
  } while (ai_was != *p_ai);
}


#define ATOMIC_STORE_BOOL(var, value) scout_macro_fn_atomic_store_bool(var, value)
#define ATOMIC_STORE_INT16(var, value) scout_macro_fn_atomic_store_int16(var, value)
#define ATOMIC_STORE_INT32(var, value) scout_macro_fn_atomic_store_int32(var, value)
#define ATOMIC_LOAD(var) __sync_fetch_and_add((var),0)
#define ATOMIC_ADD(var, value) __sync_fetch_and_add((var), value)
#define ATOMIC_INIT(value) value


#endif

/////////////////////////////////////////////////////////////////////////////////
// END ATOMIC DEFS
/////////////////////////////////////////////////////////////////////////////////



int scout_profiling_installed = 0;
int scout_profiling_running = 0;

ID sym_ScoutApm;
ID sym_Stacks;
ID sym_collect;
ID sym_scrub_bang;
VALUE ScoutApm;
VALUE Stacks;

VALUE mScoutApm;
VALUE mInstruments;
VALUE cStacks;

VALUE interval;

#define BUF_SIZE 512
#define MAX_TRACES 2000

#define NANO_SECOND_MULTIPLIER  1000000  // 1 millisecond = 1,000,000 Nanoseconds
const long INTERVAL = 1 * NANO_SECOND_MULTIPLIER; // milliseconds * NANO_SECOND_MULTIPLIER

// Max threads to remove each dead_thread_sweeper interval
#define MAX_REMOVES_PER_SWEEP 100

#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

// Forward Declarations
static void init_thread_vars();
static void scout_profile_broadcast_signal_handler(int sig);
void scout_record_sample();

////////////////////////////////////////////////////////////////////////////////////////
// Per-Thread variables
////////////////////////////////////////////////////////////////////////////////////////

struct c_trace {
  int num_tracelines;
  int lines_buf[BUF_SIZE];
  VALUE frames_buf[BUF_SIZE];
};

static __thread struct c_trace *_traces;

static __thread atomic_bool_t _ok_to_sample = ATOMIC_INIT(false);
static __thread atomic_bool_t _in_signal_handler = ATOMIC_INIT(false);

static __thread atomic_uint16_t _start_frame_index = ATOMIC_INIT(0);
static __thread atomic_uint16_t _start_trace_index = ATOMIC_INIT(0);
static __thread atomic_uint16_t _cur_traces_num = ATOMIC_INIT(0);

static __thread atomic_uint32_t _skipped_in_gc = ATOMIC_INIT(0);
static __thread atomic_uint32_t _skipped_in_signal_handler = ATOMIC_INIT(0);
static __thread atomic_uint32_t _rescued_profile_frames = ATOMIC_INIT(0);

static __thread VALUE _gc_hook;

static __thread atomic_bool_t _job_registered = ATOMIC_INIT(false);

static __thread jmp_buf _return_to_profile_handler;
static __thread sig_t _saved_abrt_handler = NULL;

////////////////////////////////////////////////////////////////////////////////////////
// Global variables
////////////////////////////////////////////////////////////////////////////////////////



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

  // Keep a pointer to the thread-local data that we ALLOC and wrap for Ruby Objectspace.
  // We need this so we can free the thread local data from the dead thread sweeper, since we don't
  // hook into a thread exiting in ruby to do it in the threads own context.
  struct c_trace *_traces;
  VALUE *_gc_hook;
};

/*
 * head_thread: The head of the linked list
 */
struct profiled_thread *head_thread = NULL;

// Mutex around editing of the thread linked list
pthread_mutex_t profiled_threads_mutex = PTHREAD_MUTEX_INITIALIZER;


// Background controller thread ID
pthread_t btid;

// Background dead thread sweeper
pthread_t thread_sweeper_id;


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
  thr->_traces = _traces;
  thr->_gc_hook = &_gc_hook;
  thr->next = NULL;

  if (head_thread == NULL) {
    head_thread = thr;
  } else {
    thr->next = head_thread;
    head_thread = thr; // now we're head_thread
  }
  fprintf(stderr, "APM DEBUG: Added thread id: %li\n", (unsigned long int)thr->th);

  pthread_mutex_unlock(&profiled_threads_mutex);
  return Qtrue;
}

/*
 * remove_profiled_thread: removes a thread from the linked list.
 * if the linked list is empty, this is a noop
 */
static int remove_profiled_thread(pthread_t th)
{
  struct profiled_thread *ptr, *prev;

  pthread_mutex_lock(&profiled_threads_mutex);

  prev = NULL;

  for(ptr = head_thread; ptr != NULL; prev = ptr, ptr = ptr->next) {
    if (pthread_equal(th, ptr->th)) {
      fprintf(stderr, "APM DEBUG: Would remove thread id: %li\n", (unsigned long int)ptr->th);

      // Unregister the _gc_hook from Ruby ObjectSpace, then free it as well as the _traces struct it wrapped.
      rb_gc_unregister_address(ptr->_gc_hook);
      xfree(ptr->_gc_hook);
      xfree(ptr->_traces);

      if (prev == NULL) {
        head_thread = ptr->next; // We are head_thread
      } else {
        prev->next = ptr->next; // We are not head thread
      }
      free(ptr);
      break;
    }
  }

  pthread_mutex_unlock(&profiled_threads_mutex);
  return 0;
}

/* rb_scout_remove_profiled_thread: removes a thread from the linked list
 *
 * Turns off _ok_to_sample, then proxies to remove_profiled_thread
 */
static VALUE rb_scout_remove_profiled_thread(VALUE self)
{
  ATOMIC_STORE_BOOL(&_ok_to_sample, false);
  remove_profiled_thread(pthread_self());
  return Qtrue;
}

////////////////////////////////////////////////////////////////////////////////////////
// Global timer
////////////////////////////////////////////////////////////////////////////////////////

static void
scout_signal_threads_to_profile()
{
  struct profiled_thread *ptr;

  if (pthread_mutex_trylock(&profiled_threads_mutex) == 0) { // Only run if we get the mutex.
    ptr = head_thread;
    while(ptr != NULL) {
      if (pthread_kill(ptr->th, 0) != ESRCH) { // Check for existence of thread. If ESRCH is returned, don't send the real signal!
        pthread_kill(ptr->th, SIGVTALRM);
      }
      ptr = ptr->next;
    }
    pthread_mutex_unlock(&profiled_threads_mutex);
  }
}

static int sweep_dead_threads() {
  int i;
  struct profiled_thread *ptr;
  pthread_t dead_thread_ids[MAX_REMOVES_PER_SWEEP];
  int dead_count = 0;

  pthread_mutex_lock(&profiled_threads_mutex);

  ptr = head_thread;
  while((ptr != NULL) && (dead_count < MAX_REMOVES_PER_SWEEP)) {
    if (pthread_kill(ptr->th, 0) == ESRCH) { // Check for existence of thread.
      dead_thread_ids[dead_count] = ptr->th; // if dead, add the id to the array
      dead_count++;                          // and increment counter.
    }
    ptr = ptr->next;
  }

  pthread_mutex_unlock(&profiled_threads_mutex);

  // Remove the dead threads outside of the simple mutex.
  for (i = 0; i < dead_count; i++) {
    fprintf(stderr, "APM DEBUG: Sweeper removed thread id: %li\n", (unsigned long int)dead_thread_ids[i]);
    remove_profiled_thread(dead_thread_ids[i]);
  }

  return 0;
}

void *
dead_thread_sweeper() {
  int clock_result;
  struct timespec clock_remaining;
  struct timespec sleep_time = {.tv_sec = 5, .tv_nsec = 0};

  while (1) {
    SWEEP_SNOOZE:

#ifdef CLOCK_MONOTONIC
    clock_result = clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep_time, &clock_remaining);
#else
    clock_result = nanosleep(&sleep_time, &clock_remaining);
    if (clock_result == -1) {
      clock_result = errno;
    }
#endif

    if (clock_result == 0) {
      sweep_dead_threads();
    } else if (clock_result == EINTR) {
      sleep_time = clock_remaining;
      goto SWEEP_SNOOZE;
    } else {
      fprintf(stderr, "Error: nanosleep returned value : %d\n", clock_result);
    }
  }
}

// Should we block signals to this thread?
void *
background_worker()
{
  int clock_result;
  struct timespec clock_remaining;
  struct timespec sleep_time = {.tv_sec = 0, .tv_nsec = INTERVAL};

  while (1) {
    //check to see if we should change values, exit, etc
    SNOOZE:
#ifdef CLOCK_MONOTONIC
    clock_result = clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep_time, &clock_remaining);
#else
    clock_result = nanosleep(&sleep_time, &clock_remaining);
    if (clock_result == -1) {
      clock_result = errno;
    }
#endif

    if (clock_result == 0) {
      scout_signal_threads_to_profile();
    } else if (clock_result == EINTR) {
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

  return Qtrue;
}

/*  rb_scout_uninstall_profiling: called when ruby is shutting down.
 *  NOTE: If ever this method should be called where Ruby should continue to run, we need to free our
 *        memory allocated in each profiled thread.
 */
static VALUE
rb_scout_uninstall_profiling(VALUE self)
{
  pthread_mutex_lock(&profiled_threads_mutex);

  // stop background worker threads
  pthread_cancel(btid); // TODO: doing a pthread_join after cancel is the only way to wait and know if the thread actually exited.
  pthread_cancel(thread_sweeper_id); // TODO: doing a pthread_join after cancel is the only way to wait and know if the thread actually exited.

  pthread_mutex_unlock(&profiled_threads_mutex);

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
  pthread_create(&thread_sweeper_id, NULL, dead_thread_sweeper, NULL);

  // Also set up an interrupt handler for when we broadcast an alarm
  new_vtaction.sa_handler = scout_profile_broadcast_signal_handler;
  new_vtaction.sa_flags = SA_RESTART;
  sigemptyset(&new_vtaction.sa_mask);
  sigaction(SIGVTALRM, &new_vtaction, &old_vtaction);

  rb_define_const(cStacks, "INSTALLED", Qtrue);
  scout_profiling_installed = 1;

  return Qtrue;
}

////////////////////////////////////////////////////////////////////////////////////////
// Per-Thread Handler
////////////////////////////////////////////////////////////////////////////////////////

static void
scoutprof_gc_mark(void *data)
{
  uint_fast16_t i;
  int n;
  for (i = 0; i < ATOMIC_LOAD(&_cur_traces_num); i++) {
    for (n = 0; n < _traces[i].num_tracelines; n++) {
      rb_gc_mark(_traces[i].frames_buf[n]);
    }
  }
}

static void
init_thread_vars()
{
  ATOMIC_STORE_BOOL(&_ok_to_sample, false);
  ATOMIC_STORE_BOOL(&_in_signal_handler, false);
  ATOMIC_STORE_INT16(&_start_frame_index, 0);
  ATOMIC_STORE_INT16(&_start_trace_index, 0);
  ATOMIC_STORE_INT16(&_cur_traces_num, 0);

  _traces = ALLOC_N(struct c_trace, MAX_TRACES); // TODO Check return

  _gc_hook = Data_Wrap_Struct(rb_cObject, &scoutprof_gc_mark, NULL, &_traces);
  rb_gc_register_address(&_gc_hook);

  return;
}

/*
 *  Signal handler for each thread. Invoked from a signal when a job is run within Ruby's postponed_job queue
 */
static void
scout_profile_broadcast_signal_handler(int sig)
{
  int register_result;

  if (ATOMIC_LOAD(&_ok_to_sample) == false) return;

  if (ATOMIC_LOAD(&_in_signal_handler) == true) {
    ATOMIC_ADD(&_skipped_in_signal_handler, 1);
    return;
  }

  ATOMIC_STORE_BOOL(&_in_signal_handler, true);

  if (rb_during_gc()) {
    ATOMIC_ADD(&_skipped_in_gc, 1);
  } else {
    if (ATOMIC_LOAD(&_job_registered) == false){
      register_result = rb_postponed_job_register(0, scout_record_sample, 0);
      if ((register_result == 1) || (register_result == 2)) {
        ATOMIC_STORE_BOOL(&_job_registered, true);
      } else {
        fprintf(stderr, "Error: job was not registered! Result: %d\n", register_result);
      }
    } // !_job_registered
  }

  ATOMIC_STORE_BOOL(&_in_signal_handler, false);
}

/*
 *  If this method is called, lngjmp to scout_record_sample()
 */
static void
scout_abrt_handler(int sig)
{
  longjmp(_return_to_profile_handler, 1);
}

/*
 * scout_record_sample: Defered function run from the per-thread handler
 *
 * Note: that this is called from *EVERY PROFILED THREAD FOR EACH CLOCK TICK
 *       INTERVAL*, so the performance of this method is crucial.
 *
 */
void
scout_record_sample()
{
  int num_frames;
  uint_fast16_t cur_traces_num, start_frame_index;

  if (ATOMIC_LOAD(&_ok_to_sample) == false) return;
  if (rb_during_gc()) {
    ATOMIC_ADD(&_skipped_in_gc, 1);
    return;
  }

  cur_traces_num = ATOMIC_LOAD(&_cur_traces_num);
  start_frame_index = ATOMIC_LOAD(&_start_frame_index);

  if (cur_traces_num < MAX_TRACES) {
    // NOTE: We are capturing any SIGABRT raised by Ruby during the call to rb_profile_frames.
    // Using setjmp/lngjmp causes intermediate frames to be **skipped at the point of the SIGABRT call
    // to where the setjmp is fist called**. This is safe to do for rb_profile_frames since it does not
    // do any allocations or need any cleanup if there is a jump.
    // setjmp returns 0 when it sets the jmp buffer
    _saved_abrt_handler = signal(SIGABRT, scout_abrt_handler);
    if (setjmp(_return_to_profile_handler) == 0) {
      num_frames = rb_profile_frames(0, sizeof(_traces[cur_traces_num].frames_buf) / sizeof(VALUE), _traces[cur_traces_num].frames_buf, _traces[cur_traces_num].lines_buf);
      if (num_frames - start_frame_index > 2) {
        _traces[cur_traces_num].num_tracelines = num_frames - start_frame_index - 2; // The extra -2 is because there's a bug when reading the very first (bottom) 2 iseq objects for some reason
        ATOMIC_ADD(&_cur_traces_num, 1);
      } // TODO: add an else with a counter so we can track if we skipped profiling here
    } else {
      // We are returning to this frame from a lngjmp
      signal(SIGABRT, _saved_abrt_handler);
      _saved_abrt_handler = NULL;
      ATOMIC_ADD(&_rescued_profile_frames, 1);
    }
  }
  ATOMIC_STORE_BOOL(&_job_registered, false);
}

/* rb_scout_profile_frames: retreive the traces for the layer that is exiting
 *
 * Note: Calls to this must have already stopped sampling
 */
static VALUE rb_scout_profile_frames(VALUE self)
{
  int n;
  uint_fast16_t i, cur_traces_num, start_trace_index;
  VALUE traces, trace, trace_line;

  cur_traces_num = ATOMIC_LOAD(&_cur_traces_num);
  start_trace_index = ATOMIC_LOAD(&_start_trace_index);

  if (cur_traces_num - start_trace_index > 0) {
    fprintf(stderr, "CUR TRACES: %"PRIuFAST16"\n", cur_traces_num);
    fprintf(stderr, "START TRACE IDX: %"PRIuFAST16"\n", start_trace_index);
    fprintf(stderr, "TRACES COUNT: %"PRIuFAST16"\n", cur_traces_num - start_trace_index);
    fprintf(stderr, "RESCUED IN ABRT: %"PRIuFAST32"\n", _rescued_profile_frames);
    traces = rb_ary_new2(cur_traces_num - start_trace_index);
    for(i = start_trace_index; i < cur_traces_num; i++) {
      if (_traces[i].num_tracelines > 0) {
        trace = rb_ary_new2(_traces[i].num_tracelines);
        for(n = 0; n < _traces[i].num_tracelines; n++) {
          trace_line = rb_ary_new2(2);
          rb_ary_store(trace_line, 0, _traces[i].frames_buf[n]);
          rb_ary_store(trace_line, 1, INT2FIX(_traces[i].lines_buf[n]));
          rb_ary_push(trace, trace_line);
        }
        rb_ary_push(traces, trace);
      }
    }
  } else {
    traces = rb_ary_new();
  }
  ATOMIC_STORE_INT16(&_cur_traces_num, start_trace_index);
  return traces;
}



/*****************************************************/
/* Control code */
/*****************************************************/

/* Per thread start sampling */
static VALUE
rb_scout_start_sampling(VALUE self)
{
  ATOMIC_STORE_BOOL(&_ok_to_sample, true);
  return Qtrue;
}

/* Per thread stop sampling */
static VALUE
rb_scout_stop_sampling(VALUE self, VALUE reset)
{
  ATOMIC_STORE_BOOL(&_ok_to_sample, false);
  // TODO: I think this can be (reset == Qtrue)
  if (TYPE(reset) == T_TRUE) {
    ATOMIC_STORE_INT16(&_cur_traces_num, 0);
    ATOMIC_STORE_INT32(&_skipped_in_gc, 0);
    ATOMIC_STORE_INT32(&_skipped_in_signal_handler, 0);
    ATOMIC_STORE_INT32(&_rescued_profile_frames, 0);
  }
  return Qtrue;
}

// rb_scout_update_indexes: Called when each layer starts or something
static VALUE
rb_scout_update_indexes(VALUE self, VALUE frame_index, VALUE trace_index)
{
  ATOMIC_STORE_INT16(&_start_trace_index, NUM2INT(trace_index));
  ATOMIC_STORE_INT16(&_start_frame_index, NUM2INT(frame_index));
  return Qtrue;
}

// rb_scout_current_trace_index: Get the current top of the trace stack
static VALUE
rb_scout_current_trace_index(VALUE self)
{
  return INT2NUM(ATOMIC_LOAD(&_cur_traces_num));
}

// rb_scout_current_trace_index: Get the current top of the trace stack
static VALUE
rb_scout_current_frame_index(VALUE self)
{
  int num_frames;
  VALUE frames_buf[BUF_SIZE];
  int lines_buf[BUF_SIZE];
  num_frames = rb_profile_frames(0, sizeof(frames_buf) / sizeof(VALUE), frames_buf, lines_buf);
  if (num_frames > 1) {
    return INT2NUM(num_frames - 1);
  } else {
    return INT2NUM(0);
  }
}



static VALUE
rb_scout_skipped_in_gc(VALUE self)
{
  return INT2NUM(ATOMIC_LOAD(&_skipped_in_gc));
}

static VALUE
rb_scout_skipped_in_handler(VALUE self)
{
  return INT2NUM(ATOMIC_LOAD(&_skipped_in_signal_handler));
}

static VALUE
rb_scout_rescued_profile_frames(VALUE self)
{
  return INT2NUM(ATOMIC_LOAD(&_rescued_profile_frames));
}

////////////////////////////////////////////////////////////////
// Fetch details from a frame
////////////////////////////////////////////////////////////////

static VALUE
rb_scout_frame_klass(VALUE self, VALUE frame)
{
  return rb_profile_frame_classpath(frame);
}

static VALUE
rb_scout_frame_method(VALUE self, VALUE frame)
{
  return rb_profile_frame_label(frame);
}

static VALUE
rb_scout_frame_file(VALUE self, VALUE frame)
{
  return rb_profile_frame_absolute_path(frame);
}

static VALUE
rb_scout_frame_lineno(VALUE self, VALUE frame)
{
  return rb_profile_frame_first_lineno(frame);

}


////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////

// Gem Init. Set up constants, attach methods
void Init_stacks()
{
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cStacks = rb_define_class_under(mInstruments, "Stacks", rb_cObject);

    sym_ScoutApm = rb_intern("ScoutApm");
    sym_Stacks = rb_intern("Stacks");
    sym_collect = rb_intern("collect");

    ScoutApm = rb_const_get(rb_cObject, sym_ScoutApm);
    Stacks = rb_const_get(ScoutApm, sym_Stacks);
    rb_warn("Init_stacks");

    // Installs/uninstalls the signal handler.
    rb_define_singleton_method(cStacks, "install", rb_scout_install_profiling, 0);
    rb_define_singleton_method(cStacks, "uninstall", rb_scout_uninstall_profiling, 0);

    rb_define_singleton_method(cStacks, "start", rb_scout_start_profiling, 0);

    rb_define_singleton_method(cStacks, "add_profiled_thread", rb_scout_add_profiled_thread, 0);
    rb_define_singleton_method(cStacks, "remove_profiled_thread", rb_scout_remove_profiled_thread, 0);

    rb_define_singleton_method(cStacks, "profile_frames", rb_scout_profile_frames, 0);
    rb_define_singleton_method(cStacks, "start_sampling", rb_scout_start_sampling, 0);
    rb_define_singleton_method(cStacks, "stop_sampling", rb_scout_stop_sampling, 1);
    rb_define_singleton_method(cStacks, "update_indexes", rb_scout_update_indexes, 2);
    rb_define_singleton_method(cStacks, "current_trace_index", rb_scout_current_trace_index, 0);
    rb_define_singleton_method(cStacks, "current_frame_index", rb_scout_current_frame_index, 0);

    rb_define_singleton_method(cStacks, "frame_klass", rb_scout_frame_klass, 1);
    rb_define_singleton_method(cStacks, "frame_method", rb_scout_frame_method, 1);
    rb_define_singleton_method(cStacks, "frame_file", rb_scout_frame_file, 1);
    rb_define_singleton_method(cStacks, "frame_lineno", rb_scout_frame_lineno, 1);

    rb_define_singleton_method(cStacks, "skipped_in_gc", rb_scout_skipped_in_gc, 0);
    rb_define_singleton_method(cStacks, "skipped_in_handler", rb_scout_skipped_in_handler, 0);
    rb_define_singleton_method(cStacks, "rescued_profile_frames", rb_scout_rescued_profile_frames, 0);

    rb_define_const(cStacks, "ENABLED", Qtrue);
    rb_warn("Finished Initializing ScoutProf Native Extension");
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

void rb_scout_add_profiled_thread(VALUE module)
{
  return Qnil;
}

void rb_scout_remove_profiled_thread(VALUE module)
{
  return Qnil;
}

static VALUE rb_scout_profile_frames(VALUE self)
{
  return rb_ary_new();
}

static VALUE
rb_scout_start_sampling(VALUE self)
{
  return Qtrue;
}

static VALUE
rb_scout_update_indexes(VALUE self, VALUE frame_index, VALUE trace_index)
{
  return Qtrue;
}

// rb_scout_current_trace_index: Get the current top of the trace stack
static VALUE
rb_scout_current_trace_index(VALUE self)
{
  return INT2NUM(0);
}

// rb_scout_current_trace_index: Get the current top of the trace stack
static VALUE
rb_scout_current_frame_index(VALUE self)
{
  return INT2NUM(0);
}

static VALUE
rb_scout_klass_for_frame(VALUE self, VALUE frame)
{
  return Qnil;
}

static VALUE
rb_scout_skipped_in_gc(VALUE self)
{
  return INT2NUM(0);
}

static VALUE
rb_scout_skipped_in_handler(VALUE self)
{
  return INT2NUM(0);
}

static VALUE
rb_scout_rescued_profile_frames(VALUE self)
{
  return INT2NUM(0);
}

static VALUE
rb_scout_frame_klass(VALUE self, VALUE frame)
{
  return Qnil;
}

static VALUE
rb_scout_frame_method(VALUE self, VALUE frame)
{
  return Qnil;
}

static VALUE
rb_scout_frame_file(VALUE self, VALUE frame)
{
  return Qnil;
}

static VALUE
rb_scout_frame_lineno(VALUE self, VALUE frame)
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

    rb_define_singleton_method(cStacks, "profile_frames", rb_scout_profile_frames, 0);
    rb_define_singleton_method(cStacks, "start_sampling", rb_scout_start_sampling, 0);
    rb_define_singleton_method(cStacks, "stop_sampling", rb_scout_stop_sampling, 1);
    rb_define_singleton_method(cStacks, "update_indexes", rb_scout_update_indexes, 2);
    rb_define_singleton_method(cStacks, "current_trace_index", rb_scout_current_trace_index, 0);
    rb_define_singleton_method(cStacks, "current_frame_index", rb_scout_current_frame_index, 0);

    rb_define_singleton_method(cStacks, "frame_klass", rb_scout_frame_klass, 1);
    rb_define_singleton_method(cStacks, "frame_method", rb_scout_frame_method, 1);
    rb_define_singleton_method(cStacks, "frame_file", rb_scout_frame_file, 1);
    rb_define_singleton_method(cStacks, "frame_lineno", rb_scout_frame_lineno, 1);

    rb_define_singleton_method(cStacks, "skipped_in_gc", rb_scout_skipped_in_gc, 0);
    rb_define_singleton_method(cStacks, "skipped_in_handler", rb_scout_skipped_in_handler, 0);
    rb_define_singleton_method(cStacks, "rescued_profile_frames", rb_scout_rescued_profile_frames, 0);

    rb_define_const(cStacks, "ENABLED", Qfalse);
    rb_define_const(cStacks, "INSTALLED", Qfalse);
}

#endif //#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

