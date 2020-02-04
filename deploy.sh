#!/bin/bash

DB_ENGINE=mariadb
CONTAINERS="nginx $DB_ENGINE redis"
if [[ ${PRODUCTION^^} != Y* ]]; then
    CONTAINERS+=" phpmyadmin"
# else
#     CONTAINERS+=" mailu"
fi

for ((i = 1; i <= $#; i++)); do
    if [[ ${!i} == "-p" ]] || [[ ${!i} == "--path" ]]; then
        ((i++))
        APP_DIR=${!i}
    elif [[ ${!i} = "-t" ]] || [[ ${!i} = "--target" ]]; then
        ((i++))
        TARGET=${!i}
    elif [[ ${!i} = "-s" ]] || [[ ${!i} = "--scripts" ]]; then
        ((i++))
        DEPLOY_SCRIPT=${!i}
    elif [[ ${!i} = "-u" ]] || [[ ${!i} = "--update" ]]; then
        FORCE_UPDATE="y"
    elif [[ ${!i} = "-h" ]] || [[ ${!i} = "--help" ]]; then
        echo "-p --path <path>    (folder path)"
        echo "-t --target deploy  (optional, if not set just workspace will load)"
        echo "-u --update         (force install project libraries even if not changed.)"
        echo "-f --format         (remove everything and fresh install docker and project)"
        exit
    fi
done

_path() {
    if [[ -z $APP_DIR ]]; then
        if [[ -d "$PWD/public" ]]; then
            APP_DIR=$(basename $PWD)
        else
            read -p "APP_DIR: " APP_DIR
        fi
    fi

    SCRIPT_PATH=$(realpath $0)
    LARAVEL_PATH=$(dirname $SCRIPT_PATH)/$APP_DIR
    LARADOCK_PATH=$(dirname $SCRIPT_PATH)/laradock

    if [[ -d "$(dirname $SCRIPT_PATH)/public" ]]; then
        echo "You must run this script in project parent folder!"
        rm -fv $SCRIPT_PATH
        exit
    elif [[ -z $APP_DIR ]] || [[ ! -d "$LARAVEL_PATH/public" ]]; then
        unset APP_DIR
        _path
    fi
}
_path

_format() {
    if [[ $TARGET != "docker" ]]; then
        RESET_WORKSPACE="y"

        read -p "RESET_LARADOCK [y/n]? " RESET_LARADOCK
        echo $RESET_LARADOCK
        if [[ ${RESET_LARADOCK^^} == Y* ]]; then
            if [[ ! -z $(docker container ls -aq) ]]; then
                docker container stop $(docker container ls -aq)
                docker container rm -fv $(docker container ls -aq)
            fi
            docker system prune -f --volumes
            sudo rm -fvr ~/.laradock $LARADOCK_PATH

            sudo sed -i "s|.*$SCRIPT_PATH.*||" /etc/crontab
            sudo sed -i "s|.*truncate -s 0 /var/lib/docker/containers.*||" /etc/crontab
        else
            sed -i "s|.*/var/www/$APP_DIR/artisan.*||" $LARADOCK_PATH/workspace/crontab/laradock
            sed -i "/^$/d" $LARADOCK_PATH/workspace/crontab/laradock
            rm -fv $LARADOCK_PATH/$DB_ENGINE/docker-entrypoint-initdb.d/$APP_DIR.sql
            rm -fv $LARADOCK_PATH/nginx/sites/$APP_DIR.conf
        fi

        sudo sed -i "s|.*cd $LARADOCK_PATH && docker-compose up.*||" /etc/crontab
        sudo sed -i "s|.*$SCRIPT_PATH --target deploy --path $APP_DIR .*||" /etc/crontab
        sudo sed -i "/^$/d" /etc/crontab

        sudo sed -i "s|.*127.0.0.1 $APP_DIR..*||" /etc/hosts
        sudo sed -i "/^$/d" /etc/hosts

        sudo git -C $LARAVEL_PATH clean -fxd
        sudo git -C $LARAVEL_PATH checkout -f $LARAVEL_PATH
    fi
}
if [[ "$*" == *-f* ]] || [[ "$*" == *--format* ]]; then
    _format
fi

_getenv() {
    if [[ ! -d "$LARADOCK_PATH" ]] || [[ ! -d "$LARAVEL_PATH/vendor" ]] || [[ ! -d "$LARAVEL_PATH/node_modules" ]]; then
        if [[ -z $INSTALL ]] && [[ $TARGET != "docker" ]] && [[ -f "$LARAVEL_PATH/.env" ]] && [[ -f "$LARADOCK_PATH/.env" ]]; then
            read -e -p "Is this first install? [y/n] " -i "y" INSTALL
        fi
        INSTALL=${INSTALL:-y}
    fi

    if [[ -f $LARAVEL_PATH/.env ]] && [[ $(grep APP_ENV $LARAVEL_PATH/.env | cut -d "=" -f2) == "production" ]]; then
        PRODUCTION="y"
    elif [[ ${INSTALL^^} == Y* ]] && [[ $TARGET != "docker" ]]; then
        read -p "Is the project in production? [y/n] " PRODUCTION
    fi

    if [[ ${INSTALL^^} == Y* ]] && [[ $TARGET != "docker" ]] && [[ ${RESET_WORKSPACE^^} != Y* ]]; then
        read -e -p "RESET_DATABASE [y/n]? " -i "n" RESET_DATABASE
    fi

    if [[ -f $LARAVEL_PATH/.env ]]; then
        DB_DATABASE=$(grep DB_DATABASE $LARAVEL_PATH/.env | cut -d "=" -f2)
        DB_USERNAME=$(grep DB_USERNAME $LARAVEL_PATH/.env | cut -d "=" -f2)
        DB_PASSWORD=$(grep DB_PASSWORD $LARAVEL_PATH/.env | cut -d "=" -f2)
    fi
    if [[ -f $LARADOCK_PATH/.env ]]; then
        REDIS_PASSWORD=$(grep REDIS_STORAGE_SERVER_PASSWORD $LARADOCK_PATH/.env | cut -d "=" -f2)
        DB_ROOT_PASSWORD=$(grep ${DB_ENGINE^^}_ROOT_PASSWORD $LARADOCK_PATH/.env | cut -d "=" -f2)
    fi

    if [[ ${INSTALL^^} == Y* ]] && [[ $TARGET != "docker" ]]; then
        read -e -p "DOMAIN: " -i "$APP_DIR." DOMAIN
        read -e -p "APP_NAME: " -i "$APP_DIR" APP_NAME
        read -e -p "PMA_PORT: " -i "8001" PMA_PORT

        if [[ ${PRODUCTION^^} == Y* ]]; then
            read -e -p "MAIL_USERNAME: " -i "info@$DOMAIN" MAIL_USERNAME
            read -e -p "MAIL_ENCRYPTION: " -i "tls" MAIL_ENCRYPTION
        fi

        DB_DATABASE="${APP_DIR}_db"
        DB_USERNAME="${APP_DIR}_user"
        DB_PASSWORD=$(openssl rand -base64 15)
        MAIL_HOST="mail.$DOMAIN"
        MAIL_PASSWORD=$(openssl rand -base64 15)
        if [[ ${#DB_ROOT_PASSWORD} < 15 ]]; then
            DB_ROOT_PASSWORD=$(openssl rand -base64 15)
        fi
        if [[ ${#REDIS_PASSWORD} < 15 ]]; then
            REDIS_PASSWORD=$(openssl rand -base64 15)
        fi
    fi

    if ([[ ${INSTALL^^} == Y* ]] || [[ ${FORCE_UPDATE^^} == Y* ]]) && (
        ! grep -q "/var/www/$APP_DIR" $LARADOCK_PATH/workspace/crontab/laradock ||
            ! grep -q "cd $LARADOCK_PATH && docker-compose up" /etc/crontab ||
            ! grep -q "$SCRIPT_PATH --target deploy --path $APP_DIR" /etc/crontab
    ); then
        read -p "Do you want write crons? [y/n] " WRITE_CRONS
    fi
}
_getenv

_laradock() {
    if [[ ! -d "$LARADOCK_PATH" ]]; then
        wget -N https://github.com/laradock/laradock/archive/master.zip -P $LARAVEL_PATH &&
            unzip $LARAVEL_PATH/master.zip -d $LARAVEL_PATH &&
            mv $LARAVEL_PATH/laradock-master $LARADOCK_PATH &&
            rm -fv $LARAVEL_PATH/master.zip
    fi

    if [[ -d $LARADOCK_PATH ]]; then
        if ! grep -q "nr=" $LARADOCK_PATH/workspace/aliases.sh; then
            echo "alias nr='npm run'" >>$LARADOCK_PATH/workspace/aliases.sh
        fi
        if ! grep -q "pa=" $LARADOCK_PATH/workspace/aliases.sh; then
            echo "alias pa='php artisan'" >>$LARADOCK_PATH/workspace/aliases.sh
        fi
        cd $LARADOCK_PATH
    else
        _laradock
    fi
}

_swap() {
    if [[ ! -f /swapfile ]]; then
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
    fi
}

_setenv() {
    if [[ ${INSTALL^^} == Y* ]]; then
        if [[ ! -f "$LARADOCK_PATH/.env" ]]; then
            cp $LARADOCK_PATH/env-example $LARADOCK_PATH/.env
        fi

        sed -i "s|PHP_FPM_INSTALL_SOAP=.*|PHP_FPM_INSTALL_SOAP=true|" $LARADOCK_PATH/.env
        sed -i "s|PHP_FPM_INSTALL_SWOOLE=.*|PHP_FPM_INSTALL_SWOOLE=true|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_SWOOLE=.*|WORKSPACE_INSTALL_SWOOLE=true|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_MYSQL_CLIENT=.*|WORKSPACE_INSTALL_MYSQL_CLIENT=true|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_NPM_GULP=.*|WORKSPACE_INSTALL_NPM_GULP=false|" $LARADOCK_PATH/.env
        sed -i "s|WORKSPACE_INSTALL_NPM_VUE_CLI=.*|WORKSPACE_INSTALL_NPM_VUE_CLI=false|" $LARADOCK_PATH/.env

        sed -i "s|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|MARIADB_ROOT_PASSWORD=.*|MARIADB_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|PMA_DB_ENGINE=.*|PMA_DB_ENGINE=$DB_ENGINE|" $LARADOCK_PATH/.env
        sed -i "s|PMA_PORT=.*|PMA_PORT=$PMA_PORT|" $LARADOCK_PATH/.env
        sed -i "s|PMA_USER=.*|PMA_USER=root|" $LARADOCK_PATH/.env
        sed -i "s|PMA_PASSWORD=.*|PMA_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|PMA_ROOT_PASSWORD=.*|PMA_ROOT_PASSWORD=$DB_ROOT_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|REDIS_STORAGE_SERVER_PASSWORD=.*|REDIS_STORAGE_SERVER_PASSWORD=$REDIS_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|REDIS_RESULT_STORAGE_SERVER_PASSWORD=.*|REDIS_RESULT_STORAGE_SERVER_PASSWORD=$REDIS_PASSWORD|" $LARADOCK_PATH/.env
        sed -i "s|REDIS_QUEUE_SERVER_PASSWORD=.*|REDIS_QUEUE_SERVER_PASSWORD=$REDIS_PASSWORD|" $LARADOCK_PATH/.env

        if [[ ${PRODUCTION^^} == Y* ]]; then
            sed -i "s|MAILU_DOMAIN=.*|MAILU_DOMAIN=$DOMAIN|" $LARADOCK_PATH/.env
            sed -i "s|MAILU_HOSTNAMES=.*|MAILU_HOSTNAMES=$MAIL_HOST|" $LARADOCK_PATH/.env
            sed -i "s|MAILU_SECRET_KEY=.*|MAILU_SECRET_KEY=$(openssl rand -base64 16)|" $LARADOCK_PATH/.env
            sed -i "s|MAILU_INIT_ADMIN_USERNAME=.*|MAILU_INIT_ADMIN_USERNAME=$MAIL_USERNAME|" $LARADOCK_PATH/.env
            sed -i "s|MAILU_INIT_ADMIN_PASSWORD=.*|MAILU_INIT_ADMIN_PASSWORD=$MAIL_PASSWORD|" $LARADOCK_PATH/.env
        fi
    fi

    if [[ ${INSTALL^^} == Y* ]]; then
        if [[ ! -f "$LARAVEL_PATH/.env" ]]; then
            cp $LARAVEL_PATH/.env.example $LARAVEL_PATH/.env
        fi

        if [[ ${PRODUCTION^^} == Y* ]]; then
            sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" $LARAVEL_PATH/.env
            sed -i "s|APP_ENV=.*|APP_ENV=production|" $LARAVEL_PATH/.env
            sed -i "s|APP_DEBUG=.*|APP_DEBUG=false|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_HOST=.*|MAIL_HOST=$MAIL_HOST|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_USERNAME=.*|MAIL_USERNAME=$MAIL_USERNAME|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_PASSWORD=.*|MAIL_PASSWORD=$MAIL_PASSWORD|" $LARAVEL_PATH/.env
            sed -i "s|MAIL_ENCRYPTION=.*|MAIL_ENCRYPTION=$MAIL_ENCRYPTION|" $LARAVEL_PATH/.env
            sed -i "s|RESPONSE_CACHE_ENABLED=.*|RESPONSE_CACHE_ENABLED=true|" $LARAVEL_PATH/.env
        else
            sed -i "s|APP_URL=.*|APP_URL=http://$DOMAIN|" $LARAVEL_PATH/.env
            sed -i "s|APP_ENV=.*|APP_ENV=local|" $LARAVEL_PATH/.env
            sed -i "s|APP_DEBUG=.*|APP_DEBUG=true|" $LARAVEL_PATH/.env
            sed -i "s|RESPONSE_CACHE_ENABLED=.*|RESPONSE_CACHE_ENABLED=false|" $LARAVEL_PATH/.env
        fi

        sed -i "s|DB_HOST=.*|DB_HOST=$DB_ENGINE|" $LARAVEL_PATH/.env
        sed -i "s|REDIS_HOST=.*|REDIS_HOST=redis|" $LARAVEL_PATH/.env

        sed -i "s|BROADCAST_DRIVER=.*|BROADCAST_DRIVER=redis|" $LARAVEL_PATH/.env
        sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|" $LARAVEL_PATH/.env
        sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|" $LARAVEL_PATH/.env

        sed -i "s|APP_NAME=.*|APP_NAME=$APP_NAME|" $LARAVEL_PATH/.env
        sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" $LARAVEL_PATH/.env
        sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USERNAME|" $LARAVEL_PATH/.env
        sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" $LARAVEL_PATH/.env
        sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD|" $LARAVEL_PATH/.env
    fi
}

_crontab() {
    if [[ ${PRODUCTION^^} == Y* ]] || [[ ${WRITE_CRONS^^} == Y* ]]; then
        if grep -q "/var/www/artisan" $LARADOCK_PATH/workspace/crontab/laradock; then
            echo "" >$LARADOCK_PATH/workspace/crontab/laradock
        fi
        if ! grep -q "$APP_DIR/artisan" $LARADOCK_PATH/workspace/crontab/laradock; then
            echo "* * * * * laradock /usr/bin/php /var/www/$APP_DIR/artisan schedule:run >/dev/null 2>&1" >>$LARADOCK_PATH/workspace/crontab/laradock
            echo "@reboot laradock /usr/bin/php /var/www/$APP_DIR/artisan queue:work --timeout=60 --sleep=3 >/dev/null 2>&1" >>$LARADOCK_PATH/workspace/crontab/laradock
        fi
    fi
    if ! grep -q "$APP_DIR/artisan swoole:http" $LARADOCK_PATH/workspace/crontab/laradock; then
        echo "@reboot laradock /usr/bin/php /var/www/$APP_DIR/artisan swoole:http restart >/dev/null 2>&1" >>$LARADOCK_PATH/workspace/crontab/laradock
    fi

    if [[ ${PRODUCTION^^} == Y* ]] || [[ ${WRITE_CRONS^^} == Y* ]]; then
        sudo systemctl enable cron || sudo systemctl enable crond
        if ! grep -q "cd $LARADOCK_PATH && docker-compose up" /etc/crontab; then
            sudo bash -c "echo '@reboot root cd $LARADOCK_PATH && docker-compose up -d $CONTAINERS >/dev/null 2>&1' >>/etc/crontab"
        fi

        if ! grep -q "$SCRIPT_PATH --target deploy --path $APP_DIR" /etc/crontab; then
            sudo bash -c "echo '0 5 * * * root  $SCRIPT_PATH --target deploy --path $APP_DIR >/dev/null 2>&1' >>/etc/crontab"
        fi
    fi

    if ! grep -q "truncate -s 0 /var/lib/docker/containers/" /etc/crontab; then
        sudo bash -c "echo '@weekly root truncate -s 0 /var/lib/docker/containers/*/*-json.log' >>/etc/crontab"
    fi
}

_mysql() {
    if [[ $TARGET == "deploy" ]]; then
        if [[ ${DB_WAITING^^} != Y* ]]; then
            if [[ ${RESET_DATABASE^^} == Y* ]]; then
                sudo rm -fvr ~/.laradock/data/$DB_ENGINE
                docker-compose build --no-cache $DB_ENGINE
            fi
            docker-compose up -d $DB_ENGINE

            if ! grep -q "max_allowed_packet=16M" $LARADOCK_PATH/$DB_ENGINE/my.cnf; then
                echo "[mysqld]" >$LARADOCK_PATH/$DB_ENGINE/my.cnf
                echo "max_allowed_packet=16M" >>$LARADOCK_PATH/$DB_ENGINE/my.cnf
            fi

            INITDB_FILE="$LARADOCK_PATH/$DB_ENGINE/docker-entrypoint-initdb.d/$APP_DIR.sql"
            if [[ ! -f $INITDB_FILE ]]; then
                rm -fv $LARADOCK_PATH/$DB_ENGINE/docker-entrypoint-initdb.d/*.example
                SQL="DROP USER IF EXISTS 'default'@'%';"
                SQL+="CREATE USER IF NOT EXISTS '$DB_USERNAME'@'%' IDENTIFIED BY '$DB_PASSWORD';"
                SQL+="ALTER USER '$DB_USERNAME'@'%' IDENTIFIED BY '$DB_PASSWORD';"
                SQL+="CREATE DATABASE IF NOT EXISTS $DB_DATABASE COLLATE 'utf8_general_ci';"
                SQL+="GRANT ALL ON $DB_DATABASE.* TO '$DB_USERNAME'@'%';"
                SQL+="FLUSH PRIVILEGES;"
                IFS=';' read -r -a SQL_ARRAY <<<$SQL
                rm -fv $INITDB_FILE
                for QUERY in "${SQL_ARRAY[@]}"; do
                    echo "$QUERY;" >>$INITDB_FILE
                done
                RELOAD_DATABASE="y"
            fi
        fi

        if [[ ${RELOAD_DATABASE^^} == Y* ]]; then
            if ! eval "docker-compose exec $DB_ENGINE mysql -u root -p$DB_ROOT_PASSWORD -e 'SHOW DATABASES;'"; then
                DB_WAITING="y"
                sleep 5
                _mysql
            else
                eval "docker-compose exec $DB_ENGINE mysql -u root -p$DB_ROOT_PASSWORD -e 'source /docker-entrypoint-initdb.d/$APP_DIR.sql;'"
            fi
        fi
    fi
}
_swoole() {
    if [[ ${INSTALL^^} == Y* ]]; then
        for i in {1251..1400}; do
            if ! grep -q "^EXPOSE.*$i" $LARADOCK_PATH/workspace/Dockerfile; then
                SWOOLE_PORT=$i
                break
            fi
        done

        if grep -q "^EXPOSE" $LARADOCK_PATH/workspace/Dockerfile; then
            sed -i "s|^EXPOSE .*|& $SWOOLE_PORT|" $LARADOCK_PATH/workspace/Dockerfile
        else
            echo -e "\nEXPOSE $SWOOLE_PORT" >>$LARADOCK_PATH/workspace/Dockerfile
        fi

        if grep -q "SWOOLE_HTTP_PORT" $LARAVEL_PATH/.env; then
            sed -i "s|SWOOLE_HTTP_PORT=.*|SWOOLE_HTTP_PORT=$SWOOLE_PORT|" $LARAVEL_PATH/.env
        else
            echo -e"\n\nSWOOLE_HTTP_PORT=$SWOOLE_PORT" >>$LARAVEL_PATH/.env
        fi

        if grep -q "SWOOLE_HTTP_HOST" $LARAVEL_PATH/.env; then
            sed -i "s|SWOOLE_HTTP_HOST=.*|SWOOLE_HTTP_HOST=workspace|" $LARAVEL_PATH/.env
        else
            echo "SWOOLE_HTTP_HOST=workspace" >>$LARAVEL_PATH/.env
        fi

        if grep -q "SWOOLE_HTTP_DAEMONIZE" $LARAVEL_PATH/.env; then
            sed -i "s|SWOOLE_HTTP_DAEMONIZE=.*|SWOOLE_HTTP_DAEMONIZE=true|" $LARAVEL_PATH/.env
        else
            echo "SWOOLE_HTTP_DAEMONIZE=true" >>$LARAVEL_PATH/.env
        fi
    fi
}

_nginx() {
    if [[ ${INSTALL^^} == Y* ]]; then
        rm -fv $LARADOCK_PATH/nginx/sites/default.conf $LARADOCK_PATH/nginx/sites/*.example
        wget -N https://raw.githubusercontent.com/alirezamaleky/nginx-config/master/default.conf -P $LARADOCK_PATH/nginx/sites
        mv $LARADOCK_PATH/nginx/sites/default.conf $LARADOCK_PATH/nginx/sites/$APP_DIR.conf

        sed -i "s|/var/www/public;|/var/www/$APP_DIR/public;|" $LARADOCK_PATH/nginx/sites/$APP_DIR.conf
        sed -i "s|server_name localhost;|server_name $DOMAIN;|" $LARADOCK_PATH/nginx/sites/$APP_DIR.conf
        sed -i "s|upstream websocket.*;|upstream websocket_$SWOOLE_PORT {|" $LARADOCK_PATH/nginx/sites/$APP_DIR.conf
        sed -i "s|proxy_pass http://websocket|proxy_pass http://websocket_$SWOOLE_PORT|" $LARADOCK_PATH/nginx/sites/$APP_DIR.conf
        sed -i "s|server workspace:.*;|server workspace:$SWOOLE_PORT;|" $LARADOCK_PATH/nginx/sites/$APP_DIR.conf

        if ! grep -q "$DOMAIN" /etc/hosts; then
            sudo bash -c "echo '127.0.0.1 $DOMAIN' >>/etc/hosts"
        fi

        docker-compose build --no-cache nginx || docker-compose restart nginx
    fi
}

_redis() {
    if [[ ${INSTALL^^} == Y* ]]; then
        sed -i "s|^REDIS_PORT=.*|REDIS_PORT=127.0.0.1:6379|" $LARADOCK_PATH/.env

        sed -i "s|^bind|#bind|" $LARADOCK_PATH/redis/redis.conf
        if ! grep -q "^requirepass" $LARADOCK_PATH/redis/redis.conf; then
            echo -e "\nrequirepass $REDIS_PASSWORD" >>$LARADOCK_PATH/redis/redis.conf
        else
            sed -i "s|^requirepass.*|requirepass $REDIS_PASSWORD|" $LARADOCK_PATH/redis/redis.conf
        fi

        sed -i "s|^#RUN|RUN|" $LARADOCK_PATH/redis/Dockerfile
        sed -i "s|^#COPY|COPY|" $LARADOCK_PATH/redis/Dockerfile
        sed -i 's|^CMD.*|CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]|' $LARADOCK_PATH/redis/Dockerfile

        docker-compose build --no-cache redis
    fi
}

_php() {
    if [[ ${INSTALL^^} == Y* ]] && [[ ${PRODUCTION^^} == Y* ]] && ! grep -q "puppeteer" $LARADOCK_PATH/php-fpm/Dockerfile; then
        echo "USER root" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN curl -sL https://deb.nodesource.com/setup_13.x | bash -" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN apt-get install -y nodejs gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN npm install --global --unsafe-perm puppeteer" >>$LARADOCK_PATH/php-fpm/Dockerfile
        echo "RUN chmod -R o+rx /usr/lib/node_modules/puppeteer/.local-chromium" >>$LARADOCK_PATH/php-fpm/Dockerfile
        docker-compose build --no-cache php-fpm
    fi
}

_git() {
    if [[ ${PRODUCTION^^} == Y* ]] && [[ $TARGET == "deploy" ]]; then
        sudo git -C $LARAVEL_PATH checkout -f master
        sudo git -C $LARAVEL_PATH checkout -f $LARAVEL_PATH
    fi

    if [[ ${INSTALL^^} != Y* ]]; then
        git -C $LARAVEL_PATH fetch origin master
        DIFF_SCRIPT="git -C $LARAVEL_PATH diff master origin/master --name-only --"
        if [[ $($DIFF_SCRIPT yarn.lock package.json package-lock.json resources/fonts/ resources/images/ resources/js/ resources/css/ resources/scss/ resources/sass/ resources/vue/) ]]; then
            DEPLOY_SCRIPT+="_yarn,"
        fi
        if [[ $($DIFF_SCRIPT composer.lock composer.json) ]]; then
            DEPLOY_SCRIPT+="_composer,"
        fi
        if [[ $($DIFF_SCRIPT database/) ]]; then
            DEPLOY_SCRIPT+="_backup,_migrate,"
        fi
        if [[ $($DIFF_SCRIPT resources/views/) ]]; then
            DEPLOY_SCRIPT+="_blade"
        fi
    fi

    if [[ ${PRODUCTION^^} == Y* ]] && [[ $TARGET == "deploy" ]]; then
        git -C $LARAVEL_PATH pull origin master
    fi
}

_up() {
    docker-compose up -d $CONTAINERS
    if [[ $TARGET == "deploy" ]]; then
        COMPOSE_SCRIPT="sudo docker-compose exec -T workspace /var/www/deploy.sh --target docker --path $APP_DIR"
        if [[ ${FORCE_UPDATE^^} == Y* ]]; then
            COMPOSE_SCRIPT+=" --update"
        fi
        if [[ ! -z $DEPLOY_SCRIPT ]]; then
            COMPOSE_SCRIPT+=" --scripts $DEPLOY_SCRIPT"
        fi
        eval $COMPOSE_SCRIPT
    else
        docker-compose exec workspace bash -c "cd $APP_DIR; bash"
    fi
}

_yarn() {
    killall yarn npm
    if [[ ${PRODUCTION^^} == Y* ]]; then
        yarn --cwd $LARAVEL_PATH install --production --pure-lockfile --non-interactive
    else
        yarn --cwd $LARAVEL_PATH install
    fi
    yarn --cwd $LARAVEL_PATH run prod
}

_composer() {
    killall composer
    if ! eval "composer global show" || ! eval "composer global show" | grep "hirak/prestissimo"; then
        composer global require hirak/prestissimo
    fi

    if ! eval "composer --working-dir=$LARAVEL_PATH show" | grep "swooletw/laravel-swoole"; then
        composer --working-dir=$LARAVEL_PATH require swooletw/laravel-swoole
    fi

    if [[ ${PRODUCTION^^} == Y* ]]; then
        composer --working-dir=$LARAVEL_PATH install --optimize-autoloader --no-dev --no-interaction --prefer-dist
    else
        composer --working-dir=$LARAVEL_PATH install
    fi

    if [[ ${INSTALL^^} == Y* ]]; then
        composer --working-dir=$LARAVEL_PATH run-script "post-autoload-dump"
        composer --working-dir=$LARAVEL_PATH run-script "post-root-package-install"
        composer --working-dir=$LARAVEL_PATH run-script "post-create-project-cmd"
    fi
}

_backup() {
    if [[ ! -d "$LARAVEL_PATH/storage/app/databases" ]]; then
        mkdir -p $LARAVEL_PATH/storage/app/databases
    fi
    if [[ ${INSTALL^^} != Y* ]] && [[ ${PRODUCTION^^} == Y* ]]; then
        mysqldump \
            --force \
            --skip-lock-tables \
            --host=$DB_ENGINE \
            --port=$(grep DB_PORT $LARAVEL_PATH/.env | cut -d "=" -f2) \
            -p$DB_PASSWORD \
            --user=$DB_USERNAME \
            --databases $DB_DATABASE \
            --ignore-table=$DB_DATABASE.migrations \
            --ignore-table=$DB_DATABASE.telescope_entries \
            --ignore-table=$DB_DATABASE.telescope_entries_tags \
            --ignore-table=$DB_DATABASE.telescope_monitoring \
            --result-file=/var/www/$APP_DIR/storage/app/databases/$(date "+%y-%m-%d_%H:%M").sql
    fi
}

_migrate() {
    if [[ ${PRODUCTION^^} == Y* ]]; then
        if [[ ${INSTALL^^} == Y* ]]; then
            php $LARAVEL_PATH/artisan migrate --force --seed
        else
            php $LARAVEL_PATH/artisan migrate --force
        fi
    else
        php $LARAVEL_PATH/artisan migrate:fresh --force --seed
    fi
}

_blade() {
    if [[ ${PRODUCTION^^} == Y* ]]; then
        php $LARAVEL_PATH/artisan view:clear
        php $LARAVEL_PATH/artisan view:cache
    else
        php $LARAVEL_PATH/artisan view:clear
    fi

    if [[ ${PRODUCTION^^} == Y* ]]; then
        yarn global add html-minifier
        html-minifier --collapse-whitespace --remove-comments --remove-optional-tags --remove-redundant-attributes --remove-script-type-attributes --remove-tag-whitespace --use-short-doctype --minify-css true --minify-js true --input-dir $LARAVEL_PATH/storage/framework/views --output-dir $LARAVEL_PATH/storage/framework/views --file-ext "php"
    fi
}

_optimize() {
    if [[ ${PRODUCTION^^} == Y* ]]; then
        php $LARAVEL_PATH/artisan config:cache
        php $LARAVEL_PATH/artisan route:cache
    else
        php $LARAVEL_PATH/artisan cache:clear
        php $LARAVEL_PATH/artisan route:clear
        php $LARAVEL_PATH/artisan config:clear
        php $LARAVEL_PATH/artisan clear-compiled
    fi
}

_laravel() {
    if [[ ${INSTALL^^} == Y* ]]; then
        php $LARAVEL_PATH/artisan storage:link
    fi

    php $LARAVEL_PATH/artisan swoole:http restart

    php $LARAVEL_PATH/artisan telescope:publish

    if [[ ${PRODUCTION^^} != Y* ]]; then
        php $LARAVEL_PATH/artisan ide-helper:generate
        php $LARAVEL_PATH/artisan ide-helper:models -N
        mv -f _ide_helper*.php $LARAVEL_PATH
    fi
}

_queue() {
    if [[ ${INSTALL^^} != Y* ]]; then
        php $LARAVEL_PATH/artisan queue:restart
    fi
}

_permission() {
    if [[ ${INSTALL^^} == Y* ]] && [[ ${PRODUCTION^^} != Y* ]]; then
        killall find
        find $LARAVEL_PATH -type f -exec chmod 644 {} \;
        find $LARAVEL_PATH -type d -exec chmod 755 {} \;
    fi
    chmod -R 775 $LARAVEL_PATH/storage $LARAVEL_PATH/bootstrap/cache $LARAVEL_PATH/node_modules
    chmod -R 600 $LARAVEL_PATH/.env $LARAVEL_PATH/storage/app/databases
    chmod +x $SCRIPT_PATH
    if [[ -f "$LARAVEL_PATH/vendor/bin/phpunit" ]]; then
        chmod +x $LARAVEL_PATH/vendor/bin/phpunit
    fi
    chown -R laradock:laradock $LARAVEL_PATH
}

_router() {
    ELAPSED_SEC=$SECONDS

    if [[ $TARGET == "docker" ]]; then
        if [[ ${FORCE_UPDATE^^} == Y* ]] || [[ ${INSTALL^^} == Y* ]]; then
            _yarn
            _composer
            _backup
            _migrate
            _blade
        else
            IFS=',' read -r -a SCRIPT_ARRAY <<<$DEPLOY_SCRIPT
            for SCRIPT in "${SCRIPT_ARRAY[@]}"; do
                $SCRIPT
            done
        fi
        _optimize
        _laravel
        _queue
        _permission

        echo "Deployment takes $((SECONDS - ELAPSED_SEC)) second."
    else
        if [[ -z $USER ]]; then
            echo "You can't run this script in docker!"
            exit
        fi

        if [[ -f "/usr/bin/git" ]] &&
            [[ -f "/usr/bin/docker" ]] &&
            [[ -f "/usr/bin/docker-compose" ]]; then
            _laradock
            _setenv
            _swap
            _crontab
            _mysql
            _swoole
            _nginx
            _redis
            _php
            _git
            _up

            if [[ $TARGET == "deploy" ]]; then
                echo "Installation takes $((SECONDS - ELAPSED_SEC)) second."
            fi
        else
            read -p "What is your OS [debian/ubuntu/centos/fedora]? " OS_DISTRO

            if [[ $OS_DISTRO == "debian" ]]; then
                PKM="apt-get"
            elif [[ $OS_DISTRO == "ubuntu" ]]; then
                PKM="apt"
            elif [[ $OS_DISTRO == "centos" ]]; then
                PKM="yum"
            elif [[ $OS_DISTRO == "fedora" ]]; then
                PKM="dnf"
            fi

            if [[ -z $PKM ]]; then
                echo "Your OS is undefined!"
                exit
            fi
            PKM="sudo $PKM"

            eval "$PKM update"

            if [[ $OS_DISTRO == "centos" ]]; then
                eval "$PKM install -y epel-release yum-utils"
                eval "$PKM install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm"
                eval "yum-config-manager --enable remi"
                eval "$PKM install -y yum-fastestmirror"
                eval "$PKM install -y http://opensource.wandisco.com/centos/7/git/x86_64/wandisco-git-release-7-2.noarch.rpm"
            elif [[ $OS_DISTRO == "fedora" ]]; then
                eval "$PKM install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
                eval "$PKM install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
                eval "$PKM install -y dnf-plugins-core fedora-workstation-repositories"
                eval "$PKM install -y yum-plugin-fastestmirror yum-axelget"
                echo "fastestmirror=true" >>/etc/dnf/dnf.conf
            fi

            IFS=' ' read -r -a PACKAGE_ARRAY <<<"apache2 apache nginx"
            for PACKAGE in "${PACKAGE_ARRAY[@]}"; do
                eval "$PKM remove -y $PACKAGE"
            done

            eval "$PKM update"
            eval "$PKM upgrade -y"
            eval "$PKM autoremove -y"

            IFS=' ' read -r -a PACKAGE_ARRAY <<<"cron curl htop make nano tmux unrar unzip vim wget"
            for PACKAGE in "${PACKAGE_ARRAY[@]}"; do
                eval "$PKM install -y $PACKAGE"
            done

            if [[ ! -f "/usr/bin/git" ]] || [[ ! -f ~/.ssh/id_rsa.pub ]]; then
                eval "$PKM install -y git"
                read -e -p "GIT_NAME: " -i "Alireza Maleky" GIT_NAME
                read -e -p "GIT_EMAIL: " -i "alirezaabdalmaleky@gmail.com" GIT_EMAIL
                eval "git config --global user.name '$GIT_NAME'"
                eval "git config --global user.email '$GIT_EMAIL'"
                eval "git config --global alias.mg '!git checkout master; git merge dev --no-edit --no-ff; git push --all; git checkout dev'"
                eval "ssh-keygen -t rsa -b 4096 -C '$GIT_EMAIL' -f ~/.ssh/id_rsa -q -N ''"
                eval "cat ~/.ssh/id_rsa.pub"
                read -p "Are you saved this informations?" OK
            fi

            if [[ ! -f "/usr/bin/docker" ]]; then
                if [[ $OS_DISTRO == "debian" ]]; then
                    eval "$PKM remove -y docker docker-engine docker.io containerd runc"
                    eval "$PKM install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common"
                    eval "curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -"
                    eval "sudo apt-key fingerprint 0EBFCD88"
                    eval "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable'"
                elif [[ $OS_DISTRO == "ubuntu" ]]; then
                    eval "$PKM remove -y docker docker-engine docker.io containerd runc"
                    eval "$PKM install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common"
                    eval "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -"
                    eval "sudo apt-key fingerprint 0EBFCD88"
                    eval "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu disco stable'"
                elif [[ $OS_DISTRO == "centos" ]]; then
                    eval "$PKM remove -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine"
                    eval "$PKM install -y yum-utils device-mapper-persistent-data lvm2"
                    eval "sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
                elif [[ $OS_DISTRO == "fedora" ]]; then
                    eval "$PKM remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine"
                    eval "$PKM config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo"
                fi

                eval "$PKM update"
                eval "$PKM install -y docker-ce docker-ce-cli containerd.io"

                eval "sudo systemctl restart docker"
                eval "sudo systemctl enable docker"
                eval "docker system prune -f --all"

                if [[ $USER != "root" ]]; then
                    eval "sudo groupadd docker"
                    eval "sudo usermod -aG docker $USER"
                    eval "newgrp docker"
                    eval "mkdir -p /home/$USER/.docker"
                    eval "chown $USER:$USER /home/$USER/.docker -R"
                    eval "chmod g+rwx /home/$USER/.docker -R"
                    eval "sudo chown root:docker /var/run/docker.sock"
                fi
            fi

            if [[ ! -f "/usr/bin/docker-compose" ]]; then
                eval "sudo curl -L 'https://github.com/docker/compose/releases/download/1.25.0/docker-compose-$(uname -s)-$(uname -m)' -o /usr/local/bin/docker-compose"
                eval "sudo chmod +x /usr/local/bin/docker-compose"
                eval "sudo rm -f /usr/bin/docker-compose"
                eval "sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose"
            fi

            _router
        fi
    fi
}
_router
