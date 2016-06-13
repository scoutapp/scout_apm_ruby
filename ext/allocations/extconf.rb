begin
  require 'mkmf'
  can_compile_extensions = true
rescue Exception
  # This will appear only in verbose mode.
  $stderr.puts "Could not require 'mkmf'. Not fatal, the Allocations extension is optional."
end

if can_compile_extensions &&
   have_func('rb_tracepoint_new') &&
   have_func('rb_tracepoint_enable') &&
   have_func('rb_tracearg_from_tracepoint') &&
   have_func('rb_tracearg_event_flag') &&
   have_const('RUBY_INTERNAL_EVENT_NEWOBJ')
  create_makefile('allocations')
else
  # Create a dummy Makefile, to satisfy Gem::Installer#install
  mfile = open("Makefile", "wb")
  mfile.puts '.PHONY: install'
  mfile.puts 'install:'
  mfile.puts "\t" + '@echo "Allocations extension not installed, skipping."'
  mfile.close
end