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
VALUE ScoutApm;
VALUE Stacks;

VALUE mScoutApm;
VALUE mInstruments;
VALUE cStacks;

#define BUF_SIZE 2048
#define INTERVAL 5000

VALUE interval;

#ifdef RUBY_INTERNAL_EVENT_NEWOBJ

#include <sys/resource.h> // is this needed?
#include <sys/time.h>
#include <ruby/debug.h>

pthread_t btid; // Broadcast thread ID
sem_t do_broadcast; // Broadcast thread blocks on this semaphore. Timer signals increment it.

struct profiled_thread
{
  pthread_t th;
  struct profiled_thread *next;
};

// Profiled threads are joined as a linked list
pthread_mutex_t profiled_threads_mutex;
pthread_mutexattr_t profiled_threads_mutex_attr;
struct profiled_thread *head_thread = NULL;

static VALUE rb_scout_add_profiled_thread(VALUE self)
{
  struct profiled_thread *thr;
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

static VALUE rb_scout_remove_profiled_thread()
{
  remove_profiled_thread(pthread_self());
  return Qtrue;
}

void *
broadcast_profile_signal()
{
  struct profiled_thread *ptr, *next;
  while(1) {
    sem_wait(&do_broadcast);
    ptr = head_thread;
    next = NULL;
    pthread_mutex_lock(&profiled_threads_mutex);
    while(ptr != NULL) {
      if (pthread_kill(ptr->th, SIGVTALRM) == ESRCH) { // Send signal to the specific thread. If ESRCH is returned, remove the dead thread
        next = ptr->next;
        remove_profiled_thread(ptr->th);
        ptr = next;
      } else {
        ptr = ptr->next;
      }
    }
    pthread_mutex_unlock(&profiled_threads_mutex);
  }
  return 0; // should never get here.
}

// Goal is to collect the backtrace, and shuffle it off back to ruby-land for further analysis
// Note that this is called from *EVERY PROFILED THREAD FOR EACH CLOCK TICK INTERVAL*, so the performance of this method is crucial.
void
scout_record_sample()
{
  VALUE frames_buffer[BUF_SIZE], trace, trace_line;
  int lines_buffer[BUF_SIZE], i, num;

  // Get frames
  num = rb_profile_frames(0, sizeof(frames_buffer) / sizeof(VALUE), frames_buffer, lines_buffer);

  // Create an array to hold trace lines
  trace = rb_ary_new2(num);

  trace_line = Qnil;
  for (i = 0; i < num; i++) {
    // Extract values
    VALUE frame = frames_buffer[i];
    VALUE file  = rb_profile_frame_absolute_path(frame);
    VALUE line  = INT2FIX(lines_buffer[i]);
    VALUE klass = rb_profile_frame_classpath(frame);
    VALUE label = rb_profile_frame_label(frame);

    // Create and populate array to hold one line of the trace
    trace_line = rb_ary_new2(4);
    rb_ary_store(trace_line, 0, file);
    rb_ary_store(trace_line, 1, line);
    rb_ary_store(trace_line, 2, klass);
    rb_ary_store(trace_line, 3, label);

    rb_ary_push(trace, trace_line);
  }

  // Store the Trace
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
scout_profile_broadcast_signal_handler(int sig)
{
  if (rb_during_gc()) {
    // _stackprof.during_gc++, _stackprof.overall_samples++;
  } else {
    rb_postponed_job_register_one(0, scout_profile_job_handler, 0);
  }
}

//scout_profile_signal_handler(int sig, siginfo_t *sinfo, void *ucontext)
static void
scout_profile_timer_signal_handler(int sig)
{
  sem_post(&do_broadcast);
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


  sem_init(&do_broadcast, 0, 1);
  pthread_mutexattr_init(&profiled_threads_mutex_attr);
  pthread_mutexattr_settype(&profiled_threads_mutex_attr, PTHREAD_MUTEX_RECURSIVE);
  pthread_mutex_init(&profiled_threads_mutex, &profiled_threads_mutex_attr);
  pthread_create(&btid, NULL, broadcast_profile_signal, NULL);

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

void Init_stacks()
{
    mScoutApm = rb_define_module("ScoutApm");
    mInstruments = rb_define_module_under(mScoutApm, "Instruments");
    cStacks = rb_define_class_under(mInstruments, "Stacks", rb_cObject);
    // Lookup the classes
    sym_ScoutApm = rb_intern("ScoutApm");
    sym_Stacks = rb_intern("Stacks");
    sym_collect = rb_intern("collect");
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

