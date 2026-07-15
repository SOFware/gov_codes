#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic DAFECD enlisted extractor (Phase C.1a).
#
# Reads the official Department of the Air Force Enlisted Classification
# Directory (DAFECD) PDF, builds a verified specialty-keyed index, writes the
# versioned release artifact + manifest, and prints a coverage report.
#
# Usage:
#   mise exec -- ruby bin/extract_afsc_from_pdf.rb "DAFECD -31 October 25 v3.5 FINAL.pdf"
#
# This is offline dev tooling: it requires pdf-reader (a dev dependency) and is
# never loaded by the gem runtime.

require "pdf-reader"
require "yaml"
require "fileutils"
require_relative "../lib/gov_codes/dafecd/index_builder"
require_relative "../lib/gov_codes/dafecd/text"
require_relative "../lib/gov_codes/dafecd/title_degluer"

DIRECTORY_NAME = "Department of the Air Force Enlisted Classification Directory"
# The plan estimated ~161 enlisted specialties; the 31 Oct 25 edition actually
# contains ~136 skill-ladder AFSC specialties (career fields 1-8). Shown for
# reference only.
PLAN_ESTIMATE = 161

def effective_date_from(text)
  raw = text[/DAFECD,\s+(\d{1,2}\s+\w{3,9}\s+\d{2,4})/, 1]
  raw && GovCodes::Dafecd::Text.parse_date(raw)
end

def version_label_from(filename)
  filename[/\bv(\d+(?:\.\d+)?)/i]&.then { |m| "v#{m[/[\d.]+/]}" }
end

def clean_entry(entry)
  {
    name: entry[:name],
    acronym: entry[:acronym],
    career_field: entry[:career_field],
    cem_code: entry[:cem_code],
    changed_date: entry[:changed_date],
    skill_levels: entry[:skill_levels].sort.to_h,
    shredouts: entry[:shredouts].sort_by { |k, _| k.to_s }.to_h
  }.reject { |_, v| v.nil? }
end

pdf_file = ARGV[0]

unless pdf_file
  warn "ERROR: PDF file required"
  warn "Usage: #{$PROGRAM_NAME} PDF_FILE"
  exit 1
end

unless File.exist?(pdf_file)
  warn "ERROR: File not found: #{pdf_file}"
  exit 1
end

puts "=" * 72
puts "DAFECD enlisted extractor (Phase C.1a)"
puts "=" * 72
puts "Source: #{pdf_file}"

full_text = PDF::Reader.new(pdf_file).pages.map(&:text).join("\n")
puts "Extracted #{full_text.length} characters"

degluer = GovCodes::Dafecd::TitleDegluer.load
builder = GovCodes::Dafecd::IndexBuilder.new(full_text, degluer: degluer)
index = builder.build

# --- Fail loudly on any verification failure BEFORE writing ----------------
# A drifting title override (letters no longer match the source) or an
# ungrounded code must abort the build rather than emit a stale/hallucinated
# value.
if builder.unverified?
  warn "\nBUILD FAILED: verification gate rejected #{builder.unverified_codes.size} code(s), " \
       "#{builder.unverified_titles.size} title override(s), and " \
       "#{builder.unverified_acronyms.size} acronym(s)."
  builder.unverified_codes.uniq.sort.each { |c| warn "  ungrounded code: #{c}" }
  builder.unverified_titles.each do |t|
    warn "  drifting title override #{t[:specialty]}: applied=#{t[:applied].inspect} " \
         "source=#{t[:raw_title].inspect} (#{t[:reason]})"
  end
  builder.unverified_acronyms.uniq.sort.each { |a| warn "  ungrounded acronym: #{a}" }
  warn "Nothing was written. Fix the overrides (lib/gov_codes/dafecd/title_overrides.yml)."
  exit 1
end

effective_date = effective_date_from(full_text) || "unknown"
version_label = version_label_from(File.basename(pdf_file))

# --- Write the release artifact -------------------------------------------
sorted_index = index.sort_by { |k, _| k.to_s }.to_h.transform_values { |e| clean_entry(e) }

release_dir = File.join("lib/gov_codes/afsc/releases/dafecd", effective_date)
FileUtils.mkdir_p(release_dir)
enlisted_path = File.join(release_dir, "enlisted.yml")

