# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.1.3] - Unreleased

## [0.1.2] - 2026-07-16

### Added

- 6C0X1 Contracting (4a6c87e)
- 6F0X1 Financial Management and Comptroller (4a6c87e)
- 7S0X1 Special Investigations (4a6c87e)
- 5Z700/5Z800/5Z900 Chief Enlisted Manager codes (4a6c87e)
- Concrete skill-level AFSC code lookup (e.g. 1A172Y) (1cea6af)
- Version-aware lookup via find(code, as_of:) with effective_date (1cea6af)
- Officer AFSC lookups versioned by DAFOCD release with as_of (1a43a2d)
- Officer qualification-level titles and specialty/shredout acronyms (e.g. TACPO) (1a43a2d)
- Officer specialties 17DX, 44BX, 45AX, 47BX, 47PX, 48GX from the DAFOCD (b28f308)
- RI/SDI extraction pipeline (parser, index builder, CLI) for DAFECD and DAFOCD (5d068dd)
- versioned RI/SDI release data at releases/{dafecd,dafocd}/2025-10-31/ri.yml (de03f09)
- RI.find_by_acronym as a real reverse lookup; as_of threading through RI.find and RI.search (712f624)

### Changed

- Set dependabot cooldown to 14 days (fde4b9a)
- Test against Ruby 4.0.5 (61983ce)
- Source enlisted AFSC data from the official DAFECD instead of Wikipedia (1cea6af)
- Source officer AFSC data from the official DAFOCD instead of Wikipedia (1a43a2d)
- as_of defaults to today, not the newest release regardless of date (ff86c00)
- RI resolves from the versioned DAFECD/DAFOCD release indexes instead of Wikipedia-sourced data (712f624)

### Fixed

- SimpleCov reporting inaccurate coverage due to at_exit ordering (de7063c)
- glued shredout names in the enlisted release data (be773cf)
- required_ruby_version understated the actual floor (b8d64b8)
- officer ladder missed no-comma, glued-shred, and glyph-prefixed cards (b28f308)
