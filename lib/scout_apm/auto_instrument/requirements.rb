begin
  require 'prism'
rescue LoadError
end

unless defined?(Prism)
  begin
    require 'parser'
  rescue LoadError
  end
end
