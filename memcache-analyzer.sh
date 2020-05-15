#!/bin/bash
# Memcache analyzer

tmp="/tmp/memcache-dump"
tmp2="/tmp/memcache-dump.$$"

echo "Dump file is in $tmp"
# Gather data from memcache
rm -f $tmp 2>/dev/null
for i in {1..42}
do
  echo "stats cachedump $i 0" | nc $(hostname -s) 11211 |grep -v "END" | awk '{ print "SLAB='$i' " $0 }' >>$tmp
done

num_total=`grep -c . $tmp`
#num_hashed=`egrep -c "ITEM [0-9a-z]{40} " $tmp`

echo "Total memcache items: $num_total"
#echo "CIDs that are hashes (therefore, can't be analyzed): $num_hashed"

# Number of items by prefix
(echo "#items prefix"; cat $tmp | egrep -o "^SLAB=[0-9][0-9]* ITEM [a-z][a-z0-9\.]*" |cut -f3 -d' ' |sort |uniq -c |sort -nr) |column -t
echo "" 

# Get prefixes, but sorted by most-to-least frequent
prefixes=`cat $tmp | egrep -o "^SLAB=[0-9][0-9]* ITEM [a-z][a-z0-9\.]*" |cut -f3 -d' ' |sort |uniq -c |sort -nr |awk '{print $2 }'`
for nom in $prefixes
do

  grep "SLAB=[0-9][0-9]* ITEM ${nom}_" $tmp >$tmp2

  # Figure out the data format...
  format=dash
  if [ `grep -c "SLAB=[0-9][0-9]* ITEM ${nom}_%3A" $tmp2` -gt 0 ]
  then
    format=other
  fi

  echo "== Key prefix: $nom =================";

  if [ $format = other ]
  then
    (echo "#items cache_bin"; cat $tmp2 | cut -f2 -d% |cut -c3- |sed -e 's/ .*$//g' |sort |uniq -c |sort -nr |head -20) | column -t
  else
    (echo "#items cache_bin"; cat $tmp2 | cut -f2 -d- |sed -e 's/ .*$//g' |sort |uniq -c |sort -nr |head -20) | column -t
  fi

  echo ""

  (echo "#items bin_size"; cat $tmp2|egrep -o '\[[1-9][0-9]* b;' |awk 'function doround(val) { power=1; while (power<val) { power=power*2; } return power; } { size=substr($1,2)+0; bin=doround(size); count[bin]++ } END { for (i in count) { if (count[i]>1) printf("%d %d\n",count[i], i) } }' |sort -nr -t' ' -k2) |column -t

  echo ""

  echo "Top patterns observed:"

  (echo "# pattern"; cat $tmp2 |awk 'length($0) < 250 { print }' | cut -f2- -d_ |cut -f1 -d' ' | php -r '$result = urldecode(trim(stream_get_contents(STDIN))); print_r($result);' |sed -e 's/\.html_[a-zA-Z0-9_-]\{6,100\}/.html_{hash-value}/g' |sed -e 's/\.html\.twig_[a-zA-Z0-9_-]\{6,100\}/.html.twig_{hash-value}/g' | sed -e 's/[0-9a-f]\{6,100\}/{hex-hash-value}/g' -e 's/:[a-zA-Z0-9_-]*[A-Z][a-zA_Z0-9_-]*/:{hash}/g' | sed -e 's/^views_data:[a-z0-9_]\{2,50\}/views_data:{view-id}/g'  | sed -e 's/^views\.view\.[a-z0-9_]\{2,50\}/views.view.{view-id}/g' |sed -e 's/[0-9][0-9]*/{num}/g' |cut -c2- |sort |uniq -c |sort -nr |head -20) |column -t
  echo ""
done
