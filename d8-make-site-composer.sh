#!/bin/bash

admin_username=admin
admin_password=mypassword
admin_mail=janogarza@gmail.com
db_password=mypassword
site_root_name="d8memcached"

#Make
#  ./d8search-test-make-site-composer.sh 20170309
#Backup
#  drush sql-dump --result-file=../d8search-20170309-backup.sql --gzip
#Restore
#  pv -p ../d8search-20170309-backup.sql |gzip -d -c |drush sql-cli

# Latest stable modules
packages="drupal/search_api:~1 drupal/search_api_solr:~1 drupal/acquia_connector:~1 drupal/memcache:~2 drupal/devel:~1"
drupal_version="~8.6"


if [ ${1:-x} = x ]
then
  echo "Usage: $0 [uniquename]"
  echo "Example:"
  echo "    $0 2016-06-01"
  exit 1
fi
name="${site_root_name}-$1"

function pausemsg() {
  echo "=== ENTER TO CONTINUE ==="
  read
}

cd ~/Sites

if [ -d localhost/$name ]
then
  echo "Site exists"
  echo "You can remove it with:"
  echo "  mysqladmin --force drop local-$name"
  echo "  sudo rm -rf ~/Sites/localhost/$name"
  exit 1
fi

function Mycomposer()
{
  #echo " ... Running composer without XDebug ...";
  if [ ! -r /tmp/phpini-noxdebug.ini ]
  then
    cat /opt/lampp/etc/php.ini | egrep -v "xdebug.so|xhprof.so" > /tmp/phpini-noxdebug.ini;
  fi
  php -c /tmp/phpini-noxdebug.ini /usr/local/bin/composer $@
}

######### Download Drupal with composer
cd localhost
composer create-project drupal/drupal $name $drupal_version --no-progress --profile --prefer-dist
cd $name
# Where D8 composer packages come from:
Mycomposer config repositories.drupal composer https://packages.drupal.org/8

######### Install drupal
echo ""
echo "Creating DB: local-$name"
mysqladmin -u root --password=${db_password} create local-$name

echo "Starting drush site install command."
drush -y si standard --notify --db-url=mysql://root:joomlii34@localhost/local-$name --account-mail=x@x.com --account-name=admin --account-pass=$mypassword

# Make DB the default cache backend
chmod +w sites/default/settings.php
echo '$settings["cache"]["default"] = "cache.backend.database";' >> sites/default/settings.php
echo '$_ENV["AH_SITE_ENVIRONMENT"] = "dev";' >> sites/default/settings.php

#if [ -r ../local-$name-backup.sql.gz ]
#then
#  echo "Restoring DB"
#  pv -p ../local-$name-backup.sql.gz |gzip -d -c |drush sql-cli
#fi

######### Place under VCS
echo "Making Git repo"
cat <<EOF >.gitignore
sites/default/files/css/*
sites/default/files/js/*
sites/default/files/php/*
sites/default/files/*
EOF
git init
git add .
git commit -m "First commit: Drupal $drupal_version" >/dev/null

# Use composer to add modules and dependencies
echo "Adding Composer packages: $packages"
# SSL Stuff so that composer works correctly with https://packages.drupal.org/8
export SSL_CERT_DIR=/etc/ssl/certs
# Download packages
Mycomposer require $packages
# Add packages to git
git add .
git commit -m "Downloaded modules" >/dev/null

# Generate fake content
echo "Enabling/disabling some modules..."
drush en -y acquia_connector devel_generate syslog simpletest search_api_attachments facets
drush pm-uninstall -y dblog
drush -y config-set automated_cron.settings interval 0

# Export configuration
echo "Exporting configuration and committing to git..."
drush config-export --destination=config
git add .
git commit -m "Added config folder with initial configuration"

echo "Generating content..."
drush generate-terms tags 10
drush generate-content 50

# Manual stuff
echo "Log into site"
drush uli -l http://localhost/$name
#pausemsg

# Make DB Backup just in case
if [ ! -r ../local-$name-backup.sql.gz ]
then
  echo "Backing up site..."
  drush sql-dump --result-file=../local-$name-backup.sql --gzip
  pausemsg
fi

echo "DONE."
echo ""
