.PHONY: test-breakpoint

test-breakpoint:
	xcodebuild -project Rockxy.xcodeproj -scheme Rockxy -destination 'platform=macOS' -only-testing:RockxyTests/Breakpoint test
