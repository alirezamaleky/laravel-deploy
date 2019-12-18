#!/bin/bash

TARGET=$1

SCRIPT_PATH=$(realpath $0)
LARAVEL_PATH=$(dirname $SCRIPT_PATH)
LARADOCK_PATH=$LARAVEL_PATH/laradock

if [[ ! -d "$LARAVEL_PATH/laradock" ]] || [[ ! -d "$LARAVEL_PATH/vendor" ]] || [[ ! -d "$LARAVEL_PATH/node_modules" ]]; then
    INSTALL="y"
fi

if [[ $INSTALL == "y" ]] && [[ $TARGET != "docker" ]]; then
    echo -n "Is the project in production? [y/N] " && read PRODUCTION
else
    if [[ $(grep APP_ENV $LARAVEL_PATH/.env | cut -d '=' -f2) == "production" ]]; then
        PRODUCTION="y"
    fi
fi

CONTAINERS="nginx mariadb redis phpmyadmin"
if [[ $PRODUCTION == "y" ]]; then
    CONTAINERS+="php-worker" #mailu
fi

if [[ $CONTAINERS == *"mariadb"* ]]; then
    DB_ENGINE=mariadb
else
    DB_ENGINE=mysql
fi

if [[ $INSTALL == "y" ]] && [[ $TARGET != "docker" ]]; then
    echo -n "DB_DATABASE: " && read DATABASE
    echo -n "DOMAIN: " && read DOMAIN
    echo -n "APP_NAME: " && read APP_NAME
    echo -n "MAIL_USERNAME: " && read MAIL_USERNAME
    echo -n "MAIL_ENCRYPTION: " && read MAIL_ENCRYPTION
    echo -n "FTP_HOST: " && read FTP_HOST
    echo -n "FTP_USERNAME: " && read FTP_USERNAME
    echo -n "FTP_PASSWORD: " && read FTP_PASSWORD
    echo -n "PMA_PORT: " && read PMA_PORT
    echo -n "MAILU_RECAPTCHA_PUBLIC_KEY: " && read MAILU_RECAPTCHA_PUBLIC_KEY
    echo -n "MAILU_RECAPTCHA_PRIVATE_KEY: " && read MAILU_RECAPTCHA_PRIVATE_KEY

    DB_DATABASE="${DATABASE}_db"
    DB_USERNAME="${DATABASE}_user"
    DB_PASSWORD=$(openssl rand -base64 15)
    DB_ROOT_PASSWORD=$(openssl rand -base64 15)
    MAIL_PASSWORD=$(openssl rand -base64 15)
    MAILU_HOSTNAMES="mail.$DOMAIN"
    MAILU_SECRET_KEY=$(openssl rand -base64 15)

    printf "\nDB_DATABASE=$DB_DATABASE"
    printf "\nDB_USERNAME=$DB_USERNAME"
    printf "\nDB_PASSWORD=$DB_PASSWORD"
    printf "\nDB_ROOT_PASSWORD=$DB_ROOT_PASSWORD"
    printf "\nPMA_PORT=$PMA_PORT"
    printf "\n\n Are you saved this informations?" && read NOTED
fi

_backup() {
    mkdir -p $LARAVEL_PATH/storage/app/databases
    if [[ $TARGET == "deploy" ]] && [[ $INSTALL != "y" ]] && [[ $PRODUCTION == "y" ]]; then
        cd $LARADOCK_PATH
        docker-compose exec workspace mysqldump \
            --force \
            --skip-lock-tables \
            --host=$(grep DB_HOST $LARAVEL_PATH/.env | cut -d '=' -f2) \
            --port=$(grep DB_PORT $LARAVEL_PATH/.env | cut -d '=' -f2) \
            -p$(grep DB_PASSWORD $LARAVEL_PATH/.env | cut -d '=' -f2) \
            --user=$(grep DB_USERNAME $LARAVEL_PATH/.env | cut -d '=' -f2) \
            --databases $(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2) \
            --ignore-table=$(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2).migrations \
            --ignore-table=$(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2).telescope_entries \
            --ignore-table=$(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2).telescope_entries_tags \
            --ignore-table=$(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2).telescope_monitoring \
            --result-file=./storage/app/databases/$(date '+%y-%m-%d_%H:%M').sql
    fi
}

