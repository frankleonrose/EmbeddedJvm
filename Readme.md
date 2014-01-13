EmbeddedJvm Framework
=====================

How to Use
------------

1. Add EmbeddedJvm to your Podfile

2. Add script step to copy JRE to application PlugIns folder.
  a. Editor > Add Build Phase > Add Run Script Build Phase
  b. Specify the 'CopyJavaToPluginsFolder.sh' script with optional parameter pointing
     to the JRE you would like to embed.  If no parameter is specified, the script
     using $JAVA_HOME by default.
  c. Add the "--deep" option to Other Code Signing Flags.  Otherwise codesign chokes on the JRE.

(If anyone knows how to do step 2 within the podspec, lemme know!)

Copyright (c) 2014 Futurose
