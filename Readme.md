EmbeddedJvm Framework
=====================

How to Use
------------

1. Add EmbeddedJvm to your Podfile

2. Add script step to copy JRE to application PlugIns folder.
    a. Editor > Add Build Phase > Add Run Script Build Phase
    b. Specify the 'CopyJavaToPluginsFolder.sh' script with parameter pointing
       to the JRE or JDK you would like to embed.  The path will look like 
       "/Library/Java/JavaVirtualMachines/jre1.7.0_51.jre".
    c. Following the JRE or JDK path, add paths to .jar files you would like copied
       to the default app/Contents/Resources/Java folder.

3. Add the "--deep" option to Other Code Signing Flags.  Otherwise codesign chokes on the JRE.

4. Add a key to the app's main bundle (Info.plist) called "EmbeddedJvm" with the name
   of the JRE or JDK, like "jre1.7.0_51.jre".  (In the future, we will eliminate this step by
   scanning the Plugins folder for things that look like JREs.)

(If anyone knows how to add the script step within the podspec, lemme know!  You'd still have 
to manually add parameters, but it would be nice to give the pod user a helpful start.)

Copyright (c) 2014 Futurose
