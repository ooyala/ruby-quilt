#!/usr/bin/env ruby

require "./test/test_helper"

require "./lib/quilt"
require "faraday"
require "webrick"
require "ecology"

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

BAD_ECOLOGY="./test/mock/ecologies/bad.ecology"
NO_REMOTE_ECOLOGY="./test/mock/ecologies/noremote.ecology"
BAD_REMOTE_ECOLOGY="./test/mock/ecologies/badremote.ecology"
BAD_REMOTE_PATH_ECOLOGY="./test/mock/ecologies/badremotepath.ecology"
TEST_ECOLOGY="./test/mock/ecologies/test.ecology"

class QuiltTest < Scope::TestCase
  context "class functions" do
    context "new" do
      should "throw an exception if Ecology is not initialized" do
        error = nil
        begin
          Quilt.new("quilt", FakeLogger.new)
        rescue Exception => e
          error = e
        end
        assert error
      end

      should "throw an exception if no local_path is specified" do
        Ecology.reset
        Ecology.read(BAD_ECOLOGY)
        error = nil
        begin
          Quilt.new("quilt", FakeLogger.new)
        rescue Exception => e
          error = e
        end
        assert error
      end

      should "create a quilt" do
        Ecology.reset
        Ecology.read(TEST_ECOLOGY)
        error = nil
        begin
          quilt = Quilt.new("quilt", FakeLogger.new)
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
      started = false
      count = 0
      while (!started && count < 10) # wait a max of 5 seconds for the server to start
        begin
          conn = Faraday.new(:url => "http://localhost:1337") do |faraday|
            faraday.adapter Faraday.default_adapter
          end
          res = conn.get('/health_check.txt')
          if (res.status.to_i == 200 && res.body != nil)
            started = true
          end
        rescue Exception => e
        end
        count += 1
        sleep(0.5)
      end
    end

    setup do
      Ecology.reset
      Ecology.read(TEST_ECOLOGY)
      @quilt = Quilt.new("quilt", FakeLogger.new)
      Ecology.reset
      Ecology.read(BAD_REMOTE_PATH_ECOLOGY)
      @bad_remote_path_quilt = Quilt.new("quilt", FakeLogger.new)
      Ecology.reset
      Ecology.read(BAD_REMOTE_ECOLOGY)
      @bad_remote_quilt = Quilt.new("quilt", FakeLogger.new)
      Ecology.reset
      Ecology.read(NO_REMOTE_ECOLOGY)
      @no_remote_quilt = Quilt.new("quilt", FakeLogger.new)
    end

    context "get_module_name" do
      should "return nil for bad file names" do
        name = @quilt.get_module_name(nil)
        assert_nil name
        name = @quilt.get_module_name("")
        assert_nil name
        assert_nil name
        name = @quilt.get_module_name("/")
        assert_nil name
        name = @quilt.get_module_name("./")
        assert_nil name
        name = @quilt.get_module_name("/hello/")
        assert_nil name
        name = @quilt.get_module_name("./hello/")
        assert_nil name
      end

      should "return a valid name for good file names" do
        name = @quilt.get_module_name("hello.js")
        assert_equal "hello.js", name
        name = @quilt.get_module_name("/hello.js")
        assert_equal "hello.js", name
        name = @quilt.get_module_name("./hello.js")
        assert_equal "hello.js", name
        name = @quilt.get_module_name("hi/hello.js")
        assert_equal "hello.js", name
        name = @quilt.get_module_name("/hi/hello.js")
        assert_equal "hello.js", name
        name = @quilt.get_module_name("./hi/hello.js")
        assert_equal "hello.js", name
      end
    end

    context "get_module" do
      should "return nil if the module does not exist" do
        mod = @quilt.get_module("randomjunk", [], :optional, "morerandomjunk")
        assert_nil mod
      end

      should "return the module if the module does exist" do
        mod = @quilt.get_module("optional/0.js", ["1.js"], :optional, File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        assert_equal ["1.js"], mod[:dependancies]
        assert_equal "0\n", mod[:module]
      end

      should "handle relative and non-relative filenames" do
        mod = @quilt.get_module("optional/0.js", [], :optional, File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        mod = @quilt.get_module("1.js", [], :optional, File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        mod = @quilt.get_module("./optional/0.js", [], :optional, File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        mod = @quilt.get_module("./1.js", [], :optional, File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
      end

      should "handle a single dependancy as a string" do
        mod = @quilt.get_module("optional/0.js", "1.js", :optional, File.dirname(__FILE__) + "/mock/good_project/1.0.0/")
        assert mod
        assert_equal ["1.js"], mod[:dependancies]
        assert_equal :optional, mod[:position]
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
        assert_equal "h\n", version[:default][:header]
        assert_equal "c\n", version[:default][:common]
        expected = {
          "c2.js" => { :position => :before_common, :dependancies=> [], :module=>"c2\n" },
          "0.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "0\n" },
          "1.js" => { :position => :optional, :dependancies => [ "7.js", "9.js" ], :module => "1\n" },
          "2.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "2\n" },
          "3.js" => { :position => :optional, :dependancies => [], :module => "3\n" },
          "4.js" => { :position => :optional, :dependancies => [], :module => "4\n" },
          "5.js" => { :position => :before_header, :dependancies => [], :module => "5\n" },
          "6.js" => { :position => :after_header, :dependancies => [], :module => "6\n" },
          "7.js" => { :position => :optional, :dependancies => [], :module => "7\n" },
          "8.js" => { :position => :optional, :dependancies => [], :module => "8\n" },
          "9.js" => { :position => :optional, :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:default][:optional]
        assert_equal version[:default][:footer], "f1.0.0\n"
      end

      should "gracefully handle bad manifest entries" do
        version = @quilt.load_version(File.dirname(__FILE__) + "/mock/bad_project", "1.0.0")
        assert version
        assert_equal '', version[:default][:header]
        assert_equal "c\n", version[:default][:common]
        expected = {
          "0.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "0\n" },
          "1.js" => { :position => :optional, :dependancies => [ "7.js", "9.js" ], :module => "1\n" },
          "2.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "2\n" },
          "3.js" => { :position => :optional, :dependancies => [], :module => "3\n" },
          "4.js" => { :position => :optional, :dependancies => [], :module => "4\n" },
          "5.js" => { :position => :optional, :dependancies => [], :module => "5\n" },
          "6.js" => { :position => :optional, :dependancies => [], :module => "6\n" },
          "7.js" => { :position => :optional, :dependancies => [], :module => "7\n" },
          "8.js" => { :position => :optional, :dependancies => [], :module => "8\n" },
          "9.js" => { :position => :optional, :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:default][:optional]
        assert_equal '', version[:default][:footer]
      end
    end

    context "resolve_dependancies" do
      setup do
        @version = {
          :default => {
            :header => "h\n",
            :common => "c\n",
            :optional => {
              "0.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "0\n" },
              "1.js" => { :position => :optional, :dependancies => [ "7.js", "9.js" ], :module => "1\n" },
              "2.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "2\n" },
              "3.js" => { :position => :optional, :dependancies => [], :module => "3\n" },
              "4.js" => { :position => :optional, :dependancies => [], :module => "4\n" },
              "5.js" => { :position => :optional, :dependancies => [ "6.js" ], :module => "5\n" },
              "6.js" => { :position => :optional, :dependancies => [ "5.js" ], :module => "6\n" },
              "7.js" => { :position => :optional, :dependancies => [], :module => "7\n" },
              "8.js" => { :position => :optional, :dependancies => [ "9.js" ], :module => "8\n" },
              "9.js" => { :position => :optional, :dependancies => [], :module => "9\n" }
            }
          }
        }
      end

      should "return an empty string for no modules" do
        out = @quilt.resolve_dependancies(:optional, nil, @version[:default]);
        assert_equal '', out
        out = @quilt.resolve_dependancies(:optional, [], @version[:default]);
        assert_equal '', out
        out = @quilt.resolve_dependancies(:optional, { "yo" => "sup" }, @version[:default]);
        assert_equal '', out
        out = @quilt.resolve_dependancies(:optional, "hi", @version[:default]);
        assert_equal '', out
      end

      should "resolve dependancies" do
        out = @quilt.resolve_dependancies(:optional, [ "0.js", "1.js", "2.js" ], @version[:default]);
        assert_equal "9\n8\n0\n7\n1\n2\n", out
      end

      should "gracefully handle circular dependancies" do
        out = @quilt.resolve_dependancies(:optional, [ "5.js" ], @version[:default]);
        assert_equal "6\n5\n", out
      end

      should "gracefully handle non-existant modules" do
        out = @quilt.resolve_dependancies(:optional, [ "5.js", "oogabooga" ], @version[:default]);
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
        assert_equal "h\n", version[:default][:header]
        assert_equal "c\n", version[:default][:common]
        expected = {
          "c2.js" => { :position => :before_common, :dependancies=> [], :module=>"c2\n" },
          "0.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "0\n" },
          "1.js" => { :position => :optional, :dependancies => [ "7.js", "9.js" ], :module => "1\n" },
          "2.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "2\n" },
          "3.js" => { :position => :optional, :dependancies => [], :module => "3\n" },
          "4.js" => { :position => :optional, :dependancies => [], :module => "4\n" },
          "5.js" => { :position => :before_header, :dependancies => [], :module => "5\n" },
          "6.js" => { :position => :after_header, :dependancies => [], :module => "6\n" },
          "7.js" => { :position => :optional, :dependancies => [], :module => "7\n" },
          "8.js" => { :position => :optional, :dependancies => [], :module => "8\n" },
          "9.js" => { :position => :optional, :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:default][:optional]
        assert_equal "f1.0.0\n", version[:default][:footer]
      end

      should "fetch remote version if it does not exist locally" do
        version = @quilt.get_version('2.0.0')
        assert version
        assert_equal "h\n", version[:default][:header]
        assert_equal "c\n", version[:default][:common]
        expected = {
          "0.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "0\n" },
          "1.js" => { :position => :optional, :dependancies => [ "7.js", "9.js" ], :module => "1\n" },
          "2.js" => { :position => :optional, :dependancies => [ "8.js" ], :module => "2\n" },
          "3.js" => { :position => :optional, :dependancies => [], :module => "3\n" },
          "4.js" => { :position => :optional, :dependancies => [], :module => "4\n" },
          "5.js" => { :position => :optional, :dependancies => [], :module => "5\n" },
          "6.js" => { :position => :optional, :dependancies => [], :module => "6\n" },
          "7.js" => { :position => :optional, :dependancies => [], :module => "7\n" },
          "8.js" => { :position => :optional, :dependancies => [], :module => "8\n" },
          "9.js" => { :position => :optional, :dependancies => [], :module => "9\n" }
        }
        assert_equal expected, version[:default][:optional]
        assert_equal "f2.0.0\n", version[:default][:footer]
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
      should "return nil for a non-existant version when no remote information exists" do
        assert_equal nil, @no_remote_quilt.stitch(['0.js'], '2.0.0')
      end

      should "properly stitch for an existing version with selector array" do
        assert_equal "h\nc2\nc\n8\n0\nf1.0.0\n", @no_remote_quilt.stitch(['0.js'], '1.0.0')
      end

      should "properly stitch valid modules with selector array and invalid modules" do
        assert_equal "h\nc2\nc\n8\n0\nf1.0.0\n", @no_remote_quilt.stitch(['invalid.js', '0.js'], '1.0.0')
      end

      should "properly stitch for an existing version with selector function" do
        assert_equal "5\nh\n6\nc2\nc\n8\n0\n7\n9\n1\n2\n3\n4\nf1.0.0\n", @no_remote_quilt.stitch(Proc.new do |m|
          true
        end, '1.0.0')
      end

      should "properly stitch for remote version with selector array" do
        assert_equal "h\nc\n8\n0\nf2.0.0\n", @quilt.stitch(['0.js'], '2.0.0')
        `rm -rf #{File.join(File.dirname(__FILE__), "mock", "good_project", "2.0.0")}`
      end

      should "properly stitch for remote version with selector function" do
        assert_equal "h\nc\n8\n0\n7\n9\n1\n2\n3\n4\n5\n6\nf2.0.0\n", @quilt.stitch(Proc.new do |m|
          true
        end, '2.0.0')
        `rm -rf #{File.join(File.dirname(__FILE__), "mock", "good_project", "2.0.0")}`
      end

      should "properly stitch for debug version" do
        assert_equal "h\nc\n8\n0\nf1.0.0-debug\n", @quilt.stitch(['0.js'], 'hasdebug', :debug)
        `rm -rf #{File.join(File.dirname(__FILE__), "mock", "good_project", "hasdebug")}`
      end

      should "fallback to non-debug if debug does not exist" do
        assert_equal "h\nc2\nc\n8\n0\nf1.0.0\n", @no_remote_quilt.stitch(['0.js'], '1.0.0', :debug)
      end

      should "add dynamic module if it exists" do
        assert_equal "[bh]h\n[ah][bc]c2\nc\n[ac][bo]8\n0\n[ao][bf]f1.0.0\n[af]",
          @no_remote_quilt.stitch(['0.js'], '1.0.0', :debug, {
            :before_header => '[bh]',
            :after_header => '[ah]',
            :before_common => '[bc]',
            :after_common => '[ac]',
            :before_optional => '[bo]',
            :after_optional => '[ao]',
            :before_footer => '[bf]',
            :after_footer => '[af]'
        })
      end
      should "add modules to the correct position" do
        assert_equal "[bh]5\nh\n6\n[bc]c2\nc\n[ac][bo]8\n0\n[ao][bf]f1.0.0\n[af]",
          @no_remote_quilt.stitch(['0.js', '5.js'], '1.0.0', :debug, {
            :before_header => '[bh]',
            :after_header => [ '6.js' ],
            :before_common => '[bc]',
            :after_common => '[ac]',
            :before_optional => '[bo]',
            :after_optional => '[ao]',
            :before_footer => '[bf]',
            :after_footer => '[af]'
        })
      end
      should "properly stitch dev version" do
        assert_equal "DEVh\nc2\nc\n8\n0\nf1.0.0\n", @quilt.stitch(['0.js'], 'dev')
      end
    end

    context "health" do
      should "return false for bad config" do
        healthy, problem = @bad_remote_quilt.health
        assert !healthy
        healthy, problem = @bad_remote_path_quilt.health
        assert !healthy
      end

      should "return true for no remote config" do
        healthy, problem = @no_remote_quilt.health
        assert healthy
      end

      should "return true for good config" do
        healthy, problem = @quilt.health
        assert healthy
      end
    end

    context "status" do
      should "return status" do
        status = @quilt.status
        assert status
      end
    end
  end
end
