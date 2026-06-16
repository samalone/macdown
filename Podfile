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
  # hoedown is vendored as a local SPM package (Packages/Hoedown); see
  # macdown-5xp.3. Kept out of CocoaPods as the de-pod template.
  # JJPluralForm vendored as a local SPM package (Packages/JJPluralForm); see
  # macdown-x8z. Kept out of CocoaPods following the de-pod template.
  # LibYAML replaced by the pure-Swift swift-yaml SPM package (macdown-5mi);
  # front-matter parsing lives in MPFrontMatterParser.swift.
  # handlebars-objc retired and M13OrderedDictionary replaced by the Swift-native
  # MPOrderedDictionary (swift-collections); HTML is built directly now
  # (macdown-j8g).
  # PAPreferences retired: MPPreferences is now a plain NSObject singleton with
  # explicit NSUserDefaults-backed accessors (macdown-e2h).
  pod 'MASPreferences', '~> 1.3'
  pod 'Sparkle', '~> 1.18', :inhibit_warnings => false

  # MacDownTests had only PAPreferences (now retired). It hosts in the MacDown
  # app, so it links no pods of its own; it only needs the pod header search
  # paths (e.g. MASPreferences, imported transitively by the print-settings
  # tests), which inherit! :search_paths provides without re-linking.
  target "MacDownTests" do
    inherit! :search_paths
  end
end

# macdown-cmd has no CocoaPods dependencies: GBCli is vendored as a local SPM
# package (Packages/GBCli; see macdown-50e), so the target is fully off
# CocoaPods and no longer integrated here.
