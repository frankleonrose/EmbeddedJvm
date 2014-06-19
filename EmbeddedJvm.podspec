Pod::Spec.new do |s|
  s.name         = "EmbeddedJvm"
  s.version      = "0.0.17"
  s.summary      = "EmbeddedJvm simplifies communicating with an embedded JVM."
  s.description  = <<-DESC
                   EmbeddedJvm loads a JRE into an Objective-C app and presents
                   a block-based API for calling Java, Scala, Clojure, or other 
                   JVM based code.
                    DESC
  s.homepage     = "http://github.com/esorf/EmbeddedJvm"
  s.license      = 'MIT'
  s.author       = { "Frank Leon Rose" => "frankleonrose@gmail.com" }
  s.social_media_url = 'https://twitter.com/frankleonrose'
  
  s.platform     = :osx, '10.7'

  s.source       = { :git => "https://github.com/esorf/EmbeddedJvm.git", :tag => "v#{s.version}" }

  s.library = 'stdc++'
  s.requires_arc = true
  s.compiler_flags = '-DOS_OBJECT_USE_OBJC=0'

  s.preserve_paths = 'Java/**/*.java', 'LICENSE.md'
  
  s.default_subspec = 'Core'
  
  s.subspec "Core" do |sp|
    sp.source_files  = 'EmbeddedJvm/*.{h,m,mm}', 'EmbeddedJvm/jdk/**/*.h', 'CopyJavaToPluginsFolder.sh'
  end

  s.subspec "Thrift" do |sp|
    sp.source_files = "EmbeddedJvm/Thrift/*.{h,m,mm}"
    sp.dependency "EmbeddedJvm/Core"
    sp.dependency 'thrift', '~> 0.9.1'
  end

  #subspec "Protobuf" do |sp|
  #  sp.source_files = "Classes/Pinboard"
  #  sp.dependency 'protobuf'
  #end
end
