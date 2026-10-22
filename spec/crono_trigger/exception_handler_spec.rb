require "spec_helper"

RSpec.describe CronoTrigger::ExceptionHandler do
  let(:record) { Notification.new(name: "notification") }
  let(:error) { RuntimeError.new("error") }

  around do |example|
    original = CronoTrigger.config.error_handlers
    example.run
  ensure
    CronoTrigger.config.error_handlers = original
  end

  describe ".handle_exception" do
    it "calls the following handlers even if a handler raises an error" do
      called = []
      CronoTrigger.config.error_handlers = [
        proc { |ex| called << [:first, ex] },
        proc { raise "handler error" },
        "not callable",
        proc { |ex, r| called << [:last, ex, r] },
      ]

      described_class.handle_exception(record, error)

      expect(called).to eq([[:first, error], [:last, error, record]])
    end
  end
end

RSpec.describe CronoTrigger::GlobalExceptionHandler do
  let(:error) { RuntimeError.new("error") }

  around do |example|
    original = CronoTrigger.config.global_error_handlers
    example.run
  ensure
    CronoTrigger.config.global_error_handlers = original
  end

  describe ".handle_global_exception" do
    it "calls the following handlers even if a handler raises an error" do
      called = []
      CronoTrigger.config.global_error_handlers = [
        proc { |ex| called << [:first, ex] },
        proc { raise "handler error" },
        "not callable",
        proc { |ex| called << [:last, ex] },
      ]

      described_class.handle_global_exception(error)

      expect(called).to eq([[:first, error], [:last, error]])
    end
  end
end
