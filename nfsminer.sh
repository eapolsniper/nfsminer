#!/bin/bash

logfile="nfsscanner.log"
projectprefix=`date +Results_%d%b%Y_%Hh%Mm%Ss`
singlescan=0
scanfile=0
dt=0
ft=0
gt=0
disablescans=0
disablefilescans=0
enablegrepscans=0
disableunmount=0

#Command Line Options
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--help)
	echo "<HELP>"
    	echo "NFS Miner"
	echo "Created by Tim Jensen @eapolsniper"
	echo "BSI CSIR - bsigroup.com"
	echo ""
	echo "---------------------"
	echo ""
	echo "-t   --  Text file containing a list of IP's to scan. All exports on each host is scanned."
	echo "-s   --  Single host to scan. Scans all exports on host"
	echo "-dt  --  Discovery Timeout. Useful for slow networks to skip over very slow hosts. Default 5 seconds."
    	echo "-ft  --  File Scan Timeout. Sets maximum scan timeout for recursive filetype discovery, per host.  Default 10 minutes."
	echo "-df  --  Disables all file scanning, only discovers exports and lists top directory lists. This is very fast."
	echo "-du  --  Disables unmounting of all shares, allowing easy manual discovery/searching without having to remount the drives again."
	echo ""
	echo "----------------------"
	echo "SLOW (I warned you) options"
	echo "----------------------"
	echo ""
	echo "-eg  --  Enable grep scans. Recursively searches all files for keywords"
	echo "-gt  --  Grep scan timeout. Set maxiumum scan time for recursive grep scans, per host. Default 10 minutes."
	echo ""
	echo ""
	echo "</HELP>"
	echo ""
	shift # past argument
    	shift # past value
    	;;
    -t|--targetfile)
    	targetfile="$2"
    	scanfile=1
    	echo "Target File is: $targetfile"
    	shift # past argument
    	shift # past value
    	;;
    -s|--singlehost)
    	hosttoscan="$2"
    	singlescan=1
    	scanip="$2"
    	shift # past argument
    	shift # past value
    	;;
    -dt|--discoverytimeout)
	dt=1
	dtimeout=$2
	shift
	shift
	;;
    -ft|--filescantimeout)
	ft=1
	ftimeout=$2
    	shift
	shift
	;;
    -gt|--grepscantimeout)
    	gt=1
	gtimeout=$2
	shift
	shift
	;;
    -ds|--disablescans)
	disablescans=1
	shift
	;;
    -df|--disablefilescans)
    	disablefilescans=1
	shift
	;;
    -eg|--enablegrepscans)
	enablegrepscans=1
	shift
	;;
    -du|--disbaleunmount)
	disableunmount=1
	shift
	;;
 	
    *)    # unknown option
	    echo "unknown option included. Try Harder."
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

#ID Generation
generate_dirname () {
	dirid=(`num=$((\`date +%s\` * $RANDOM)); echo $num | sha256sum | base64 | head -c 20`)
	#echo "DIR ID is: $dirid"
}

exporttest () {
	exportresult=0
	if [ $dt -eq 0 ]
	then
	#Standard showmount timeout of 5 seconds. If $dt is set by command line then the value presented by the user is accepted.
	dtimeout=5
	fi
	if [[ $(timeout -k 1 $dtimeout showmount -e $scantarget 2>&1) == *"Export list"* ]]
	then	
		exportresult=1
		echo "Exports available on $scantarget!"
	else
		echo -e "\e[31mNo accessible Exports on $scantarget or timeout exceeded. Skipping host\e[0m"
	fi
}

dismount () {
	if [ $disableunmount -eq 0 ] 
	then
		umount $scandir

		if [ "$(ls -A $scandir)" ]
		then
			echo "Not Deleting $scandir, not empty. dismount may have failed!"
		else
			#echo "unmounting drive $scandir"
		rm -rf $scandir
		fi
	else
		echo -e "\e[33m\tLeaving $scantarget:$exporttarget mounted at $scandir \e[0m"
	fi

}


