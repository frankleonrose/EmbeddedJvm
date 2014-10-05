#!/bin/sh

#  EmbeddedJvm/CopyJavaToPluginsFolder.sh
#  Copyright (c) 2014 Futurose. All rights reserved.

pluginsPath=$BUILT_PRODUCTS_DIR/$PLUGINS_FOLDER_PATH
# Make certain that pluginsPath directory exists
[ -d $pluginsPath ] || mkdir -p $pluginsPath

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

# Copy or Link jre to pluginsPath
if [ $CONFIGURATION = "Release" ]
then
  echo Copying $javaBundle to $pluginsPath
# a: archive.  "Preserve almost everything"
  rsync -a "$javaBundle" "$pluginsPath/"

  appJREBundle="$pluginsPath"/$(basename "$javaBundle")
  javaInfoPlist="$appJREBundle/Contents/Info.plist"

  # Remove the two files referring to the now-deprecated (10.9) QTKit
  # otool -L $appJREBundle/Contents/Home/jre/lib/*dylib | grep QTKit should yield nothing
  rm -f $appJREBundle/Contents/Home/lib/libgstplugins-lite.dylib
  rm -f $appJREBundle/Contents/Home/lib/libjfxmedia.dylib
else
  echo Linking $javaBundle to $pluginsPath
# s: symbolic link
# h: target is already a symbolic link, do not follow it.  Because we want to replace.
# f: force.  Unlink the target file if it already exists.
# F: unlink directory. Even if target is a directory, unlink it so the link may occur.
  ln -shfF "$javaBundle" "$pluginsPath/"
fi


####### Copy build java files (if any specified) to app/Contents/Resources/Java
# Classpaths may be specified as $APP_JAVA/my.jar and they will point to this folder.
shift
jarPath=$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Java
# Make certain that jarPath directory exists
[ -d $jarPath ] || mkdir -p $jarPath

for ((i=0; i < SCRIPT_INPUT_FILE_COUNT ; i++)) ; do
  inputFile=`eval echo '$SCRIPT_INPUT_FILE_'$i`
  if [ -e $inputFile ] ; then
    echo Copying $inputFile to $jarPath
    rsync -az "$inputFile" "$jarPath"
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

  echo Signing all .jar files in $jarPath with $appIdentifier
  find "$jarPath" -type f \( -name "*.jar" -or -name "*.dylib" -or -name "Info.plist" \) -exec codesign --verbose=4 --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements" --identifier "$appIdentifier" {} \;

  jreIdentifier=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$javaInfoPlist")

  # Codesign used to materialize links, which changed the jre/Contents/MacOS/libjli.dylib symbolic link to a real file,
  # which causes the JVM's relative path logic to fail to find libjava.dylib.
  # Learned about materialization here: https://lists.macosforge.org/pipermail/macruby-devel/2012-June/008839.html
  # Now (2014-10-04, 10.9.5, Xcode 6.0.1) codesign simply refuses to sign an executable that is a symlink.
  # The solution is to remove the symlink, edit the Info.plist to point directly to libjli.dylib,
  # and then sign the whole jre.
  echo Redirecting JRE executable
  rm "$appJREBundle/Contents/MacOS/libjli.dylib"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ../Home/lib/jli/libjli.dylib" "$javaInfoPlist"\

  echo Signing $appJREBundle with identifier $jreIdentifier
  codesign --verbose --verbose --force --deep --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements" --identifier "$jreIdentifier" "$appJREBundle"
fi
