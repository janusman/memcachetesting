# Get current folder
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

echo "Run this script from within the Drupal installation"

#echo "Clearing memcached daemon"
#sudo service memcached restart
#echo ""

#XDEBUG_CONFIG="idekey=session_name" "/opt/lampp/bin/php" "$HOME/.composer/vendor/drush/drush/drush.php" --php="/opt/lampp/bin/php" --php-options=""  ev '
drush ev '

  class CacheTester {
    private $bin, $cid;

    function __construct($bin, $cid) {
      $this->bin = $bin;
      $this->cid = $cid;
    }

    function storeAndFetchTest($value) {
      \Drupal::cache($this->bin)->set($this->cid, $value);
      $fetched = \Drupal::cache($this->bin)->get($this->cid);
      return !empty($fetched);
    }

  }
  
  class LockTester {
    private $name;
    
    function __construct($name) {
      $this->name = $name;
    }
    function error($msg) {
      echo "Lock: name=" . $this->name . " | " . $msg . PHP_EOL;
    }
    function runLockTest() {
      $locks = \Drupal::service("lock");
      if (!$locks->lockMayBeAvailable($this->name)) {
        $this->error("Problem: Lock wasnt available (lockMayBeAvailable() == false)");
        return false;
      }
      if (!$locks->acquire($this->name)) {
        $this->error("Problem: Couldnt acquire() lock");
        return false;
      }
      if (!$locks->acquire($this->name)) {
        $this->error("Problem: Lock was not properly acquired");
        return false;
      }
      #$locks->release($this->name);
      #if (!$locks->acquire($this->name)) {
      #  $this->error("Problem: Lock was not properly released");
      #  return false;
      #}
      return true;
    }

  }

  // Return random string of size $length
  function random_string($length) {
    return substr(str_shuffle(str_repeat($x="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", ceil($length/strlen($x)) )),1,$length);
  }

  $bin = "data";

  // Try increasing value sizes
  echo "Testing with various data value sizes\n";
  $cid_base = "TEST_LARGE_DATA_";
  foreach ( [1, 32, 512, 1024, 2048, 4096] as $kb) {
    $cid = $cid_base . $kb . "KB";
    $t = new CacheTester($bin, $cid);
    $value = random_string(1024 * $kb);
    $success = $t->storeAndFetchTest($value);
    echo "CID $cid " . ($success ? "FOUND" : "NOT FOUND") . PHP_EOL;
  }
  echo "\n";

  // Try increasing cache ID sizes
  echo "Testing with various cache ID sizes\n";
  $cid_base = "TEST_NAME_SIZE_";
  foreach ( [1, 32, 128, 256, 512, 1024] as $bytes) {
    $cid = $cid_base . random_string($bytes);
    $t = new CacheTester($bin, $cid);
    $value = random_string(1024);
    $success = $t->storeAndFetchTest($value);
    echo "CID of size " . ($bytes + strlen($cid_base)) . " " . ($success ? "FOUND" : "NOT FOUND") . PHP_EOL;
  }
  echo "\n";
  
  // LOCK TESTS
  
  $name = "onething";
  $t = new LockTester($name);
  $success = $t->runLockTest($name);
  echo "LOCK with name of $name " . ($success ? "SUCCESS" : "FAILURE") . PHP_EOL;
    
  echo "Testing locks with various name sizes\n";
  $cid_base = "TEST_LOCK_NAME_";
  foreach ( [1, 32, 128, 256, 512, 1024] as $bytes) {
    $name = $cid_base . random_string($bytes);
    $t = new LockTester($name);
    $success = $t->runLockTest($name);
    echo "LOCK with name of size " . ($bytes + strlen($cid_base)) . " " . ($success ? "SUCCESS" : "FAILURE") . PHP_EOL;
  }
  echo "\n";

  echo "Sleeping for 30 seconds so you can check memcache if needed!\n";
  sleep(30);
'

echo "Analyzing memcache data"
bash $DIR/memcache-analyzer.sh
echo ""

#echo "Dumping memcache data for items in 'data' bin"
#sort  /tmp/memcache-dump | grep "%3Adata"
#echo ""

echo "DONE"
