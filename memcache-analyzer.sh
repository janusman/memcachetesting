#!/bin/bash
# Memcache analyzer

tmp="/tmp/memcache-dump.$$"
tmp2="/tmp/memcache-dump-2.$$"
tmp_parsed="/tmp/memcache-dump-parsed.$$"
tmp_stats="/tmp/memcache-stats.$$"

function show_crosstab() {
  input_file=$1
  colfield=$2
  rowfield=$3
  header_cols=$4
  header_rows=$5
  
  method=count
  if [ ${6:-x} != x ]
  then
    method=sum
    sum_field="${6:-x}"
  fi
  
  echo "Crosstab: number of items by $header_cols/$header_rows"
  echo "-------------------------------------------------------------"
  # WORKING: (cat $tmp_parsed |awk -v colfield=$colfield -v rowfield=$rowfield -v header_cols="$header_cols" -v header_rows="$header_rows" 'BEGIN { print ".\t" header_cols; } { col=$colfield; row=$rowfield; val=1; cols[col]=col; rows[row]=row; tot[col,row]+=val; tot_col[col]+=val; tot_row[row]+=val} END { printf("%s",header_rows); for(col in cols) { printf("\t%s", cols[col]); } printf("\n"); for(row in rows) { printf("%s", rows[row]); for(col in cols) { t=tot[col,row]; if (!t) { t="-"; } printf("\t%s", t); } printf "\n"; } printf "Total"; for(col in cols) { printf("\t%d", tot_col[col]); } printf "\n";}') |column -t
  (cat $input_file |awk -v sum_field=$sum_field -v method=${method} -v colfield=$colfield -v rowfield=$rowfield -v header_cols="$header_cols" -v header_rows="$header_rows" '
  function track(col,row,val) {
    #print col row val;
    cols[col]=col; 
    rows[row]=row; 
    tot[col,row]+=val; 
    tot_col[col]+=val; 
    tot_row[row]+=val
    grand_total+=val;
  }
  BEGIN { 
    print ".\t.\t" header_cols "→"; } 
  { 
    # Track
    val=1;
    if (method=="sum") {
      val=$sum_field;
    }
    track($colfield,$rowfield,val);    
  } 
  END { 
    row_num=asort(rows)
    col_num=asort(cols)
    
    # Header row
    printf("↓%s\tTOTAL",header_rows);
    #for(col in cols) { 
    #  printf("\t%s", cols[col]);
    #} 
    for(col_i=1;col_i<=col_num;col_i++) {
      printf("\t%s", cols[col_i]);
    }
    printf("\n");
    sep="----";
    printf("%s\t%s", sep, sep);
    for(col_i=1;col_i<=col_num;col_i++) {
      printf("\t%s",sep);
    }
    printf("\n");
    
    # Totals row 
    printf "TOTAL\t" grand_total;
    for(col_i=1;col_i<=col_num;col_i++) {
      printf("\t%d", tot_col[cols[col_i]]);
    } 
    printf "\n";

    # Print all rows
    #for(row in rows) { 
    for(row_i=1;row_i<=row_num;row_i++) {
      row=rows[row_i]
      # Label
      printf("%s", row);
      
      # Totals column
      printf("\t%s", tot_row[row]);
      
      # Each column
      #for(col in cols) {
      for(col_i=1;col_i<=col_num;col_i++) {
        col=cols[col_i]
        t=tot[col,row];
        
        #count++
        #if (count%20==0) print "DEBUG: col=" col " row=" row " value=" t >"/dev/stderr"
        if (!t) { t="-"; }
        printf("\t%s", t);
      } 
      printf "\n";
    }

  }') |column -t
  echo "" 
}
  
  
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

# Parse all items
# 2 formats:
#  (A) SLAB=7 ITEM alejandrotest%3Aconfig%3A-core.base_field_override.comment.comment.mail [227 b; 1541892267 s]
#  (B) SLAB=2 ITEM hercampus_-cache_menu-.wildcard-admin_menu%3A821856%3A [1 b; 0 s]
#
# Detect:
if [ `head -100 $tmp |egrep -c '^SLAB=[0-9][0-9]* ITEM [a-z][a-z]*_'` -gt 0 ]
then
  # Format B
  cat $tmp |awk -F ' ' '{ slab=substr($1,index($1,"=")+1,2); pos1=index($3, "_-"); prefix=substr($3,1,pos1-1); tmp=substr($3,pos1+2); pos2=index(tmp, "-"); bin=substr(tmp, 1, pos2-1); item=substr(tmp, pos2+1); print slab "\t" prefix "\t" bin "\t" item}' >$tmp_parsed
else
  # Format A
  cat $tmp | awk -F ' ' '{ slab=substr($1,index($1,"=")+1,2); pos1=index($3, "%3A"); prefix=substr($3,1,pos1-2); tmp=substr($3,pos1+3); pos2=index(tmp, "%3A"); bin=substr(tmp, 1, pos2-1); item=substr(tmp, pos2+4); print slab "\t" prefix "\t" bin "\t" item}' >$tmp_parsed
fi

# Example output in $tmp_parsed:
# { ... snip ... }
# 10	local.test.sede.sede	config	core.entity_view_mode.config_pages.token
# 10	local.test.sede.sede	config	paragraphs.paragraphs_type.price_category
# 11	local.test.sede.sede	config	core.base_field_override.media.file.path
# 11	local.test.sede.sede	config	field.storage.node.field_show_hotline_visible
# 11	local.test.sede.sede	config	language.en%3Aviews.view.comments_recent
# 11	local.test.sede.sede	config	metatag.metatag_defaults.front
# 11	local.test.sede.sede	config	system.action.pathauto_update_alias_user
# 12	local.test.sede.sede	config	core.base_field_override.node.cards.promote
# 12	local.test.sede.sede	config	core.entity_view_display.block_content.basic.default
# 12	local.test.sede.sede	config	core.entity_view_display.paragraph.image.default
# { ... snip ... }

# Number of items by prefix
#(echo "#items prefix"; cat $tmp | egrep -o "^SLAB=[0-9][0-9]* ITEM [a-z][a-z0-9\.]*" |cut -f3 -d' ' |sort |uniq -c |sort -nr) |column -t
#echo "" 

show_crosstab $tmp_parsed 2 3 Prefix Bin
show_crosstab $tmp_parsed 3 1 Cache_Bins Slab
show_crosstab $tmp_parsed 2 1 Prefix Slab

# Get stats
echo stats slabs |nc localhost 11211 |grep "STAT [0-9]" |tr ':' ' ' |egrep "[^_](chunk_size|chunks_per_page|cmd_set|delete_hits|free_chunks|get_hits|mem_requested|total_chunks|total_pages|used_chunks)[^_]" >$tmp_stats
show_crosstab $tmp_stats 3 2 Stats_slab Slab 4

# Get stats
echo stats items |nc localhost 11211 |grep "STAT items:[0-9]" |tr ':' ' ' |egrep "[^_]age|evicted|evicted_time|evicted_unfetched|expired_unfetched|number|outofmemory|reclaimed[^_]" >$tmp_stats
show_crosstab $tmp_stats 4 3 Stats_etc Slab 5


# Get prefixes, but sorted by most-to-least frequent
#prefixes=`cat $tmp | egrep -o "^SLAB=[0-9][0-9]* ITEM [a-z][a-z0-9\.]*" |cut -f3 -d' ' |sort |uniq -c |sort -nr |awk '{print $2 }'`
prefixes=`cat $tmp_parsed |cut -f2 |sort |uniq -c |sort -nr |awk '{print $2 }'`

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

  (echo "# pattern"; cat $tmp2 |awk 'length($0) < 300 { print }' | cut -f2- -d_ |cut -f1 -d' ' | php -r '$result = urldecode(trim(stream_get_contents(STDIN))); print_r($result);' |sed -e 's/\.html_[a-zA-Z0-9_-]\{6,100\}/.html_{hash-value}/g' |sed -e 's/\.html\.twig_[a-zA-Z0-9_-]\{6,100\}/.html.twig_{hash-value}/g' | sed -e 's/[0-9a-f]\{6,100\}/{hex-hash-value}/g' -e 's/:[a-zA-Z0-9_-]*[A-Z][a-zA_Z0-9_-]*/:{hash}/g' | sed -e 's/^views_data:[a-z0-9_]\{2,50\}/views_data:{view-id}/g'  | sed -e 's/^views\.view\.[a-z0-9_]\{2,50\}/views.view.{view-id}/g' |sed -e 's/[0-9][0-9]*/{num}/g' |cut -c2- |sort |uniq -c |sort -nr |head -20) |column -t
  echo ""
done

rm $tmp $tmp2 $tmp_parsed
