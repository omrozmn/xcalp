Pod::Spec.new do |s|
  s.name         = "SensorCapabilityManager"
  s.version      = "0.1.0"
  s.summary      = "A short description of SensorCapabilityManager."
  s.description  = <<-DESC
                    A longer description of SensorCapabilityManager in Markdown format.
                   DESC
  s.homepage     = "https://github.com/your_github/SensorCapabilityManager"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author             = { "Your Name" => "email@example.com" }
  s.platform     = :ios, "17.0"
  s.swift_version = "5.9"
  s.source       = { :git => "https://github.com/your_github/SensorCapabilityManager.git", :tag => s.version.to_s }
  s.source_files  = "SensorCapabilityManager.swift"
end
