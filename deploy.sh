#!/bin/bash

TARGET=$1

ELAPSED_SEC=$SECONDS
SCRIPT_PATH=$(realpath $0)
LARAVEL_PATH=$(dirname $SCRIPT_PATH)
LARADOCK_PATH=$LARAVEL_PATH/laradock

if [[ ! -d "$LARAVEL_PATH/laradock" ]] || [[ ! -d "$LARAVEL_PATH/vendor" ]] || [[ ! -d "$LARAVEL_PATH/node_modules" ]]; then
    if [[ $TARGET != "docker" ]]; then
        echo -n "Is this first install? [y/N] " && read INSTALL
    fi
    if [[ -z $INSTALL ]]; then
        INSTALL="y"
    fi
fi

if [[ $INSTALL == "y" ]] && [[ $TARGET != "docker" ]]; then
    echo -n "Is the project in production? [y/N] " && read PRODUCTION
else
    if [[ $(grep APP_ENV $LARAVEL_PATH/.env | cut -d '=' -f2) == "production" ]]; then
        PRODUCTION="y"
    fi
fi

CONTAINERS="nginx mariadb phpmyadmin redis"
# if [[ $PRODUCTION == "y" ]]; then
#     CONTAINERS+=" mailu"
# fi

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
    echo -n "PMA_PORT: " && read PMA_PORT
    echo -n "MAILU_RECAPTCHA_PUBLIC_KEY: " && read MAILU_RECAPTCHA_PUBLIC_KEY
    echo -n "MAILU_RECAPTCHA_PRIVATE_KEY: " && read MAILU_RECAPTCHA_PRIVATE_KEY

    DB_DATABASE="${DATABASE}_db"
    DB_USERNAME="${DATABASE}_user"
    DB_PASSWORD=$(openssl rand -base64 15)
    DB_ROOT_PASSWORD=$(openssl rand -base64 15)
    MAIL_HOST="mail.$DOMAIN"
    MAIL_PASSWORD=$(openssl rand -base64 15)
    REDIS_PASSWORD=$(openssl rand -base64 15)

    printf "\nDB_DATABASE=$DB_DATABASE"
    printf "\nDB_USERNAME=$DB_USERNAME"
    printf "\nDB_PASSWORD=$DB_PASSWORD"
    printf "\nDB_ROOT_PASSWORD=$DB_ROOT_PASSWORD"
    printf "\nREDIS_PASSWORD=$REDIS_PASSWORD"
    printf "\nPMA_PORT=$PMA_PORT"
    printf "\n\n Are you saved this informations?" && read NOTED
else
    DB_DATABASE=$(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d '=' -f2)
    DB_USERNAME=$(grep DB_USERNAME $LARAVEL_PATH/.env | cut -d '=' -f2)
    DB_PASSWORD=$(grep DB_PASSWORD $LARAVEL_PATH/.env | cut -d '=' -f2)
    DB_ROOT_PASSWORD=$(grep ${DB_ENGINE^^}_ROOT_PASSWORD $LARADOCK_PATH/.env | cut -d '=' -f2)
    REDIS_PASSWORD=$(grep REDIS_PASSWORD $LARAVEL_PATH/.env | cut -d '=' -f2)
fi

_laradock() {
    if [[ ! -d "$LARAVEL_PATH/laradock" ]]; then
        wget -N https://github.com/laradock/laradock/archive/master.zip -P $LARAVEL_PATH &&
            unzip $LARAVEL_PATH/master.zip -d $LARAVEL_PATH &&
            mv $LARAVEL_PATH/laradock-master $LARAVEL_PATH/laradock &&
            rm -f $LARAVEL_PATH/master.zip
        cp $LARADOCK_PATH/env-example $LARADOCK_PATH/.env
    fi

    if [[ $PRODUCTION == "y" ]] && [[ $TARGET != "docker" ]]; then
        if ! grep -q "schedule:run" $LARADOCK_PATH/workspace/crontab/laradock || ! grep -q "queue:work" $LARADOCK_PATH/workspace/crontab/laradock; then
            echo "" >$LARADOCK_PATH/workspace/crontab/laradock
            echo "* * * * * laradock /usr/bin/php /var/www/artisan schedule:run >>/dev/null 2>&1" >>$LARADOCK_PATH/workspace/crontab/laradock
            echo "@reboot laradock /usr/bin/php /var/www/artisan queue:work --timeout=60 --sleep=3 >>/dev/null 2>&1" >>$LARADOCK_PATH/workspace/crontab/laradock
            if [[ $INSTALL != "y" ]]; then
                cd $LARADOCK_PATH
                docker-compose build --no-cache workspace
                docker-compose up -d workspace
            fi
        fi
    elif [[ $PRODUCTION != "y" ]] && [[ $INSTALL == "y" ]]; then
        echo "" >$LARADOCK_PATH/workspace/crontab/laradock
    fi
}

