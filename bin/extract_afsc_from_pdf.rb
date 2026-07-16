#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic Air Force classification-directory extractor.
#
# Reads an official Department of the Air Force classification directory PDF --
# either the DAFECD (Enlisted) or the DAFOCD (Officer) -- builds a verified
# specialty-keyed index, writes the versioned release artifact + manifest, and
# prints a coverage report. The publication is auto-detected from the running
# page header ("DAFECD," / "DAFOCD,"); pass "dafecd"/"dafocd" as a second
# argument to force it.
#
# Usage:
#   mise exec -- ruby bin/extract_afsc_from_pdf.rb "DAFECD -31 October 25 v3.5 FINAL.pdf"
#   mise exec -- ruby bin/extract_afsc_from_pdf.rb "DAFOCD 31 Oct 25 v3.pdf"
#
# This is offline dev tooling: it requires pdf-reader (a dev dependency) and is
# never loaded by the gem runtime.

require "pdf-reader"
require "yaml"
require "fileutils"
require_relative "../lib/gov_codes/dafecd/publication"
require_relative "../lib/gov_codes/dafecd/index_builder"
require_relative "../lib/gov_codes/dafecd/text"
require_relative "../lib/gov_codes/dafecd/title_degluer"
require_relative "../lib/gov_codes/dafecd/shredout_degluer"
require_relative "../lib/gov_codes/dafecd/ri_sdi/index_builder"

# Human-readable label for the index header comment + report banner.
INDEX_LABELS = {dafecd: "DAFECD enlisted", dafocd: "DAFOCD officer"}.freeze

# A few representative specialty keys per publication for the sample section.
SAMPLE_KEYS = {
  dafecd: %i[1A1X2 1C3X1 1Z3X1 2A3X7 3N3X1 4J0X2],
  dafocd: %i[11BX 12BX 16FX 19ZX 46YX 10C0]
}.freeze

