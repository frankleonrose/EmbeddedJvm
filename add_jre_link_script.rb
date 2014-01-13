require 'xcodeproj'
project = Xcodeproj::Project.open(path_to_project)
main_target = project.targets.first
phase = main_target.new_shell_script_build_phase("Link JVM files to app")
phase.shell_script = "mkdir Plugins ; mkdir Plugins/Java ; do sth with ${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/your.file"
project.save()
