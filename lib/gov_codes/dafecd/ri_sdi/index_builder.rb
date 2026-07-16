# frozen_string_literal: true

require_relative "../patterns"
require_relative "../publication"
require_relative "../record_splitter"
require_relative "../specialty_parser"
require_relative "../shredout_parser"
require_relative "../shredout_acronyms"
require_relative "../title_degluer"
require_relative "config"
require_relative "section_slicer"
require_relative "sdi_section_splitter"
require_relative "sdi_card_parser"
require_relative "ri_list_parser"

module GovCodes
  module Dafecd
    module RiSdi
      # Assembles the RI and SDI records of one publication into a single
      # code-keyed index and surfaces the reconciliation data the CLI reports.
      #
      # Every section named by the Config is sliced out and parsed by the format
      # it uses: SDI sections by the SdiSectionSplitter + SdiCardParser (plus the
      # one embedded CEM ladder record, parsed by the AFSC SpecialtyParser and
      # keyed by its CEM code), RI sections by the RiListParser.
      #
      # Verification gate: every emitted code must appear verbatim in the source,
      # and every emitted acronym must appear as a "(ACRONYM)" parenthetical in
      # its record's raw title (whitespace/dash/case tolerant). Titles are
      # extracted verbatim (only sanitized) and then de-glued via human-verified
      # overrides supplied by an injected TitleDegluer: each applied override is
      # gated against the raw source title (spacing/case only), so drift lands in
      # #unverified_titles and fails the build; a code with no override keeps its
      # verbatim title and is reported in #codes_needing_deglue (not an error).
      # #unverified? must be false before anything is written.
      #
      # Acronyms are captured from a title's trailing parenthetical, EXCEPT for
      # the per-publication Config#acronym_exclusions (organization/sub-phrase
      # abbreviations). Every candidate — shipped or excluded — is reported via
      # #acronym_candidates for review.
      class IndexBuilder
        # A trailing parenthetical whose sole token is an uppercase abbreviation.
        # Mirrors Dafecd::IndexBuilder::ACRONYM_PATTERN.
        ACRONYM_PATTERN = /\(([A-Z][A-Z0-9]{1,7})\)\s*\z/

        UNICODE_DASHES = Patterns::UNICODE_DASHES

        attr_reader :index, :dropped_records, :collisions, :acronym_candidates,
          :unverified_codes, :unverified_titles, :unverified_acronyms,
          :codes_needing_deglue, :section_counts, :section_codes, :sequence_numbers

        def initialize(full_text, config: Config.dafecd, degluer: TitleDegluer.empty)
          @full_text = full_text
          @config = config
          @degluer = degluer
        end

        def build
          @index = {}
          @dropped_records = []
          @collisions = []
          @acronym_candidates = []
          @unverified_codes = []
          @unverified_titles = []
          @unverified_acronyms = []
          @codes_needing_deglue = []
          @section_counts = Hash.new(0)
          @section_codes = Hash.new { |h, k| h[k] = [] }
          @sequence_numbers = Hash.new { |h, k| h[k] = [] }

          SectionSlicer.new(@full_text, config: @config).sections.each do |section|
            case section.kind
            when :sdi then build_sdi(section)
            when :ri then build_ri(section)
            end
          end

          @index.each { |code, entry| apply_override(code, entry) }
          @index.each { |code, entry| capture_acronym(code, entry) }
          @index.each { |code, entry| verify(code, entry) }
          @index
        end

        # True if any emitted value failed verification; the CLI must not write.
        def unverified?
          @unverified_codes.any? || @unverified_titles.any? || @unverified_acronyms.any?
        end

        # @return [Hash{Symbol=>Hash}] force => {present:, missing:, duplicates:}
        def sequence_report
          @sequence_numbers.transform_values do |numbers|
            present = numbers.uniq.sort
            duplicates = numbers.group_by(&:itself).select { |_, v| v.size > 1 }.keys.sort
            missing = present.empty? ? [] : ((present.first..present.last).to_a - present)
            {present: present, missing: missing, duplicates: duplicates}
          end
        end

        # @return [Array<Hash>] {code:, raw_title:} in code order, for the
        #   governed de-glue pass (titles are NOT cleaned here).
        def title_inventory
          @index.sort_by { |code, _| code.to_s }.map do |code, entry|
            {code: code, name: entry[:name], raw_title: entry[:raw_title], glued: entry[:glued_title]}
          end
        end

        private

        # --- SDI sections --------------------------------------------------------

        def build_sdi(section)
          SdiSectionSplitter.new(section.text, config: @config).records.each do |record|
            entries = SdiCardParser.new(record, config: @config).entries

            if entries.empty?
              if record.match?(@config.cem)
                entries = [cem_entry(record)]
              else
                note_sdi_drop(record)
                next
              end
            end

            entries.each { |entry| add(section, entry) }
          end
        end

        # The single embedded CEM ladder record (Premier Honor Guard, 8G000),
        # parsed by the AFSC pipeline and keyed by its CEM code.
        def cem_entry(record)
          header = SpecialtyParser.new(record, publication: Publication.dafecd).parse
          shredouts = ShredoutParser.new(record, publication: Publication.dafecd).parse
          {
            code: header[:cem_code],
            name: header[:name],
            raw_title: header[:raw_title],
            changed_date: header[:changed_date],
            glued_title: header[:glued_title],
            shredouts: shredouts
          }
        end

        def note_sdi_drop(record)
          # Detect the anchor with the SAME structural regexes the splitter/parser
          # use — a standalone "SDI <code>" line OR an inline "<code>,<title>" line
          # (the latter now tolerates a missing "SDI " prefix), so a future dropped
          # bare-format card is logged rather than silently skipped.
          anchor = record.lines.find do |line|
            line.match?(@config.sdi_anchor) || line.match?(@config.sdi_inline_anchor)
          end
          return unless anchor
          @dropped_records << {
            section: :sdi,
            first_line: anchor.strip,
            reason: "SDI anchor produced no valid entry"
          }
        end

        # --- RI sections ---------------------------------------------------------

        def build_ri(section)
          RiListParser.new(section.text, config: @config).entries.each do |entry|
            @sequence_numbers[section.force] << entry[:number]
            add(section, entry)
          end
        end

        # --- Index assembly ------------------------------------------------------

        def add(section, entry)
          code = entry[:code].to_sym
          key = [section.force, section.kind]

          if @index.key?(code)
            @collisions << {code: code, section: key, kept: @index[code][:name], discarded: entry[:name]}
            return
          end

          @index[code] = build_entry(section, entry)
          @section_counts[key] += 1
          @section_codes[key] << code
        end

        def build_entry(section, entry)
          shredouts = entry[:shredouts] || {}
          {
            force: section.force,
            kind: section.kind,
            name: entry[:name],
            raw_title: entry[:raw_title],
            changed_date: entry[:changed_date],
            glued_title: entry[:glued_title],
            shredouts: shredouts,
            shredout_acronyms: ShredoutAcronyms.from_table(shredouts)
          }
        end

        # --- Title de-gluing (verified overrides) --------------------------------

        # Apply a verified de-glued title override to +entry[:name]+, enforcing
        # the same invariant as the AFSC pipeline: an override may differ from the
        # raw source title only in spacing/case (TitleDegluer.matches_source?).
        # Drift (a changed letter/digit/punctuation, or a stale rename) is
        # recorded in #unverified_titles and never silently applied. A code with
        # no override keeps its verbatim (glued) title and is merely reported in
        # #codes_needing_deglue -- unlike the AFSC titles, full override coverage
        # is not required for the build to pass.
        def apply_override(code, entry)
          override = @degluer.override_for(code)

          if override.nil?
            @codes_needing_deglue << code if entry[:name]
            return
          end

          if TitleDegluer.matches_source?(override, entry[:raw_title])
            entry[:name] = override
          else
            @unverified_titles << {
              code: code,
              applied: override,
              raw_title: entry[:raw_title],
              reason: "override differs from source title by more than spacing/case"
            }
          end
        end

        # --- Acronyms ------------------------------------------------------------

        def capture_acronym(code, entry)
          name = entry[:name]
          return if name.nil?
          match = name.match(ACRONYM_PATTERN)
          return unless match

          acronym = match[1]
          shipped = !@config.acronym_exclusions.include?(code)
          @acronym_candidates << {code: code, acronym: acronym, name: name, shipped: shipped}
          entry[:acronym] = acronym if shipped
        end

        # --- Verification gate ---------------------------------------------------

        def verify(code, entry)
          @unverified_codes << code.to_s unless @full_text.include?(code.to_s)

          raw = entry[:raw_title]
          if raw && !norm(@full_text).include?(norm(raw))
            @unverified_titles << {code: code, raw_title: raw}
          end

          acronym = entry[:acronym]
          if acronym && !norm(raw).include?(norm("(#{acronym})"))
            @unverified_acronyms << acronym
          end
        end

        # Whitespace-, dash-, and case-insensitive normalization for the gate.
        def norm(str)
          str.to_s.gsub(UNICODE_DASHES, "-").gsub(/\s+/, "").downcase
        end
      end
    end
  end
end
