platform :tvos, '16.0'

target 'Moonfin' do
  use_frameworks!
  pod 'TVVLCKit', '~> 3.0'
  pod 'ZIPFoundation', '~> 0.9'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
