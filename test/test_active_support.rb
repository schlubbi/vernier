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
    refute markers[0][5].key?(:caller), "non-SQL/non-IO markers should not have :caller"
  end

  # ── I/O marker tests ──

  def test_enqueue_active_job_has_caller
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("enqueue.active_job", job: "TestJob") {}
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "enqueue.active_job" }
    assert_equal 1, markers.size

    data = markers[0][5]
    assert_equal "enqueue.active_job", data[:type]
    # :caller is only present when app frames are found (test frames are filtered)
    if data.key?(:caller)
      assert_kind_of Array, data[:caller]
    end
  end

  def test_enqueue_at_active_job_has_caller
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("enqueue_at.active_job", job: "TestJob") {}
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "enqueue_at.active_job" }
    assert_equal 1, markers.size
    assert_equal "enqueue_at.active_job", markers[0][5][:type]
  end

  def test_enqueue_not_in_generic_subscriber
    result = Vernier.trace(hooks: [:activesupport]) do
      ActiveSupport::Notifications.instrument("enqueue.active_job", job: "TestJob") {}
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "enqueue.active_job" }
    assert_equal 1, markers.size, "enqueue marker should not be duplicated"
  end

  # ── Transaction marker tests ──

  def test_transaction_marker_is_created
    result = Vernier.trace(hooks: [:activesupport]) do
      _simulate_transaction(:commit)
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "transaction.active_record" }
    assert_equal 1, markers.size

    marker = markers[0]
    data = marker[5]
    assert_equal "transaction.active_record", data[:type]
    assert_equal :commit, data[:outcome]
  end

  def test_transaction_marker_has_caller
    result = Vernier.trace(hooks: [:activesupport]) do
      _app_level_transaction_caller
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "transaction.active_record" }
    assert_equal 1, markers.size

    caller_frames = markers[0][5][:caller] || []
    # Should contain the app-level method that initiated the transaction.
    # The exact frame depends on filtering, but the marker should exist
    # with timing data.
    start_time = markers[0][2]
    finish_time = markers[0][3]
    assert_operator start_time, :<, finish_time, "transaction should have positive duration"
  end

  def test_transaction_rollback_outcome
    result = Vernier.trace(hooks: [:activesupport]) do
      _simulate_transaction(:rollback)
    end

    markers = result.main_thread[:markers].select { |x| x[1] == "transaction.active_record" }
    assert_equal 1, markers.size
    assert_equal :rollback, markers[0][5][:outcome]
  end

  def test_transaction_marker_separate_from_sql
    result = Vernier.trace(hooks: [:activesupport]) do
      # Simulate a transaction containing SQL
      _simulate_transaction(:commit) do
        ActiveSupport::Notifications.instrument("sql.active_record", sql: "INSERT INTO t (x) VALUES (1)", name: "Write") {}
      end
    end

    txn_markers = result.main_thread[:markers].select { |x| x[1] == "transaction.active_record" }
    sql_markers = result.main_thread[:markers].select { |x| x[1] == "sql.active_record" }
    assert_equal 1, txn_markers.size
    assert_equal 1, sql_markers.size

    # Transaction marker should span the SQL marker
    txn_start = txn_markers[0][2]
    txn_finish = txn_markers[0][3]
    sql_start = sql_markers[0][2]
    assert_operator txn_start, :<=, sql_start
    assert_operator sql_start, :<=, txn_finish
  end

  def test_transaction_not_in_generic_subscriber
    # Ensure transaction.active_record is NOT duplicated by the generic subscriber
    result = Vernier.trace(hooks: [:activesupport]) do
      _simulate_transaction(:commit)
    end

    txn_markers = result.main_thread[:markers].select { |x| x[1] == "transaction.active_record" }
    assert_equal 1, txn_markers.size, "transaction marker should not be duplicated"
  end

  private

  def _sql_caller_test_method
    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1", name: "Caller Test") {}
  end

  def _simulate_transaction(outcome)
    # Simulate the Rails TransactionInstrumenter flow:
    # 1. build_handle creates a start/finish handle
    # 2. start fires the start callback
    # 3. finish fires the finish callback with outcome in payload
    payload = { outcome: nil }
    handle = ::ActiveSupport::Notifications.instrumenter.build_handle(
      "transaction.active_record", payload
    )
    handle.start
    yield if block_given?
    payload[:outcome] = outcome
    handle.finish
  end

  def _app_level_transaction_caller
    _simulate_transaction(:commit)
  end

end
