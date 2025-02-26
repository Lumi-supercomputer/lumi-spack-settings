#! /bin/bash
#
# Script to do a single synchronization of the /appl/lumi/spack subdirectories
# It will only add stuff except for modules: Modules that are deleted from the
# master copy, will also be deleted everywhere else, and the etc directory will
# also be cleaned up.
#
# Another script should be used later to clean up all directories once in a while,
# but it is dangerous to delete software right after cleaning up the module as 
# users may still be running with that software.
#

main_appl='/pfs/lustref1/appl/lumi'
destinations=( '/pfs/lustrep1/appl/lumi' '/pfs/lustrep2/appl/lumi' '/pfs/lustrep3/appl/lumi' '/pfs/lustrep4/appl/lumi' )
dest_short=(   'lustrep1'                'lustrep2'                'lustrep3'                'lustrep4' )
destinations_git=( '/pfs/lustrep1/appl/lumi' )
dest_git_short=(   'lustrep1' )

logdir="$HOME/appl_sync_logs"
mkdir -p $logdir
logfile="$(date --iso-8601=seconds).txt"

#
# Ask for confirmation. We may want to remove this once we have a more final solution.
#
echo -e "\nCopying Spack software installation from $main_appl/spack, are you sure?"
select yn in "Yes" "No"
do
    case $yn in
        No ) exit  ;;
        * )  break ;;
    esac
done

#
# First step: Sync the complete Spack directories, but don't delete anything for now.
#
printf "\nPushing the spack directory, but not deleting anything...\n"
for i in "${!destinations[@]}"
do
    destination="${destinations[$i]}"
    echo "- Starting the sync of from $main_appl/spack to $destination/spack."
    mkdir -p $destination/spack
    rsync --archive --exclude '.git*' $main_appl/spack/ $destination/spack/ >& "$logdir/${dest_short[$i]}_$logfile" &
done
wait
echo "Done"

#
# Second step: Clean up the modules directories with names similar to
# 23.03/0.19.2/share/spack/modules.
#
cd "$main_appl/spack"
printf "\nCleaning up the system spack module directories...\n"
for directory in $(lfs find . -name modules -maxdepth 5 | egrep "\./[[:digit:]]{2}.[[:digit:]]{2}" | sed -e 's|./||')
do
    echo "Cleaning $directory"
    for i in "${!destinations[@]}"
    do
        destination="${destinations[$i]}"
        echo "- Starting the sync with delete from $main_appl/spack/$directory to $destination/spack/$directory."
        mkdir -p $destination/spack/$directory
        rsync --archive --delete $main_appl/spack/$directory/ $destination/spack/$directory/ >& "$logdir/${dest_short[$i]}_$logfile" &
    done
    wait
    echo "Done"
done

#
# Third step: Sync the etc subdirectory, minus the git data structures.
#
directory='etc'
printf "\nPushing the $directory directory...\n"
for i in "${!destinations[@]}"
do
    destination="${destinations[$i]}"
    echo "- Starting the sync from $main_appl/spack/$directory to $destination/spack/$directory."
    mkdir -p $destination/spack/$directory
    rsync --archive --delete --exclude '.git*' "$main_appl/spack/$directory/" "$destination/spack/$directory/" >& "$logdir/${dest_short[$i]}_$logfile" &
done
wait
echo "Done"

#
# Fourth step: Synchronise the git repository to lustrep1.
#
directory='etc/.git'
printf "\nPushing the $directory directory...\n"
for i in "${!destinations_git[@]}"
do
    destination="${destinations_git[$i]}"
    echo "- Starting the sync from $main_appl/spack/$directory to $destination/spack/$directory."
    mkdir -p $destination/$directory
    rsync --archive --delete "$main_appl/spack/$directory/" "$destination/spack/$directory/" >& "$logdir/${dest_git_short[$i]}_$logfile" &
done
wait
echo "Done, sync completed"
