begin
  require 'mkmf'
  can_compile = true
rescue Exception
  # This will appear only in verbose mode.
  $stderr.puts "Could not require 'mkmf'. Not fatal, the ScoutProf extension is optional."
end

can_compile &&= have_func('rb_profile_frames')
can_compile &&= have_func('rb_profile_frame_absolute_path')
can_compile &&= have_func('rb_profile_frame_label')
can_compile &&= have_func('rb_profile_frame_classpath')

if can_compile
  create_makefile('scoutprof')
else
  # Create a dummy Makefile, to satisfy Gem::Installer#install
  mfile = open("Makefile", "wb")
  mfile.puts '.PHONY: install'
  mfile.puts 'install:'
  mfile.puts "\t" + '@echo "ScoutProf extension not installed, skipping."'
  mfile.close
end