# sprockets problem, see https://github.com/middleman/middleman-sprockets/pull/15, once fixed should be removed
module Middleman::Sprockets
  module CurrentPathFix
    def self.included base
      base.alias_method_chain :initialize, :current_path_fix
    end

    def initialize_with_current_path_fix app
      initialize_without_current_path_fix app

      context_class.class_eval do
        def mm_path
          @mm_path ||= app.sitemap.file_to_path(pathname.to_s)
        end

        def method_missing(*args)
          name = args.first
          if app.respond_to?(name)
            app.current_path = mm_path unless app.current_path
            app.send(*args)
          else
            super
          end
        end
      end
    end
  end
  MiddlemanSprocketsEnvironment.send :include, CurrentPathFix
end