_pull() {
    if [[ $PRODUCTION == "y" ]]; then
        git checkout -f $LARAVEL_PATH
        git pull origin master
    fi

    if [[ $PRODUCTION == "y" ]]; then
        if [[ $TARGET == "deploy" ]]; then
            find $LARAVEL_PATH -type f -exec chmod 644 {} \;
            find $LARAVEL_PATH -type d -exec chmod 755 {} \;
        fi

        if [ -f /etc/lsb-release ] && [ ! -f /etc/lsb-release ]; then
            sudo chown -R ubuntu:ubuntu $LARAVEL_PATH
        else
            sudo chown -R $USER:$USER $LARAVEL_PATH
        fi
    else
        sudo chown -R $USER:$USER $LARAVEL_PATH
    fi

    if [[ $INSTALL != "y" ]]; then
        sudo chmod -R 775 $LARAVEL_PATH/storage $LARAVEL_PATH/bootstrap/cache $LARAVEL_PATH/node_modules
        sudo chmod -R 600 $LARAVEL_PATH/storage/app/databases
    fi

    chmod +x $LARAVEL_PATH/deploy.sh
}

_env() {
    if ! grep -q "deploy.sh" $LARAVEL_PATH/.gitignore; then
        echo "deploy.sh" >>$LARAVEL_PATH/.gitignore
    fi
    if ! grep -q "laradock" $LARAVEL_PATH/.gitignore; then
        echo "laradock" >>$LARAVEL_PATH/.gitignore
    fi

    if [[ ! -d "$LARAVEL_PATH/laradock" ]]; then
        wget -N https://github.com/laradock/laradock/archive/master.zip -P $LARAVEL_PATH &&
            unzip $LARAVEL_PATH/master.zip -d $LARAVEL_PATH &&
            mv $LARAVEL_PATH/laradock-master $LARAVEL_PATH/laradock &&
            rm -f $LARAVEL_PATH/master.zip
    fi

    if [[ $INSTALL == "y" ]]; then
        cp $LARADOCK_PATH/env-example $LARADOCK_PATH/.env
        cp $LARADOCK_PATH/php-worker/supervisord.d/laravel-worker.conf.example $LARADOCK_PATH/php-worker/supervisord.d/laravel-worker.conf

        rm -f $LARADOCK_PATH/nginx/sites/default.conf
        wget -N https://raw.githubusercontent.com/alirezamaleky/nginx-config/master/default.conf -P $LARADOCK_PATH/nginx/sites
        sed -i "s|server_name localhost;|server_name $DOMAIN;|" $LARADOCK_PATH/nginx/sites/default.conf

        sed -i "s|PHP_FPM_INSTALL_SOAP=.*|PHP_FPM_INSTALL_SOAP=true|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_MYSQL_CLIENT=.*|WORKSPACE_INSTALL_MYSQL_CLIENT=true|" $LARADOCK_PATH/.env

        sed -i "s|PMA_DB_ENGINE=.*|PMA_DB_ENGINE=$DB_ENGINE|" $LARADOCK_PATH/.env
        sed -i "s|PMA_PORT=.*|PMA_PORT=$PMA_PORT|" $LARADOCK_PATH/.env
        sed -i "s|PMA_USER=.*|PMA_USER=$DB_USERNAME|" $LARADOCK_PATH/.env
        sed -i "s|PMA_PASSWORD=.*|PMA_PASSWORD=$DB_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|PMA_ROOT_PASSWORD=.*|PMA_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MYSQL_DATABASE=.*|MYSQL_DATABASE=$DB_DATABASE|" $LARADOCK_PATH/.env
        sed -i "s|MYSQL_USER=.*|MYSQL_USER=$DB_USERNAME|" $LARADOCK_PATH/.env
        sed -i "s|MYSQL_PASSWORD=.*|MYSQL_PASSWORD=$DB_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_DATABASE=.*|MARIADB_DATABASE=$DB_DATABASE|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_USER=.*|MARIADB_USER=$DB_USERNAME|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_PASSWORD=.*|MARIADB_PASSWORD=$DB_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_ROOT_PASSWORD=.*|MARIADB_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_DOMAIN=.*|MAILU_DOMAIN=$DOMAIN|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_RECAPTCHA_PUBLIC_KEY=.*|MAILU_RECAPTCHA_PUBLIC_KEY=$MAILU_RECAPTCHA_PUBLIC_KEY|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_RECAPTCHA_PRIVATE_KEY=.*|MAILU_RECAPTCHA_PRIVATE_KEY=$MAILU_RECAPTCHA_PRIVATE_KEY|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_HOSTNAMES=.*|MAILU_HOSTNAMES=$MAILU_HOSTNAMES|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_SECRET_KEY=.*|MAILU_SECRET_KEY=$MAILU_SECRET_KEY|" $LARADOCK_PATH/.env

        echo "alias nr='npm run'" >>$LARADOCK_PATH/workspace/aliases.sh
        echo "alias pa='php artisan'" >>$LARADOCK_PATH/workspace/aliases.sh
    fi

    if ! grep -q "max_allowed_packet" $LARADOCK_PATH/$DB_ENGINE/my.cnf; then
        echo "[mysqld]" >>$LARADOCK_PATH/$DB_ENGINE/my.cnf
        echo "max_allowed_packet=16M" >>$LARADOCK_PATH/$DB_ENGINE/my.cnf
    else
        sed -i "s|max_allowed_packet=.*|max_allowed_packet=16M|" $LARADOCK_PATH/$DB_ENGINE/my.cnf
    fi

    if [[ $INSTALL == "y" ]]; then
        cp $LARAVEL_PATH/.env.example $LARAVEL_PATH/.env

        if [[ $PRODUCTION == "y" ]]; then
            sed -i "s|APP_ENV=.*|APP_ENV=production|" $LARAVEL_PATH/.env
            sed -i "s|APP_DEBUG=.*|APP_DEBUG=false|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_USERNAME=.*|MAIL_USERNAME=$MAIL_USERNAME|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_PASSWORD=.*|MAIL_PASSWORD=$MAIL_PASSWORD|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_ENCRYPTION=.*|MAIL_ENCRYPTION=$MAIL_ENCRYPTION|" $LARAVEL_PATH/.env
            sed -i "s|FTP_HOST=.*|FTP_HOST=$FTP_HOST|" $LARAVEL_PATH/.env
            sed -i "s|FTP_USERNAME=.*|FTP_USERNAME=$FTP_USERNAME|" $LARAVEL_PATH/.env
            sed -i "s|FTP_PASSWORD=.*|FTP_PASSWORD=$FTP_PASSWORD|" $LARAVEL_PATH/.env
            sed -i "s|RESPONSE_CACHE_ENABLED=.*|RESPONSE_CACHE_ENABLED=true|" $LARAVEL_PATH/.env
            sed -i "s|ZARINPAL_MERCHANT_ID=.*|ZARINPAL_MERCHANT_ID=$ZARINPAL_MERCHANT_ID|" $LARAVEL_PATH/.env
        fi

        sed -i "s|DB_HOST=.*|DB_HOST=$DB_ENGINE|" $LARAVEL_PATH/.env
        sed -i "s|REDIS_HOST=.*|REDIS_HOST=redis|" $LARAVEL_PATH/.env

        sed -i "s|LOG_CHANNEL=.*|LOG_CHANNEL=daily|" $LARAVEL_PATH/.env
        sed -i "s|BROADCAST_DRIVER=.*|BROADCAST_DRIVER=redis|" $LARAVEL_PATH/.env
        sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|" $LARAVEL_PATH/.env
        sed -i "s|QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|" $LARAVEL_PATH/.env
        sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|" $LARAVEL_PATH/.env

        sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" $LARAVEL_PATH/.env
        sed -i "s|APP_NAME=.*|APP_NAME=$APP_NAME|" $LARAVEL_PATH/.env
        sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" $LARAVEL_PATH/.env
        sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USERNAME|" $LARAVEL_PATH/.env
        sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" $LARAVEL_PATH/.env
    fi

    if [[ $PRODUCTION == "y" ]]; then
        if ! grep -q "$LARADOCK_PATH && docker-compose up -d $CONTAINERS" /etc/crontab; then
            sudo echo "@reboot   root   cd $LARADOCK_PATH && docker-compose up -d $CONTAINERS" >>/etc/crontab
        fi

        if ! grep -q "$SCRIPT_PATH deploy" /etc/crontab; then
            sudo echo "0 5 * * *   root   $SCRIPT_PATH deploy" >>/etc/crontab
        fi
    fi
}

