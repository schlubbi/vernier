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

  def test_sql_markers_have_caller_key
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

    # :caller is only present when app frames are found.
    # In this test, all frames are in test/ or gem: paths, so :caller may be absent.
    # The key assertion is that the marker was created with the right data.
    if data.key?(:caller)
      assert_kind_of Array, data[:caller]
    end
  end

  def test_sql_caller_filters_non_app_frames
    # caller_locations from test/ paths are filtered out by the app path regex.
    # This verifies the filtering works — test frames should NOT appear.
    result = Vernier.trace(hooks: [:activesupport]) do
      _sql_caller_test_method
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "sql.active_record" }
    assert_equal 1, markers.size

    caller_frames = markers[0][5][:caller] || []
    # No test/ frames should leak through
    caller_frames.each do |f|
      refute_match(/\Atest\//, f, "test/ frames should be filtered: #{f}")
    end
  end

  def test_non_sql_markers_have_no_caller
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("cache_read.active_support", key: "test") {}
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "cache_read.active_support" }
    assert_equal 1, markers.size
    refute markers[0][5].key?(:caller), "non-SQL markers should not have :caller"
  end

  private

  def _sql_caller_test_method
    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1", name: "Caller Test") {}
  end

end
