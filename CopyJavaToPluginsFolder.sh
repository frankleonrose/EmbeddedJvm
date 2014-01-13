#!/bin/sh

#  EmbeddedJvm/CopyJavaToPluginsFolder.sh
#  Copyright (c) 2014 Futurose. All rights reserved.

copyTo=$BUILT_PRODUCTS_DIR/$PLUGINS_FOLDER_PATH/Java
[ -d $copyTo ] || mkdir -p $copyTo

javaHome=$1
[ -n "$javaHome" ] || javaHome=$JAVA_HOME
[ -n "$javaHome" ] || echo CopyJavaToPluginsFolder.sh needs parameter or JAVA_HOME set in environment
[ -n "$javaHome" ] || exit 1
jre=$javaHome/jre

if [ $CONFIGURATION = "Release" ]
then
  echo Copying $jre to $copyTo
  rsync -avz $jre $copyTo
else
  echo Linking $jre to $copyTo
  ln -shvfF $jre $copyTo
fi