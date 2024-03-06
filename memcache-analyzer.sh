#!/bin/bash
# Memcache analyzer

# Constants
# See http://linuxtidbits.wordpress.com/2008/08/11/output-color-on-bash-scripts/
COLOR_BLACK=$(tput setaf 0) #"\[\033[0;31m\]"
COLOR_RED=$(tput setaf 1) #"\[\033[0;31m\]"
COLOR_YELLOW=$(tput setaf 3) #"\[\033[0;33m\]"
COLOR_GREEN=$(tput setaf 2) #"\[\033[0;32m\]"
COLOR_GRAY=$(tput setaf 7) #"\[\033[2;37m\]"
COLOR_NONE=$(tput sgr0) #"\[\033[0m\]"
COLOR_BACKGROUND_NONE=$(tput setab 0)
COLOR_BACKGROUND_RED=$(tput setab 1)
COLOR_BACKGROUND_GREEN=$(tput setab 2)
COLOR_BACKGROUND_YELLOW=$(tput setab 3)
COLOR_BACKGROUND_WHITE=$(tput setab 7)

SCRIPT_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_FOLDER

DUMP_FILE=""

tmp="/tmp/memcache-dump"
tmp_parsed="/tmp/memcache-dump-parsed"
tmp_parsed_prefix="/tmp/memcache-dump-parsed-prefix"
tmp_stats="/tmp/memcache-stats.$$"
GREPSTRING="."

function cleanup() {
  echo "Cleaning up temporary files"
  rm 2>/dev/null $tmp $tmp_parsed $tmp_parsed_prefix $tmp_stats
}

function header() {
  echo ""
  echo "${COLOR_GRAY}._____________________________________________________________________________"
  echo "|${COLOR_GREEN}  $1"
  echo "${COLOR_NONE}"
}

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
  if [ ${7:-x} != x ]
  then
    totals_exclude="${7:-x}"
  fi

  echo "Crosstab: number of items by $header_cols/$header_rows"
  echo "-------------------------------------------------------------"
  (cat $input_file |awk -v sum_field=$sum_field -v method=${method} -v colfield=$colfield -v rowfield=$rowfield -v header_cols="$header_cols" -v header_rows="$header_rows" -v totals_exclude=",$totals_exclude," '
  function track(col,row,val) {
    #print col row val;
    cols[col]=col;
    rows[row]=row;
    tot[col,row]+=val;
    tot_col[col]+=val;
    tot_row[row]+=val
    grand_total+=val;
  }
  function should_exclude_from_totals(name) {
    return (index(totals_exclude, sprintf(",%s,", name)) > 0)
  }
  BEGIN {
    printf ".\t"
    if (!should_exclude_from_totals("_ROW_")) {
      printf ".\t"
    }
    print header_cols "→"; }
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

    #### Header row
    printf("↓%s",header_rows);

    # Total column
    if (!should_exclude_from_totals("_ROW_")) {
      printf "\tTOTAL";
    }

    # Rest of columns
    for(col_i=1;col_i<=col_num;col_i++) {
      printf("\t%s", cols[col_i]);
    }
    printf("\n");

    # Print divider below header row
    sep="----";
    printf("%s", sep)
    if (!should_exclude_from_totals("_ROW_")) {
      printf("\t%s", sep);
    }
    for(col_i=1;col_i<=col_num;col_i++) {
      printf("\t%s",sep);
    }
    printf("\n");
    #### END header row

    #### TOTALS row
    printf "TOTAL"

    if (!should_exclude_from_totals("_ROW_")) {
      printf "\t" grand_total;
    }
    for(col_i=1;col_i<=col_num;col_i++) {
      val = "-";
      # If column not excluded from totals
      if (should_exclude_from_totals(cols[col_i]) == 0 ) {
        val = tot_col[cols[col_i]];
      }
      printf("\t%s", val);
    }
    printf "\n";
    #### END TOTALS row

    #### ALL rows
    for(row_i=1;row_i<=row_num;row_i++) {
      row=rows[row_i]
      # Label
      printf("%s", row);

      # Totals column
      if (!should_exclude_from_totals("_ROW_")) {
        printf "\t" tot_row[row];
      }

      # Each column
      #for(col in cols) {
      for(col_i=1;col_i<=col_num;col_i++) {
        col=cols[col_i]
        t=tot[col,row];
        if (!t) { t="-"; }
        printf("\t%s", t);
      }
      printf "\n";
    }

  }') |column -t
  echo ""
}

