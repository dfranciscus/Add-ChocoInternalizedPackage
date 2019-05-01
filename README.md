# Add-ChocoInternalizedPackage

## Take a look at Chocolatey-tools as a better solution for this - https://github.com/dfranciscus/Chocolatey-tools
Recompiles new Chocolatey packages to internal feed when new packages are released. This should be used on a test machine that has all of the packages that you want to recompile from the Chocolatey public feed.

For example, install all Chocolatey packages on one machine, and then run this function at a specified interval via Task Scheduler so that any new packages released on the Chocolatey public feed will be recompiled, installed on the test machine, and pushed to an internal repository.
