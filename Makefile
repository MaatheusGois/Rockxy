.PHONY: build test-breakpoint

build:
	xcodebuild -project Rockxy.xcodeproj -scheme Rockxy -destination 'platform=macOS' build STRING_CATALOG_GENERATE_SYMBOLS=NO CODE_SIGNING_ALLOWED=NO

build-release:
	xcodebuild -project Rockxy.xcodeproj -scheme Rockxy -destination 'platform=macOS' -configuration Release build STRING_CATALOG_GENERATE_SYMBOLS=NO CODE_SIGNING_ALLOWED=NO

test-breakpoint:
	xcodebuild -project Rockxy.xcodeproj -scheme Rockxy -destination 'platform=macOS' -only-testing:RockxyTests/Breakpoint test
