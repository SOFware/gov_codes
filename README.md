# Gov Codes

Understand and process information used by the US government.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'gov_codes'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install gov_codes
```

## Usage

### Basic Usage

```ruby
require 'gov_codes/afsc'

# Find an enlisted AFSC code
code = GovCodes::AFSC.find("1A1X2")
puts code.name # => "Mobility Force Aviator"
puts code.career_field # => "1A"
puts code.career_field_subdivision # => "1A1"
puts code.skill_level # => "X"
puts code.specific_afsc # => "1A1X2"
puts code.shredout # => nil
puts code.effective_date # => #<Date: 2025-10-31>

# Look up the concrete code an HR system actually stores
# (the "7" is the airman's skill level: Craftsman)
code = GovCodes::AFSC.find("1A172Y")
code.specialty_name     # => "Mobility Force Aviator"
code.skill_level_number # => 7
code.skill_level_name   # => "Craftsman" (title comes from the directory)
code.specialty          # => :"1A1X2"

# shredout_name resolves the shredout's meaning when that shredout
# exists in the data (nil otherwise)
code = GovCodes::AFSC.find("1A172A")
code.shredout_name      # => "C-5 Flight Engineer"

# Enlisted lookups are versioned by DAFECD release (published each 30 Apr and
# 31 Oct). `find`/`search` default to the latest shipped release; pass `as_of:`
# (a Date or "YYYY-MM-DD" string) to resolve the release in effect on that date.
code = GovCodes::AFSC.find("1A172Y", as_of: "2025-11-01")
code.effective_date     # => #<Date: 2025-10-31>
# A date before the earliest shipped release has no data and returns nil.
GovCodes::AFSC.find("1A172Y", as_of: "2000-01-01") # => nil

# Find an officer AFSC code
code = GovCodes::AFSC.find("11MX")
puts code.name # => "Mobility pilot"
puts code.career_group # => "11"
puts code.functional_area # => "M"
puts code.qualification_level # => "X"
puts code.shredout # => nil

# Find a Reporting Identifier (RI) or Special Duty Identifier (SDI)
code = GovCodes::AFSC.find("8A400")
puts code.name # => "Talent management consultant"
puts code.career_field # => "8A"
puts code.identifier # => "400"
puts code.suffix # => nil

# Find a code with a shredout/suffix
code = GovCodes::AFSC.find("11BXA")
puts code.name # => "B-1"
puts code.specific_afsc # => "11BX"
puts code.shredout # => "A"
```

### Searching for Codes

You can search for all codes matching a prefix:

```ruby
# Search for all Special Warfare codes
results = GovCodes::AFSC.search("1Z")
results.each do |code|
  puts "#{code.specific_afsc}: #{code.name}"
end
# Output:
# 1Z1X1: Pararescue
# 1Z2X1: Combat Control
# 1Z3X1: Tactical Air Control Party (TACP)
# 1Z4X1: Special Reconnaissance

# Search for Bomber Pilot shredouts
results = GovCodes::AFSC.search("11BX")
results.each do |code|
  shredout = code.shredout ? code.shredout.to_s : ""
  puts "#{code.specific_afsc}#{shredout}: #{code.name}"
end
# Output:
# 11BX: Bomber pilot
# 11BXA: B-1
# 11BXB: B-2
# 11BXC: B-52
# ...

# Search is case-insensitive
GovCodes::AFSC.search("1z1") # Same as search("1Z1")
```

### Extending with Custom AFSC Codes

Enlisted codes are stored as a specialty-keyed index per DAFECD release. You can
extend or override a release by dropping an index file for that release's
effective date onto your application's load path:

```yaml
# In your application's lib/gov_codes/afsc/releases/dafecd/2025-10-31/enlisted.yml
:"9Z9X9":
  :name: Custom Specialty
  :career_field: :"9Z"
  :skill_levels:
    7:
      :code: 9Z979
      :title: Craftsman
  :shredouts:
    :A: Custom Shredout
```

The gem merges your index over the shipped index for the matching release,
adding new specialties and overriding existing ones.

You can also add a whole new release (e.g. a newer directory the gem has not
shipped yet) by listing it in a `releases.yml` on your load path. Release lists
are unioned by effective date, so adding a release never hides the shipped ones;
a same-date entry from your file overrides the shipped manifest entry:

```yaml
# In your application's lib/gov_codes/afsc/releases.yml
:dafecd:
- :effective_date: '2026-04-30'
  :version_label: v3.6
  :source: DAFECD-30-April-26.pdf
  :name: Department of the Air Force Enlisted Classification Directory
```

Pair it with a matching `releases/dafecd/2026-04-30/enlisted.yml` index, and
`find(code, as_of: "2026-04-30")` will resolve against it.

## Data source & provenance

AFSC data is extracted from the official **Department of the Air Force classification directories** — the DAFECD (enlisted) and DAFOCD (officer) — not third-party sources. Extraction is deterministic, and every code is verified to appear verbatim in the source directory: no predicted or hallucinated codes.

The data is **versioned by each directory's effective date** (the directories are republished roughly semi-annually, on 30 April and 31 October). Look a code up as it stood for a given release, or take the latest:

```ruby
GovCodes::AFSC.find("1A172Y")                        # latest shipped release
GovCodes::AFSC.find("1A172Y", as_of: "2025-11-01")   # the release in effect on that date
GovCodes::AFSC.find("1A172Y").effective_date         # => the release the result came from
```

**Currently shipped:** enlisted AFSCs from the DAFECD effective 31 October 2025. Officer (DAFOCD), reporting/special-duty identifiers, SEIs, prefixes, and Space Force codes are planned.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

This project is managed with [Reissue](https://github.com/SOFware/reissue).

Releases are automated via the [shared release workflow](https://github.com/SOFware/reissue/blob/main/.github/workflows/SHARED_WORKFLOW_README.md). Trigger a release by running the "Release gem to RubyGems.org" workflow from the Actions tab.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/SOFware/gov_codes.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
