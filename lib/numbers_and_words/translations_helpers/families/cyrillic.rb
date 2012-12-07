module NumbersAndWords
  module TranslationsHelpers
    module Families
      module Cyrillic
        include NumbersAndWords::TranslationsHelpers::Families::Base

        private

        def translation_ones number
          t([:ones, gender].join('_'))[number]
        end

        def translation_hundreds number
          t(:hundreds)[number]
        end

        def translation_megs capacity
          super(capacity, figures.number_in_capacity(capacity))
        end

        def zero
          t(:ones_male)[0]
        end
      end
    end
  end
end
