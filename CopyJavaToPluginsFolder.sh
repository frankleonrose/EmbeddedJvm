#!/bin/sh

#  CopyJavaToPluginsFolder.sh
#  EmbeddedJvm
#
#  Created by Frank on 2014/1/13.
#  Copyright (c) 2014 Futurose. All rights reserved.

linkTo=$BUILT_PRODUCTS_DIR/$PLUGINS_FOLDER_PATH/Java
[ -d $linkTo ] || mkdir -p $linkTo

javaHome=${1-$JAVA_HOME}
jre=$javaHome/jre

echo ====================
echo Linking $jre to $linkTo
rsync -avz $jre $linkTo
