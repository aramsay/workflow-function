function setpid {
pidname=$1
pidfile=/var/run/$pidname.pid
if [ -e $pidfile ]; then
        pid=`cat $pidfile`
        if kill -0 $pid > /dev/null 2>&1 ; then
                echo "Already running"
                exit 1
        else
                rm $pidfile
        fi
fi
echo $$ > $pidfile
trap 'rm -f "$pidfile"; exit $?' INT TERM EXIT
}
# the real stuff starts now

function get_list_smb {
# call function passing "host" "volume" "authfile" "remote location" "mask file" "max number of files" and "temporary storage file"
if [ $# -ne 7 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi
local host=$1
local volume=$2
local authfile=$3
local remote_loc=$4
local mask_file=$5
local max_files=$6
local tmp_file=$7
        # get list of top 100 files matching expression below
        smbclient //$host/$volume -A $authfile -D $remote_loc -c "ls" 2> /dev/null | awk '{print substr($0,1,length($0)-38)}' | sed 's/ *$//' | grep -i -f $mask_file | sed 's/^[ \t]*//;s/^/\"/;s/[ \t]*$//;s/$/\"/;' | head -$max_files 1> $tmp_file
        if [ $? -ne 0 ]; then
                echo "`date` - *******Something went wrong with $FUNCNAME function" >> $log_file
                exit 5
        fi
}

function get_list_local {
# call function passing "local location" "mask file" "max number of files" and "temporary storage file"
if [ $# -ne 4 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi
local local_loc=$1
local mask_file=$2
local max_files=$3
local tmp_file=$4
        pushd $local_loc
        echo "`date` - Getting list of files from $local_loc" >> $log_file
        find . -maxdepth 1 -type f | cut -f2- -d'/' |  grep -i -f $mask_file | sort | sed 's/^[ \t]*//;s/^/\"/;s/[ \t]*$//;s/$/\"/;' | head -$max_files > $tmp_file
        if [ $? -ne 0 ]; then
                echo "`date` - *******Something went wrong with the $FUNCNAME function" >> $log_file
                exit 6
        fi
        echo "`date` - Got list of files from $local_loc" >> $log_file
        popd
}

function copy_to_smb {
# call function passing "local location" "host" "volume" "authfile" "remote location" "filename"
if [ $# -ne 6 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi
local local_loc=$1
local host=$2
local volume=$3
local authfile=$4
local remote_loc=$5
local filename=$6
        pushd $local_loc
        echo "`date` - About to copy to smb $filename" >> $log_file
        smbclient //$host/$volume -A $authfile -D $remote_loc -E -c "prompt; mput $filename" >> $log_file
        if [ $? -ne 0 ]; then
                echo "`date` - *******Something went wrong with the $FUNCNAME function " >> $log_file
                exit 7
        fi
        echo "`date` - Copy to smb successful for $filename" >> $log_file
        popd

}

function copy_to_smb_rename {
# call function passing "local location" "host" "volume" "authfile" "remote location" "filename" "newfilename"
if [ $# -ne 7 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi
local local_loc=$1
local host=$2
local volume=$3
local authfile=$4
local remote_loc=$5
local filename=$6
local newfilename=$7
        pushd $local_loc
        echo "`date` - About to copy to smb $filename" >> $log_file
        smbclient //$host/$volume -A $authfile -D $remote_loc -E -c "prompt; put $filename $newfilename" >> $log_file
        if [ $? -ne 0 ]; then
                echo "`date` - *******Something went wrong with the $FUNCNAME function " >> $log_file
                exit 7
        fi
        echo "`date` - Copy to smb successful for $filename" >> $log_file
        popd

}

function copy_from_smb {
# call function passing "local location" "host" "volume" "authfile" "remote location" "filename"
if [ $# -ne 6 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi

local local_loc=$1
local host=$2
local volume=$3
local authfile=$4
local remote_loc=$5
local filename=$6
pushd $local_loc
        echo "`date` - About to copy from smb $filename" >> $log_file
        smbclient //$host/$volume -A $authfile -D $remote_loc -E -c "prompt; mget $filename"
        if [ $? -ne 0 ]; then
                echo "`date` - *******Something went wrong with the $FUNCNAME function $filename " >> $log_file
                exit 8
        fi
        echo "`date` - Copy from smb successful for $filename" >> $log_file
        echo $filename
        chown cacheusr:cacheusr $filename
        popd
}
function move_smb {
# call function passing "host" "volume" "authfile" "remote source location" "remote dest location" "filename" "move or delete"
if [ $# -ne 7 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi

local host=$1
local volume=$2
local authfile=$3
local remote_source_loc=$4
local remote_dest_loc=$5
local filename=$6
local move_or_delete=$7
        if [ $move_or_delete -eq 1 ]; then
                echo "`date` - About to move on smb $filename" >> $log_file
                file_rename=1
		date_string=`date +"%Y%m%d%H%M%S"`
                smbclient //$host/$volume -A $authfile -D $remote_source_loc\\$remote_dest_loc -E -c "rename $filename $filename.old.$date_string"
                if [ $? -ne 0 ]; then
                        echo "`date` - Didnt find prexisting remote file to remove, so carrying on anyway " >>$log_file
                        file_rename=0
                fi
                smbclient //$host/$volume -A $authfile -D $remote_source_loc -E -c "rename $filename $remote_dest_loc\\$filename"
                if [ $? -ne 0 ]; then
                        echo "`date` - *******Something went wrong with the $FUNCNAME remote rename function $filename " >>$log_file
                        if [ $file_rename = 1 ]; then
                                smbclient //$host/$volume -A $authfile -D $remote_source_loc\\$remote_dest_loc -E -c "rename $filename.old $filename"
                                if [ $? -ne 0 ]; then
                                        echo "`date` - *******Something went wrong with the $FUNCNAME trying to put old file back" >>$log_file
                                fi
                        fi
                        exit 9
                fi
                if [ $file_rename -eq 1 ]; then
                        smbclient //$host/$volume -A $authfile -D $remote_source_loc\\$remote_dest_loc -E -c "rm $filename.old"
                fi
                echo "`date` - Move on smb successful for $filename" >>$log_file
        else
                echo "`date` - About to delete on smb $filename" >> $log_file
                smbclient //$host/$volume -A $authfile -D $remote_source_loc -E -c "del $filename"
                if [ $? -ne 0 ]; then
                        echo "`date` - *******Something went wrong with the $FUNCNAME trying to delete $filename " >>$log_file
                        exit 8
                fi
                echo "`date` - Delete on smb successful for $filename" >>$log_file
        fi
}
function move_local {
# call function passing "original location" "new location" "filename" "move or delete"
if [ $# -ne 4 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi

local orig_loc=$1
local new_loc=$2
local filename=$3
local move_or_delete=$4
local old_ifs=$IFS
IFS=$'
'
local new_filename=`echo $filename | sed 's/^"//;s/"$//'`
pushd $orig_loc
        if [ $move_or_delete -eq 1 ]; then
                echo "`date` - About to move on local $new_filename" >> $log_file
                file_rename=0
                if [ -f "$new_loc/$filename" ]; then
                        echo "`date` - Found existing file on local system - removing " >>$log_file
                        mv -- "$new_loc/$new_filename" "$new_loc/$new_filename.old"
                        file_rename=1
                fi
                mv -- "$orig_loc/$new_filename" $new_loc/
                if [ $? -ne 0 ]; then
                        echo "`date` - *******Something went wrong with the $FUNCNAME locate rename function " >>$log_file
                        if [ $file_rename -eq 1 ]; then
                                mv -- "$new_loc/$new_filename.old" "$new_loc/$new_filename"
                                if [ $? -ne 0 ]; then
                                        echo "`date` - *******Something went wrong with the $FUNCNAME trying to put old file back" >>$log_file
                                fi
                        fi
                        exit 10
                fi
                if [ $file_rename -eq 1 ]; then
                        rm -- "$new_loc/$new_filename.old"
                fi
                echo "`date` - Move on local successful for $new_filename" >>$log_file
        else
                echo "`date` - About to delete on local $new_filename" >> $log_file
                rm -- $new_filename
                if [ $? -ne 0 ]; then
                        echo "`date` - *******Something went wrong with the $FUNCNAME trying to delete $new_filename " >>$log_file
                        exit 8
                fi
                echo "`date` - Delete on local successful for $new_filename" >>$log_file
        fi

IFS=$old_ifs
popd
}

function strip_quotes {
# call function passing "string to strip quote"
echo $1 | sed 's/^"//;s/"$//'
}

function check_local_filecount {
# call function passing "location" "max files"
if [ $# -ne 2 ]; then
        echo "`date` - *******Something went wrong - wrong number of parameters passed to $FUNCNAME" >> $log_file
        exit 99
fi
local local_loc=$1
local max_files=$2

        dest_file_counter=$(ls -l $local_loc | wc -l)
        if [ $dest_file_counter -gt $max_files ]; then
                echo "`date` - Too many files in destination - exiting" >> $log_file
                exit 11
        fi
        echo "`date` - Number of files in destination OK - continuing" >> $log_file
}

function send_to_slack {
	error_msg=payload={\\"""channel\\""":\\"""#server-monitor-alerts\\""",\\"""username\\""":\\"""webhookbot\\""",\\"""text\\""":\\"""Error detected on `uname -n` in script $(basename $0)\\""",\\"""icon_emoji\\""":\\""":ghost:\\"""}
	echo $error_msg
	#curl -X POST --data-urlencode 'payload={"channel": "#server-monitor-alerts", "username": "webhookbot", "text": "Error detected on `uname -n` in script $(basename $0)", "icon_emoji": ":ghost:"}' https://pcs-publishing.slack.com/services/hooks/incoming-webhook?token=zmhoAXB3LWR0QA6SFDSjqn8L
	curl -X POST --data-urlencode '$error_msg' https://pcs-publishing.slack.com/services/hooks/incoming-webhook?token=zmhoAXB3LWR0QA6SFDSjqn8L

	exit 100
}
