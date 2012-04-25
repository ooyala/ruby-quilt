require "rake/testtask"

task :test => ["test:all"]

namespace :test do
  Rake::TestTask.new(:all) do |task|
    task.libs << "test"
    task.test_files = FileList["test/*.rb"]
  end
end
