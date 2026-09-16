# Contributing to PureMac (Golden Gate Edition)

Thanks for your interest in contributing to this custom fork of PureMac!

## Getting Started

1. Fork the repo (`buddhi-art/PureMac`)
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/PureMac.git`
3. Install prerequisites: `brew install xcodegen`
4. Generate the Xcode project: `xcodegen generate`
5. Open in Xcode: `open PureMac.xcodeproj`

## Development

- PureMac is built with **SwiftUI** and targets **macOS 13.0+**
- Project structure is defined in `project.yml` (XcodeGen)
- Run the app from Xcode with Cmd+R

## Pull Requests

- Keep PRs focused on a single change
- Test your changes on at least macOS Ventura (13.0)
- Follow the "Liquid Glass" design language
- Update the README if your change affects user-facing behavior

## What to Contribute

- Bug fixes
- UI enhancements specifically for macOS 27 Golden Gate
- New Liquid Glass components
- Performance improvements
- Localization (translations)

## Reporting Bugs

Open an issue in the `buddhi-art/PureMac` repository. Include:
- macOS version
- PureMac version
- Steps to reproduce
- Expected vs actual behavior