header = <<~HEADER
  # DAFECD enlisted AFSC index (specialty-keyed, X-form)
  # Source: #{File.basename(pdf_file)}
  # Directory: #{DIRECTORY_NAME}
  # Effective date: #{effective_date}#{"  (#{version_label})" if version_label}
  # Generated deterministically by bin/extract_afsc_from_pdf.rb (Phase C.1a).
  # Do not edit by hand; re-run the extractor against the source PDF.
HEADER

File.write(enlisted_path, header + sorted_index.to_yaml)

# --- Update the release manifest ------------------------------------------
manifest_path = "lib/gov_codes/afsc/releases.yml"
manifest = File.exist?(manifest_path) ? (YAML.safe_load_file(manifest_path, permitted_classes: [Symbol]) || {}) : {}
manifest[:dafecd] ||= []
manifest[:dafecd].reject! { |r| r[:effective_date] == effective_date }
manifest[:dafecd] << {
  effective_date: effective_date,
  version_label: version_label,
  source: File.basename(pdf_file),
  name: DIRECTORY_NAME
}
manifest[:dafecd].sort_by! { |r| r[:effective_date].to_s }
File.write(manifest_path, manifest.to_yaml)

# --- Coverage report -------------------------------------------------------
concrete_codes = index.values.flat_map { |e| e[:skill_levels].values.map { |l| l[:code] } }
cem_codes = index.values.filter_map { |e| e[:cem_code] }

puts
puts "-" * 72
puts "COVERAGE REPORT"
puts "-" * 72
puts "Effective date:           #{effective_date}"
puts "Version label:            #{version_label || "(none found)"}"
puts "(Plan estimated ~#{PLAN_ESTIMATE} specialties; that was high. Actual counts below.)"
puts
puts "RECORD RECONCILIATION (split == parsed + merged + dropped)"
puts "  Records split:          #{builder.records_split}"
puts "  Specialties parsed:     #{index.size}"
puts "  Records merged:         #{builder.merged_count}   (duplicate/continuation records folded into an existing specialty)"
puts "  Records dropped:        #{builder.dropped_records.size}"
reconciled = index.size + builder.merged_count + builder.dropped_records.size
puts "  Reconciled total:       #{reconciled}   (#{(reconciled == builder.records_split) ? "OK" : "MISMATCH!"})"
builder.dropped_records.each do |d|
  puts "    dropped: cem=#{d[:cem_code].inspect} first=#{d[:first_line].inspect}"
  puts "             reason: #{d[:reason]}"
end
puts
puts "CODES"
puts "  Skill-level codes:      #{concrete_codes.size}"
puts "  CEM codes:              #{cem_codes.size}"
puts "  Unverified codes:       #{builder.unverified_codes.size}"
unless builder.unverified_codes.empty?
  puts "    !! #{builder.unverified_codes.uniq.sort.join(", ")}"
end
puts "  NOTE: the code gate is a regression guard — every code here is a verbatim"
puts "  slice of the source, so 0 unverified is guaranteed by construction."
puts
puts "TITLES (de-glued via verified overrides)"
missing_title = builder.specialties_missing_title
puts "  Specialties missing title:     #{missing_title.size}"
puts "    #{missing_title.map(&:to_s).sort.join(", ")}" unless missing_title.empty?
puts "  Needs de-gluing (no override):  #{builder.specialties_needing_deglue.size}"
unless builder.specialties_needing_deglue.empty?
  puts "    #{builder.specialties_needing_deglue.map(&:to_s).sort.join(", ")}"
end
puts "  Drifting overrides (rejected):  #{builder.unverified_titles.size}   (build fails if > 0)"
puts "  Applied clean titles:          #{index.size - builder.specialties_needing_deglue.size}"
puts "  The title gate is MEANINGFUL: each applied override is verified to match"
puts "  its raw source title with only spacing/case changed; drift fails the build."
no_shred = builder.specialties_without_shredouts
puts "  Specialties without shredouts:  #{no_shred.size}  (normal for many specialties)"
puts
puts "SAMPLE DE-GLUED NAMES"
%i[1A1X2 1C3X1 1Z3X1 2A3X7 3N3X1 4J0X2].each do |spec|
  puts "  #{spec}: #{index[spec]&.dig(:name).inspect}"
end

puts
puts "Wrote #{enlisted_path}"
puts "Wrote #{manifest_path}"
puts "Review the diff with 'git diff' before committing (do NOT commit the PDF)."
