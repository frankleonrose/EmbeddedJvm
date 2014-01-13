Pod::Spec.new do |s|
  s.name         = "EmbeddedJvm"
  s.version      = "0.0.9"
  s.summary      = "EmbeddedJvm simplifies communicating with an embedded JVM."
  s.description  = <<-DESC
                   EmbeddedJvm loads a JRE into an Objective-C app and presents
                   a block-based API for calling Java or other JVM based code.
                    DESC
  s.homepage     = "http://github.com/esorf/EmbeddedJvm"
  s.license      = 'MIT'
  s.author       = { "Frank Leon Rose" => "frankleonrose@gmail.com" }
  s.social_media_url = 'https://twitter.com/frankleonrose'
  
  s.platform     = :osx, '10.7'

  s.source       = { :git => "https://github.com/esorf/EmbeddedJvm.git", :tag => "v#{s.version}" }
  s.source_files  = 'EmbeddedJvm/**/*.{h,m,mm}', 'CopyJavaToPluginsFolder.sh', 'LICENSE.md'

  s.library = 'stdc++'
  s.requires_arc = true
  s.compiler_flags = '-DOS_OBJECT_USE_OBJC=0'
end
