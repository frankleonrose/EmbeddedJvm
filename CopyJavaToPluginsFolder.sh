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
# v: verbose
# z: compress
  rsync -avz "$javaBundle" "$copyTo/"
else
  echo Linking $javaBundle to $copyTo
# s: symbolic link
# v: verbose
# h: target is already a symbolic link, do not follow it.  Because we want to replace.
# f: force.  Unlink the target file if it already exists.
# F: unlink directory. Even if target is a directory, unlink it so the link may occur.
  ln -shvfF "$javaBundle" "$copyTo/"
fi


####### Copy build java files (if any specified) to app/Contents/Resources/Java
# Classpaths may be specified as $APP_JAVA/my.jar and they will point to this folder.
shift
copyTo=$BUILT_PRODUCTS_DIR/$JAVA_FOLDER_PATH
# Make certain that copyTo directory exists
[ -d $copyTo ] || mkdir -p $copyTo

for f in $@
do
  if [ $CONFIGURATION = "Release" ]
  then
    echo Copying $f to $copyTo
    rsync -avz "$f" "$copyTo"
  else
    echo Linking $f to $copyTo
    ln -shvfF "$f" "$copyTo"
  fi
done