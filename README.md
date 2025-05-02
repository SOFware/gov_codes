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
puts code.name # => "Aircrew operations"
puts code.career_field # => "1A"
puts code.career_field_subdivision # => "1A1"
puts code.skill_level # => "X"
puts code.specific_afsc # => "1A1X2"
puts code.shredout # => nil

# Find an officer AFSC code
code = GovCodes::AFSC.find("11M4")
puts code.name # => "Pilot"
puts code.career_group # => "11"
puts code.functional_area # => "M"
puts code.qualification_level # => "4"
puts code.shredout # => nil
```

### Extending with Custom AFSC Codes

You can extend the default AFSC codes with your own custom codes by placing a YAML file in your application's load path:

```ruby
# In your application's lib/gov_codes/afsc/enlisted.yml
9Z:
  name: Custom AFSC
  subcategories:
    0X1:
      name: Custom Subcategory
      subcategories:
        A:
          name: Custom Shredout
```

The gem will automatically merge your custom codes with the default codes, overriding any existing codes.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

This project is managed with [Reissue](https://github.com/SOFware/reissue).

To release a new version, make your changes and be sure to update the CHANGELOG.md.

To release a new version:

1. `bundle exec rake build:checksum`
2. `bundle exec rake release`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/SOFware/gov_codes.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