def effective_date_from(text, publication)
  header = publication.id.to_s.upcase
  raw = text[/#{header},\s+(\d{1,2}\s+\w{3,9}\s+\d{2,4})/, 1]
  raw && GovCodes::Dafecd::Text.parse_date(raw)
end

def version_label_from(filename)
  filename[/\bv(\d+(?:\.\d+)?)/i]&.then { |m| "v#{m[/[\d.]+/]}" }
end

def clean_entry(entry, publication)
  levels_key = publication.levels_key
  # Ordered pairs (YAML key order matters); nil values are dropped, empty maps
  # are kept -- matching the established enlisted artifact byte-for-byte.
  [
    [:name, entry[:name]],
    [:acronym, entry[:acronym]],
    [:career_field, entry[:career_field]],
    [:cem_code, entry[:cem_code]],
    [:changed_date, entry[:changed_date]],
    [levels_key, entry[levels_key].sort.to_h],
    [:shredouts, entry[:shredouts].sort_by { |k, _| k.to_s }.to_h],
    [:shredout_acronyms, entry[:shredout_acronyms]&.sort_by { |k, _| k.to_s }&.to_h]
  ].reject { |_, v| v.nil? }.to_h
end

# Ordered, nil-pruned RI/SDI entry for the combined ri.yml (SDI + RI + SF
# variants), keyed by the identifier code. Suffix codes live under :shredouts,
# never as top-level keys (mirroring the AFSC specialty shredouts).
def clean_ri_entry(entry)
  shredouts = entry[:shredouts]
  shredout_acronyms = entry[:shredout_acronyms]
  [
    [:name, entry[:name]],
    [:acronym, entry[:acronym]],
    [:changed_date, entry[:changed_date]],
    [:shredouts, shredouts.empty? ? nil : shredouts.sort_by { |k, _| k.to_s }.to_h],
    [:shredout_acronyms, shredout_acronyms.nil? || shredout_acronyms.empty? ? nil : shredout_acronyms.sort_by { |k, _| k.to_s }.to_h]
  ].reject { |_, v| v.nil? }.to_h
end

# Extract the RI/SDI sections of +full_text+ for +publication+, write the
# combined ri.yml alongside the AFSC index, and print a reconciliation report.
# Aborts (exit 1) if the verification gate rejects any value.
def extract_ri_sdi(full_text, publication, pdf_file, effective_date, version_label, release_dir)
  config = GovCodes::Dafecd::RiSdi::Config.for(publication.id)
  degluer = GovCodes::Dafecd::TitleDegluer.for(config)
  builder = GovCodes::Dafecd::RiSdi::IndexBuilder.new(full_text, config: config, degluer: degluer)
  index = builder.build

  puts
  puts "=" * 72
  puts "RI / SDI EXTRACTION (#{publication.id})"
  puts "=" * 72

  section_labels = {
    [:af, :sdi] => "AF  SDI", [:af, :ri] => "AF  RI ",
    [:sf, :sdi] => "SF  SDI", [:sf, :ri] => "SF  RI ",
    [:officer, :sdi] => "Officer SDI", [:officer, :ri] => "Officer RI"
  }
  puts "SECTION COUNTS"
  builder.section_counts.sort_by { |k, _| k.map(&:to_s) }.each do |key, count|
    puts "  #{section_labels.fetch(key, key.inspect).ljust(12)} #{count}"
  end
  puts "  #{"TOTAL".ljust(12)} #{index.size}"

  puts
  puts "SEQUENTIAL COMPLETENESS (RI list numbered 1..N, no gaps expected)"
  builder.sequence_report.each do |force, report|
    span = report[:present].empty? ? "(none)" : "#{report[:present].first}..#{report[:present].last}"
    status = (report[:missing].empty? && report[:duplicates].empty?) ? "OK" : "CHECK"
    puts "  #{force.to_s.ljust(8)} present=#{report[:present].size} span=#{span} " \
         "missing=#{report[:missing].inspect} duplicates=#{report[:duplicates].inspect}  #{status}"
  end

  puts
  puts "RECONCILIATION"
  puts "  Codes indexed:      #{index.size}"
  puts "  Collisions:         #{builder.collisions.size}"
  builder.collisions.each { |c| puts "    collision #{c[:code]}: kept #{c[:kept].inspect}, dropped #{c[:discarded].inspect}" }
  puts "  Dropped records:    #{builder.dropped_records.size}"
  builder.dropped_records.each { |d| puts "    dropped: #{d[:first_line].inspect} (#{d[:reason]})" }
  puts "  Unverified codes:    #{builder.unverified_codes.size}"
  puts "  Unverified titles:   #{builder.unverified_titles.size}"
  puts "  Unverified acronyms: #{builder.unverified_acronyms.size}"

  puts
  puts "ACRONYM CLASSIFICATION (shipped vs excluded)"
  builder.acronym_candidates.sort_by { |c| c[:code].to_s }.each do |c|
    puts "  #{c[:shipped] ? "SHIP" : "EXCL"}  #{c[:code].to_s.ljust(6)} (#{c[:acronym]})  #{c[:name].inspect}"
  end

  glued = index.select { |_, e| e[:glued_title] }
  puts
  puts "TITLES (de-glued via verified overrides)"
  puts "  Codes indexed:                    #{index.size}"
  puts "  Applied clean titles:             #{index.size - builder.codes_needing_deglue.size}"
  puts "  Missing override (kept verbatim):  #{builder.codes_needing_deglue.size}"
  puts "    #{builder.codes_needing_deglue.map(&:to_s).sort.join(", ")}" unless builder.codes_needing_deglue.empty?
  puts "  Raw titles flagged as pdf glue:   #{glued.size}   (informational; flags the raw source title)"
  puts "  Drifting overrides (rejected):    #{builder.unverified_titles.size}   (build fails if > 0)"

  if builder.unverified?
    warn "\nRI/SDI BUILD FAILED: verification gate rejected " \
         "#{builder.unverified_codes.size} code(s), #{builder.unverified_titles.size} title(s), " \
         "#{builder.unverified_acronyms.size} acronym(s). Nothing written."
    builder.unverified_codes.each { |c| warn "  ungrounded code: #{c}" }
    builder.unverified_titles.each do |t|
      if t[:applied]
        warn "  drifting title override #{t[:code]}: applied=#{t[:applied].inspect} " \
             "source=#{t[:raw_title].inspect} (#{t[:reason]})"
      else
        warn "  ungrounded title #{t[:code]}: #{t[:raw_title].inspect}"
      end
    end
    builder.unverified_acronyms.each { |a| warn "  ungrounded acronym: #{a}" }
    exit 1
  end

  sorted = index.sort_by { |k, _| k.to_s }.to_h.transform_values { |e| clean_ri_entry(e) }
  ri_path = File.join(release_dir, config.index_filename)
  header = <<~HEADER
    # #{publication.id.to_s.upcase} Reporting Identifiers (RI) + Special Duty Identifiers (SDI)
    # Source: #{File.basename(pdf_file)}
    # Directory: #{publication.directory_name}
    # Effective date: #{effective_date}#{"  (#{version_label})" if version_label}
    # Generated deterministically by bin/extract_afsc_from_pdf.rb.
    # Do not edit by hand; re-run the extractor against the source PDF.
    # Titles are de-glued via human-verified overrides (spacing/case only, gated
    # against the verbatim source); a title without an override is kept verbatim.
  HEADER
  File.write(ri_path, header + sorted.to_yaml)
  puts
  puts "Wrote #{ri_path}"
end

pdf_file = ARGV[0]
forced_publication = ARGV[1]

unless pdf_file
  warn "ERROR: PDF file required"
  warn "Usage: #{$PROGRAM_NAME} PDF_FILE [dafecd|dafocd]"
  exit 1
end

unless File.exist?(pdf_file)
  warn "ERROR: File not found: #{pdf_file}"
  exit 1
end

full_text = PDF::Reader.new(pdf_file).pages.map(&:text).join("\n")

publication =
  if forced_publication
    GovCodes::Dafecd::Publication.for(forced_publication)
  else
    GovCodes::Dafecd::Publication.detect(full_text)
  end
label = INDEX_LABELS.fetch(publication.id)

puts "=" * 72
puts "#{label} classification-directory extractor"
puts "=" * 72
puts "Source: #{pdf_file}"
puts "Publication: #{publication.id}"
puts "Extracted #{full_text.length} characters"

degluer = GovCodes::Dafecd::TitleDegluer.for(publication)
shredout_degluer = GovCodes::Dafecd::ShredoutDegluer.for(publication)
builder = GovCodes::Dafecd::IndexBuilder.new(
  full_text, publication: publication, degluer: degluer, shredout_degluer: shredout_degluer
)
index = builder.build

# --- Fail loudly on any verification failure BEFORE writing ----------------
# A drifting title override (letters no longer match the source) or an
# ungrounded code/acronym must abort the build rather than emit a
# stale/hallucinated value.
if builder.unverified?
  warn "\nBUILD FAILED: verification gate rejected #{builder.unverified_codes.size} code(s), " \
       "#{builder.unverified_titles.size} title override(s), " \
       "#{builder.unverified_acronyms.size} acronym(s), and " \
       "#{builder.unverified_shredouts.size} shredout override(s)."
  builder.unverified_codes.uniq.sort.each { |c| warn "  ungrounded code: #{c}" }
  builder.unverified_titles.each do |t|
    warn "  drifting title override #{t[:specialty]}: applied=#{t[:applied].inspect} " \
         "source=#{t[:raw_title].inspect} (#{t[:reason]})"
  end
  builder.unverified_acronyms.uniq.sort.each { |a| warn "  ungrounded acronym: #{a}" }
  builder.unverified_shredouts.each do |s|
    warn "  drifting shredout override #{s[:specialty]}:#{s[:suffix]}: applied=#{s[:applied].inspect} " \
         "source=#{s[:raw].inspect} (#{s[:reason]})"
  end
  warn "Nothing was written. Fix the overrides (#{publication.title_overrides_path}, " \
       "#{publication.shredout_overrides_path})."
  exit 1
end

effective_date = effective_date_from(full_text, publication) || "unknown"
version_label = version_label_from(File.basename(pdf_file))

# --- Write the release artifact -------------------------------------------
sorted_index = index.sort_by { |k, _| k.to_s }.to_h.transform_values { |e| clean_entry(e, publication) }

release_dir = File.join("lib/gov_codes/afsc/releases", publication.release_dir, effective_date)
FileUtils.mkdir_p(release_dir)
index_path = File.join(release_dir, publication.index_filename)

header = <<~HEADER
  # #{label} AFSC index (specialty-keyed, X-form)
  # Source: #{File.basename(pdf_file)}
  # Directory: #{publication.directory_name}
  # Effective date: #{effective_date}#{"  (#{version_label})" if version_label}
  # Generated deterministically by bin/extract_afsc_from_pdf.rb (Phase C.1a).
  # Do not edit by hand; re-run the extractor against the source PDF.
HEADER

File.write(index_path, header + sorted_index.to_yaml)

# --- Update the release manifest ------------------------------------------
manifest_path = "lib/gov_codes/afsc/releases.yml"
manifest = File.exist?(manifest_path) ? (YAML.safe_load_file(manifest_path, permitted_classes: [Symbol]) || {}) : {}
manifest[publication.id] ||= []
manifest[publication.id].reject! { |r| r[:effective_date] == effective_date }
manifest[publication.id] << {
  effective_date: effective_date,
  version_label: version_label,
  source: File.basename(pdf_file),
  name: publication.directory_name
}
manifest[publication.id].sort_by! { |r| r[:effective_date].to_s }
File.write(manifest_path, manifest.to_yaml)

# --- Coverage report -------------------------------------------------------
concrete_codes = index.values.flat_map { |e| e[publication.levels_key].values.map { |l| l[:code] } }
cem_codes = index.values.filter_map { |e| e[:cem_code] }
bare_codes = index.values.filter_map { |e| e[:bare_code] }
shredout_acronyms = index.select { |_, e| e[:shredout_acronyms] }

puts
puts "-" * 72
puts "COVERAGE REPORT"
puts "-" * 72
puts "Effective date:           #{effective_date}"
puts "Version label:            #{version_label || "(none found)"}"
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
puts "  Merge title conflicts:  #{builder.merge_conflicts.size}   (level re-titled on merge; existing kept, incoming surfaced)"
builder.merge_conflicts.each do |c|
  puts "    conflict: #{c[:specialty]} level #{c[:level]} (#{c[:code]}): " \
       "kept #{c[:kept].inspect}, dropped #{c[:discarded].inspect}"
end
puts
puts "CODES"
puts "  Ladder-level codes:     #{concrete_codes.size}"
puts "  Bare single codes:      #{bare_codes.size}   #{bare_codes.sort.join(", ")}" unless bare_codes.empty?
puts "  CEM codes:              #{cem_codes.size}"
puts "  Unverified codes:       #{builder.unverified_codes.size}"
unless builder.unverified_codes.empty?
  puts "    !! #{builder.unverified_codes.uniq.sort.join(", ")}"
end
puts
puts "ACRONYMS"
specialty_acronyms = index.select { |_, e| e[:acronym] }
puts "  Specialty acronyms:     #{specialty_acronyms.size}"
specialty_acronyms.sort_by { |k, _| k.to_s }.each do |spec, e|
  puts "    #{spec}: #{e[:acronym]}  (#{e[:name]})"
end
puts "  Records w/ shredout acronyms: #{shredout_acronyms.size}"
shredout_acronyms.sort_by { |k, _| k.to_s }.each do |spec, e|
  puts "    #{spec}: #{e[:shredout_acronyms].sort_by { |k, _| k.to_s }.to_h}"
end
puts "  Unverified acronyms:    #{builder.unverified_acronyms.size}"
puts
puts "SHREDOUT VALUES (de-glued via verified overrides)"
declared_shredout_overrides = shredout_degluer.each_override.to_a.size
puts "  Declared overrides:             #{declared_shredout_overrides}"
puts "  Applied clean values:           #{declared_shredout_overrides - builder.unverified_shredouts.size}"
puts "  Drifting overrides (rejected):  #{builder.unverified_shredouts.size}   (build fails if > 0)"
puts
puts "TITLES (de-glued via verified overrides)"
missing_title = builder.specialties_missing_title
puts "  Specialties missing title:     #{missing_title.size}"
puts "    #{missing_title.map(&:to_s).sort.join(", ")}" unless missing_title.empty?
puts "  Needs de-gluing (no override):  #{builder.specialties_needing_deglue.size}"
puts "  Probable glued titles (flag):   #{builder.glued_titles.size}"
puts "  Drifting overrides (rejected):  #{builder.unverified_titles.size}   (build fails if > 0)"
puts "  Applied clean titles:          #{index.size - builder.specialties_needing_deglue.size}"
no_shred = builder.specialties_without_shredouts
puts "  Specialties without shredouts:  #{no_shred.size}  (normal for many specialties)"
puts
puts "SAMPLE NAMES"
SAMPLE_KEYS.fetch(publication.id).each do |spec|
  puts "  #{spec}: #{index[spec]&.dig(:name).inspect}"
end

puts
puts "Wrote #{index_path}"
puts "Wrote #{manifest_path}"

# --- RI / SDI extraction (combined ri.yml, clearly-separated code path) -----
extract_ri_sdi(full_text, publication, pdf_file, effective_date, version_label, release_dir)

puts
puts "Review the diff with 'git diff' before committing (do NOT commit the PDF)."
