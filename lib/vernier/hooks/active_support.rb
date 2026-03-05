# frozen_string_literal: true

module Vernier
  module Hooks
    class ActiveSupport
      FIREFOX_MARKER_SCHEMA = Ractor.make_shareable([
        {
          name: "sql.active_record",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: "{marker.data.name}",
          chartLabel: "{marker.data.name}",
          tableLabel: "{marker.data.sql}",
          data: [
            { key: "sql", format: "string", searchable: true },
            { key: "name", format: "string", searchable: true },
            { key: "type_casted_binds", label: "binds", format: "string"
            }
          ]
        },
        {
          name: "instantiation.active_record",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: "{marker.data.record_count} × {marker.data.class_name}",
          chartLabel: "{marker.data.record_count} × {marker.data.class_name}",
          tableLabel: "Instantiate {marker.data.record_count} × {marker.data.class_name}",
          data: [
            { key: "record_count", format: "integer" },
            { key: "class_name", format: "string" }
          ]
        },
        {
          name: "start_processing.action_controller",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.method} {marker.data.controller}#{marker.data.action}',
          chartLabel:   '{marker.data.method} {marker.data.controller}#{marker.data.action}',
          tableLabel:   '{marker.data.method} {marker.data.controller}#{marker.data.action}',
          data: [
            { key: "controller", format: "string" },
            { key: "action", format: "string" },
            { key: "status", format: "integer" },
            { key: "path", format: "string" },
            { key: "method", format: "string" },
            { key: "format", format: "string" }
          ]
        },
        {
          name: "process_action.action_controller",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.method} {marker.data.controller}#{marker.data.action}',
          chartLabel:   '{marker.data.method} {marker.data.controller}#{marker.data.action}',
          tableLabel:   '{marker.data.method} {marker.data.controller}#{marker.data.action}',
          data: [
            { key: "controller", format: "string" },
            { key: "action", format: "string" },
            { key: "status", format: "integer" },
            { key: "path", format: "string" },
            { key: "method", format: "string" },
            { key: "format", format: "string" }
          ]
        },
        {
          name: "cache_read.active_support",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.super_operation} {marker.data.key}',
          chartLabel:   '{marker.data.super_operation} {marker.data.key}',
          tableLabel:   '{marker.data.super_operation} {marker.data.key}',
          data: [
            { key: "key", format: "string" },
            { key: "store", format: "string" },
            { key: "hit", format: "string" },
            { key: "super_operation", format: "string" }
          ]
        },
        {
          name: "cache_read_multi.active_support",
          display: [ "marker-chart", "marker-table" ],
          data: [
            { key: "key", format: "string" },
            { key: "store", format: "string" },
            { key: "hit", format: "string" },
            { key: "super_operation", format: "string" }
          ]
        },
        {
          name: "cache_fetch_hit.active_support",
          tooltipLabel: 'HIT {marker.data.key}',
          chartLabel:   'HIT {marker.data.key}',
          tableLabel:   'HIT {marker.data.key}',
          display: [ "marker-chart", "marker-table" ],
          data: [
            { key: "key", format: "string" },
            { key: "store", format: "string" }
          ]
        },
        {
          name: "render_template.action_view",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.identifier}',
          chartLabel:   '{marker.data.identifier}',
          tableLabel:   '{marker.data.identifier}',
          data: [
            { key: "identifier", format: "string" }
          ]
        },
        {
          name: "render_layout.action_view",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.identifier}',
          chartLabel:   '{marker.data.identifier}',
          tableLabel:   '{marker.data.identifier}',
          data: [
            { key: "identifier", format: "string" }
          ]
        },
        {
          name: "render_partial.action_view",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.identifier}',
          chartLabel:   '{marker.data.identifier}',
          tableLabel:   '{marker.data.identifier}',
          data: [
            { key: "identifier", format: "string" }
          ]
        },
        {
          name: "render_collection.action_view",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.identifier}',
          chartLabel:   '{marker.data.identifier}',
          tableLabel:   '{marker.data.identifier}',
          data: [
            { key: "identifier", format: "string" },
            { key: "count", format: "integer" }
          ]
        },
        {
          name: "load_config_initializer.railties",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: '{marker.data.initializer}',
          chartLabel:   '{marker.data.initializer}',
          tableLabel:   '{marker.data.initializer}',
          data: [
            { key: "initializer", format: "string" }
          ]
        },
        {
          name: "transaction.active_record",
          display: [ "marker-chart", "marker-table" ],
          tooltipLabel: "transaction ({marker.data.outcome})",
          chartLabel:   "transaction ({marker.data.outcome})",
          tableLabel:   "Transaction ({marker.data.outcome})",
          data: [
            { key: "outcome", format: "string", searchable: true }
          ]
        }
      ])

      SERIALIZED_KEYS = FIREFOX_MARKER_SCHEMA.map do |format|
        [
          format[:name],
          format[:data].map { _1[:key].to_sym }.freeze
        ]
      end.to_h.freeze

      def initialize(collector)
        @collector = collector
      end

      # Paths to exclude from caller frames — gem/vendor/framework internals.
      # Everything else is kept. The consumer (e.g. querymap) applies further
      # app-vs-infrastructure filtering.
      EXCLUDED_PATH_RE = Regexp.union(
        /\bgem:/,                       # bundled gems (gem:activerecord-8.0:...)
        /\bvendor\//,                   # vendored gems
        /\/<internal:/,                 # Ruby internals
        /\A<internal:/,
        /\A\(eval/,                     # eval'd code
        /\A<cfunc>/,                    # C functions
        /\bactive_support\/notifications/,  # AS::Notifications dispatch
        /\bactive_support\/subscriber/,
        /\bactive_support\/callbacks/,
        /\bactive_record\/connection_adapters/,  # AR connection/transaction internals
        /\bactive_record\/transactions/,
        /\bvernier\//,                  # Vernier itself
      ).freeze

      def enable
        require "active_support"
        collector = @collector

        # Build an evented subscriber that captures caller_locations at `start`
        # time (before the instrumented block executes). This gives accurate
        # application-level backtraces for both SQL queries and transactions.
        build_caller_subscriber = ->(collector_ref) do
          sub = Object.new
          sub.instance_variable_set(:@collector, collector_ref)
          sub.instance_variable_set(:@pending, {})
          sub.define_singleton_method(:start) do |name, id, _payload|
            locs = Kernel.caller_locations(2, 50)
            caller_frames = []
            locs&.each do |loc|
              path = loc.absolute_path || loc.path || ""
              next if EXCLUDED_PATH_RE.match?(path)
              rel = path
              caller_frames << "#{loc.label}  [#{rel}:#{loc.lineno}]"
              break if caller_frames.size >= 8
            end
            @pending[id] = [
              Process.clock_gettime(Process::CLOCK_MONOTONIC),
              caller_frames
            ]
          end
          sub.define_singleton_method(:finish) do |name, id, payload|
            start_time, caller_frames = @pending.delete(id)
            return unless start_time
            finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            data = { type: name }
            if keys = SERIALIZED_KEYS[name]
              keys.each { |key| data[key] = payload[key] }
            end
            data[:caller] = caller_frames if caller_frames && !caller_frames.empty?
            @collector.add_marker(
              name: name,
              start: (start_time * 1_000_000_000.0).to_i,
              finish: (finish_time * 1_000_000_000.0).to_i,
              data: data
            )
          end
          sub
        end

        # sql.active_record: captures caller stack showing who issued the query
        @sql_subscription = ::ActiveSupport::Notifications.subscribe(
          "sql.active_record", build_caller_subscriber.call(collector)
        )

        # transaction.active_record: captures caller stack showing who opened
        # the transaction. The stack is captured at materialization time (first
        # SQL in the transaction), which still has the transaction do block on
        # the call stack.
        @txn_subscription = ::ActiveSupport::Notifications.subscribe(
          "transaction.active_record", build_caller_subscriber.call(collector)
        )

        # I/O events inside transactions: capture caller stacks so the analyzer
        # can attribute enqueue/RPC calls to the code that initiated them,
        # rather than conflating with the SQL caller stack.
        io_events = %w[
          enqueue.active_job
          enqueue_at.active_job
        ]
        @io_subscriptions = io_events.map do |event|
          ::ActiveSupport::Notifications.subscribe(event, build_caller_subscriber.call(collector))
        end

        # Everything else: block subscriber (no stack capture needed)
        caller_captured = (["sql.active_record", "transaction.active_record"] + io_events).to_h { |e| [e, true] }
        @subscription = ::ActiveSupport::Notifications.monotonic_subscribe(/\A[^!]/) do |name, start, finish, id, payload|
          next if caller_captured[name]
          unless Float === start && Float === finish
            next
          end
          data = { type: name }
          if keys = SERIALIZED_KEYS[name]
            keys.each { |key| data[key] = payload[key] }
          end
          collector.add_marker(
            name: name,
            start: (start * 1_000_000_000.0).to_i,
            finish: (finish * 1_000_000_000.0).to_i,
            data: data
          )
        end
      end

      def disable
        ::ActiveSupport::Notifications.unsubscribe(@subscription)
        ::ActiveSupport::Notifications.unsubscribe(@sql_subscription)
        ::ActiveSupport::Notifications.unsubscribe(@txn_subscription)
        @io_subscriptions&.each { |s| ::ActiveSupport::Notifications.unsubscribe(s) }
        @subscription = nil
        @sql_subscription = nil
        @txn_subscription = nil
      end

      def firefox_marker_schema
        FIREFOX_MARKER_SCHEMA
      end
    end
  end
end
