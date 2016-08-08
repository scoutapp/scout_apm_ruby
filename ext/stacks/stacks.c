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

/*
 *  System
 */
#include <sys/syscall.h>
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

// For support of thread id in timer_create
#define sigev_notify_thread_id _sigev_un._tid

#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

// Forward Declarations
static void init_thread_vars();
static void scout_profile_broadcast_signal_handler(int sig);
void scout_record_sample();
static void scout_start_thread_timer();
static void scout_stop_thread_timer();

////////////////////////////////////////////////////////////////////////////////////////
// Per-Thread variables
////////////////////////////////////////////////////////////////////////////////////////

struct c_trace {
  int num_tracelines;
  int lines_buf[BUF_SIZE];
  VALUE frames_buf[BUF_SIZE];
};

static __thread atomic_bool_t _thread_registered = ATOMIC_INIT(false);

typedef struct _scoutprof _scoutprof;

struct _scoutprof {
  struct c_trace *traces;
  atomic_bool_t ok_to_sample;
  atomic_bool_t in_signal_handler;

  atomic_uint16_t start_frame_index;
  atomic_uint16_t start_trace_index;
  atomic_uint16_t cur_traces_num;

  atomic_uint32_t skipped_in_gc;
  atomic_uint32_t skipped_in_signal_handler;
  atomic_uint32_t skipped_in_job_registered;

  VALUE gc_hook;

  atomic_bool_t job_registered;

  timer_t timerid;
  struct sigevent sev;
};

static __thread _scoutprof *_sp;

static pthread_key_t _sp_key;
static pthread_once_t _sp_key_once = PTHREAD_ONCE_INIT;


////////////////////////////////////////////////////////////////////////////////////////
// Global variables
////////////////////////////////////////////////////////////////////////////////////////

static int
scout_add_profiled_thread()
{
  if (ATOMIC_LOAD(&_thread_registered) == true) return 1;

  init_thread_vars();
  ATOMIC_STORE_BOOL(&_thread_registered, true);

  fprintf(stderr, "APM DEBUG: Added thread id: %li\n", (unsigned long int)pthread_self());
  return 1;
}

/*
 * rb_scout_add_profiled_thread: adds the currently running thread to the head of the linked list
 *
 * Initializes thread locals:
 *   - ok_to_sample to false
 *   - start_frame_index and start_trace_index to 0
 *   - cur_traces_num to 0
 */
static VALUE
rb_scout_add_profiled_thread(VALUE self)
{
  scout_add_profiled_thread();
  return Qtrue;
}

/*
 * remove_profiled_thread: removes a thread from the linked list.
 * if the linked list is empty, this is a noop
 */
static int
remove_profiled_thread()
{
  if (ATOMIC_LOAD(&_thread_registered) == false) return 1;

  ATOMIC_STORE_BOOL(&_thread_registered, false);

  ATOMIC_STORE_BOOL(&_sp->ok_to_sample, false);

  fprintf(stderr, "APM DEBUG: Removed thread id: %li\n", (unsigned long int)pthread_self());

  // Unregister the _gc_hook from Ruby ObjectSpace, then free it as well as the _traces struct it wrapped.
  rb_gc_unregister_address(&_sp->gc_hook);
  xfree(&_sp->gc_hook);
  xfree(&_sp->traces);

  timer_delete(_sp->timerid);

  free(_sp);
  _sp = NULL;

  return 0;
}

/* rb_scout_remove_profiled_thread: removes a thread from the linked list
 *
 */
static VALUE rb_scout_remove_profiled_thread(VALUE self)
{
  remove_profiled_thread();
  return Qtrue;
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

  // Also set up an interrupt handler for when we broadcast an alarm
  new_vtaction.sa_handler = scout_profile_broadcast_signal_handler;
  new_vtaction.sa_flags = SA_RESTART;
  sigemptyset(&new_vtaction.sa_mask);
  sigaction(SIGALRM, &new_vtaction, &old_vtaction);

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
  for (i = 0; i < ATOMIC_LOAD(&_sp->cur_traces_num); i++) {
    for (n = 0; n < _sp->traces[i].num_tracelines; n++) {
      rb_gc_mark(_sp->traces[i].frames_buf[n]);
    }
  }
}

