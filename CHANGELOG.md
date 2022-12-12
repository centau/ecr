# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

---

## [0.2.0] - 2022-12-08

### Added

- Method `View:include()` and `Observer:include()`.
- Method `Registry:patch()`.
- Method `Registry:add()` and optional default parameter for `ecr.component()`.

### Changed

- Behavior `for ... in View do` now behaves the same as `for ... in View:each() do`.
- Signal diconnect API (Signal now returns a connection object to call disconnect on).

### Improved

- Entity creation and release speed by ~100%.
- Multi-type view iteration speed by ~60%.

## [0.1.0] - 2022-11-16

- Initial release