_env() {
    if [[ $INSTALL == "y" ]]; then
        sed -i "s|PHP_FPM_INSTALL_SOAP=.*|PHP_FPM_INSTALL_SOAP=true|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_MYSQL_CLIENT=.*|WORKSPACE_INSTALL_MYSQL_CLIENT=true|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_NPM_GULP=.*|WORKSPACE_INSTALL_NPM_GULP=false|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_NPM_VUE_CLI=.*|WORKSPACE_INSTALL_NPM_VUE_CLI=false|" $LARADOCK_PATH/.env

        sed -i "s|MYSQL_DATABASE=.*|MYSQL_DATABASE=$DB_DATABASE|" $LARADOCK_PATH/.env
        sed -i "s|MYSQL_USER=.*|MYSQL_USER=$DB_USERNAME|" $LARADOCK_PATH/.env
        sed -i "s|MYSQL_PASSWORD=.*|MYSQL_PASSWORD=$DB_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_DATABASE=.*|MARIADB_DATABASE=$DB_DATABASE|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_USER=.*|MARIADB_USER=$DB_USERNAME|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_PASSWORD=.*|MARIADB_PASSWORD=$DB_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_ROOT_PASSWORD=.*|MARIADB_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|PMA_DB_ENGINE=.*|PMA_DB_ENGINE=$DB_ENGINE|" $LARADOCK_PATH/.env
        sed -i "s|PMA_PORT=.*|PMA_PORT=$PMA_PORT|" $LARADOCK_PATH/.env
        sed -i "s|PMA_USER=.*|PMA_USER=$DB_USERNAME|" $LARADOCK_PATH/.env
        sed -i "s|PMA_PASSWORD=.*|PMA_PASSWORD=$DB_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|PMA_ROOT_PASSWORD=.*|PMA_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_DOMAIN=.*|MAILU_DOMAIN=$DOMAIN|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_RECAPTCHA_PUBLIC_KEY=.*|MAILU_RECAPTCHA_PUBLIC_KEY=$MAILU_RECAPTCHA_PUBLIC_KEY|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_RECAPTCHA_PRIVATE_KEY=.*|MAILU_RECAPTCHA_PRIVATE_KEY=$MAILU_RECAPTCHA_PRIVATE_KEY|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_HOSTNAMES=.*|MAILU_HOSTNAMES=$MAIL_HOST|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_SECRET_KEY=.*|MAILU_SECRET_KEY=$(openssl rand -base64 16)|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_INIT_ADMIN_USERNAME=.*|MAILU_INIT_ADMIN_USERNAME=$MAIL_USERNAME|" $LARADOCK_PATH/.env
        sed -i "s|MAILU_INIT_ADMIN_PASSWORD=.*|MAILU_INIT_ADMIN_PASSWORD=$MAIL_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|REDIS_STORAGE_SERVER_PASSWORD=.*|REDIS_STORAGE_SERVER_PASSWORD=$REDIS_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|REDIS_RESULT_STORAGE_SERVER_PASSWORD=.*|REDIS_RESULT_STORAGE_SERVER_PASSWORD=$REDIS_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|REDIS_QUEUE_SERVER_PASSWORD=.*|REDIS_QUEUE_SERVER_PASSWORD=$REDIS_PASSWORD|" $LARADOCK_PATH/.env
        if ! grep -q "REDIS_PASSWORD" $LARADOCK_PATH/.env; then
            echo "REDIS_PASSWORD=$REDIS_PASSWORD" >>$LARADOCK_PATH/.env
        else
            sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD|" $LARADOCK_PATH/.env
        fi

        echo "alias nr='npm run'" >>$LARADOCK_PATH/workspace/aliases.sh
        echo "alias pa='php artisan'" >>$LARADOCK_PATH/workspace/aliases.sh
    fi

    if [[ $INSTALL == "y" ]]; then
        cp $LARAVEL_PATH/.env.example $LARAVEL_PATH/.env

        if [[ $PRODUCTION == "y" ]]; then
            sed -i "s|APP_ENV=.*|APP_ENV=production|" $LARAVEL_PATH/.env
            sed -i "s|APP_DEBUG=.*|APP_DEBUG=false|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_HOST=.*|MAIL_HOST=$MAIL_HOST|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_USERNAME=.*|MAIL_USERNAME=$MAIL_USERNAME|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_PASSWORD=.*|MAIL_PASSWORD=$MAIL_PASSWORD|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_ENCRYPTION=.*|MAIL_ENCRYPTION=$MAIL_ENCRYPTION|" $LARAVEL_PATH/.env
            sed -i "s|RESPONSE_CACHE_ENABLED=.*|RESPONSE_CACHE_ENABLED=true|" $LARAVEL_PATH/.env
        else
            sed -i "s|APP_ENV=.*|APP_ENV=local|" $LARAVEL_PATH/.env
            sed -i "s|APP_DEBUG=.*|APP_DEBUG=true|" $LARAVEL_PATH/.env
            sed -i "s|RESPONSE_CACHE_ENABLED=.*|RESPONSE_CACHE_ENABLED=false|" $LARAVEL_PATH/.env
        fi

        sed -i "s|DB_HOST=.*|DB_HOST=$DB_ENGINE|" $LARAVEL_PATH/.env
        sed -i "s|REDIS_HOST=.*|REDIS_HOST=redis|" $LARAVEL_PATH/.env

        sed -i "s|LOG_CHANNEL=.*|LOG_CHANNEL=daily|" $LARAVEL_PATH/.env
        sed -i "s|BROADCAST_DRIVER=.*|BROADCAST_DRIVER=redis|" $LARAVEL_PATH/.env
        sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|" $LARAVEL_PATH/.env
        sed -i "s|QUEUE_CONNECTION=.*|QUEUE_CONNECTION=sync|" $LARAVEL_PATH/.env
        sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|" $LARAVEL_PATH/.env

        sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" $LARAVEL_PATH/.env
        sed -i "s|APP_NAME=.*|APP_NAME=$APP_NAME|" $LARAVEL_PATH/.env
        sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" $LARAVEL_PATH/.env
        sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USERNAME|" $LARAVEL_PATH/.env
        sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" $LARAVEL_PATH/.env
        sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD|" $LARAVEL_PATH/.env
    fi
}