### MAIN

memcache_server=$(hostname -s)
# On ACN?
if [ ${HOME:-x} = "/home/clouduser" ]
then
  memcache_server=`nc -v -w1 -q1 "localhost" "11211" 2>&1 <<<"get __mcrouter__.preprocessed_config" 2>/dev/null |grep 11211 |cut -f2 -d'"' |cut -f1 -d: |head -1`
fi

# Get options
# http://stackoverflow.com/questions/402377/using-getopts-in-bash-shell-script-to-get-long-and-short-command-line-options/7680682#7680682
FLAG_LIST_KEYS=0
FLAG_RAW=0
FLAG_GET=0
while test $# -gt 0
do
  case $1 in

  # Normal option processing
    -h | --help)
      # usage and help
      showhelp
      exit
      ;;
    -v | -vvv | --verbose)
      VERBOSE=1
      ;;
  # ...

  # Special cases
    --)
      break
      ;;
    --dump-file=*)
      DUMP_FILE=$1
      ;;
    --grep=*)
      GREPSTRING=$1
      ;;
    --list-keys | --keys)
      FLAG_LIST_KEYS=1
      ;;
    --raw )
      FLAG_RAW=1
      ;;
    --item | --get)
      FLAG_GET=1
      ;;
    --*)
      # error unknown (long) option $1
      echo "${COLOR_RED}Unknown option $1${COLOR_NONE}"
      ;;
    -?)
      # error unknown (short) option $1
      echo "${COLOR_RED}Unknown option $1${COLOR_NONE}"
      ;;

  # Split apart combined short options
  #  -*)
  #    split=$1
  #    shift
  #    set -- $(echo "$split" | cut -c 2- | sed 's/./-& /g') "$@"
  #    continue
  #    ;;

  # Done with options
    #Catchall
    *)
      GREPSTRING="$1"
      ;;
  esac

  shift
done

# Dump a single item
if [ $FLAG_GET = 1 ]
then
  echo "Dumping item $GREPSTRING"
  echo "-------------------------------------"
  echo ""
  drush --root=/var/www/html/${AH_SITE_NAME}/docroot ev '
    $m = \Drupal::service("memcache.factory")->get();
    $cid="'"$GREPSTRING"'";
    print_r($m->getMemcache()->get($cid));
  '
  echo ""
  exit 0
fi

if [ ${DUMP_FILE:-x} = x ]
then
  echo "Dumping memcache data to file $tmp"
  # Gather data from memcache
  rm -f $tmp 2>/dev/null
  for i in {1..42}
  do
    echo "stats cachedump $i 0" | nc $memcache_server 11211 | grep "$GREPSTRING" | grep -v "END" | awk '{ print "SLAB='$i' " $0 }' >>$tmp
  done
else
  echo "Using dump file $DUMP_FILE"
  grep "$GREPSTRING" $DUMP_FILE >$tmp
  if [ $? -gt 0 ]
  then
    echo "Error: could not use file $DUMP_FILE"
    cleanup
    exit 1
  fi
fi

if [ ! -s $tmp ]
then
  echo "Dumpfile has no data. Perhaps memcache is not running or has no data."
  cleanup
  exit 0
fi

if [ $FLAG_LIST_KEYS -eq 1 ]
then
  dumpfile=$tmp_parsed
  if [ $FLAG_RAW -eq 1 ]
  then
    dumpfile=$tmp
  fi

  if [ "$GREPSTRING" = "." ]
  then
    less $dumpfile
  else
    egrep --color "^|$GREPSTRING" $dumpfile | less
  fi
  exit 0
fi

num_total=`grep -c . $tmp`
#num_hashed=`egrep -c "ITEM [0-9a-z]{40} " $tmp`

echo "Total memcache items: $num_total"
#echo "CIDs that are hashes (therefore, can't be analyzed): $num_hashed"

