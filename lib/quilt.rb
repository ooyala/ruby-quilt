require 'logger'
require 'json'
require 'net/http'
require 'popen4'
require 'fileutils'

class Quilt
  HEADER_KEY = "header"
  COMMON_KEY = "common"
  OPTIONAL_KEY = "optional"
  FOOTER_KEY = "footer"
  PREFIX_KEY = "prefix"
  DEBUG_PREFIX_KEY = "debug_prefix"

  def initialize(config, log = Logger.new(STDOUT))
    @config = config;
    @versions = {};
    @log = log

    if (config[:local_path])
      Dir.foreach(config[:local_path]) do |version_dir|
        next if version_dir == "." || version_dir == ".."
        @versions[version_dir] = load_version(config[:local_path], version_dir)
      end
    else
      throw "Quilt: local path not specified";
    end
  end

  def log_error(msg, e = nil)
    return unless @log && @log.error?
    @log.error(msg) if msg
    if (e)
      @log.error(e.message)
      @log.error(e.backtrace.inspect)
    end
  end

  def log_debug(msg)
    return unless @log && @log.debug?
    @log.debug(msg)
  end

  def get_module_name(filename)
    return nil unless filename
    matches = filename.match(/(^.*\/|^)([^\/]+)$/)
    return nil unless matches && matches.length >= 3
    matches[2]
  end

  def get_module(filename, dependancies, version_dir)
    tmp_module = {}
    tmp_module[:dependancies] = dependancies.is_a?(Array) ? dependancies :
                                                            (dependancies.is_a?(String) ? [ dependancies ] :
                                                            [])
    begin
      tmp_module[:module] = File.open(File.join(version_dir, filename), "rb").read
    rescue Exception => e
      log_error("  Could not load module: #{filename}", e)
      return nil
    end
    tmp_module
  end

  def load_version(local_path, version_name)
    log_debug("Loading Version: "+version_name)
    manifest = {}
    new_version = {
      :name => version_name,
      :dir => File.join(local_path, version_name),
      :default => {
        :base => '',
        :optional => {},
      }
    }
    begin
      manifest = JSON.parse(File.read(File.join(new_version[:dir], "manifest.json")))
      new_version[:default][:dir] =
        manifest[PREFIX_KEY] ? File.join(new_version[:dir], manifest[PREFIX_KEY]) :
                               new_version[:dir]
      if (manifest[DEBUG_PREFIX_KEY])
        new_version[:debug] = {
          :dir => manifest[DEBUG_PREFIX_KEY] ?  File.join(new_version[:dir], manifest[DEBUG_PREFIX_KEY]) :
                                                new_version[:dir],
          :base => '',
          :optional => {}
        }
      end
    rescue Exception => e
      log_error("  Could not read manifest!", e);
      return nil
    end
    #  manifest.json:
    #  {
    #    "prefix" : "<prefix directory>"
    #    "debug_prefix : "<debug prefix directory"
    #    "header" : "<header file>",
    #    "footer" : "<footer file>",
    #    "common" : [
    #      "<module file>",
    #      ...
    #    ],
    #    "optional" : {
    #      "<module file>" : [ "<dependancy module name>", ... ],
    #      ...
    #    }
    #  }
    module_loader = Proc.new do |prefix|
      dir = new_version[prefix][:dir]
      if manifest[HEADER_KEY]
        begin
          new_version[prefix][:base] =
            "#{new_version[prefix][:base]}#{File.open(File.join(dir, manifest[HEADER_KEY]), "rb").read}"
        rescue Exception => e
          log_error("  Could not load #{prefix.to_s} header: #{manifest[HEADER_KEY]}", e)
        end
      end
      if manifest[COMMON_KEY] && manifest[COMMON_KEY].is_a?(Array)
        manifest[COMMON_KEY].each do |filename|
          begin
            new_version[prefix][:base] =
              "#{new_version[prefix][:base]}#{File.open(File.join(dir, filename), "rb").read}"
          rescue Exception => e
            log_error("  Could not load #{prefix.to_s} common module: #{filename}", e)
          end
        end
      end
      if manifest[OPTIONAL_KEY] && manifest[OPTIONAL_KEY].is_a?(Hash)
        manifest[OPTIONAL_KEY].each do |filename, dependancies|
          tmp_module_name = get_module_name(filename)
          if (tmp_module_name)
            tmp_module = get_module(filename, dependancies, dir)
            if (tmp_module)
              new_version[prefix][:optional][tmp_module_name] = tmp_module
            end
          else
            log_error("  Could not extract #{prefix.to_s} module name from: #{filename}")
          end
        end
      end
      if manifest[FOOTER_KEY]
        begin
          new_version[prefix][:footer] = File.open(File.join(dir, manifest[FOOTER_KEY]), "rb").read
        rescue Exception => e
          log_error("  Could not load #{prefix.to_s} footer: #{manifest[FOOTER_KEY]}", e)
          new_version[:footer] = nil
        end
      end
    end

    module_loader.call(:default)
    module_loader.call(:debug) if new_version[:debug]

    new_version
  end

  def resolve_dependancies(modules, version, all_modules = {})
    out = ''
    return out if !modules || !(modules.is_a?(Array)) || modules.empty?
    my_all_modules = all_modules
    modules.each do |name|
      break if my_all_modules[name] == 2
      if (!version[:optional][name] || !version[:optional][name][:module])
        log_error("  invalid module: #{name}");
        my_all_modules[name] = 2
        break
      end
      if (my_all_modules[name] == 1)
        log_error("  circular module dependancy: #{name}")
        break
      end
      my_all_modules[name] = 1
      out = "#{out}#{resolve_dependancies(version[:optional][name][:dependancies], version, my_all_modules)}"
      out = "#{out}#{version[:optional][name][:module]}"
      my_all_modules[name] = 2
    end
    out
  end

  def get_version(name)
    return @versions[name] if @versions[name]
    if (!@config[:remote_host] || !@config[:remote_path])
      log_error("unable to load from host: #{@config[:remote_host]}, path: #{@config[:remote_path]}")
      return nil
    end
    port = @config[:remote_port] ? @config[:remote_port].to_i : 80
    # Fetch the version
    filename = "#{name}.tgz"
    version_dir = File.join(@config[:local_path], name)
    begin
      res = Net::HTTP.get_response(@config[:remote_host].to_s,
                                   File.join(@config[:remote_path].to_s, "#{name}.tgz"), port)
      if (res.code != "200")
        log_error("no version fetched : #{res.code}")
        return nil
      end
      FileUtils.mkdir(version_dir) unless File.exists?(version_dir)
      open(File.join(version_dir, filename), "wb") do |file|
        file.write(res.body)
      end
    rescue Exception => e
      log_error("could not fetch version", e)
      return nil
    end
    # Untar the version
    tar_stdout = nil
    tar_stderr = nil
    tar_status =
      POpen4::popen4("cd #{version_dir} && tar -xzf #{filename} && rm #{filename}") do |stdo, stde, stdi, pid|
      stdi.close
      tar_stdout = stdo.read.strip
      tar_stderr = stde.read.strip
    end
    if (!tar_status.exitstatus.zero?)
      log_error("unable to untar package: cd #{version_dir} && tar -xzf #{filename} && rm #{filename}")
      log_error("stdout: #{tar_stdout}")
      log_error("stderr: #{tar_stderr}")
      begin
        FileUtils.rm_r(version_dir)
      rescue Exception => e
        # do nothing
      end
      return nil
    end
    # Load the version
    @versions[name] = load_version(@config[:local_path], name)
    if (!@versions[name])
      begin
        FileUtils.rm_r(version_dir)
      rescue Exception => e
        # do nothing
      end
      return nil
    end
    @versions[name]
  end

  def stitch(selector, version_name, prefix = :default)
    return '' if !selector
    version = get_version(version_name)
    if (!version)
      log_error("could not fetch version: #{version_name}")
      return ''
    end
    outversion = version[prefix] || version[:default]

    # get modules we want to use
    modules = []
    if (selector.is_a?(Proc))
      modules = outversion[:optional].keys.select do |mod|
        selector.call(mod)
      end
    elsif (selector.is_a?(Array))
      modules = selector
    end

    # resolve dependancies
    output = "#{outversion[:base]}#{resolve_dependancies(modules, outversion, {})}#{outversion[:footer] ?
                                                                                    outversion[:footer] :
                                                                                    ''}"
  end

  def healthy?
    # return true if no remote info
    return [true, nil] if !@config[:remote_host] || !@config[:remote_path]
    # fetch health_check.txt from remote URL
    host = @config[:remote_host].to_s
    port = @config[:remote_port] ? @config[:remote_port].to_i : 80
    path = File.join(@config[:remote_path].to_s, 'health_check.txt')
    begin
      res = Net::HTTP.get_response(host, path, port)
      if (res.code != "200")
        return [false, "Could not fetch heath check file: http://#{host}:#{port}#{path} - status #{res.code}"]
      end
    rescue Exception => e
      return [false, "Could not fetch heath check file: http://#{host}:#{port}#{path} - #{e.message}"]
    end
    [true, nil]
  end
end