_crontab() {
    if [[ $PRODUCTION == "y" ]] && [[ $TARGET != "docker" ]]; then
        if ! grep -q "$LARADOCK_PATH && docker-compose up -d" /etc/crontab; then
            sudo echo "@reboot root  cd $LARADOCK_PATH && docker-compose up -d $CONTAINERS" >>/etc/crontab
        fi

        if ! grep -q "$SCRIPT_PATH deploy" /etc/crontab; then
            sudo echo "0 5 * * * root  $SCRIPT_PATH deploy" >>/etc/crontab
        fi
    fi
}

_backup() {
    if [[ ! -d "$LARAVEL_PATH/storage/app/databases" ]] && [[ $TARGET != "docker" ]]; then
        mkdir -p $LARAVEL_PATH/storage/app/databases
    fi
    if [[ $TARGET == "deploy" ]] && [[ $INSTALL != "y" ]] && [[ $PRODUCTION == "y" ]]; then
        cd $LARADOCK_PATH
        docker-compose -T workspace mysqldump \
            --force \
            --skip-lock-tables \
            --host=$DB_ENGINE \
            --port=$(grep DB_PORT $LARAVEL_PATH/.env | cut -d '=' -f2) \
            -p$DB_PASSWORD \
            --user=$DB_USERNAME \
            --databases $DB_DATABASE \
            --ignore-table=$DB_DATABASE.migrations \
            --ignore-table=$DB_DATABASE.telescope_entries \
            --ignore-table=$DB_DATABASE.telescope_entries_tags \
            --ignore-table=$DB_DATABASE.telescope_monitoring \
            --result-file=./storage/app/databases/$(date '+%y-%m-%d_%H:%M').sql
    fi
}