targetscan () {
	#echo "Checking $scantarget for exports"
	exporttest
	if [ $exportresult -eq 1 ]
	then
		echo "Exports found on $scantarget. Scanning exports."
		#Gather list of exports for the scan target
		for exporttarget in `timeout -k 1 $dtimeout showmount -e $scantarget | cut -d" " -f 1 | grep -v "Export"`
		do
			#Generate a Directory Name
			generate_dirname
			#Setup Scanfile Log Name
			local hostscanlog=$(echo $scantarget | sed -e 's/\./\_/g')
			local hostscanlog="$projectprefix/$hostscanlog.log"
			#Attempt to Mount the exports
			scandir="/mnt/nfscanner/$dirid"
			if [ -d $scandir ]
			then
				echo "Directory $scandir already exists. Trying to generate a new mount point."
				generate_dirname
				scandir="/mnt/nfsscanner/$dirid"
			fi
			mkdir -p $scandir
			local drivestatus=0
			if [ "$(ls -A $scandir)" ]
			then
				#echo "Mountpoint $scandir is not empty!"
				drivestatus=1
			fi
		
			echo "Mounting $scantarget:$exporttarget to $scandir" >> $hostscanlog
			local mountsuccess=0
			if [ -z $(mount -o ro $scantarget:$exporttarget $scandir) ]
			then
				local  mountsuccess=1
				echo "Export $exporttarget should have mounted fine" >> $hostscanlog
			else
				echo "Drive failed to mount" >> $hostscanlog
			fi
			if [ $mountsuccess -eq 1 ]
			then
			if [ "$(ls -A $scandir)" ]
			then
				#Determining NFSv3 or V4 based on port (2048 vs 2049)
				nfsport="NFS"
				if nc -z $scantarget 2048
				then
					echo "Port 2048 in use" >> $hostscanlog
					nfsport="2048"
					nfsprot="NFSv3"
				fi
				
				if nc -z $scantarget 2049
				then
					echo "port 2049 in use" >> $hostscanlog
					nfsport="2049"
					nfsprot="NFSv4"
					fi
				echo -e "\e[33m\tExport $scantarget:$exporttarget mounted and has data in it!\e[0m"
				echo -e "$scantarget\t$nfsport\t$nfsprot\t$exporttarget" >> $projectprefix/exportsWithData.txt
			else
				echo "Export is empty!"
			fi
			fi

			#Do scanning things on the export
			echo "ls of $scandir" >> $hostscanlog
			echo "--------------" >> $hostscanlog
			ls -alh $scandir >> $hostscanlog
			echo "--------------" >> $hostscanlog
			echo "Capturing 3 layers of $scantarget:$exporttarget to $hostscanlog.verbose"
			exportshort=$(echo $exporttarget | sed -r 's/^.{1}//' | sed -e 's/\//_/g')
			if [ -z $exportshort ]
			then
				exportshort="DRIVEROOT"
			fi

			echo "3 layers of $scantarget:$exporttarget" >> $hostscanlog.$exportshort.verbose
			find $scandir -maxdepth 3 2>/dev/null >> $hostscanlog.$exportshort.verbose
			echo "--------------" >> $hostscanlog.$exportshort.verbose
			
			if [ $disablescans -eq 0 ]
			then
				if [ $disablefilescans -eq 0 ]
				then
				#Interesting File scan
				if test -f "filelist.txt"
				then
					local counter=0
					for filesearch in `cat filelist.txt`
					do
						if [ $counter -eq 0 ]
						then
							local filestring=$(echo "-iname $filesearch")
							local counter=1
						else
							local filestring=$(echo "$filestring -o -iname $filesearch")
						fi
					done

					#Checking for Timeout override. Default is 10 Minutes
					if [ $ft -eq 0 ]
					then
						ftimeout=10m
					fi
					#Loaded Find statement to look for interesting files:
					for findloot in `timeout -k 1 $ftimeout find $scandir \( $filestring \) 2>/dev/null`
					do
						echo -e "\e[92mPossible Interesting File Found: $findloot\e[0m" | tee $projectprevix/loot.txt
					done


				else
					echo "filelist.txt is missing, populate to test for interesting files on NFS exports!"
				fi
			fi

				if [ $enablegrepscans -eq 1 ]
				then
					#Grep Based File Contents Scan
					
					#Checking for Timeout override. Default is 10 minutes.
					if [ $gt -eq 0 ]
					then
						gtimeout=10m
					fi

					#Loaded Grep statement to look for contents of files:
					for greploot in `timeout -k 1 $gtimeout egrep -ir "pass=|password=|" $scandir 2>/dev/null`
					do
						local cleanloot=$(echo $greploot | cut -d"/" -f 5)
						echo -e "\e[92mPossible Interesting Content Found: $scantarget:$exporttarget/$cleanloot\e[0m"| tee $projectprefix/loot.txt
					done
				fi
			fi

			#Unmount the export
			echo $scandir
			dismount

		done
		
	fi
}

testcases () {
ls $scandir
}




#MAIN

if [ $scanfile -eq 1 ]
then
	#targetfile process
	#echo "Scan File Chosen: $targetfile"
	mkdir $projectprefix
	cp $targetfile $projectprefix/
	for scantarget in `cat $targetfile`
	do
		#echo "Starting scan on $scantarget"
		targetscan
	done
elif [ $singlescan -eq 1 ]
then
	#singlescan process
	#echo "Single Scan Chosen $scanip"
	scantarget=$scanip
	mkdir $projectprefix
	targetscan

else
	echo "No host information provided. Provide a targetfile (-t) or single host (-s)  to scan"
fi


