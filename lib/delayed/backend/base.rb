module Delayed
  module Backend
    class DeserializationError < StandardError
    end

    module Base
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        # Add a job to the queue
        def enqueue(*args)
          options = {
            :priority => Delayed::Worker.default_priority,
            :context => Delayed::Worker.context
          }

          if args.size == 1 && args.first.is_a?(Hash)
            options.merge!(args.first)
          else
            options[:payload_object]  = args.shift
            options[:priority]        = args.first || options[:priority]
            options[:run_at]          = args[1]
            options[:context]         = args[2] || options[:context]
          end

          unless options[:payload_object].respond_to?(:perform)
            raise ArgumentError, 'Cannot enqueue items which do not respond to perform'
          end

          self.create(options).tap do |job|
            job.hook(:enqueue)
          end
        end

        # Hook method that is called before a new worker is forked
        def before_fork
        end

        # Hook method that is called after a new worker is forked
        def after_fork
        end

        def work_off(num = 100)
          warn "[DEPRECATION] `Delayed::Job.work_off` is deprecated. Use `Delayed::Worker.new.work_off instead."
          Delayed::Worker.new.work_off(num)
        end
      end

      ParseObjectFromYaml = /\!ruby\/\w+\:([^\s]+)/

      def failed?
        failed_at
      end
      alias_method :failed, :failed?

      def name
        @name ||= begin
          payload = payload_object
          payload.respond_to?(:display_name) ? payload.display_name : payload.class.name
        end
      end

      def payload_object=(object)
        @payload_object = object
        self.handler = object.to_yaml
      end

      def payload_object
        @payload_object ||= YAML.load(self.handler)
      rescue TypeError, LoadError, NameError => e
          raise DeserializationError,
            "Job failed to load: #{e.message}. Try to manually require the required file. Handler: #{handler.inspect}"
      end

      def invoke_job
        hook :before
        payload_object.perform
        hook :success
      rescue Exception => e
        hook :error, e
        raise e
      ensure
        hook :after
      end

      # Unlock this job (note: not saved to DB)
      def unlock
        self.locked_at    = nil
        self.locked_by    = nil
      end

      def hook(name, *args)
        if payload_object.respond_to?(name)
          method = payload_object.method(name)
          method.arity == 0 ? method.call : method.call(self, *args)
        end
      end

      def reschedule_at
        payload_object.respond_to?(:reschedule_at) ? 
          payload_object.reschedule_at(self.class.db_time_now, attempts) :
          self.class.db_time_now + (attempts ** 4) + 5
      end
      
    protected

      def set_default_run_at
        self.run_at ||= self.class.db_time_now
      end
    end
  end
end
