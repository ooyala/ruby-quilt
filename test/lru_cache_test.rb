#!/usr/bin/env ruby

require "./test/test_helper"
require "./lib/lru_cache"

class LRUCacheTest < Scope::TestCase
  context "instance functions" do
    setup do
      @cache = LRUCache.new(2)
    end
    context "set and get" do
      should "set and get the value" do
        @cache.set(:a, 'a')
        @cache[:b] = 'b'
        assert_equal 'a', @cache[:a]
        assert_equal 'b', @cache.get(:b)
      end

      should "drop last value" do
        @cache.set(:a, 'a')
        @cache[:b] = 'b'
        @cache.set(:c, 'c')
        assert_nil @cache[:a]
        assert_equal 'b', @cache.get(:b)
        assert_equal 'c', @cache[:c]
      end

      should "keep key if fetched" do
        @cache.set(:a, 'a')
        @cache[:b] = 'b'
        @cache[:a]
        @cache.set(:c, 'c')
        assert_nil @cache[:b]
        assert_equal 'a', @cache.get(:a)
        assert_equal 'c', @cache[:c]
      end

      should "keep key if set" do
        @cache.set(:a, 'a')
        @cache[:b] = 'b'
        @cache[:a] = 'a'
        @cache.set(:c, 'c')
        assert_nil @cache[:b]
        assert_equal 'a', @cache.get(:a)
        assert_equal 'c', @cache[:c]
      end
    end

    context "delete" do
      should "delete" do
        @cache.set(:a, 'a')
        @cache.set(:b, 'b')
        @cache.delete(:b)
        @cache.set(:c, 'c')
        assert_equal 'a', @cache.get(:a)
        assert_nil @cache.get(:b)
        assert_equal 'c', @cache.get(:c)
      end
    end
  end
end
