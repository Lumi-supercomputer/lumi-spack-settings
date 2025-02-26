# Scripts

-   `sync_appl_lumi_spack.sh`:  Sync the Spack installation from the master on the 
    flash file system on uan06 to the four lustrep file systems.
    
    This synchronisation will not delete software, but it will delete modules that 
    are no longer present in the master copy and also ensure the the copy of the 
    repository is cleaned. This is to ensure that programs that may be running 
    already, don't crash.
    
-   Some time after cleaning up removed modules, it may be a good idea to clean up
    the software too, and this is the goal of the 
    `sync_appl_lumi_spack_cleanup.sh` script. 
    
    Just to be sure, it first cleans up the modules, but then goes on to 
    clean up the whole Spack installation.
