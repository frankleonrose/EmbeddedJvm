Pod::Spec.new do |s|
  s.name         = "EmbeddedJvm"
  s.version      = "0.0.7"
  s.summary      = "EmbeddedJvm simplifies communicating with an embedded JVM."
  s.description  = <<-DESC
                   I'm writing a native Mac app for sale in the Mac App Store, but
                   part of it is written in cross-platform Scala that needs a JVM.
                   In order to host a JVM there are details that don't change that you
                   have to get exactly right.  Sounds like a pod!
                   
                   The one thing I was not able to make the pod do is embed the actual
                   JRE in the target app's PlugIns directory.  But there is a shell
                   script included in the pod that will copy the appropriate files
                   into the right place.  You need to add a Run Script build phase
                   that runs the shell script and bundles the JRE you specify.
                    DESC
  s.homepage     = "http://github.com/esorf/EmbeddedJvm"
  s.license      = 'MIT'
  s.author       = { "Frank Leon Rose" => "frankleonrose@gmail.com" }
  s.social_media_url = 'https://twitter.com/frankleonrose'
  s.platform     = :osx, '10.7'
  s.source       = { :git => "https://github.com/esorf/EmbeddedJvm.git", :tag => "v#{s.version}" }
  s.source_files  = 'EmbeddedJvm/**/*.{h,m,mm}'
  s.preserve_paths = "CopyJavaToPluginsFolder.sh"
  s.library = 'stdc++'
  s.requires_arc = true
end
