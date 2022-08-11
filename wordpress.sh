#!/bin/bash
function generateNginxEntries {
          cleanDomainName=${domainName#www.}
          cleanProject=${project#www.}


          sudo cp /etc/nginx/sites-available/"$project" /etc/nginx/sites-available/"$domainName"
          sudo sed -i "s/$cleanProject/$cleanDomainName/g" /etc/nginx/sites-available/"$domainName"
          sudo sed -i '/ssl/s/^/#/' /etc/nginx/sites-available/$domainName
          sudo ln -s /etc/nginx/sites-available/$domainName /etc/nginx/sites-enabled/$domainName

          echo "*********************"
              echo "Please check /etc/nginx/sites-available/$domainName manually, and make sure, that the DNS is set correctly, before you continue"
          echo "*********************"

          read -p "Press any key to continue"

          if sudo /etc/init.d/nginx reload ; then
              echo "Nginx successfully reloaded"
              sudo certbot --nginx -d $domainName
          else
              echo "*********************"
              echo "Please check /etc/nginx/sites-available/$domainName manually, and make sure, that the DNS is set correctly, before you continue"
              echo "*********************"
              read -p "Press any key to continue"

             if sudo /etc/init.d/nginx reload ; then
                        echo "Nginx successfully reloaded"
                        sudo certbot --nginx -d $domainName
                    else
                       echo "Restart failed"
                       exit
                    fi
          fi
}

#Get the correct Path to the Folder
function getProjectFolder {
  var=$(cat /etc/nginx/sites-available/"$project" | grep -n '/var/www/' | cut -f1 -d:)
  sedcmd=$(sed -n "$var"p /etc/nginx/sites-available/"$project")
  arr=($sedcmd)
  echo "${arr[@]: -1}" | rev | cut -c 2- | rev
}

function getSourceDatabaseName {
    projectPath=$(getProjectFolder project)
    var=$(grep DB_NAME "$projectPath""/wp-config.php" | tr -d ' ')
    result=`echo $var | cut -d "," -f 2`
    echo "${result%???}"
}

function createAnewUserAndDatabase {
  password=$(pwgen -s 25 1);

        database=${domainName//./_}
        echo 'Please enter your MySQL password'

        mysql -u root -p -e "CREATE DATABASE $database;CREATE USER $database@'localhost' IDENTIFIED BY '$password';GRANT ALL ON $database.* TO $database@'localhost';FLUSH PRIVILEGES;"
        echo '[success]MySQL User  + Table created. Granted all rights'

        sed -i "s/'DB_PASSWORD', '.*'/'DB_PASSWORD', '$password'/" wp-config.php
        sed -i "s/'DB_NAME', '.*'/'DB_NAME', '$database'/" wp-config.php
        sed -i "s/'DB_USER', '.*'/'DB_USER', '$database'/" wp-config.php
}

#prompt for a domain name, and when the name is given it creates the folder
while true; do




  read -p "Enter the Domain Name (e.g. www.aesence.com): " domainName

  if [ -d "/var/www/$domainName" ]; then
    echo "That folder already exists!"
  else
    sudo mkdir "/var/www/$domainName"
    cd "/var/www/$domainName"
    break
  fi
done

while true; do
 read -p "Do you want to create a new project, or copy an existing one? (new/copy): " projectChoice
    if [ "$projectChoice" = "new" ]; then
      sudo wget https://wordpress.org/latest.tar.gz
      sudo tar -xvf latest.tar.gz
      sudo mv wordpress/* ./
      sudo rm -rf wordpress latest.tar.gz

      project="standard.com"

      sudo mv wp-config-sample.php wp-config.php
      echo 'I have moved wp-config-sample.php to wp-config.php'

      sed -i "s/'AUTH_KEY',         'put your unique phrase here'/'AUTH_KEY',         '$(pwgen -s 65 1)'/g" wp-config.php
      sed -i "s/'SECURE_AUTH_KEY',  'put your unique phrase here'/'SECURE_AUTH_KEY',  '$(pwgen -s 65 1)'/g" wp-config.php
      sed -i "s/'LOGGED_IN_KEY',    'put your unique phrase here'/'LOGGED_IN_KEY',    '$(pwgen -s 65 1)'/g" wp-config.php
      sed -i "s/'NONCE_KEY',        'put your unique phrase here'/'NONCE_KEY',        '$(pwgen -s 65 1)'/g" wp-config.php
      sed -i "s/'AUTH_SALT',        'put your unique phrase here'/'AUTH_SALT',        '$(pwgen -s 65 1)'/g" wp-config.php
      sed -i "s/'SECURE_AUTH_SALT', 'put your unique phrase here'/'SECURE_AUTH_SALT', '$(pwgen -s 65 1)'/g" wp-config.php
      sed -i "s/'LOGGED_IN_SALT',   'put your unique phrase here'/'LOGGED_IN_SALT',   '$(pwgen -s 65 1)'/g" wp-config.php
      sed -i "s/'NONCE_SALT',       'put your unique phrase here'/'NONCE_SALT',       '$(pwgen -s 65 1)'/g" wp-config.php

      echo '[success]Auth keys modified with random phrases'

      createAnewUserAndDatabase domainName

      echo '[success]Credentials stored in the wp-config.php'

      cd /var/www/
      sudo chown -R www-data:www-data "$domainName"
      echo '[success]Set Owner to www-data'

      generateNginxEntries domainName project

      echo 'Setup finished'
      exit

      break
    elif [ "$projectChoice" = "copy" ]; then
      # This script will prompt the user to select a project to copy from /etc/nginx/sites-available/
      # except for the default project.
        items=($(ls /etc/nginx/sites-available/ | grep -v -e default -e standard.com))
        echo "Available projects:"
        # shellcheck disable=SC2068
        for i in ${!items[@]}; do
            echo "$((i+1))) ${items[$i]}"
        done

        read -p "Enter your selection: " selection

        if (( selection < 1 || selection > ${#items[@]} )); then
            echo "Invalid selection"
            exit 1
        fi

        project=${items[selection - 1]}
        projectPath=$(getProjectFolder project)

        cd /var/www/
        sudo cp -r "$projectPath"/* "$domainName"

        cd /var/www/$domainName

        createAnewUserAndDatabase

        project=${items[$((selection-1))]}

          sourceDatabaseName=$(getSourceDatabaseName project)

          sourceDatabaseName="${sourceDatabaseName:1:-1}"
          echo "${sourceDatabaseName}"

          #copy Database
          mysqldump -u root -p $sourceDatabaseName > $sourceDatabaseName.sql
          database=${domainName//./_}
          mysql -u root -p $database < $sourceDatabaseName.sql

          mysql -u root -p -e "USE $database;UPDATE wp_options SET option_value = 'https://$domainName' WHERE option_name = 'siteurl' OR option_name = 'home';"

          sudo rm $sourceDatabaseName.sql

          cd /var/www/
          sudo chown -R www-data:www-data "$domainName"
          echo '[success]Set Owner to www-data'

        generateNginxEntries domainName project
        echo 'Setup finished'
        exit
    else
      echo "Please enter 'new' or 'copy'"
    fi
done