static void
scout_parent_atfork_prepare()
{
  // TODO: Should we track how much time the fork took?
  if (ATOMIC_LOAD(&_sp->ok_to_sample) == true) {
    scout_stop_thread_timer();
  }
}

static void
scout_parent_atfork_finish()
{
  if (ATOMIC_LOAD(&_sp->ok_to_sample) == true) {
    scout_start_thread_timer();
  }
}


static void
pthread_sp_destructor()
{
  remove_profiled_thread();
}

static void
make_sp_key()
{
  pthread_key_create(&_sp_key, pthread_sp_destructor);
}

static void
init_thread_vars()
{
  int res;

  fprintf(stderr, "INITIALIZED A THREAD");

  pthread_once(&_sp_key_once, make_sp_key);
  if ((_sp = pthread_getspecific(_sp_key)) == NULL) {
      _sp = malloc(sizeof(struct _scoutprof));
      pthread_setspecific(_sp_key, _sp);
  }

  ATOMIC_STORE_BOOL(&_sp->ok_to_sample, false);
  ATOMIC_STORE_BOOL(&_sp->in_signal_handler, false);
  ATOMIC_STORE_BOOL(&_sp->job_registered, false);

  ATOMIC_STORE_INT16(&_sp->start_frame_index, 0);
  ATOMIC_STORE_INT16(&_sp->start_trace_index, 0);
  ATOMIC_STORE_INT16(&_sp->cur_traces_num, 0);

  ATOMIC_STORE_INT32(&_sp->skipped_in_gc, 0);
  ATOMIC_STORE_INT32(&_sp->skipped_in_signal_handler, 0);
  ATOMIC_STORE_INT32(&_sp->skipped_in_job_registered, 0);

  _sp->traces = ALLOC_N(struct c_trace, MAX_TRACES); // TODO Check return

  _sp->gc_hook = Data_Wrap_Struct(rb_cObject, &scoutprof_gc_mark, NULL, &_sp->traces);
  rb_gc_register_address(&_sp->gc_hook);

  res = pthread_atfork(scout_parent_atfork_prepare, scout_parent_atfork_finish, NULL);
  if (res != 0) {
    fprintf(stderr, "Pthread_atfork failed: %d\n", res);
  }

  // Create timer to target this thread
  _sp->sev.sigev_notify = SIGEV_THREAD_ID;
  _sp->sev.sigev_signo = SIGALRM;
  _sp->sev.sigev_notify_thread_id = syscall(SYS_gettid);
  _sp->sev.sigev_value.sival_ptr = &_sp->timerid;
  if (timer_create(CLOCK_MONOTONIC, &_sp->sev, &_sp->timerid) == -1) {
    fprintf(stderr, "Time create failed: %d\n", errno);
  }

  return;
}

/*
 *  Signal handler for each thread. Invoked from a signal when a job is run within Ruby's postponed_job queue
 */
