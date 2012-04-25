require "rake/testtask"

task :test => ["test:unit"]

namespace :test do
  Rake::TestTask.new(:unit) do |task|
    task.libs << "test"
    task.test_files = FileList["test/*.rb"]
  end
end
