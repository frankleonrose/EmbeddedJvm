#!/bin/sh

#  EmbeddedJvm/CopyJavaToPluginsFolder.sh
#  Copyright (c) 2014 Futurose. All rights reserved.

copyTo=$BUILT_PRODUCTS_DIR/$PLUGINS_FOLDER_PATH
# Make certain that copyTo directory exists
[ -d $copyTo ] || mkdir -p $copyTo

javaBundle=$1
[ -n "$javaBundle" ] || javaBundle=$(cd $JAVA_HOME/../..; pwd)
[ -n "$javaBundle" ] || echo CopyJavaToPluginsFolder.sh needs parameter or JAVA_HOME set in environment
[ -n "$javaBundle" ] || exit 1

valid="YES"
[ -d "$javaBundle/Contents" -a -d "$javaBundle/Contents/Home" -a -f "$javaBundle/Contents/Home/COPYRIGHT" ] || valid="NO"
if [ $valid = "NO" ]
then
  echo "The directory $javaBundle does not appear to be a valid JRE or JDK bundle"
exit 1
fi

# Copy or Link jre to copyTo
if [ $CONFIGURATION = "Release" ]
then
  echo Copying $javaBundle to $copyTo
# a: archive.  "Preserve almost everything"
  rsync -a "$javaBundle" "$copyTo/"

  appJREBundle="$copyTo"/$(basename "$javaBundle")
  javaInfoPlist="$appJREBundle/Contents/Info.plist"

  # Remove the two files referring to the now-deprecated (10.9) QTKit
  # otool -L $appJREBundle/Contents/Home/jre/lib/*dylib | grep QTKit should yield nothing
  rm -f $appJREBundle/Contents/Home/lib/libgstplugins-lite.dylib
  rm -f $appJREBundle/Contents/Home/lib/libjfxmedia.dylib
else
  echo Linking $javaBundle to $copyTo
# s: symbolic link
# h: target is already a symbolic link, do not follow it.  Because we want to replace.
# f: force.  Unlink the target file if it already exists.
# F: unlink directory. Even if target is a directory, unlink it so the link may occur.
  ln -shfF "$javaBundle" "$copyTo/"
fi


####### Copy build java files (if any specified) to app/Contents/Resources/Java
# Classpaths may be specified as $APP_JAVA/my.jar and they will point to this folder.
shift
copyTo=$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Java
# Make certain that copyTo directory exists
[ -d $copyTo ] || mkdir -p $copyTo

for ((i=0; i < SCRIPT_INPUT_FILE_COUNT ; i++)) ; do
  inputFile=`eval echo '$SCRIPT_INPUT_FILE_'$i`
  if [ -e $inputFile ] ; then
    echo Copying $inputFile to $copyTo
    rsync -az "$inputFile" "$copyTo"
  fi
done


######## Sign code
# Per discussion here: http://mail.openjdk.java.net/pipermail/macosx-port-dev/2012-August/004771.html
# and http://www.bornsleepy.com/bornsleepy/signing-nested-app-bundles
if [ $CONFIGURATION = "Release" ]
then
  cd $PROJECT_DIR
  CODESIGN_ALLOCATE=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate

  entitlements=$PROJECT_DIR/$CODE_SIGN_ENTITLEMENTS

  appIdentifier=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH")
  jarPath=$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Java
  echo Signing all .jar files in $jarPath with $appIdentifier
  find "$jarPath" -type f \( -name "*.jar" -or -name "*.dylib" -or -name "Info.plist" \) -exec codesign --verbose=4 --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements" --identifier "$appIdentifier" {} \;

  jreIdentifier=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$javaInfoPlist")

  # Codesign materializes links, so we explicitly DO NOT sign $appJREBundle, because that would
  # change the jre/Contents/MacOS/libjli.dylib symbolic link to a real file, which causes the JVM's relative
  # path logic to fail to find libjava.dylib.
  # Learned about materialization here: https://lists.macosforge.org/pipermail/macruby-devel/2012-June/008839.html
  echo Signing all .jar and dylib files in $appJREBundle with identifier $jreIdentifier
  find "$appJREBundle/Contents/Home" -type f \( -name "*.jar" -or -name "*.dylib" -or -name "Info.plist" \) -exec codesign --verbose=4 --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements" --identifier "$jreIdentifier" {} \;
fi