static void
scout_profile_broadcast_signal_handler(int sig)
{
  int register_result;

  if (ATOMIC_LOAD(&_sp->ok_to_sample) == false) return;

  if (ATOMIC_LOAD(&_sp->in_signal_handler) == true) {
    ATOMIC_ADD(&_sp->skipped_in_signal_handler, 1);
    return;
  }

  ATOMIC_STORE_BOOL(&_sp->in_signal_handler, true);

  if (rb_during_gc()) {
    ATOMIC_ADD(&_sp->skipped_in_gc, 1);
  } else {
    if (ATOMIC_LOAD(&_sp->job_registered) == false){
      register_result = rb_postponed_job_register(0, scout_record_sample, 0);
      if ((register_result == 1) || (register_result == 2)) {
        ATOMIC_STORE_BOOL(&_sp->job_registered, true);
      } else {
        ATOMIC_ADD(&_sp->skipped_in_job_registered, 1);
      }
    } // !_job_registered
  }

  ATOMIC_STORE_BOOL(&_sp->in_signal_handler, false);
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

  if (ATOMIC_LOAD(&_sp->ok_to_sample) == false) return;
  if (rb_during_gc()) {
    ATOMIC_ADD(&_sp->skipped_in_gc, 1);
    return;
  }

  cur_traces_num = ATOMIC_LOAD(&_sp->cur_traces_num);
  start_frame_index = ATOMIC_LOAD(&_sp->start_frame_index);

  if (cur_traces_num < MAX_TRACES) {
    num_frames = rb_profile_frames(0, sizeof(_sp->traces[cur_traces_num].frames_buf) / sizeof(VALUE), _sp->traces[cur_traces_num].frames_buf, _sp->traces[cur_traces_num].lines_buf);
    if (num_frames - start_frame_index > 2) {
      _sp->traces[cur_traces_num].num_tracelines = num_frames - start_frame_index - 2; // The extra -2 is because there's a bug when reading the very first (bottom) 2 iseq objects for some reason
      ATOMIC_ADD(&_sp->cur_traces_num, 1);
    } // TODO: add an else with a counter so we can track if we skipped profiling here
  }
  ATOMIC_STORE_BOOL(&_sp->job_registered, false);
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

  if (ATOMIC_LOAD(&_thread_registered) == false) {
    fprintf(stderr, "Error: trying to get profiled frames on a non-profiled thread!\n");
    return rb_ary_new();
  }

  cur_traces_num = ATOMIC_LOAD(&_sp->cur_traces_num);
  start_trace_index = ATOMIC_LOAD(&_sp->start_trace_index);

  if (cur_traces_num - start_trace_index > 0) {
    traces = rb_ary_new2(cur_traces_num - start_trace_index);
    for(i = start_trace_index; i < cur_traces_num; i++) {
      if (_sp->traces[i].num_tracelines > 0) {
        trace = rb_ary_new2(_sp->traces[i].num_tracelines);
        for(n = 0; n < _sp->traces[i].num_tracelines; n++) {
          trace_line = rb_ary_new2(2);
          rb_ary_store(trace_line, 0, _sp->traces[i].frames_buf[n]);
          rb_ary_store(trace_line, 1, INT2FIX(_sp->traces[i].lines_buf[n]));
          rb_ary_push(trace, trace_line);
        }
        rb_ary_push(traces, trace);
      }
    }
  } else {
    traces = rb_ary_new();
  }
  ATOMIC_STORE_INT16(&_sp->cur_traces_num, start_trace_index);
  return traces;
}



/*****************************************************/
/* Control code */
/*****************************************************/

static void
scout_start_thread_timer()
{
  struct itimerspec its;
  sigset_t mask;

  if (ATOMIC_LOAD(&_thread_registered) == false) return;

  sigemptyset(&mask);
  sigaddset(&mask, SIGALRM);
  if (sigprocmask(SIG_SETMASK, &mask, NULL) == -1) {
    fprintf(stderr, "Block mask failed: %d\n", errno);
  }

  its.it_value.tv_sec = 0;
  its.it_value.tv_nsec = INTERVAL;
  its.it_interval.tv_sec = its.it_value.tv_sec;
  its.it_interval.tv_nsec = its.it_value.tv_nsec;

  if (timer_settime(_sp->timerid, 0, &its, NULL) == -1) {
    fprintf(stderr, "Timer set failed in start sampling: %d\n", errno);
  }

  if (sigprocmask(SIG_UNBLOCK, &mask, NULL) == -1) {
    fprintf(stderr, "UNBlock mask failed: %d\n", errno);
  }
}

static void
scout_stop_thread_timer()
{
  struct itimerspec its;

  if (ATOMIC_LOAD(&_thread_registered) == false) return;

  memset((void*)&its, 0, sizeof(its));
  if (timer_settime(_sp->timerid, 0, &its, NULL) == -1 ) {
    fprintf(stderr, "Timer set failed: %d\n", errno);
  }
}

