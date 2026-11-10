#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pick_photo.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pick_photo'
  s.version          = '0.0.1'
  s.summary          = 'A fast, privacy-friendly Flutter image picker plugin.'
  s.description      = <<-DESC
A fast, privacy-friendly, modern Flutter image picker plugin supporting Photo Picker, PHPicker, and native camera capture.
                       DESC
  s.homepage         = 'https://github.com/shithin/pick_photo'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Shithin' => 'dev@shithin.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'pick_photo/Sources/pick_photo/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
