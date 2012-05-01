class LRUCache
  def initialize(size = 10)
    @size = size
    @store = {}
    @lru = []
  end

  def set(key, value = nil)
    @store[key] = value
    set_lru(key)
    @store.delete(@lru.pop) if @lru.size > @size
    value
  end

  def get(key)
    return nil unless @store.key?(key)
    set_lru(key)
    @store[key]
  end

  def [](key)
    get(key)
  end

  def []=(key, value)
    set(key, value)
  end

  def keys
    @store.keys
  end

  def delete(key)
    @store.delete(key)
    @lru.delete(key)
  end

  private
  def set_lru(key)
    @lru.unshift(@lru.delete(key) || key)
  end
end
