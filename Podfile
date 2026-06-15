# Raised from "10.8" during the 2026 revival: Xcode 27 only supports macOS
# deployment targets >= 12.0.
platform :osx, "12.0"

source 'https://github.com/MacDownApp/cocoapods-specs.git'  # Patched libraries.
source 'https://cdn.cocoapods.org/'

project 'MacDown.xcodeproj'

inhibit_all_warnings!

# Several of the pinned pods still declare ancient deployment targets
# (10.6-10.8) in their podspecs, which Xcode 27 rejects. Raise any pod
# target below our minimum up to it. Guarded so we only ever raise a
# target, never downgrade a pod that legitimately needs macOS 13+.
post_install do |installer|
  minimum = Gem::Version.new('12.0')
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      current = config.build_settings['MACOSX_DEPLOYMENT_TARGET']
      # Treat a missing or non-version value (nil, "", "$(inherited)", ...)
      # as below the floor; Gem::Version.new would raise on those.
      if current.nil? ||
         !Gem::Version.correct?(current) ||
         Gem::Version.new(current) < minimum
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
      end
    end
  end
end

target "MacDown" do
  pod 'handlebars-objc', '~> 1.4'
  # hoedown is vendored as a local SPM package (Packages/Hoedown); see
  # macdown-5xp.3. Kept out of CocoaPods as the de-pod template.
  pod 'JJPluralForm', '~> 2.1'
  # LibYAML replaced by the pure-Swift swift-yaml SPM package (macdown-5mi);
  # front-matter parsing lives in MPFrontMatterParser.swift.
  pod 'M13OrderedDictionary', '~> 1.1'
  pod 'MASPreferences', '~> 1.3'
  pod 'Sparkle', '~> 1.18', :inhibit_warnings => false

  # Locked on 0.4.x until we drop 10.8.
  pod 'PAPreferences', '~> 0.4'
end

target "MacDownTests" do
  pod 'PAPreferences', '~> 0.4'
end

target "macdown-cmd" do
  pod 'GBCli', '~> 1.1'
end
