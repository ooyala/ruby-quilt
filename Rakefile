require "rake/testtask"

task :test => ["test:unit"]

namespace :test do
  Rake::TestTask.new(:unit) do |task|
    mask.libs << "test"
    task.test_files = FileList["test/*.rb"]
  end
end
