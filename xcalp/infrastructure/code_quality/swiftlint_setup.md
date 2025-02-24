# SwiftLint Run Script

To add SwiftLint and the issue analyzer to your build process, add this script to a new Run Script Phase in Xcode:

```bash
if [[ "$(uname -m)" == arm64 ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

if which swiftlint > /dev/null; then
  swiftlint | swift "${SRCROOT}/tools/analyze_issues.swift"
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

Steps to add this to Xcode:
1. Open xcalp.xcworkspace
2. Select the xcalp target
3. Go to Build Phases tab
4. Click + to add a new Run Script Phase
5. Paste the script above
6. Drag this new phase to run just after "Target Dependencies"

The analyzer will now provide a clear summary of issues categorized by severity, showing:
- Total number of issues
- Count of errors vs warnings
- Top 5 most common errors
- Top 5 most common warnings

This helps you quickly identify which types of issues to tackle first.