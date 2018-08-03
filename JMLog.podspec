Pod::Spec.new do |s|

s.name        = "JMLog"

s.version      = "1.0.0"

s.summary      = "log日志打印,支持Html远程查看"

s.homepage    = "https://github.com/jimmylen/JMLog"

s.license      = "MIT"

s.author      = { "jimmylen" => "jimmy_lem@163.com" }

s.platform    = :ios, "7.0"

s.source      = { :git => "https://github.com/jimmylen/JMLog.git", :tag => s.version }

s.source_files  = "JMLog", "JMLog/*.{h,m}"

s.framework  = "UIKit"

s.requires_arc = true

s.dependency 'PocketSocket', '~> 1.0.1'


end


