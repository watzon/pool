# Generic pool.
#
# It will create N instances that can be checkin then checkout. Trying to
# checkout an instance from an empty pool will block until another coroutine
# checkin an instance back, up until a timeout is reached.
class Pool(T)
  # TODO: shutdown (close all connections)

  # Returns how many instances can be started at maximum capacity.
  getter capacity : Int32

  # Returns how much time to wait for an instance to be available before raising
  # a Timeout exception.
  getter timeout : Int32 | Float64

  # Returns how many instances are available for checkout.
  getter pending : Int32

  # Returns how many instances have been started.
  getter size : Int32

  private getter pool

  @r : IO::FileDescriptor
  @w : IO::FileDescriptor

  def initialize(@capacity : Int32 = 5, initial : Int32 = 0, @timeout = 5, &block : -> T)
    @r, @w = IO.pipe(read_blocking: false, write_blocking: false)
    @r.read_timeout = @timeout

    @buffer = Slice(UInt8).new(1)
    @size = 0
    @pending = @capacity
    @pool = [] of T
    @block = block
    @mutex = Mutex.new

    initial.times do
      start_one
    end
  end

  def start_all
    until size >= @capacity
      start_one
    end
  end

  # Checkout an instance from the pool. Blocks until an instance is available if
  # all instances are busy. Eventually raises an `IO::Timeout` error.
  def checkout : T
    loop do
      if pool.empty? && size < @capacity
        start_one
      end

      @r.read(@buffer)

      if obj = pool.shift?
        @pending -= 1
        return obj
      end
    end
  end

  # Checkin an instance back into the pool.
  def checkin(connection : T)
    unless pool.includes?(connection)
      pool << connection
      @pending += 1
      @w.write(@buffer)
    end
  end

  # Checkout an item and pass it to the block, then check it back
  # in when the block exits.
  def use(&block)
    item = checkout
    result = yield item
    checkin(item)
    result
  end

  private def start_one
    @mutex.synchronize do
      @size += 1
      pool << @block.call
      @w.write(@buffer)
    end
  end
end
