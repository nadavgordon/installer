#!/bin/bash

if [ -f "$CWMCONFIGFILE" ];
then

CONFIG=`cat $CWMCONFIGFILE`

IFS=$'\n'

for d in $CONFIG; 
do

    export `echo $d | cut -f 1 -d"="`="`echo $d | cut -f 2 -d"="`"

done

CWMSITE=$url
ADMINEMAIL=$email
ADMINPASSWORD=$password
ZONE=$zone
VMNAME=$name
WANNICIDS=`cat $CWMCONFIGFILE | grep ^vlan.*=wan-.* | cut -f 1 -d"=" | cut -f 2 -d"n"`
LANNICIDS=`cat $CWMCONFIGFILE | grep ^vlan.*=lan-.* | cut -f 1 -d"=" | cut -f 2 -d"n"`
DISKS=`cat $CWMCONFIGFILE | grep ^disk.*size=.* | wc -l`
UUID=`cat /sys/class/dmi/id/product_uuid | tr '[:upper:]' '[:lower:]'`

var=0

for nicid in $WANNICIDS;
do

    var=$((var+1))
    nicvar=ip${nicid}
    export `echo WANIP$var`=`echo ${!nicvar}`
    unset nicvar

done

var=0

for nicid in $LANNICIDS;
do

    var=$((var+1))
    nicvar=ip${nicid}
    export `echo LANIP$var`=`echo ${!nicvar}`
    unset nicvar

done

fi

# Function: updateServerDescription
# Purpose: Update CWM Server's Overview->Descriptoin text field.
# Usage: updateServerDescription "Some kind of description"

function updateServerDescription() {

    if [[ ! -z "$apiClientId" && ! -z "$apiSecret" ]];
    then

        curl -f -X PUT -H "AuthClientId: ${apiClientId}" -H "AuthSecret: ${apiSecret}"  "https://$CWMSITE/svc/server/$UUID/description" -d $'description='"$1"
        errorCode=$?

        if [ $errorCode != '0' ]; 
        then
		echo "Erorr updating server description" | log

	else 

	    echo "Updated Overview->Description data for $UUID" | log
        fi

    else

	echo "No API Client ID or Secret is set, description not set" | log

    fi

}


function getServerDescription() {

    if [[ ! -z "$apiClientId" && ! -z "$apiSecret" ]];
    then

        description=`curl -f -H "AuthClientId: ${apiClientId}" -H "AuthSecret: ${apiSecret}" "https://$CWMSITE/svc/server/$UUID/overview" | grep -Po '(?<="description":")(.*?)(?=",")'`
        errorCode=$?

        if [ $errorCode != '0' ]; 
        then
                echo "Erorr retrieving server overview"

        else 

            echo -e $description
        fi

    else

        echo "No API Client ID or Secret is set, unable to retrieve server overview"

    fi

}

function appendServerDescription() {

    description=`getServerDescription`
    updateServerDescription "$description $1"

}

function appendServerDescriptionTXT() {

   rootDir=$(rootDir)
   file=$rootDir/DESCRIPTION.TXT

    if [ -f "$file" ];
    then

        fileContent=`cat $file`

    fi

    description=`getServerDescription`
    updateServerDescription "$description $fileContent"

}

function setServerDescriptionTXT() {

   rootDir=$(rootDir)
   file=$rootDir/DESCRIPTION.TXT

    if [ -f "$file" ];
    then

        fileContent=`cat $file`

    fi

    updateServerDescription "$fileContent"

}

function getServerIP() {

    IPS=`cat $1 | grep ^ip.*=* | cut -f 2 -d"i" | cut -f 2 -d"p"`

    if [ -z "$IPS" ]
    then
        hostname -I
        return 0
    fi

    if [ ! -z "$WANNICIDS" ]
    then
        index=`echo $WANNICIDS | awk '{print $1;}'`
        index=$((index+1))
        echo $IPS | awk -v a="$index" '{print $a;}' | cut -f 2 -d"="
        return 0
    fi

    if [ ! -z "$LANNICIDS" ]
    then
        index=`echo $LANNICIDS | awk '{print $1;}'`
        index=$((index+1))
        echo $IPS | awk -v a="$index" '{print $a;}' | cut -f 2 -d"="
        return 0
    fi

}

function createSwapFile() {
    # 1:filename, 2:megabytes, 3:path

    # if path is given, know how to handle it when creating swap
    if [ ! -z $3 ];
    then
        if [ -d $3 ];
        then
            # path exists
            createDir=0
        else
            # new path
            createDir=1
        fi
    else
        # path not given
        createDir=2
    fi

    if [ -z $1 ];
    then
        # (>&2 echo "error: no filename given to swap file")
        echo "error: no filename given to swap file" | log
        return 1
    fi

    if [[ $createDir -eq 2 && -e $1 ]] || [[ $createDir -eq 0 && -e "$3/$1" ]];
    then
        echo "error: a file with this name already exists" | log
        return 1
    fi

    if [ -z $2 ];
    then
        echo "error: swap size (in MB) must be provided" | log
        return 1
    fi

    if [[ $2 =~ '^[0-9]+$' ]] || [[ $2 -le 0 ]];
    then
        echo "error: swap size must be a number greater than 0" | log
        return 1
    fi

    diskSizeMb=`df --output=avail -m "$PWD" | sed '1d;s/[^0-9]//g'`
    swapSizeAllowed=$((diskSizeMb/2))

    if [ $2 -gt $swapSizeAllowed ];
    then
        echo "error: maximum swap size (in MB) can be $swapSizeAllowed" | log
        return 1
    fi

    # create swap in existing directory
    if [ $createDir -eq 0 ];
    then
        swapFile="$3/$1"
    fi

    # create new directory for swap
    if [ $createDir -eq 1 ];
    then
        mkdir -p $3
        swapFile="$3/$1"
    fi

    # create swap in current path
    if [ $createDir -eq 2 ];
    then
        swapFile="$1"
    fi

    # generate swap file and mount it
    dd if=/dev/zero of=$swapFile bs=1M count=$2
    mkswap $swapFile
    swapon $swapFile
    chmod 600 $swapFile

    echo "$swapFile"
    return 0
}

function removeSwapFile() {
    # 1: filename given when created swap with createSwapFile()
    if [ ! -e $1 ];
    then
        echo "error: a swapfile with this name does not exist. did nothing" | log
        return 1
    fi

    swapoff -v $1 | log
    rm -f $1

    return 0
}

SERVERIP="$(getServerIP $CWMCONFIGFILE)"