_sql() {
    cd $LARADOCK_PATH
    docker-compose up -d $DB_ENGINE

    if [[ $(docker-compose exec $DB_ENGINE mysql -u root -p$(grep MARIADB_ROOT_PASSWORD $LARADOCK_PATH/.env | cut -d '=' -f2) -e "SHOW DATABASES;") == *"ERROR"* ]] ||
        [[ $(docker-compose exec $DB_ENGINE mysql -u $(grep DB_USERNAME $LARAVEL_PATH/.env | cut -d '=' -f2) -p$(grep DB_PASSWORD $LARAVEL_PATH/.env | cut -d '=' -f2) -e "SHOW DATABASES;") == *"ERROR"* ]]; then
        if [[ $INSTALL == "y" ]]; then
            docker-compose rm --force --stop -v $DB_ENGINE
            rm -rf ~/.laradock/data/$DB_ENGINE
            docker-compose up -d --build --force-recreate $DB_ENGINE
        fi

        SQL="ALTER USER 'root'@'localhost' IDENTIFIED BY '$(grep MARIADB_ROOT_PASSWORD $LARADOCK_PATH/.env | cut -d '=' -f2)';"
        SQL+="CREATE DATABASE IF NOT EXISTS $(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2) COLLATE 'utf8_general_ci';"
        SQL+="CREATE USER '$(grep DB_USERNAME $LARAVEL_PATH/.env | cut -d '=' -f2)'@'localhost' IDENTIFIED BY '$(grep DB_PASSWORD $LARAVEL_PATH/.env | cut -d '=' -f2)';"
        SQL+="GRANT ALL ON $(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2).* TO '$(grep DB_USERNAME $LARAVEL_PATH/.env | cut -d '=' -f2)'@'localhost';"
        SQL+="FLUSH PRIVILEGES;"

        if [[ $(docker-compose exec $DB_ENGINE mysql -u root -e "SHOW DATABASES;") != *"ERROR"* ]]; then
            docker-compose exec $DB_ENGINE mysql -u root -e "$SQL"
        elif [[ $(docker-compose exec $DB_ENGINE mysql -u root -p$(grep MARIADB_ROOT_PASSWORD $LARADOCK_PATH/.env | cut -d '=' -f2) -e "SHOW DATABASES;") != *"ERROR"* ]]; then
            docker-compose exec $DB_ENGINE mysql -u root -p$(grep MARIADB_ROOT_PASSWORD $LARADOCK_PATH/.env | cut -d '=' -f2) -e "$SQL"
        elif [[ $(docker-compose exec $DB_ENGINE mysql -u root -proot -e "SHOW DATABASES;") != *"ERROR"* ]]; then
            docker-compose exec $DB_ENGINE mysql -u root -proot -e "$SQL"
        elif [[ $(docker-compose exec $DB_ENGINE mysql -u root -psecret -e "SHOW DATABASES;") != *"ERROR"* ]]; then
            docker-compose exec $DB_ENGINE mysql -u root -psecret -e "$SQL"
        fi
    fi
}

