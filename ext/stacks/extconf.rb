begin
  require 'mkmf'
  can_compile = true
rescue Exception
  # This will appear only in verbose mode.
  $stderr.puts "Could not require 'mkmf'. Not fatal, the Stacks extension is optional."
end

can_compile &&= have_func('rb_postponed_job_register_one')
can_compile &&= have_func('rb_profile_frames')
can_compile &&= have_func('rb_profile_frame_absolute_path')
can_compile &&= have_func('rb_profile_frame_label')
can_compile &&= have_func('rb_profile_frame_classpath')

# Explicitly link against librt
if have_macro('__linux__')
  can_compile &&= have_library('rt') # for timer_create, timer_settime
end

# Pick the atomics implementation
has_atomics_header = have_header("stdatomic.h")
if has_atomics_header
  $defs.push "-DSCOUT_USE_NEW_ATOMICS"
else
  $defs.push "-DSCOUT_USE_OLD_ATOMICS"
end

if can_compile
  create_makefile('stacks')
else
  # Create a dummy Makefile, to satisfy Gem::Installer#install
  mfile = open("Makefile", "wb")
  mfile.puts '.PHONY: install'
  mfile.puts 'install:'
  mfile.puts "\t" + '@echo "Stack extension not installed, skipping."'
  mfile.close
end