# frozen_string_literal: true

require_relative "config"

module GovCodes
  module Dafecd
    module RiSdi
      # Slices the full directory text into the RI/SDI sections named in the
      # injected Config.
      #
      # Each section is located by its header line (e.g.
      # "AIR FORCE REPORTING IDENTIFIERS (RI)"). The header regexes require the
      # "(SDI)"/"(RI)"/"(SFSC)" parenthetical, which the table-of-contents entries
      # lack, so the TOC is never mistaken for a section. A section runs from its
      # header to the next located header. The out-of-scope Space Force Specialty
      # Codes (SFSC) section is used only as a boundary (it terminates the AF RI
      # section) and is dropped from the result.
      class SectionSlicer
        Section = Struct.new(:kind, :force, :text, keyword_init: true)

        def initialize(text, config: Config.dafecd)
          @text = text
          @config = config
        end

        # @return [Array<Section>] located, in-scope sections in document order
        def sections
          located = @config.sections
            .map { |spec| {spec: spec, at: (@text =~ spec[:header])} }
            .reject { |m| m[:at].nil? }
            .sort_by { |m| m[:at] }

          located.each_with_index.map do |mark, i|
            finish = (i + 1 < located.size) ? located[i + 1][:at] : @text.length
            Section.new(
              kind: mark[:spec][:kind],
              force: mark[:spec][:force],
              text: @text[mark[:at]...finish]
            )
          end.reject { |section| section.kind == :skip }
        end
      end
    end
  end
end
