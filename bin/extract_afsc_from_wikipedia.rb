#!/usr/bin/env ruby
# frozen_string_literal: true

require "nokogiri"
require "yaml"
require "date"

# AFSC Wikipedia HTML Parser
# Extracts AFSC codes from a Wikipedia HTML file from https://en.wikipedia.org/wiki/Air_Force_Specialty_Code

class HTMLExtractor
  def initialize(html_path)
    @html_path = html_path
    @doc = Nokogiri::HTML(File.read(html_path))
    @stats = {extracted: 0, warnings: []}
  end

  def extract_text(node)
    return "" unless node

    # Get text from node, handling links and other elements
    if node.is_a?(Nokogiri::XML::Text)
    else
      # Remove citation markers
      node.css("sup").remove
    end
    text = node.text

    # Clean up HTML entities
    text.gsub("&amp;", "&")
      .gsub("&#91;", "[")
      .gsub("&#93;", "]")
      .strip
  end

  def extract_first_line_text(li)
    # Extract text from first line of LI, before any nested <ul>
    # Handles cases where text is split across text nodes and links
    text_parts = []

    li.children.each do |child|
      break if child.name == "ul" # Stop at nested list
      break if child.name == "figure" # Stop at figures

      if child.is_a?(Nokogiri::XML::Text)
        text_parts << child.text
      elsif child.name == "a"
        # Extract link text
        text_parts << child.text
      end
    end

    extract_text(Nokogiri::XML::Text.new(text_parts.join(""), @doc))
  end

  def parse_code_line(text)
    # Parse "1A1X2 – Mobility force aviator" or "11BX – Bomber pilot"
    # Returns [code, name] or nil if not a valid format
    return nil unless text

    # Try with en-dash
    if text =~ /^([0-9A-Z]+)\s*[–-]\s*(.+)$/
      code = $1.strip
      name = $2.strip
      return [code, name] if code.length >= 2 && !name.empty?
    end

    # Try with colon (for codes like "10C0: Operations commander")
    if text =~ /^([0-9A-Z]+)\s*:\s*(.+)$/
      code = $1.strip
      name = $2.strip
      return [code, name] if code.length >= 2 && !name.empty?
    end

    nil
  end

  def log_stat(message)
    puts message
    @stats[:warnings] << message
  end

  attr_reader :stats
end

class EnlistedExtractor < HTMLExtractor
  def extract
    codes = {}

    # Extract from all enlisted sections
    enlisted_sections = [
      "h3#Operations",
      "h3#Maintenance_and_logistics",
      "h3#Support",
      "h3#Medical"
    ]

    enlisted_sections.each do |section_id|
      section_h3 = @doc.at_css(section_id)
      next unless section_h3

      section_name = section_h3.text
      log_stat "Processing enlisted section: #{section_name}"

      # Find the next h3 (section boundary)
      all_h3s = @doc.css("h3")
      current_index = all_h3s.index(section_h3)
      next_h3 = all_h3s[current_index + 1]

      parent_div = section_h3.parent
      current = parent_div.next_element
      lists = []

      # Collect all <ul> elements until next section or officer section
      while current && current != next_h3&.parent
        # Stop if we hit an officer section (Operations_2, Support_2, Medical_2)
        break if next_h3&.attr("id")&.end_with?("_2")

        lists << current if current.name == "ul"
        current = current.next_element
      end

      log_stat "  Found #{lists.length} lists in #{section_name}"

      # Process all lists
      lists.each do |main_list|
        main_list.css("> li").each do |career_field_li|
          text = extract_first_line_text(career_field_li)

          parsed = parse_code_line(text)
          next unless parsed

          cf_code, cf_name = parsed

          # Only process if it looks like a career field (1-2 chars)
          next if cf_code.length > 2

          log_stat "  Found career field: #{cf_code} - #{cf_name}"

          codes[cf_code.to_sym] = {
            name: cf_name,
            subcategories: extract_subcategories(career_field_li, cf_code)
          }

          @stats[:extracted] += 1
        end
      end
    end

    codes
  end

  private

  def extract_subcategories(parent_li, parent_code)
    subcats = {}

    # Find nested <ul>
    ul = parent_li.at_css("ul")
    return subcats unless ul

    ul.css("> li").each do |li|
      # Get first line text
      text = extract_first_line_text(li)

      parsed = parse_code_line(text)
      next unless parsed

      code, name = parsed

      # Determine the subcategory key
      # For enlisted: extract the subdivision part (e.g., "1X2" from "1A1X2")
      subcat_key = determine_subcat_key(code, parent_code)
      next unless subcat_key

      subcats[subcat_key.to_sym] = {
        name: name,
        subcategories: extract_subcategories(li, code)
      }

      @stats[:extracted] += 1
    end

    # Convert to simple string if no nested subcategories
    subcats.transform_values do |v|
      v[:subcategories].empty? ? v[:name] : v
    end
  end

  def determine_subcat_key(code, parent_code)
    # For codes like "1A1X2" under "1A", extract "1X2"
    # For codes like "1A1X2A" under "1A1X2", extract "A"

    if code.start_with?(parent_code) && code.length > parent_code.length
      code[parent_code.length..]
    elsif code.length == 1
      # Single letter shredout
      code
    elsif code.match?(/^\d[A-Z]\d[A-Z]\d[A-Z]?$/)
      # Full AFSC like 1A1X2
      # Extract last 3-4 chars after career field
      code[2..]
    else
      log_stat "WARNING: Could not determine subcat key for #{code} under #{parent_code}"
      nil
    end
  end
end

