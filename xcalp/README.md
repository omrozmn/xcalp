# XCALP

Clinical platform that bridges clinicians and customers through advanced 3D scanning and visualization technology.

## Project Structure
```
xcalp/
├── apps/              # Platform-specific applications
│   ├── android/       # Android apps (clinic & customer)
│   ├── desktop/       # macOS & Windows apps
│   ├── ios/          # iOS apps (clinic & customer)
│   └── web/          # Web applications
├── blueprints/        # Technical specifications & guidelines
├── docs/             # Documentation
├── infrastructure/   # Backend & cloud infrastructure
└── tools/           # Development & deployment tools
```

## iOS Clinic App

### Requirements
- Xcode 15.0+
- iOS 17.0 SDK
- Swift 5.9+
- Git 2.39+

### Getting Started

1. Clone the repository:
```bash
git clone https://github.com/xcalp/xcalp.git
cd xcalp
```

2. Open the iOS clinic project:
```bash
cd apps/ios/clinic
open Package.swift
```

3. Build and run the project in Xcode

### Development Guidelines

- Follow SwiftUI and The Composable Architecture (TCA) patterns
- Ensure HIPAA compliance in all features
- Add unit tests for all business logic
- Add UI tests for critical user flows
- Use SwiftLint for code style consistency
- Support localization (English & Turkish)
- Implement proper accessibility features

### Key Features

- 3D head scanning using LiDAR
- Treatment planning tools
- Patient management
- Clinical analysis
- HIPAA-compliant data handling

### Architecture

The app follows The Composable Architecture (TCA) pattern with clear separation of:
- Features (independent modules)
- Core services
- UI components
- Business logic

### Testing

Run tests from Xcode or command line:
```bash
swift test
```

### Contributing

1. Create a feature branch from develop
2. Make your changes
3. Add or update tests
4. Submit a pull request

### Documentation

Additional documentation available in:
- `/docs` - Technical documentation
- `/blueprints` - Architecture & design specs
- In-code documentation for public APIs