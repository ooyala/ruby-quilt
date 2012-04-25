require 'logger'
require 'json'

class Quilt
  HEADER_KEY = "header"
  COMMON_KEY = "common"
  OPTIONAL_KEY = "optional"
  FOOTER_KEY = "footer"

  def initialize(config, log = Logger.new(STDOUT))
    @config = config;
    @versions = {};
    @log = log
  end

  def logError(msg)
    @log.error(msg) if @log && @log.error?
  end

  def logDebug(msg)
    @log.debug(msg) if @log && @log.debug?
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
      logError("  Could not load module: #{filename}")
      logError(e.message)
      logError(e.backtrace.inspect)
      return nil
    end
    tmp_module
  end

  def load_version(local_path, version_name)
    logDebug("Loading Version: "+version_name)
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
      logError("  Could not read manifest!");
      logError(e.message)
      logError(e.backtrace.inspect)
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
        logError("  Could not load header: #{manifest[HEADER_KEY]}")
        logError(e.message)
        logError(e.backtrace.inspect)
      end
    end
    if manifest[COMMON_KEY] && manifest[COMMON_KEY].is_a?(Array)
      manifest[COMMON_KEY].each do |filename|
        begin
          newVersion[:base] = "#{newVersion[:base]}#{File.open(File.join(newVersion[:dir],
                                                                         filename), "rb").read}"
        rescue Exception => e
          logError("  Could not load common module: #{filename}")
          logError(e.message)
          logError(e.backtrace.inspect)
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
            logError("  Could not extract module name from: #{filename}")
          end
        end
      end
    end
    if manifest[FOOTER_KEY]
      begin
        newVersion[:footer] = File.open(File.join(newVersion[:dir], manifest[FOOTER_KEY]), "rb").read
      rescue Exception => e
        logError("  Could not load footer: #{manifest[FOOTER_KEY]}")
        logError(e.message)
        logError(e.backtrace.inspect)
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
        logError("  invalid module: #{name}");
        my_all_modules[name] = 2
        break
      end
      if (my_all_modules[name] == 1)
        logError("  circular module dependancy: #{name}")
        break
      end
      my_all_modules[name] = 1
      out = "#{out}#{resolve_dependancies(version[:modules][name][:dependancies], version, my_all_modules)}"
      out = "#{out}#{version[:modules][name][:module]}"
      my_all_modules[name] = 2
    end
    out
  end
end
