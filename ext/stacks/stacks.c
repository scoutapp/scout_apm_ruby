#include <ruby/ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>
#include <ruby/io.h>
#include <ruby/intern.h>
#include <signal.h>
#include <sys/time.h>
#include <pthread.h>
#include <semaphore.h>


ID sym_ScoutApm;
ID sym_Stacks;
ID sym_collect;
VALUE ScoutApm;
VALUE Stacks;

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

pthread_t btid; //Broadcast thread ID
sem_t do_broadcast; // Broadcast thread blocks on this semaphore. Timer signals increment it.

struct profiled_thread
{
  pthread_t th;
  struct profiled_thread *next;
};

// Profiled threads are joined as a linked list
pthread_mutex_t profiled_threads_mutex;
struct profiled_thread *root_thread = NULL;
struct profiled_thread *last_thread = NULL;

static VALUE add_profiled_thread()
{
  struct profiled_thread *thr;
  pthread_mutex_lock(&profiled_threads_mutex);
  thr = (struct profiled_thread *) malloc(sizeof(struct profiled_thread ));
  thr->th = pthread_self();
  thr->next = NULL;
  if (root_thread == NULL) {
    root_thread = thr;
  } else {
    last_thread->next = thr;
  }
  last_thread = thr;
  pthread_mutex_unlock(&profiled_threads_mutex);
  return Qtrue;
}

static VALUE remove_profiled_thread()
{
  struct profiled_thread *ptr = root_thread;
  struct profiled_thread *prev = NULL;
  pthread_t cur_thread = pthread_self();
  pthread_mutex_lock(&profiled_threads_mutex);
  while(ptr != NULL) {
    if (pthread_equal(cur_thread, ptr->th)) {
      if (root_thread == ptr) { // we're the root_thread
        if (root_thread == last_thread) { // we're also the last
          root_thread = NULL;
          last_thread = NULL;
          free(ptr);
          ptr = NULL;
        } else { // Just the root, not the last. Reassign root_thread to next
          root_thread = ptr->next;
          free(ptr);
          ptr = NULL;
        } // if root_thread == last_thread
      } else if (last_thread == ptr) { // we're the last thread, but not the root_thread
        prev->next = NULL;
        last_thread = prev;
        free(ptr);
        ptr = NULL;
      } else { // we're not the root_thread or last_thread
        prev->next = ptr->next; // cut ptr out of the linked list
        free(ptr);
        ptr = NULL;
      }
    } else { // pthread_equal()
      ptr = ptr->next;
    }
  } // while (ptr != NULL)
  pthread_mutex_unlock(&profiled_threads_mutex);
  return Qtrue;
}

void *
broadcast_profile_signal()
{
  struct profiled_thread *ptr;
  while(1) {
    sem_wait(&do_broadcast);
    ptr = root_thread;
    pthread_mutex_lock(&profiled_threads_mutex);

    while(ptr != NULL) {
      pthread_kill(ptr->th, SIGVTALRM); // Send signal to the specific thread
      ptr = ptr->next;
    }
    pthread_mutex_unlock(&profiled_threads_mutex);
  }
  return 0;
}

// Called every single time a tick happens.
// Goal is to collect the backtrace, and shuffle it off back to ruby-land for further analysis
//
// NOTE: This runs inside of a signal handler, which limits the work you can do
// here, or when calling back to rubyland
void
scout_record_sample()
{
  VALUE trace, trace_line;
  int i, num;

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
scout_install_profiling()
{
  struct sigaction new_action, old_action;
  struct sigaction new_vtaction, old_vtaction;
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
  new_action.sa_handler = scout_profile_timer_signal_handler;
  new_action.sa_flags = SA_RESTART;
  sigemptyset(&new_action.sa_mask);
  sigaction(SIGALRM, &new_action, &old_action);


  sem_init(&do_broadcast, 0, 1);
  pthread_create(&btid, NULL, broadcast_profile_signal, NULL);

  // Also set up an interrupt handler for when we broadcast an alarm
  new_vtaction.sa_handler = scout_profile_broadcast_signal_handler;
  new_vtaction.sa_flags = SA_RESTART;
  sigemptyset(&new_vtaction.sa_mask);
  sigaction(SIGVTALRM, &new_vtaction, &old_vtaction);

  // VALUE must be returned, just return nil
  return Qnil;
}

static VALUE
scout_start_profiling()
{
  struct itimerval timer;
  struct itimerval testTimer;
  int getResult;
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

  // VALUE must be returned, just return nil
  return Qnil;
}

//static VALUE
//scout_stop_profiling(VALUE module)
//{
//  // Wipe timer
// struct itimerval timer;
//  timer.it_interval.tv_sec = 0;
//  timer.it_interval.tv_usec = 0;
//  timer.it_value = timer.it_interval;
//  setitimer(ITIMER_REAL, &timer, 0);
//
//  return Qnil;
//}

static VALUE
scout_uninstall_profiling()
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
    rb_define_singleton_method(cStacks, "install", scout_install_profiling, 0);
    rb_define_singleton_method(cStacks, "uninstall", scout_uninstall_profiling, 0);

    // Starts/removes the timer tick, leaving the sighandler.
    //rb_define_singleton_method(cStacks, "start", scout_start_profiling, 0);
    //rb_define_singleton_method(cStacks, "stop", scout_stop_profiling, 0);

    rb_define_singleton_method(cStacks, "add_profiled_thread", add_profiled_thread, 0);
    rb_define_singleton_method(cStacks, "remove_profiled_thread", remove_profiled_thread, 0);

    rb_define_const(cStacks, "ENABLED", Qtrue);
    scout_install_profiling();
    scout_start_profiling();
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

