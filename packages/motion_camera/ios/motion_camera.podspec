Pod::Spec.new do |s|
  s.name             = 'motion_camera'
  s.version          = '0.1.0'
  s.summary          = 'Native camera → MediaPipe pose bridge for the Yula Motion family.'
  s.description      = <<-DESC
Streams 33-landmark pose frames from the camera into motion_core's
PoseSourceDriver contract. MediaPipeTasksVision pinned at 0.10.21 (M-L-02);
upgrades are deliberate, never automatic.
                       DESC
  s.homepage         = 'https://yulalab.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Yula Lab' => 'dev@yulalab.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  # M-L-02 pin — exact, not pessimistic (~>): a silent 0.10.x bump is a model
  # behavior change and must arrive as a deliberate family decision.
  s.dependency 'MediaPipeTasksVision', '0.10.21'
  s.platform = :ios, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
