#!/bin/bash
# Dump the memcache keys on all memcache instances for a site and parse them
# 
# Usage:
#   bash ./aht-memcache-analyzer.sh @pinpolicy.prod

function tempfile() {
  base=`mktmp`
}

tmpfile="/tmp/$0-$1-2020-10-23.tmp"
echo $tmpfile

sitename=$1
# Gather servers to run on

if [ ! -r $tmpfile ]
then 
  echo "Gathering info for $sitename..."
  aht $sitename app:info --format=json >$tmpfile

  if [ `grep -c memcached.conf $tmpfile` -eq 0 ]
  then
    echo "Could not find application $sitename (or has no memcache)"
    exit 1
  fi

  # Build script to dump keys, labelling the slab
  cat <<EOF >/tmp/memcache-dumpscript.sh
for i in {1..42}
do
  echo "stats cachedump \$i 0" | nc \$(hostname -s) 11211 |grep -v "END" | awk '{ print "SLAB='\$i' " \$0 }' |grep -v "^END"
done
EOF

  #cat /tmp/memcache-dumpscript.sh

  echo "Gathering servers with memcache..."
  cat $tmpfile |php -r '
    $result = json_decode(trim(stream_get_contents(STDIN)));
    # Look for environment_list->[env]->servers->[servername]->settings->memcached.conf->"-m" 
    $memcached_servers = [];
    foreach ($result->environment_list as $env_id => $env_data) {
      foreach ($env_data->servers as $server_id => $server_data) {
        $settings = (array)$server_data->settings;
        if (!empty($settings["memcached.conf"])) {
          $memcached_servers[$server_id] = $server_data->info->fqdn;
        }
      }
    }
    #print_r($memcached_servers);
    
    $dumpfile = "/tmp/dumpfile.txt";
    
    # Build command to dump everything
    $dump_ssh_commands = [ "rm $dumpfile" ];
    foreach ($memcached_servers as $hostname) {
      $dump_ssh_commands[] = "echo Fetching memcache data from $hostname...";
      $dump_ssh_commands[] = "rsync -qrvzh --rsync-path=\"sudo rsync\" -e \"ssh -q -p 40506  -F \$HOME/.ssh/ah_config \" /tmp/memcache-dumpscript.sh $hostname:/tmp/memcache-dumpscript.sh";
      $dump_ssh_commands[] = "ssh -F \$HOME/.ssh/ah_config $hostname bash /tmp/memcache-dumpscript.sh >>$dumpfile";
  }
  #echo implode(PHP_EOL, $dump_ssh_commands);
  
  $scriptfile = "/tmp/script.sh";
  file_put_contents($scriptfile, implode(PHP_EOL, $dump_ssh_commands));
  echo "Wrote script to $scriptfile\n";
'

# Get dump from all servers
. /tmp/script.sh
fi

# Run analysis
./memcache-analyzer.sh /tmp/dumpfile.txt --no-report
