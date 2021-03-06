#! /bin/pfksh
#
#     Copyright 2011 Couchbase, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# profile.sh a wrapper script used to gain the privileges needed to run
# DTrace and invoke dtrace to sample the callstacks.
#

default_timeout=60
default_frequency=1000
default_num=10

timeout=$default_timeout
frequency=$default_frequency
num=$default_num
trace_pid=

usage()
{
  cat <<EOF

Usage $0 [-t sec] [-f freq] [-n num]
   -t sec      Run for n secs (default: ${default_timeout})
   -f freq     Sample at freq hz (default: ${default_frequency}Hz)
   -n num      Number of results to include (default: ${default_num})
   -p pid      Attach to pid (default: search for memcached)

EOF
  exit 1
}

args=`getopt t:f:n:p:h $*`
if [ $? -ne 0 ]
then
   usage
fi

set -- $args
if [ $? -ne 0 ]
then
   usage
fi

for i in $*
do
   case $i in
   -t)  timeout=$2
        shift 2
        ;;
   -f)  frequency=$2
        shift 2
        ;;
   -n)  num=$2
        shift 2
        ;;
   -p)  trace_pid=$2
        shift 2
        ;;
   --)  shift
        break
        ;;
   -h)  usage $0
        ;;
   esac
done

if [ x"$trace_pid" = x ]
then
  pids=`pgrep -x memcached`
  if [ $? -eq 0 ]
  then
    if [ x`echo $pids|wc -w|tr -d [:space:]` == x1 ]
    then
       trace_pid=$pids
    fi
  fi

  if [ x"$trace_pid" = x ]
  then
     echo "Failed to locate a single memcached process" >&2
     echo "  Try specify the process you want with -p" >&2
     exit 1
  fi
fi

exec dtrace -n "
BEGIN
{
   end = timestamp + $timeout * 1000000000;
}

tick-10hz
/timestamp >= end/
{
   exit(0);
}

profile-$frequency /pid == \$target/
{
   @num[ustack()] = count();
}

END
{
   trace(\"Samples over ${timeout}s at ${frequency}Hz\");
   trunc(@num, ${num});
   printa(@num);
}

" -p $trace_pid | c++filt
