require "rdoc/markup/formatter"
require "ostruct"

module Middleman
  module Extensions
    module ReadmeData
      DEFAULT_OPTIONS = {
        root_language: "en",
        path: lambda { |language| "/#{language == config.root_language && 'index' || language}.html" },
        template: "/language.html"
      }.freeze
      SECTIONS = [:home, :languages, :examples, :language_options, :requirements, :installation, :license, :bugs, :contact]

      class << self
        def registered app, options = {}, &block
          options = OpenStruct.new(DEFAULT_OPTIONS.merge options)
          yield options if block_given?

          app.set :readme_data, options
          app.send :include, InstanceMethods

          app.helpers HelperMethods
          Padrino::Helpers::TagHelpers::DATA_ATTRIBUTES.push(:ribbon, :toggle)

          app.after_configuration { proxy_readme_languages }
        end
        alias :included :registered
      end

      module InstanceMethods
        def proxy_readme_languages
          readme_store.languages.collect { |language| proxy_readme_language language }
        end

        def proxy_readme_language language
          proxy readme_store.path(language), readme_store.template, locals: {readme: readme_store.data(language)}, ignore: true
        end

        private

        def readme_store
          @readme_store ||= ReadmeStore.new readme_data, File.expand_path(data_dir, root), data.languages
        end
      end

      class ReadmeStore
        attr_reader :config, :directory, :language_map

        def initialize config, directory, language_map
          @config, @directory, @language_map = config, directory, language_map
        end

        def data language
          formatter.convert File.read(file language), language
        end

        def path language
          Proc === config.path && instance_exec(language, &config.path) || config.path
        end

        def template
          config.template
        end

        def languages
          config.languages || available_languages
        end

        private

        def available_languages
          Dir["#{directory}/README*.rdoc"].map { |file| to_language file.split("/").last[7..-6] }
        end

        def formatter
          @formatter ||= RDocFormatter.new language_map_with_urls
        end

        def file language
          "#{directory}/README#{to_filename language}.rdoc"
        end

        def to_filename language
          language == config.root_language && "" || "." + language
        end

        def to_language filename
          filename == "" && config.root_language || filename
        end

        def language_map_with_urls
          Hash[language_map.map { |language, name| [language, {name: name, url: path(language)}] }]
        end
      end

      class RDocFormatter < RDoc::Markup::Formatter
        ACCEPT_TYPES = [:raw, :rule, :blank_line, :paragraph, :verbatim, :heading]
        IGNORE_TYPES = [:list_item_start, :list_item_end, :list_end_bullet]
        attr_reader :res, :inside_list, :language_map, :current_language

        def initialize language_map
          super()
          @language_map = language_map
        end

        def convert content, language
          @current_language = language
          super content
        end

        def start_accepting
          @res, @inside_list = [[]], false
        end

        def end_accepting
          OpenStruct.new Hash[parts_with_names.map { |(part, items)| [part, send("extract_#{part}", items)] }]
        end

        def accept_list_start item
          @inside_list = true
          res.last << item
        end

        def accept_list_end item
          @inside_list = false
        end

        def accept_node item
          return if inside_list
          if RDoc::Markup::Heading === item && item.level < 3
            res << [item]
          else
            res.last << item
          end
        end

        def ignore node
        end

        ACCEPT_TYPES.each { |type| alias :"accept_#{type}" :accept_node }
        IGNORE_TYPES.each { |type| alias :"accept_#{type}" :ignore }

        private

        def extract_home items
          headline, *texts = items
          OpenStruct.new label: headline.text, paragraphs: extract_paragraphs(texts)
        end

        def extract_languages items
          headline, languages, *texts = without_blank_lines items
          languages = extract_list(languages).map { |language| OpenStruct.new(language_info language) }
          OpenStruct.new label: headline.text, languages: languages, paragraphs: extract_paragraphs(texts)
        end

        def extract_examples items
          headline, *examples = without_blank_lines items
          examples = examples.each_slice(2).collect { |label, code| OpenStruct.new(label: label.text, code: code.text) }
          general, arrays, any_locale, big_numbers = examples
          examples = OpenStruct.new general: general, arrays: arrays, any_locale: any_locale, big_numbers: big_numbers
          OpenStruct.new label: headline.text, examples: examples
        end

        def extract_language_options items
          headline, *items = without_blank_lines items
          examples = items.each_with_index.map { |item, i| RDoc::Markup::Heading === item && i || nil }.compact
          texts = items[0..examples.first || -1]
          examples = examples.push(0).each_cons(2).collect do |first, last|
            label, signature, code, *texts = items[first..last - 1]
            signature, note = signature.text.split " ("
            signature = OpenStruct.new signature: signature, note: note[0..-2]
            OpenStruct.new label: label.text, signature: signature, code: code.text, paragraphs: extract_paragraphs(texts)
          end
          OpenStruct.new label: headline.text, paragraphs: extract_paragraphs(texts), examples: examples
        end

        def extract_requirements items
          headline, requirements = without_blank_lines items
          OpenStruct.new label: headline.text, requirements: extract_list(requirements)
        end

        def extract_installation items
          headline, command, *texts = without_blank_lines items
          OpenStruct.new label: headline.text, command: command.text, paragraphs: extract_paragraphs(texts)
        end

        def extract_license items
          headline, *texts = without_blank_lines items
          OpenStruct.new label: headline.text, paragraphs: extract_paragraphs(texts)
        end

        def extract_bugs items
          headline, *texts = without_blank_lines items
          OpenStruct.new label: headline.text, paragraphs: extract_paragraphs(texts)
        end

        def extract_contact items
          headline, contacts = without_blank_lines items
          OpenStruct.new label: headline.text, contacts: extract_list(contacts)
        end

        def extract_list list
          without_blank_lines(list.items.collect(&:parts).flatten).collect(&:text)
        end

        def extract_paragraphs items
          items.select { |item| RDoc::Markup::Paragraph === item }.collect(&:text)
        end

        def without_blank_lines items
          items.reject { |item| RDoc::Markup::BlankLine === item }
        end

        def language_info language
          key, data = language_map.detect { |_, data| data[:name] == language }
          {label: language, url: data && data[:url] || nil, experimental?: language.include?("**"), current?: current_language == key, missing?: !key}
        end

        def parts_with_names
          [SECTIONS, res.reject(&:empty?)].transpose
        rescue IndexError
          raise "Invalid part size, should be #{SECTIONS.size}, was #{parts.size}."
        end
      end

      module HelperMethods
        def navigation section_source, options = {}
          content_tag :ul, options do
            SECTIONS[1..-1].map { |section| content_tag :li, link_to(section_source.send(section).label, "##{section}") }.join
          end
        end

        def language_buttons languages
          content_tag :div, id: "buttons" do
            buttons = languages.map do |language|
              classes = ["btn"]
              classes << "btn-inverse" if language.current?
              classes << "btn-danger" << "experimental-language" if language.experimental?
              classes << "missing-language" if language.missing?
              link_to language.label, language.url, class: classes.join(" ")
            end
            buttons.join
          end
        end

        def language_specific_example example
          content = content_tag :p, example.signature.signature
          content << content_tag(:p, example.signature.note, class: "note")
          content << example(example)
          content << paragraphs(example.paragraphs)
        end

        def example example, options = {}
          options[:class] = [options[:class], "code-example", "ribbon"].compact.join " "
          code = example.code.split(/^/).collect { |line| line[0..3] == "    " && line[4..-1] || line }.join
          content_tag :pre, preserve(html_escape code), options.merge(ribbon: example.label)
        end

        def paragraphs paragraphs, options = {}
          paragraphs.map { |text| content_tag :p, text, options }.join
        end

        def list items, options = {}
          content_tag :ul, items.map { |item| content_tag :li, item }.join, options
        end

        private

        def clean_example_code code
        end
      end
    end

    register :readme_data, ReadmeData
  end
end