/* Per thread start sampling */
static VALUE
rb_scout_start_sampling(VALUE self)
{
  scout_add_profiled_thread(pthread_self());
  ATOMIC_STORE_BOOL(&_sp->ok_to_sample, true);
  scout_start_thread_timer();
  return Qtrue;
}

/* Per thread stop sampling */
static VALUE
rb_scout_stop_sampling(VALUE self, VALUE reset)
{
  if(ATOMIC_LOAD(&_sp->ok_to_sample) == true ) {
    scout_stop_thread_timer();
  }

  ATOMIC_STORE_BOOL(&_sp->ok_to_sample, false);

  // TODO: I think this can be (reset == Qtrue)
  if (TYPE(reset) == T_TRUE) {
    ATOMIC_STORE_BOOL(&_sp->job_registered, 0);
    ATOMIC_STORE_BOOL(&_sp->in_signal_handler, 0);
    ATOMIC_STORE_INT16(&_sp->start_trace_index, 0);
    ATOMIC_STORE_INT16(&_sp->start_frame_index, 0);
    ATOMIC_STORE_INT16(&_sp->cur_traces_num, 0);
    ATOMIC_STORE_INT32(&_sp->skipped_in_gc, 0);
    ATOMIC_STORE_INT32(&_sp->skipped_in_signal_handler, 0);
    ATOMIC_STORE_INT32(&_sp->skipped_in_job_registered, 0);
  }
  return Qtrue;
}

// rb_scout_update_indexes: Called when each layer starts or something
static VALUE
rb_scout_update_indexes(VALUE self, VALUE frame_index, VALUE trace_index)
{
  ATOMIC_STORE_INT16(&_sp->start_trace_index, NUM2INT(trace_index));
  ATOMIC_STORE_INT16(&_sp->start_frame_index, NUM2INT(frame_index));
  return Qtrue;
}

// rb_scout_current_trace_index: Get the current top of the trace stack
static VALUE
rb_scout_current_trace_index(VALUE self)
{
  scout_add_profiled_thread(); // This is the first place non-traced layers will hit. Be sure the thread struct is initialized and ready.
  return INT2NUM(ATOMIC_LOAD(&_sp->cur_traces_num));
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
  return INT2NUM(ATOMIC_LOAD(&_sp->skipped_in_gc));
}

static VALUE
rb_scout_skipped_in_handler(VALUE self)
{
  return INT2NUM(ATOMIC_LOAD(&_sp->skipped_in_signal_handler));
}

static VALUE
rb_scout_skipped_in_job_registered(VALUE self)
{
  return INT2NUM(ATOMIC_LOAD(&_sp->skipped_in_job_registered));
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
    rb_define_singleton_method(cStacks, "skipped_in_job_registered", rb_scout_skipped_in_job_registered, 0);

    rb_define_const(cStacks, "ENABLED", Qtrue);
    rb_warn("Finished Initializing ScoutProf Native Extension");
}

#else

static VALUE rb_scout_install_profiling(VALUE module)
{
  return Qnil;
}

static VALUE rb_scout_uninstall_profiling(VALUE module)
{
  return Qnil;
}

static VALUE rb_scout_start_profiling(VALUE module)
{
  return Qnil;
}

static VALUE rb_scout_stop_profiling(VALUE module)
{
  return Qnil;
}

static VALUE rb_scout_add_profiled_thread(VALUE module)
{
  return Qnil;
}

static VALUE rb_scout_remove_profiled_thread(VALUE module)
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
rb_scout_stop_sampling(VALUE self)
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
rb_scout_skipped_in_job_registered(VALUE self)
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
    rb_define_singleton_method(cStacks, "skipped_in_job_registered", rb_scout_skipped_in_job_registered, 0);

    rb_define_const(cStacks, "ENABLED", Qfalse);
    rb_define_const(cStacks, "INSTALLED", Qfalse);
}

#endif //#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

