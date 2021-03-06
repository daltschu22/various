#!/bin/bash

#Defineables
threads=20

#These shouldnt change
log_dir="/broad/stops/ecs-migration/logs"
s3cmd='/home/unix/daltschu/git/archive-cli/s3cmd/s3cmd -c /home/unix/daltschu/git/archive-cli/.s3cfg_osarchive'
project='broad-archive-legacy'
gsutil='/home/unix/daltschu/google-cloud-sdk/bin/gsutil'
bucket=
config_file='/home/unix/daltschu/.config/rclone/rclone.conf'
range=

#Location of boto file that contains credentials for ecs and google.
BOTOFILE=/broad/stops/ecs-migration/.boto_ecs

#Using this cloud sdk config folder DOESNT WORK. Just use the boto.
#CONFIG_FOLDER=/broad/stops/ecs-migration/

#eval export DK_ROOT="/broad/software/dotkit"; . /broad/software/dotkit/ksh/.dk_init
#use -q Google-Cloud-SDK
#use -q Python-2.7

#Ask yes or no, return 1 for yes, 0 for no
GetYN() {
        while true; do
                echo -n "[Y]es or [N]o? "
                read FINAL
                case $FINAL in
                        y | Y | yes | Yes) result=1; break ;;
                        n | N | no | No) result=0; break ;;
                esac
        done
}

#Lists directories in an s3 path
S3_List(){
if [ "$range" == 1 ] ; then
    first="$( echo $up_sel | cut -d '-' -f 1 )"
	last="$( echo $up_sel | cut -d '-' -f 2 )"
	for ((i=$first;i<=$last;i++)); do
    	echo "$i: ${dirs[$i]}"
    done
else
    num=0
    readarray -t dirs <<< "$( $s3cmd ls $1 | sed 's/.*s3:/s3:/' )"
        for dir in "${dirs[@]}" ; do
    	       if [ $num -eq 0 ]; then
    		             echo "0 - $dir"
                         num=$((num+1))
    	       else
    		             echo "$num - $dir"
    		                   num=$((num+1))
                fi
        done
fi
}

#loops directories in the array returned from S3_List, then uploads each one.
Upload(){
if [ "$range" == 1 ] ; then
	first="$( echo $up_sel | cut -d '-' -f 1 )"
	last="$( echo $up_sel | cut -d '-' -f 2 )"
	for ((i=$first;i<=$last;i++)); do
		echo "Uploading - ${dirs[$i]}"
		sub_dir=${dirs[$i]}
		sub_dir_clean="$( echo $sub_dir | sed s'|s3://||' )"
		sub_dir_log="$( echo $sub_dir_clean | sed 's:/*$::' )"
		mkdir -p $log_dir/$sub_dir_clean
		rclone copy -v --config $config_file --transfers $threads ecs:$sub_dir_clean gcs:broad-ecs-$sub_dir_clean &> $log_dir/$sub_dir_log/upload.log &
	done
	else for dir in "${dirs[@]}"; do
      	 	#CLOUDSDK_CONFIG=$CONFIG_FOLDER
       		sub_dir=$dir
        	sub_dir_clean="$( echo $sub_dir | sed s'|s3://||' )"
		sub_dir_log="$( echo $sub_dir_clean | sed 's:/*$::' )"
        	mkdir -p $log_dir/$sub_dir_clean
        	#echo "BOTO_CONFIG=$BOTOFILE $gsutil -m rsync -r $bucket_lower gs://broad-ecs-$bucket_clean &> $log_dir/$bucket_clean.log"
		echo "Running sync of $dir to gs://broad-ecs-$sub_dir_clean"
        	#BOTO_CONFIG=$BOTOFILE $gsutil $multithread rsync -r $dir gs://broad-ecs-$sub_dir_clean &> $log_dir/$sub_dir_clean/upload.log &
    		rclone copy -v --config $config_file --transfers $threads ecs:$sub_dir_clean gcs:broad-ecs-$sub_dir_clean &> $log_dir/$sub_dir_log/upload.log &
		done
fi
}

#Displays top level buckets
echo -e "\nPlease select a bucket by number:\n"
S3_List
echo ""

#Asks user to pick bucket
read -p "Which bucket:" num_sel

#Pick an in bound number
until [ "$num_sel" -le "${#dirs[@]}" ]
do
	if [ "$num_sel" -gt "${#dirs[@]}" ]; then
		echo -e "not a valid bucket!\n"
		read -p "Which bucket:" num_sel
	fi
done

bucket="$( echo ${dirs[$num_sel]} )"
bucket_lower="$( echo $bucket | tr "[:upper:]" "[:lower:]" )"
bucket_clean="$( echo $bucket_lower | sed s'|s3://||' )"

echo -e "\nYou chose $bucket \n"

echo -e "Would you like to drill down?"
GetYN

#Makes a bucket in gsutil with the same name as in ECS but lowercase
#num2=0
#if [ $result -eq 1 ]; then
#	echo -e "Making bucket (Will be converted to lowercase) ...."
#	#CLOUDSDK_CONFIG=$CONFIG_FOLDER
#	BOTO_CONFIG=$BOTOFILE $gsutil -q mb -c coldline -p $project gs://broad-ecs-$bucket_clean
#else
#	exit
#fi

#List the files inside the bucket you selected
echo -e "\nHere are the files to upload: "
S3_List $bucket

read -p "Either type A for all files, or select a range of directories to upload (4-12), or drill down into a subdir: " up_sel

regex='^(([0-9]+)-([0-9]+))$'

if [ "$up_sel" == "A" ]; then
	#Loops through the directories in the first level of the bucket and uploads each
	echo "Uploading all files..."
	Upload $dirs
elif [[ "$up_sel" =~ $regex ]]; then
	range=1
	echo "The range of files is $up_sel"
	S3_List $up_sel $range $dirs
	echo "Would you like to upload these files?"
	result=0
	GetYN
	if [ "$result" == 1 ]; then
		Upload $up_sel $range $dirs
	fi

else
	sub_dir=${dirs[$up_sel]}
	echo "The list of files inside $sub_dir is:"
	S3_List $sub_dir
	echo "Would you like to upload these files?"
	result=0
	GetYN
	if [ "$result" == 1 ]; then
		#Drill down one level and do the same as above
		Upload $dirs
	elif [ "$result" == 0 ]; then
		echo "exiting"
		exit
	fi
fi
