begin
  require 'mkmf'
  can_compile_extensions = true
rescue Exception
  # This will appear only in verbose mode.
  $stderr.puts "Could not require 'mkmf'. Not fatal, the Stacks extension is optional."
end

if can_compile_extensions &&
   have_func('rb_postponed_job_register_one') &&
   have_func('rb_profile_frames') &&
   have_func('rb_profile_frame_absolute_path') &&
   have_func('rb_profile_frame_label') &&
   have_func('rb_profile_frame_classpath')
  $defs.push "-ggdb -O0" # Include debug symbols, no optimization.
  create_makefile('stacks')
else
  # Create a dummy Makefile, to satisfy Gem::Installer#install
  mfile = open("Makefile", "wb")
  mfile.puts '.PHONY: install'
  mfile.puts 'install:'
  mfile.puts "\t" + '@echo "Stack extension not installed, skipping."'
  mfile.close
end