_mysql() {
    if ! grep -q "max_allowed_packet=16M" $LARADOCK_PATH/$DB_ENGINE/my.cnf; then
        echo "" >$LARADOCK_PATH/$DB_ENGINE/my.cnf
        echo "[mysqld]" >>$LARADOCK_PATH/$DB_ENGINE/my.cnf
        echo "max_allowed_packet=16M" >>$LARADOCK_PATH/$DB_ENGINE/my.cnf
    fi

    if [[ $TARGET == "deploy" ]]; then
        cd $LARADOCK_PATH
        docker-compose up -d $DB_ENGINE

        if [[ $(docker-compose -T $DB_ENGINE mysql -u root -p$DB_ROOT_PASSWORD -e "SHOW DATABASES;") == *"ERROR"* ]] ||
            [[ $(docker-compose -T $DB_ENGINE mysql -u $DB_USERNAME -p$DB_PASSWORD -e "SHOW DATABASES;") == *"ERROR"* ]]; then
            if [[ $INSTALL == "y" ]]; then
                rm -rf ~/.laradock/data/$DB_ENGINE
                docker-compose build --no-cache $DB_ENGINE
                docker-compose up -d $DB_ENGINE
            fi

            SQL="ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';"
            SQL+="CREATE DATABASE IF NOT EXISTS $DB_DATABASE COLLATE 'utf8_general_ci';"
            SQL+="CREATE USER '$DB_USERNAME'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
            SQL+="ALTER USER '$DB_USERNAME'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
            SQL+="GRANT ALL ON $DB_DATABASE.* TO '$DB_USERNAME'@'localhost';"
            SQL+="FLUSH PRIVILEGES;"
            SQL+=${SQL//localhost/%}
            IFS=';' read -r -a SQL_ARRAY <<<"$SQL"

            if [[ $(docker-compose -T $DB_ENGINE mysql -u root -e "SHOW DATABASES;") != *"ERROR"* ]]; then
                DB_COMPOSE="docker-compose -T  $DB_ENGINE mysql -u root -e"
            elif [[ $(docker-compose -T $DB_ENGINE mysql -u root -p$DB_ROOT_PASSWORD -e "SHOW DATABASES;") != *"ERROR"* ]]; then
                DB_COMPOSE="docker-compose -T  $DB_ENGINE mysql -u root -p$DB_ROOT_PASSWORD -e"
            elif [[ $(docker-compose -T $DB_ENGINE mysql -u root -proot -e "SHOW DATABASES;") != *"ERROR"* ]]; then
                DB_COMPOSE="docker-compose -T  $DB_ENGINE mysql -u root -proot -e"
            elif [[ $(docker-compose -T $DB_ENGINE mysql -u root -psecret -e "SHOW DATABASES;") != *"ERROR"* ]]; then
                DB_COMPOSE="docker-compose -T  $DB_ENGINE mysql -u root -psecret -e"
            fi

            if [[ ! -z $DB_COMPOSE ]]; then
                for QUERY in "${SQL_ARRAY[@]}"; do
                    $DB_COMPOSE "$QUERY;"
                done
            else
                echo -e "Please config db manualy:\n"
                for QUERY in "${SQL_ARRAY[@]}"; do
                    echo "$QUERY;"
                done
                read OK
            fi
        fi
    fi
}

_nginx() {
    if [[ $TARGET != "docker" ]] && [[ $INSTALL == "y" ]]; then
        rm -f $LARADOCK_PATH/nginx/sites/default.conf
        wget -N https://raw.githubusercontent.com/alirezamaleky/nginx-config/master/default.conf -P $LARADOCK_PATH/nginx/sites
        sed -i "s|server_name localhost;|server_name $DOMAIN;|" $LARADOCK_PATH/nginx/sites/default.conf

        cd $LARADOCK_PATH
        docker-compose build --no-cache nginx
        docker-compose up -d nginx
    fi
}

_redis() {
    if [[ $INSTALL == "y" ]]; then
        sed -i "s|REDIS_PORT=.*|REDIS_PORT=127.0.0.1:6379|" $LARADOCK_PATH/.env
        sed -i "s|bind 127.0.0.1|#bind 127.0.0.1|" $LARADOCK_PATH/redis/redis.conf
        sed -i "s|build: ./redis|build:\n        context: ./redis\n        args:\n            REDIS_PASSWORD: \${REDIS_PASSWORD}|" $LARADOCK_PATH/docker-compose.yml
        if ! grep -q "requirepass __REDIS_PASSWORD__" $LARADOCK_PATH/redis/redis.conf; then
            echo "requirepass __REDIS_PASSWORD__" >>$LARADOCK_PATH/redis/redis.conf
        fi
        REDIS_DOCKERFILE='FROM redis:latest'
        REDIS_DOCKERFILE+='\n\nARG REDIS_PASSWORD=secret'
        REDIS_DOCKERFILE+='\n\nRUN mkdir -p /usr/local/etc/redis'
        REDIS_DOCKERFILE+='\nCOPY redis.conf /usr/local/etc/redis/redis.conf'
        REDIS_DOCKERFILE+='\nRUN sed -i "s|__REDIS_PASSWORD__|'$REDIS_PASSWORD'|g" /usr/local/etc/redis/redis.conf'
        REDIS_DOCKERFILE+='\n\nVOLUME /data'
        REDIS_DOCKERFILE+='\n\nEXPOSE 6379'
        REDIS_DOCKERFILE+='\n\nCMD ["redis-server", "/usr/local/etc/redis/redis.conf"]'
        echo -e $REDIS_DOCKERFILE >$LARADOCK_PATH/redis/Dockerfile
        docker-compose build --no-cache redis
        docker-compose up -d redis
    fi
}

_php() {
    if ! grep -q "puppeteer" $LARADOCK_PATH/php-fpm/Dockerfile; then
        echo "USER root" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN curl -sL https://deb.nodesource.com/setup_13.x | bash -" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN apt-get install -y nodejs gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN npm install --global --unsafe-perm puppeteer" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN chmod -R o+rx /usr/lib/node_modules/puppeteer/.local-chromium" >>$LARADOCK_PATH/php-fpm/Dockerfile
        docker-compose build --no-cache php-fpm
        docker-compose up -d php-fpm
    fi
}

_git() {
    if ! grep -q "deploy.sh" $LARAVEL_PATH/.gitignore; then
        echo "deploy.sh" >>$LARAVEL_PATH/.gitignore
    fi
    if ! grep -q "laradock" $LARAVEL_PATH/.gitignore; then
        echo "laradock" >>$LARAVEL_PATH/.gitignore
    fi

    if [[ $PRODUCTION == "y" ]]; then
        cd $LARAVEL_PATH
        git checkout -f .
        git pull origin master
    fi
}

_up() {
    cd $LARADOCK_PATH
    docker-compose up -d $CONTAINERS
    if [[ $TARGET == "deploy" ]]; then
        sudo docker-compose -T workspace "bash" /var/www/deploy.sh docker
    else
        docker-compose -T workspace bash
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
    else
        php artisan optimize:clear
        php artisan view:clear
    fi

    php artisan telescope:publish

    if [[ $PRODUCTION == "y" ]]; then
        yarn global add html-minifier
        html-minifier --collapse-whitespace --remove-comments --remove-optional-tags --remove-redundant-attributes --remove-script-type-attributes --remove-tag-whitespace --use-short-doctype --minify-css true --minify-js true --input-dir $LARAVEL_PATH/storage/framework/views --output-dir $LARAVEL_PATH/storage/framework/views --file-ext "php"
    fi
}

_permission() {
    killall find
    find $LARAVEL_PATH -type f -exec chmod 644 {} \;
    find $LARAVEL_PATH -type d -exec chmod 755 {} \;
    chmod -R 775 $LARAVEL_PATH/storage $LARAVEL_PATH/bootstrap/cache $LARAVEL_PATH/node_modules
    chmod -R 600 $LARAVEL_PATH/.env $LARAVEL_PATH/storage/app/databases
    chmod +x $LARAVEL_PATH/deploy.sh
    if [[ $PRODUCTION != "y" ]]; then
        chmod +x $LARAVEL_PATH/vendor/bin/phpunit
    fi
    chown -R laradock:laradock $LARAVEL_PATH
}

if [[ $TARGET == "docker" ]]; then
    _yarn
    _composer
    _laravel
    _permission

    echo "Deployment takes $((SECONDS - ELAPSED_SEC)) second."
else
    if [[ ! -z $USER ]]; then
        _laradock
        _env
        _crontab
        _backup
        _mysql
        _nginx
        _redis
        _php
        _git
        _up
    fi
fi
