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
# z: compress
  rsync -az "$javaBundle" "$copyTo/"

  # Codesign materializes symbolic links.  jre/Contents/MacOS/libjli.dylib is a symbolic link.
  # If it gets materialized, libjli.dylib can no longer find libjava.dylib.  So we need to
  # load libjli.dylib in its expected location so that it can find libjava.dylib in the directory
  # above.
  # Learned about materialization here: https://lists.macosforge.org/pipermail/macruby-devel/2012-June/008839.html
  javaInfoPlist="$copyTo"/$(basename "$javaBundle")/Contents/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Home/lib/jli/libjli.dylib" "$javaInfoPlist"
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