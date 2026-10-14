Pod::Spec.new do |s|
  s.name             = 'rajshala_native_print_ios'
  s.version          = '1.0.0'
  s.summary          = 'Authenticated original portal popup printing for Rajshala.'
  s.description      = s.summary
  s.homepage         = 'https://rajshaladarpan.rajasthan.gov.in/'
  s.license          = { :type => 'Proprietary', :text => 'Rajshala application source.' }
  s.author           = { 'Rajshala' => 'Ripudaman Singh Jhala' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'WebKit', 'UIKit', 'PDFKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
