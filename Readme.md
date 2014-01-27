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
    c. Add Input Files to the script step specifying paths of individual jar files
       and collections of .jar files you would like copied to the app/Contents/Java 
       folder.  Every .jar file in that folder will be included automatically in the
       classpath.

3. Add the "--deep" option to Other Code Signing Flags.  Otherwise codesign chokes on the JRE.

4. Add a key to the app's main bundle (Info.plist) called "JVMRuntime" with the name
   of the JRE or JDK, like "jre1.7.0_51.jre".  (In the future, we will eliminate this step by
   scanning the Plugins folder for things that look like JREs.)

(If anyone knows how to add the script step within the podspec, lemme know!  You'd still have 
to manually add parameters, but it would be nice to give the pod user a helpful start.)

The JVM loading code looks for properties in the applications bundle info dictionary (Info.plist).
- JVMRuntime - Example: jre1.7.0_51.jre
- JVMOptions - Example:
    - -XX:MaxPermSize=256m
    - -Xms200m
    - -Xmx1500m

Tips
- Use the -Xcheck:jni and -verbose:jni options while working out JNI issues
- Disable JIT compilation with -Djava.compiler=NONE when you encounter mysterious issues.

Code Sample
    NSError *error = nil;
    // Often no need to pass classpaths because default is generated from jars in app/Contents/Java
    // Options are read from JVMOptions in the Info.plist but may be passed as an array here
    EmbeddedJvm *jvm = [[EmbeddedJvm alloc] initWithClassPaths:nil options:nil error:&error];
    if (self.jvm==nil) {
        ... error handling ...
    }
    ...
    [jvm doWithJvmThread:^(JNIEnv *env) {
        ... block runs on attached JVM thread with valid env ...
    }];

Copyright (c) 2014 Futurose
