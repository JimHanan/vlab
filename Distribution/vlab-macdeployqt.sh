#!/bin/bash

vlabversion=$(../.binaries/version.app/Contents/MacOS/version)
vlabbuild=$(../.binaries/version.app/Contents/MacOS/version -b)
vlabname="vlab-$vlabversion"
oldrootdir="$vlabname"
rootdir="$vlabname-$vlabbuild-with-qt"

rm -rf $rootdir

cp -r $vlabname $rootdir

# Initialize the base macdeployqt command to gather all the Qt frameworks and helper apps
cmd="macdeployqt \"$rootdir/browser.app\" -codesign=-"

# Function to add -executable flags to cmd
add_executables() {
    local bundles=$1
    for bundle in $bundles; do
        # Get the bundle name without the .app extension (e.g., "vlabd")
        bundle_name=$(basename "$bundle" .app)
        # Construct path to the internal binary
        exec_path="$bundle/Contents/MacOS/$bundle_name"
        
        # Check if binary exists before adding to avoid macdeployqt errors
        if [ -f "$exec_path" ]; then
            cmd="$cmd -executable=\"$exec_path\""
        else
            echo "Warning: Binary not found at $exec_path"
        fi
    done
}

# list of all helper apps, like object, cpfg, lpfg, etc
pluginbundles=`find $rootdir/browser.app/Contents/Plug-ins -name '*.app' -type d -depth 1 -print`
echo bundles in plugins: $pluginbundles
  
systembundles=`find $rootdir/browser.app/Contents/System -name '*.app' -type d -depth 1 -print`
echo bundles in system: $systembundles

# Add bundles from both locations
add_executables "$pluginbundles"
add_executables "$systembundles"

# Execute the final macdeplotqt command
echo "Running: $cmd"
eval $cmd

# macdeployqt only writes a qt.conf (pointing at Contents/PlugIns) into the main
# browser.app bundle. The helper bundles under Plug-ins/ and System/ get their
# rpaths fixed via -executable= above, but without their own qt.conf they can't
# find the cocoa platform plugin and abort with "no Qt platform plugin could be
# initialized" the moment they try to create a QApplication. Give each helper
# bundle a qt.conf pointing back up at the main bundle's PlugIns directory.
echo "Adding qt.conf to helper bundles:"
add_qtconf() {
    local bundles=$1
    for bundle in $bundles; do
        mkdir -p "$bundle/Contents/Resources"
        cat > "$bundle/Contents/Resources/qt.conf" <<EOF
[Paths]
Plugins = ../../../PlugIns
EOF
        echo -n "."
    done
}
add_qtconf "$pluginbundles"
add_qtconf "$systembundles"
echo "OK"

# Adding files after macdeployqt's -codesign=- invalidates the seal it just
# applied, so re-sign the whole bundle (main app + all nested helper bundles)
# ad-hoc now that its contents are final.
echo "Re-signing bundle after adding qt.conf files..."
codesign --force --deep --sign - "$rootdir/browser.app"

# copy extra items to the distributable
echo "Copying oofs :"
pwd
cp -Rp ../oofs $rootdir

echo "Copying Gifts :"
pwd
cp -Rp ./Gifts $rootdir

echo "Copying README :"
pwd
cp -f README.mac $rootdir/README

# rename the folder and prepare to create DMG
if [ -d "$rootdir" ]; then
  echo -n "Renaming root directory: "
  if rm -Rf "$rootdir-native"; then
    echo -n '.'
  else
    echo "Error, cannot remove directory $rootdir-native"
    exit -2
  fi
  if mv "$rootdir" "$rootdir-native"; then
    echo "OK"
  else
    echo "Error, cannot rename directory $rootdir into $rootdir-native"
    exit -2
  fi
fi

  archname=native
  echo "Arch : $archname"
  archrootdir="$rootdir-$archname"
  # create a dmg file
  if [ -z "$dont_package" ]; then
    dmgfname="$vlabname-$vlabbuild-with-qt-$archname.dmg"
    echo -n "creating DMG $dmgfname..."
    rm -rf $dmgfname
    if hdiutil create -fs HFS+ -srcfolder $vlabname-$vlabbuild-with-qt-$archname -volname $vlabname-$vlabbuild-with-qt-$archname $dmgfname; then
      echo 'OK'
    else
      echo 'FAILED'
      exit 1
    fi
    echo `ls -l $dmgfname`
  fi



echo
echo "==========================================================="
echo "Bundle done."
echo "You may want to inspect the log: $deploylog"



