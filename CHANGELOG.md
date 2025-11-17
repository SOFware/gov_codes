# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.2] - Unreleased

## [0.1.1] - 2025-11-17

### Changed

- Test against Ruby 3.3.8 and 3.4.3
- Officer YAML structure to match Wikipedia (11BX, 11MX, etc.) (4ca6aef)
- Officer parser to accept letter qualification levels (X, Y, Z) (4ca6aef)
- Officer lookup to include qualification level in key (4ca6aef)
- Enlisted/Officer lookups to handle String leaf values (4ca6aef)
- Use git trailers to track changelog changes. (c83929a)

### Added

- AFSC Officer support (bb96aaa)
- Data extractor script for Wikipedia (c8ec55b)
- 1Z Special Warfare career field (Pararescue, Combat Control, TACP) (4ca6aef)
- Nokogiri gem for HTML parsing (4ca6aef)
- Reporting identifiers with GovCodes::AFSC::RI (6102656)
- AFSC.search to return an array of matching codes for the given prefix. (5c5bdf1)

### Removed

- 824 hallucinated codes not found in Wikipedia (4ca6aef)

### Fixed

- Tests updated to use real Wikipedia codes (4ca6aef)
