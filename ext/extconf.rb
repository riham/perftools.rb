require 'mkmf'

if RUBY_VERSION >= "1.9"
  begin 
    require "ruby_core_source"
  rescue LoadError
    STDERR.print("Makefile creation failed\n\n")
    STDERR.print("Please note that for ruby-1.9 you need the following gems installed: archive-tar-minitar, ruby_core_source  \n\n")
    STDERR.print("Those gems are not installed as dependency as ruby_core_source will install ruby header files into your ruby directory. Those headers are yet subject to change according to matz, yet they are currently needed for perftools  \n\n")        
    exit(1)
  end
end

require 'fileutils'
require 'net/http'

url = 'http://google-perftools.googlecode.com/files/google-perftools-1.3.tar.gz'
perftools = File.basename(url)
dir = File.basename(perftools, '.tar.gz')

Logging.message "(I'm about to download and compile google-perftools.. this will definitely take a while)"

FileUtils.mkdir_p('src')

if proxy = URI(ENV['http_proxy'] || ENV['HTTP_PROXY']) rescue nil
  proxy_host = proxy.host
  proxy_port = proxy.port
  proxy_user, proxy_pass = proxy.userinfo.split(/:/) if proxy.userinfo
end

Dir.chdir('src') do
  unless File.exists?(perftools)
    Net::HTTP::Proxy(proxy_host, proxy_port, proxy_user, proxy_pass).get_response(URI(url)) do |res|
      File.open(perftools, 'wb') do |out|
        res.read_body do |chunk|
          out.write(chunk)
        end
      end
    end
  end

  unless File.exists?(dir)
    xsystem("tar zxvf #{perftools}")
    Dir.chdir(dir) do
      xsystem("patch -p1 < ../../../patches/perftools.patch")
      xsystem("patch -p1 < ../../../patches/perftools-gc.patch")
      xsystem("patch -p1 < ../../../patches/perftools-osx.patch") if RUBY_PLATFORM =~ /darwin/
      xsystem("patch -p1 < ../../../patches/perftools-debug.patch")# if ENV['DEBUG']
    end
  end

  unless File.exists?('../bin/pprof')
    Dir.chdir(dir) do
      FileUtils.cp 'src/pprof', '../../../bin/'
    end
  end

  unless File.exists?('../librubyprofiler.a')
    Dir.chdir(dir) do
      xsystem("./configure --disable-heap-profiler --disable-heap-checker --disable-shared")
      xsystem("make")
      FileUtils.cp '.libs/libprofiler.a', '../../librubyprofiler.a'
    end
  end
end

case RUBY_PLATFORM
when /darwin/, /linux/
  CONFIG['LDSHARED'] = "$(CXX) " + CONFIG['LDSHARED'].split[1..-1].join(' ')
end

$libs = append_library($libs, 'rubyprofiler')
if RUBY_VERSION >= "1.9"
   hdrs = proc {
    have_header("vm_core.h") and have_header("iseq.h") and have_header("insns.inc") and 
    have_header("insns_info.inc")
  }

  if !Ruby_core_source::create_makefile_with_core( hdrs, "perftools.rb")
    STDERR.print("Makefile creation failed\n")
    STDERR.print("*************************************************************\n\n")
  exit(1)
  end 
else 
  have_func('rb_during_gc', 'ruby.h')
  create_makefile 'perftools'
end