class OfficerExtractor < HTMLExtractor
  def extract
    codes = {}

    # Extract from all officer sections
    officer_sections = [
      "h3#Operations_2",
      "h3#Support_2",
      "h3#Medical_2"
    ]

    officer_sections.each do |section_id|
      section_h3 = @doc.at_css(section_id)
      next unless section_h3

      section_name = section_h3.text
      log_stat "Processing officer section: #{section_name}"

      # Find the next h3 (section boundary)
      all_h3s = @doc.css("h3")
      current_index = all_h3s.index(section_h3)
      next_h3 = all_h3s[current_index + 1]

      parent_div = section_h3.parent
      current = parent_div.next_element
      lists = []

      # Collect all <ul> elements until next section
      while current && current != next_h3&.parent
        lists << current if current.name == "ul"
        current = current.next_element
      end

      log_stat "  Found #{lists.length} lists in #{section_name}"

      # Process all lists
      lists.each do |main_list|
        process_officer_list(main_list, codes)
      end
    end

    codes
  end

  private

  def process_officer_list(list, codes)
    list.css("> li").each do |li|
      text = extract_first_line_text(li)

      parsed = parse_code_line(text)
      next unless parsed

      code, name = parsed

      # Check if this is a 4+ character officer code (the actual AFSCs)
      # or a 2-3 char category code that we should drill into
      if code.length >= 4
        # This is an actual AFSC like "11BX", "10C0", "14F"
        log_stat "Found officer AFSC: #{code} - #{name}"

        codes[code.to_sym] = {
          name: name,
          subcategories: extract_officer_shredouts(li)
        }

        @stats[:extracted] += 1
      elsif code.length <= 3
        # This is a category like "11 - Pilot", drill into nested codes
        log_stat "Found officer category: #{code} - #{name} (drilling into nested codes)"

        # Look for nested <ul> with actual AFSCs
        ul = li.at_css("ul")
        if ul
          process_officer_list(ul, codes)
        end
      end
    end
  end

  def extract_officer_shredouts(parent_li)
    shredouts = {}

    ul = parent_li.at_css("ul")
    return shredouts unless ul

    ul.css("> li").each do |li|
      text = extract_first_line_text(li)

      parsed = parse_code_line(text)
      next unless parsed

      code, name = parsed

      # For shredouts, extract the last character(s) as the key
      # "11BXA" → "A", "11M1" → "1"
      key = if code.length > 4
        code[4..]  # Everything after the 4-char base
      else
        code[-1]  # Last character
      end

      shredouts[key.to_sym] = name
      @stats[:extracted] += 1
    end

    shredouts
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  html_file = ARGV[0] || "afsc.html"

  unless File.exist?(html_file)
    puts "ERROR: File not found: #{html_file}"
    puts "Usage: #{$PROGRAM_NAME} [path/to/afsc.html]"
    exit 1
  end

  puts "=" * 80
  puts "AFSC Wikipedia Extractor"
  puts "DEC-003 Compliant: No hallucinations, only explicit Wikipedia codes"
  puts "=" * 80
  puts

  puts "Input: #{html_file}"
  puts "File size: #{File.size(html_file)} bytes"
  puts

  # Extract enlisted codes
  puts "Extracting enlisted codes..."
  enlisted_extractor = EnlistedExtractor.new(html_file)
  enlisted_codes = enlisted_extractor.extract

  puts "Enlisted codes extracted: #{enlisted_extractor.stats[:extracted]}"
  puts

  # Extract officer codes
  puts "Extracting officer codes..."
  officer_extractor = OfficerExtractor.new(html_file)
  officer_codes = officer_extractor.extract

  puts "Officer codes extracted: #{officer_extractor.stats[:extracted]}"
  puts

  # Generate YAML with attribution header
  def generate_yaml_with_header(codes, type)
    header = <<~HEADER
      # #{type.capitalize} AFSCs extracted from Wikipedia
      # Source: https://en.wikipedia.org/wiki/Air_Force_Specialty_Code
      # Wikipedia Revision: 1318430021
      # Extracted: #{Date.today}
      #
      # IMPORTANT: This file contains ONLY codes explicitly listed on Wikipedia.
      # No predictions, no assumptions, no hallucinations.
      # See .agent-os/product/decisions.md (DEC-003) for anti-hallucination policy.
      #
      # Extraction script: bin/extract_afsc_from_wikipedia.rb
      # Verification: bundle exec ruby test/verification/wikipedia_match_test.rb

    HEADER

    header + codes.to_yaml.sub(/^---\n/, "")
  end

  # Write files
  enlisted_output = "lib/gov_codes/afsc/enlisted.yml.new"
  officer_output = "lib/gov_codes/afsc/officer.yml.new"

  File.write(enlisted_output, generate_yaml_with_header(enlisted_codes, "enlisted"))
  File.write(officer_output, generate_yaml_with_header(officer_codes, "officer"))

  puts "Output files created:"
  puts "  #{enlisted_output}"
  puts "  #{officer_output}"
  puts

  puts "Summary:"
  puts "  Total codes extracted: #{enlisted_extractor.stats[:extracted] + officer_extractor.stats[:extracted]}"
  puts "  Enlisted career fields: #{enlisted_codes.keys.length}"
  puts "  Officer base codes: #{officer_codes.keys.length}"
  puts

  if enlisted_extractor.stats[:warnings].any? || officer_extractor.stats[:warnings].any?
    puts "Warnings:"
    (enlisted_extractor.stats[:warnings] + officer_extractor.stats[:warnings]).each do |warning|
      puts "  - #{warning}"
    end
    puts
  end

  puts "Next steps:"
  puts "  1. Review the generated .new files"
  puts "  2. Compare with current YAML files"
  puts "  3. Manually verify 10-20 random codes against Wikipedia"
  puts "  4. If satisfied, rename .new files to replace current YAML"
  puts
end