# Parse all items
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
function parse_dump() {
  # 2 formats:
  #  (A) SLAB=7 ITEM alejandrotest%3Aconfig%3A-core.base_field_override.comment.comment.mail [227 b; 1541892267 s]
  #  (B) SLAB=2 ITEM hercampus_-cache_menu-.wildcard-admin_menu%3A821856%3A [1 b; 0 s]
  #

  cat $1 | awk -F ' ' '
  {
    slab=substr($1,index($1,"=")+1,2);
    piece=substr($3,1, index($3,"-"));
    pos_colon=index(piece, ":")
    pos_3a=index(piece, "%3A");
    if (pos_colon == 0 && pos_3a>0) {
      pos1=index($3, "%3A"); prefix=substr($3,1,pos1-2);
      tmp=substr($3,pos1+3); pos2=index(tmp, "%3A"); bin=substr(tmp, 1, pos2-1);
      item=substr(tmp, pos2+4);
    }
    else {
      pos1=index($3, "-"); prefix=substr($3,1,pos1-1);
      tmp=substr($3,pos1+1); pos2=index(tmp, "-"); bin=substr(tmp, 1, pos2-1);
      item=substr(tmp, pos2+1);
    }
    if (prefix != "" && bin != "") {
      print slab "\t" prefix "\t" bin "\t" item
    }
  }'
}

parse_dump $tmp >$tmp_parsed
echo "Parsed file is: $tmp_parsed"
echo ""


if [ "${1:-x}" = "--no-report" -o ${2:-x} = "--no-report" ]
then
  echo "Called with --no-report argument, exiting."
  exit 0
fi

echo "Count by prefix"
echo "---------------"
awk '{ print $2 }' $tmp_parsed |sort |uniq -c |sort -nr |head

show_crosstab $tmp_parsed 2 3 Prefix Bin
show_crosstab $tmp_parsed 2 1 Prefix Slab

# Get prefixes, but sorted by most-to-least frequent
prefixes=`cat $tmp_parsed |cut -f2 |sort |uniq -c |sort -nr |awk '{print $2 }'`

for nom in $prefixes
do

  echo "== Single Prefix analysis: prefix = $nom =================";
  echo ""

  # Filter the parsed file just to this bin.
  awk -v prefix="$nom" '($2==prefix) { print }' $tmp_parsed >$tmp_parsed_prefix

  # Crosstab.
  show_crosstab $tmp_parsed_prefix 3 1 Cache_Bins Slab

  # Top Patterns.
  echo "Top patterns observed:"
  (echo "# Cache_bin => Pattern"; echo "---- ---- -- ----"; awk '{ print $3 " => " $4 }' $tmp_parsed_prefix |awk 'length($0) < 300 { print }' | php -r '$result = urldecode(trim(stream_get_contents(STDIN))); print_r($result);' |sed -e 's/\.html_[a-zA-Z0-9_-]\{6,100\}/.html_{hash-value}/g' |sed -e 's/\.html\.twig_[a-zA-Z0-9_-]\{6,100\}/.html.twig_{hash-value}/g' | sed -e 's/[0-9a-f]\{6,100\}/{hex-hash-value}/g' -e 's/:[a-zA-Z0-9_-]*[A-Z][a-zA_Z0-9_-]*/:{hash}/g' | sed -e 's/^views_data:[a-z0-9_]\{2,50\}/views_data:{view-id}/g'  | sed -e 's/^views\.view\.[a-z0-9_]\{2,50\}/views.view.{view-id}/g' |sed -e 's/[0-9][0-9]*/{num}/g' |sort |uniq -c |sort -nr |head -20) |column -t
  echo ""
done

# Get slab stats
header "SLAB statistics"
echo stats slabs |nc $memcache_server 11211 |grep "STAT [0-9]" |tr ':' ' ' |egrep "[^_](chunk_size|chunks_per_page|cmd_set|delete_hits|free_chunks|get_hits|mem_requested|total_chunks|total_pages|used_chunks)[^_]" >$tmp_stats
show_crosstab $tmp_stats 3 2 Stats_slab Slab 4 _ROW_,chunk_size,chunks_per_page
echo ""

# More item stats
header "ITEM statistics"
echo stats items |nc $memcache_server 11211 |grep "STAT items:[0-9]" |tr ':' ' ' |egrep "[^_]age|evicted|evicted_time|evicted_unfetched|expired_unfetched|number|outofmemory|reclaimed[^_]" >$tmp_stats
show_crosstab $tmp_stats 4 3 Stats_etc Slab 5 _ROW_,age,age_hot,age_warm,evicted_time

# Cleanup
cleanup

echo "Done!"
