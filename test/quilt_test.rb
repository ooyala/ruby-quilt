#!/usr/bin/env ruby

require File.join(File.dirname(__FILE__), "test_helper")
require "net/http"
require "./lib/quilt"
require "webrick"

class FakeLogger
  def error(msg)
    # do nothing
  end
  def error?
    true
  end
  def debug(msg)
    # do nothing
  end
  def debug?
    true
  end
end

class QuiltTest < Scope::TestCase
  context "class functions" do
    context "new" do
      should "throw an exception if no config hash is specified" do
        error = nil
        begin
          Quilt.new(nil, FakeLogger.new)
        rescue Exception => e
          error = e
        end
        assert error
      end

      should "throw an exception if no local_path is specified" do
        error = nil
        begin
          Quilt.new({}, FakeLogger.new)
        rescue Exception => e
          error = e
        end
        assert error
      end

      should "create a quilt" do
        error = nil
        begin
          quilt = Quilt.new({:local_path => File.join(File.dirname(__FILE__), "mock", "good_project")},
                            FakeLogger.new)
          assert quilt.is_a?(Quilt)
        rescue Exception => e
          error = e
        end
        assert_nil error
      end
    end
  end
  context "instance functions" do
    setup_once do
      Thread.new do
        s = WEBrick::HTTPServer.new(:Port => 1337,
                                    :DocumentRoot => File.join(File.dirname(__FILE__), "mock", "server"),
                                    :Logger => nil,
                                    :AccessLog => [])
        begin
          s.start
        ensure
          s.shutdown
        end
      end
    end

    setup do
      @quilt = Quilt.new({
        :local_path => File.join(File.dirname(__FILE__), "mock", "good_project"),
        :remote_host => "localhost",
        :remote_port => 1337,
        :remote_path => "/"
      }, FakeLogger.new)
      @bad_remote_quilt = Quilt.new({
        :local_path => File.join(File.dirname(__FILE__), "mock", "good_project"),
        :remote_host => "localhost",
        :remote_port => 1338,
        :remote_path => "/"
      }, FakeLogger.new)
      @no_remote_quilt = Quilt.new({:local_path => File.join(File.dirname(__FILE__), "mock", "good_project")},
                                   FakeLogger.new)
    end

    context "get_module_name" do
      should "return nil for bad file names" do
        name = @quilt.get_module_name(nil)
        assert_nil name
        name = @quilt.get_module_name("")
        assert_nil name
        name = @quilt.get_module_name("hello")
        assert_nil name
        name = @quilt.get_module_name("/hello")
        assert_nil name
        name = @quilt.get_module_name("./hello")
        assert_nil name
        name = @quilt.get_module_name("hello/hello")
        assert_nil name
        name = @quilt.get_module_name("/hello/hello")
        assert_nil name
        name = @quilt.get_module_name("./hello/hello")
        assert_nil name
        name = @quilt.get_module_name("hello.json")
        assert_nil name
        name = @quilt.get_module_name("/hello.json")
        assert_nil name
        name = @quilt.get_module_name("./hello.json")
        assert_nil name
        name = @quilt.get_module_name("hello/hello.json")
        assert_nil name
        name = @quilt.get_module_name("/hello/hello.json")
        assert_nil name
        name = @quilt.get_module_name("./hello/hello.json")
        assert_nil name
      end

      should "return a valid name for good file names" do
        name = @quilt.get_module_name("hello.js")
        assert_equal "hello", name
        name = @quilt.get_module_name("/hello.js")
        assert_equal "hello", name
        name = @quilt.get_module_name("./hello.js")
        assert_equal "hello", name
        name = @quilt.get_module_name("hi/hello.js")
        assert_equal "hello", name
        name = @quilt.get_module_name("/hi/hello.js")
        assert_equal "hello", name
        name = @quilt.get_module_name("./hi/hello.js")
        assert_equal "hello", name
      end
    end

    context "get_module" do
      should "return nil if the module does not exist" do
        mod = @quilt.get_module("randomjunk", [], "morerandomjunk")
        assert_nil mod
      end

      should "return the module if the module does exist" do
        mod = @quilt.get_module("optional/0.js", ["1"], File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        assert_equal ["1"], mod[:dependancies]
        assert_equal "0\n", mod[:module]
      end

      should "handle relative and non-relative filenames" do
        mod = @quilt.get_module("optional/0.js", [], File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        mod = @quilt.get_module("1.js", [], File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        mod = @quilt.get_module("./optional/0.js", [], File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        mod = @quilt.get_module("./1.js", [], File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
      end

      should "handle a single dependancy as a string" do
        mod = @quilt.get_module("optional/0.js", "1", File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        assert_equal ["1"], mod[:dependancies]
        assert_equal "0\n", mod[:module]
      end
    end

    context "load_version" do
      should "return nil if there is no manifest" do
        version = @quilt.load_version(File.dirname(__FILE__) + "/mock", "good_project")
        assert_nil version
      end

      should "return a version" do
        version = @quilt.load_version(File.dirname(__FILE__) + "/mock/good_project", "1.0.0")
        assert version
        assert_equal "h\nc\n", version[:base]
        expected = {
          "0" => { :dependancies => [ "8" ], :module => "0\n" },
          "1" => { :dependancies => [ "7", "9" ], :module => "1\n" },
          "2" => { :dependancies => [ "8" ], :module => "2\n" },
          "3" => { :dependancies => [], :module => "3\n" },
          "4" => { :dependancies => [], :module => "4\n" },
          "5" => { :dependancies => [], :module => "5\n" },
          "6" => { :dependancies => [], :module => "6\n" },
          "7" => { :dependancies => [], :module => "7\n" },
          "8" => { :dependancies => [], :module => "8\n" },
          "9" => { :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:modules]
        assert_equal version[:footer], "f1.0.0\n"
      end

      should "gracefully handle bad manifest entries" do
        version = @quilt.load_version(File.dirname(__FILE__) + "/mock/bad_project", "1.0.0")
        assert version
        assert_equal "c\n", version[:base]
        expected = {
          "0" => { :dependancies => [ "8" ], :module => "0\n" },
          "1" => { :dependancies => [ "7", "9" ], :module => "1\n" },
          "2" => { :dependancies => [ "8" ], :module => "2\n" },
          "3" => { :dependancies => [], :module => "3\n" },
          "4" => { :dependancies => [], :module => "4\n" },
          "5" => { :dependancies => [], :module => "5\n" },
          "6" => { :dependancies => [], :module => "6\n" },
          "7" => { :dependancies => [], :module => "7\n" },
          "8" => { :dependancies => [], :module => "8\n" },
          "9" => { :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:modules]
        assert_nil version[:footer]
      end
    end

    context "resolve_dependancies" do
      setup do
        @version = {
          :base => "h\nc\n",
          :modules => {
            "0" => { :dependancies => [ "8" ], :module => "0\n" },
            "1" => { :dependancies => [ "7", "9" ], :module => "1\n" },
            "2" => { :dependancies => [ "8" ], :module => "2\n" },
            "3" => { :dependancies => [], :module => "3\n" },
            "4" => { :dependancies => [], :module => "4\n" },
            "5" => { :dependancies => [ "6" ], :module => "5\n" },
            "6" => { :dependancies => [ "5" ], :module => "6\n" },
            "7" => { :dependancies => [], :module => "7\n" },
            "8" => { :dependancies => [ "9" ], :module => "8\n" },
            "9" => { :dependancies => [], :module => "9\n" }
          }
        }
      end

      should "return an empty string for no modules" do
        out = @quilt.resolve_dependancies(nil, @version);
        assert_equal '', out
        out = @quilt.resolve_dependancies([], @version);
        assert_equal '', out
        out = @quilt.resolve_dependancies({ "yo" => "sup" }, @version);
        assert_equal '', out
        out = @quilt.resolve_dependancies("hi", @version);
        assert_equal '', out
      end

      should "resolve dependancies" do
        out = @quilt.resolve_dependancies([ "0", "1", "2" ], @version);
        assert_equal "9\n8\n0\n7\n1\n2\n", out
      end

      should "gracefully handle circular dependancies" do
        out = @quilt.resolve_dependancies([ "5" ], @version);
        assert_equal "6\n5\n", out
      end

      should "gracefully handle non-existant modules" do
        out = @quilt.resolve_dependancies([ "5", "oogabooga" ], @version);
        assert_equal "6\n5\n", out
      end
    end

    context "get_version" do
      should "return nil for non-existant version when no remote information exists" do
        version = @no_remote_quilt.get_version('2.0.0')
        assert_nil version
      end

      should "return version if it exists" do
        version = @no_remote_quilt.get_version('1.0.0')
        assert version
        assert_equal "h\nc\n", version[:base]
        expected = {
          "0" => { :dependancies => [ "8" ], :module => "0\n" },
          "1" => { :dependancies => [ "7", "9" ], :module => "1\n" },
          "2" => { :dependancies => [ "8" ], :module => "2\n" },
          "3" => { :dependancies => [], :module => "3\n" },
          "4" => { :dependancies => [], :module => "4\n" },
          "5" => { :dependancies => [], :module => "5\n" },
          "6" => { :dependancies => [], :module => "6\n" },
          "7" => { :dependancies => [], :module => "7\n" },
          "8" => { :dependancies => [], :module => "8\n" },
          "9" => { :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:modules]
        assert_equal "f1.0.0\n", version[:footer]
      end

      should "fetch remote version if it does not exist locally" do
        version = @quilt.get_version('2.0.0')
        assert version
        assert_equal "h\nc\n", version[:base]
        expected = {
          "0" => { :dependancies => [ "8" ], :module => "0\n" },
          "1" => { :dependancies => [ "7", "9" ], :module => "1\n" },
          "2" => { :dependancies => [ "8" ], :module => "2\n" },
          "3" => { :dependancies => [], :module => "3\n" },
          "4" => { :dependancies => [], :module => "4\n" },
          "5" => { :dependancies => [], :module => "5\n" },
          "6" => { :dependancies => [], :module => "6\n" },
          "7" => { :dependancies => [], :module => "7\n" },
          "8" => { :dependancies => [], :module => "8\n" },
          "9" => { :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:modules]
        assert_equal "f2.0.0\n", version[:footer]
        `rm -rf #{File.join(File.dirname(__FILE__), "mock", "good_project", "2.0.0")}`
      end

      should "return nil if version doesn't exist locally or remote" do
        assert_nil @quilt.get_version('3.0.0')
      end

      should "return nil if remote version file is empty" do
        assert_nil @quilt.get_version('empty')
      end

      should "return nil if remote version file is not a gzipped tar" do
        assert_nil @quilt.get_version('bad')
      end

      should "return nil if remote server doesn't exist" do
        assert_nil @bad_remote_quilt.get_version('2.0.0')
      end
    end

    context "stitch" do
      should "return empty for a non-existant version when no remote information exists" do
        assert_equal '', @no_remote_quilt.stitch(['0'], '2.0.0')
      end

      should "properly stitch for an existing version with selector array" do
        assert_equal "h\nc\n8\n0\nf1.0.0\n", @no_remote_quilt.stitch(['0'], '1.0.0')
      end

      should "properly stitch for an existing version with selector function" do
        assert_equal "h\nc\n8\n0\n7\n9\n1\n2\n3\n4\n5\n6\nf1.0.0\n", @no_remote_quilt.stitch(Proc.new do |m|
          true
        end, '1.0.0')
      end

      should "properly stitch for remote version with selector array" do
        assert_equal "h\nc\n8\n0\nf2.0.0\n", @quilt.stitch(['0'], '2.0.0')
        `rm -rf #{File.join(File.dirname(__FILE__), "mock", "good_project", "2.0.0")}`
      end

      should "properly stitch for remote version with selector function" do
        assert_equal "h\nc\n8\n0\n7\n9\n1\n2\n3\n4\n5\n6\nf2.0.0\n", @quilt.stitch(Proc.new do |m|
          true
        end, '2.0.0')
        `rm -rf #{File.join(File.dirname(__FILE__), "mock", "good_project", "2.0.0")}`
      end
    end
  end
end
