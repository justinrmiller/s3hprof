#!/bin/bash

set -e

S3_BUCKET=<insert bucket here>

HPROF_S3_FOLDER=hprofs
LOCAL_DIR=${HPROFS_LOCAL_DIR:-/tmp}
REGEX=${HPROFS_REGEX:-".*hprof.*"}

echo "Using local dir: $LOCAL_DIR"
echo "Using regex: $REGEX"

COMMAND=$1

# consider looking at sse-c as well (also aws:kms)
SERVER_SIDE_ENCRYPTION_AWS_CLI="--sse AES256"

# hi there, currently supported commands include:
#
# NOTE: this assumes that you have properly configured credentials for awscli
# and that you have access to the bucket specified in S3_BUCKET
#
# ./s3hprof.bash list <hostname> - This lists all hprofs that s3hprof can retrieve for you
# ./s3hprof.bash get <hostname> <filename> - This retrieves the file filename for host hostname
# ./s3hprof.bash check-then-upload - This command will check LOCAL_DIR for new hprofs that
# are finished and upload them (eventually this will also remove them locally, at least optionally)
# ./s3hprof.bash all-hprofs - This command will list all available hprofs (all servers/hostnames)
# ./s3hprof.bash all-hprofs-html - This command will list all available hprofs (all servers/hostnames)
# in html form, useful for periodical generation to serve out via a web server
#

# handle listing files out of the s3 hprof bucket for a particular host
if [ "$COMMAND" == "list" ] && [ "$#" -eq 2 ]; then
  host=$2
  echo "Listing available hprofs for $host:"
  echo ""
  aws s3 ls s3://$S3_BUCKET/$HPROF_S3_FOLDER/$host/ | grep hprof
  echo ""
elif [ "$COMMAND" == "list" ]; then
  echo "Usage: s3hprof.bash list server-001"
fi

# handle getting hprofs out of the s3 hprof bucket for a particular host and filename
if [ "$COMMAND" == "get" ] && [ "$#" -eq 3 ]; then
  host=$2
  filename=$3
  echo "Getting hprof for host $host and timestamp/file $filename:"
  aws s3 cp s3://$S3_BUCKET/$HPROF_S3_FOLDER/$host/$filename .
elif [ "$COMMAND" == "get" ]; then
  echo "Usage: s3hprof.bash get server-001 timestamp/java_pidXXXX.hprof"
fi

# handle uploading hprofs if their PIDs no longer exist, will upload then delete the hprof
# (this script works off the assumption that the process dies when an hprof is done)
if [ "$COMMAND" == "check-then-upload" ] && [ "$#" -eq 1 ]; then
  echo "Checking $LOCAL_DIR for hprofs to upload..."
  declare -a files_to_upload
  i=0
  cd $LOCAL_DIR
  IFS=$'\n'; for f in $( find . -maxdepth 1 -type f -mmin +30 -regex "./${REGEX}" -print )
  do
    files_to_upload[$i]="$f"
    # Evaluates to false when i==0, thanks bash!
    ((i++)) || true
  done

  if [ ${#files_to_upload[@] -gt 0} ]; then
    echo "Uploading files one at a time:"
    TS=$(date +%s)
    for f in ${files_to_upload[@]}
    do
      aws s3 cp $f "s3://$S3_BUCKET/$HPROF_S3_FOLDER/$HOSTNAME/$TS/"
      rm $f
    done
  fi
elif [ "$COMMAND" == "check-then-upload" ]; then
  echo "Usage: s3hprof.bash check-then-upload"
fi

# show all hprofs available
if [ "$COMMAND" == "all-hprofs" ] && [ "$#" -eq 1 ]; then
  # maybe pretty print this later?
  echo "Displaying all available hprofs:"
  echo ""
  aws s3 ls s3://$S3_BUCKET/$HPROF_S3_FOLDER/ --recursive | grep -v " 0 " | awk '{print $1,$2,$3,$4}'
  echo ""
elif [ "$COMMAND" == "all-hprofs" ]; then
  echo "Usage: s3hprof.bash all-hprofs"
fi

# show all hprofs html formatted (this is seriously a work in progress)
if [ "$COMMAND" == "all-hprofs-html" ] && [ "$#" -eq 1 ]; then
  echo "<link rel=stylesheet href=\"style.css\" type=\"text/css\">"
  echo "<h2>Available hprofs via s3hprofs:</h2>"
  echo "<table border=1 style=\"width:100%\">"
  echo "<tr><th>Date</th><th>Time</th><th>Bytes</th><th>Location</th></tr>"
  #echo "<tr class=\"blank_row\"><td colspan="4"></td></tr>"
  aws s3 ls s3://$S3_BUCKET/$HPROF_S3_FOLDER/ --recursive | grep -v " 0 " \
      | awk -F' ' '{print "<tr> <td> " $1 " </td> <td> " $2 " </td> <td> " $3 " </td> <td> " $4 "</td></tr>"}'
  echo "</table>"
elif [ "$COMMAND" == "all-hprofs-html" ]; then
  echo "Usage: s3hprof.bash all-hprofs-html"
fi
