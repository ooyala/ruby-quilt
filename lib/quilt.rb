require 'logger'
require 'json'
require 'net/http'

class Quilt
  HEADER_KEY = "header"
  COMMON_KEY = "common"
  OPTIONAL_KEY = "optional"
  FOOTER_KEY = "footer"

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
    matches = filename.match(/(^.*\/|^)(.*)\.js$/)
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
    newVersion = {
      :name => version_name,
      :dir => File.join(local_path, version_name),
      :base => '',
      :modules => {}
    }
    begin
      manifest = JSON.parse(File.read(File.join(newVersion[:dir], "manifest.json")))
    rescue Exception => e
      log_error("  Could not read manifest!", e);
      return nil
    end
    #  manifest.json:
    #  {
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
    if manifest[HEADER_KEY]
      begin
        newVersion[:base] = "#{newVersion[:base]}#{File.open(File.join(newVersion[:dir],
                                                                       manifest[HEADER_KEY]), "rb").read}"
      rescue Exception => e
        log_error("  Could not load header: #{manifest[HEADER_KEY]}", e)
      end
    end
    if manifest[COMMON_KEY] && manifest[COMMON_KEY].is_a?(Array)
      manifest[COMMON_KEY].each do |filename|
        begin
          newVersion[:base] = "#{newVersion[:base]}#{File.open(File.join(newVersion[:dir],
                                                                         filename), "rb").read}"
        rescue Exception => e
          log_error("  Could not load common module: #{filename}", e)
        end
      end
    end
    if manifest[OPTIONAL_KEY] && manifest[OPTIONAL_KEY].is_a?(Hash)
      manifest[OPTIONAL_KEY].each do |filename, dependancies|
        tmp_module = get_module(filename, dependancies, newVersion[:dir])
        if (tmp_module)
          tmp_module_name = get_module_name(filename)
          if (tmp_module_name)
            newVersion[:modules][tmp_module_name] = tmp_module
          else
            log_error("  Could not extract module name from: #{filename}")
          end
        end
      end
    end
    if manifest[FOOTER_KEY]
      begin
        newVersion[:footer] = File.open(File.join(newVersion[:dir], manifest[FOOTER_KEY]), "rb").read
      rescue Exception => e
        log_error("  Could not load footer: #{manifest[FOOTER_KEY]}", e)
        newVersion[FOOTER_KEY] = nil
      end
    end
    newVersion
  end

  def resolve_dependancies(modules, version, all_modules = {})
    out = ''
    return out if !modules || !(modules.is_a?(Array)) || modules.empty?
    my_all_modules = all_modules
    modules.each do |name|
      break if my_all_modules[name] == 2
      if (!version[:modules][name] || !version[:modules][name][:module])
        log_error("  invalid module: #{name}");
        my_all_modules[name] = 2
        break
      end
      if (my_all_modules[name] == 1)
        log_error("  circular module dependancy: #{name}")
        break
      end
      my_all_modules[name] = 1
      out = "#{out}#{resolve_dependancies(version[:modules][name][:dependancies], version, my_all_modules)}"
      out = "#{out}#{version[:modules][name][:module]}"
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
    begin
      Net::HTTP.start(@config[:remote_host].to_s, port) do |http|
        res = http.get("#{@config[:remote_path].to_s}#{name}.tgz")
        if (res.code != "200")
          log_error("no version fetched : #{res.code}")
          return nil
        end
        open(File.join(@config[:local_path], filename), "wb") do |file|
          file.write(res.body)
        end
      end
    rescue Exception => e
      log_error("could not fetch version", e)
      return nil
    end
    # Untar the version
    tar_output = `cd #{@config[:local_path]} && tar -xzf #{filename} 2>&1`
    if ($?.to_i != 0)
      log_error("unable to untar package")
      log_error(tar_output)
      `cd #{@config[:local_path]} && rm #{filename}`
      return nil
    end
    `cd #{@config[:local_path]} && rm #{filename}`
    # Load the version
    @versions[name] = load_version(@config[:local_path], name)
  end

  def stitch(selector, version_name)
    return '' if !selector
    version = get_version(version_name)
    if (!version)
      log_error("could not fetch version: #{version_name}")
      return ''
    end

    # get modules we want to use
    modules = []
    if (selector.is_a?(Proc))
      modules = version[:modules].keys.select do |mod|
        selector.call(mod)
      end
    elsif (selector.is_a?(Array))
      modules = selector
    end

    # resolve dependancies
    output = "#{version[:base]}#{resolve_dependancies(modules, version, {})}#{version[:footer] ?
                                                                              version[:footer] :
                                                                              ''}"
  end
end
