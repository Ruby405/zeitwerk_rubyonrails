module Zeitwerk
  # Centralizes the logic for the trace point used to detect the creation of
  # explicit namespaces, needed to descend into matching subdirectories right
  # after the constant has been defined.
  #
  # The implementation assumes an explicit namespace is managed by one loader.
  # Loaders that reopen namespaces owned by other projects are responsible for
  # loading their constant before setup. This is documented.
  module ExplicitNamespace # :nodoc: all
    class << self
      # Maps constant paths that correspond to explicit namespaces according to
      # the file system, to the loader responsible for them.
      #
      # @private
      # @return [{String => Zeitwerk::Loader}]
      attr_reader :cpaths

      # @private
      # @return [Mutex]
      attr_reader :mutex

      # @private
      # @return [TracePoint]
      attr_reader :tracer

      # Asserts `cpath` corresponds to an explicit namespace for which `loader`
      # is responsible.
      #
      # @private
      # @param cpath [String]
      # @param loader [Zeitwerk::Loader]
      # @return [void]
      def register(cpath, loader)
        mutex.synchronize do
          cpaths[cpath] = loader
          # We check enabled? because, looking at the C source code, enabling an
          # enabled tracer does not seem to be a simple no-op.
          tracer.enable unless tracer.enabled?
        end
      end

      # @private
      # @param loader [Zeitwerk::Loader]
      # @return [void]
      def unregister(loader)
        cpaths.delete_if { |_cpath, l| l == loader }
        disable_tracer_if_unneeded
      end

      def disable_tracer_if_unneeded
        mutex.synchronize do
          tracer.disable if cpaths.empty?
        end
      end
    end

    @cpaths = {}
    @mutex  = Mutex.new
    @tracer = TracePoint.new(:class) do |event|
      # If the class is a singleton class, we won't do anything with it so we can bail out immediately.
      # This is several order of magnitude faster than accessing `Module#name`, so we do it first.
      next if event.self.singleton_class?

      # MRI allocates a new string every time Module#name is called, so we hold onto it to save an allocation.
      name = event.self.name

      # If the clas is anonymous, we won't do anyhing with it, so we can bail out here as well.
      next unless name

      # Note that it makes sense to compute the hash code unconditionally,
      # because the trace point is disabled if cpaths is empty.
      if loader = cpaths.delete(name)
        loader.on_namespace_loaded(event.self)
        disable_tracer_if_unneeded
      end
    end
  end
end
