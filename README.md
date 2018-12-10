# memcachetesting
Some code to test memcache 8.x-2.x module

* You can use d8-make-site-composer.sh to install a new Drupal site. Do edit the first lines to allow DB connection.
* Run drush-tests.sh from within a Drupal installation to run tests there.
* memcache-analyzer.sh will dump the memcache contents into a file and try to analyze the results.

To monitor memcached locally:

 watch -d -n1 memcached-tool 127.0.0.1:11211 

