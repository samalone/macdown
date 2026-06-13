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
      if current.nil? || Gem::Version.new(current) < minimum
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
      end
    end
  end
end

target "MacDown" do
  pod 'handlebars-objc', '~> 1.4'
  pod 'hoedown', '~> 3.0.7', :inhibit_warnings => false
  pod 'JJPluralForm', '~> 2.1'
  pod 'LibYAML', '~> 0.1'
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
