#!/bin/sh
# Memcache analyzer

tmp="/tmp/memcache-dump"

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

prefixes=`cat $tmp | egrep -o "^SLAB=[0-9]* ITEM [a-z][a-z0-9]*" |cut -f3 -d' ' |sort -u`
for nom in $prefixes
do
  echo "== Key prefix: $nom =================";
  (echo "# cache_bin"; grep "ITEM $nom" $tmp | cut -f2 -d% |cut -c3- |sort |uniq -c |sort -nr) | column -t

  echo ""

  (echo "# size"; grep "ITEM $nom" $tmp |egrep -o '\[[1-9][0-9]* b;' |awk 'function doround(val) { power=1; while (power<val) { power=power*2; } return power; } { size=substr($1,2)+0; bin=doround(size); count[bin]++ } END { for (i in count) { printf("%d %d\n",count[i], i) } }' |sort -nr -t' ' -k2) |column -t

  echo ""

  echo "Top patterns observed:"
  (echo "# pattern";grep "ITEM $nom" $tmp |awk 'length($0) < 250 { print }' | cut -f2- -d- |cut -f1 -d' ' | php -r '$result = urldecode(trim(stream_get_contents(STDIN))); print_r($result);' |sed -e 's/[0-9][0-9]*/{num}/g' |sort |uniq -c |sort -nr |head -20) |column -t
  echo ""
done

#rm $tmp
