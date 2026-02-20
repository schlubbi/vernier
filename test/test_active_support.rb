# frozen_string_literal: true

require "test_helper"
require "active_support"

class TestActiveSupport < Minitest::Test
  def test_subscribers_removed
    refute ActiveSupport::Notifications.notifier.listening?("sql.active_record")

    Vernier.trace(hooks: [:activesupport]) do
      assert ActiveSupport::Notifications.notifier.listening?("sql.active_record")
    end

    refute ActiveSupport::Notifications.notifier.listening?("sql.active_record")
  end

  def test_instrument
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("foo.bar") {}
    end

    markers = result.main_thread[:markers].select{|x| x[1] == "foo.bar" }
    assert_equal 1, markers.size

    marker = markers[0]
    assert_equal Thread.current.object_id, marker[0]
    assert_equal Vernier::Marker::Phase::INTERVAL, marker[4]
    assert_equal({ type: "foo.bar" }, marker[5])
  end

  def test_instrument_without_block
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("foo.bar")
    end

    markers = result.main_thread[:markers].select{|x| x[1] == "foo.bar" }
    assert_equal 1, markers.size

    marker = markers[0]
    assert_equal Thread.current.object_id, marker[0]
    assert_equal Vernier::Marker::Phase::INTERVAL, marker[4]
    assert_equal({ type: "foo.bar" }, marker[5])
  end

  def test_instrument_publish
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.publish("foo.bar")
    end

    markers = result.main_thread[:markers].select{|x| x[1] == "foo.bar" }
    assert_equal 0, markers.size
  end

  def test_sql_markers_have_cause_stack
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1", name: "Test Load") {}
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "sql.active_record" }
    assert_equal 1, markers.size

    marker = markers[0]
    data = marker[5]
    assert_equal "sql.active_record", data[:type]
    assert_equal "SELECT 1", data[:sql]
    assert_equal "Test Load", data[:name]

    # The cause stack should be present and point into the stack table
    assert data.key?(:cause), "sql.active_record marker should have :cause"
    assert data[:cause].key?(:stack), "cause should have :stack"
    stack_idx = data[:cause][:stack]
    assert_kind_of Integer, stack_idx
    assert stack_idx >= 0, "stack index should be non-negative"
  end

  def test_sql_cause_stack_contains_caller
    # Define a method whose name we can search for in the captured stack
    result = Vernier.trace(hooks: [:activesupport]) do
      _sql_cause_test_caller_method
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "sql.active_record" }
    assert_equal 1, markers.size

    stack_idx = markers[0][5].dig(:cause, :stack)
    assert stack_idx, "should have cause.stack"

    # Walk the stack and look for our caller method
    st = result.stack_table
    found_caller = false
    idx = stack_idx
    100.times do
      break if idx.nil? || idx < 0
      frame_idx = st.stack_frame_idx(idx)
      func_idx = st.frame_func_idx(frame_idx)
      name = st.func_name(func_idx)
      if name&.include?("_sql_cause_test_caller_method")
        found_caller = true
        break
      end
      idx = st.stack_parent_idx(idx)
    end

    assert found_caller, "cause.stack should contain the calling method '_sql_cause_test_caller_method'"
  end

  def test_non_sql_markers_have_no_cause_stack
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("cache_read.active_support", key: "test") {}
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "cache_read.active_support" }
    assert_equal 1, markers.size
    refute markers[0][5].key?(:cause), "non-SQL markers should not have :cause"
  end

  private

  def _sql_cause_test_caller_method
    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1", name: "Caller Test") {}
  end

end
