Pod::Spec.new do |s|
  s.name             = 'dart_psd_tool'
  s.version          = '0.1.0'
  s.summary          = 'Metal GPU compositor for PSD blending.'
  s.description      = 'Native Metal compute shader plugin for PSDTool-compatible compositing.'
  s.homepage         = 'https://github.com/sawarae/dart-psd-tool'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'sawarae' => 'sawarae' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,metal}'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  s.pod_target_xcconfig = {
    'MTL_COMPILER_FLAGS' => '-std=metal2.0',
    'DEFINES_MODULE' => 'YES',
  }
end
