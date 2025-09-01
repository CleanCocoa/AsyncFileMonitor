Pod::Spec.new do |s|
  s.name             = 'AsyncFileMonitor'
  s.version          = '1.0.0'
  s.summary          = "Modern async/await Swift Package for monitoring file system events using CoreFoundation's FSEvents API."
  s.description      = <<-DESC
                       AsyncFileMonitor is the modernized successor to RxFileMonitor, providing powerful file monitoring capabilities with Swift 6 concurrency support and zero external dependencies.

                       Features:
                       • Zero Dependencies: Pure Swift package with no external frameworks required
                       • Modern Async/await: Uses AsyncStream for natural async/await integration
                       • Swift 6 Ready: Full concurrency support with Sendable conformance
                       • FSEvents Integration: Efficient file system monitoring using Apple's native FSEvents API
                       • Flexible Monitoring: Monitor single files, directories, or multiple paths
                       • Event Filtering: Rich event information with detailed change flags
                       DESC

  s.homepage         = 'https://github.com/CleanCocoa/AsyncFileMonitor'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Christian Tietze' => 'me@christiantietze.de' }
  s.source           = { :git => 'https://github.com/CleanCocoa/AsyncFileMonitor.git', :tag => s.version.to_s }
  s.social_media_url = 'https://mastodon.social/@ctietze'

  s.swift_version    = '6.0'
  s.platform         = :osx, '14.0'
  s.osx.deployment_target = '14.0'

  s.source_files = 'Sources/AsyncFileMonitor/**/*'
  s.frameworks   = 'Foundation', 'CoreServices'

  # Test specs
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/AsyncFileMonitorTests/**/*'
  end
end
