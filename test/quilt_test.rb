#!/usr/bin/env ruby

require "minitest/autorun"
require "scope"
require "./lib/quilt.rb"

class QuiltTest < Scope::TestCase
  context "instance functions" do
    setup do
      @quilt = Quilt.new({})
    end

    context "get_module_name" do
      should "return null for bad file names" do
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
      should "return null if the module does not exist" do
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
      should "return null if there is no manifest" do
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
  end
end