_up() {
    cd $LARADOCK_PATH

    if [[ $TARGET == "deploy" ]]; then
        docker system prune --volumes --force
    fi

    if [[ $INSTALL == "y" ]]; then
        docker-compose up -d $CONTAINERS
    else
        docker-compose up -d --build $CONTAINERS
    fi

    if [[ $TARGET == "deploy" ]]; then
        docker-compose exec workspace "/var/www/deploy.sh" docker
    else
        printf "\n\n\n\n\n Welcome to laradock workspace! \n\n\n\n\n"
        docker-compose exec workspace bash
    fi
}

_yarn() {
    killall yarn npm
    if [[ $PRODUCTION == "y" ]]; then
        yarn install --production --pure-lockfile --non-interactive &&
            yarn run prod
    else
        if [[ $INSTALL == "y" ]]; then
            yarn install
        else
            yarn upgrade
        fi
        yarn run dev
    fi
}

_composer() {
    killall composer
    composer global require hirak/prestissimo

    if [[ $PRODUCTION == "y" ]]; then
        composer install --optimize-autoloader --no-dev --no-interaction --prefer-dist
    else
        if [[ $INSTALL == "y" ]]; then
            composer install
        else
            composer update
        fi
    fi

    if [[ $INSTALL == "y" ]]; then
        composer run-script "post-autoload-dump"
        composer run-script "post-root-package-install"
        composer run-script "post-create-project-cmd"
    fi
}

_laravel() {
    if [[ $INSTALL == "y" ]]; then
        php artisan migrate --force --seed
        php artisan storage:link
    else
        php artisan migrate --force
        php artisan queue:restart
    fi

    if [[ $PRODUCTION == "y" ]]; then
        php artisan optimize
        php artisan view:clear
        php artisan view:cache
    fi

    if [[ $PRODUCTION == "y" ]]; then
        yarn global add html-minifier
        html-minifier --collapse-whitespace --remove-comments --remove-optional-tags --remove-redundant-attributes --remove-script-type-attributes --remove-tag-whitespace --use-short-doctype --minify-css true --minify-js true --input-dir $LARAVEL_PATH/storage/framework/views --output-dir $LARAVEL_PATH/storage/framework/views --file-ext "php"
    fi
}

if [[ $TARGET == "docker" ]]; then
    _yarn
    _composer
    _laravel
else
    if [[ ! -z $USER ]]; then
        _backup
        _pull
        _env
        _sql
        _up
    fi
fi
