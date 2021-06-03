#!/bin/bash

# Auto Host multiple wordpress site on one server nginx (LEMP)
# Made by: tehv1007
# Date: 01/06/2021

install_services() {

    # Disable firewall
    systemctl disable firewalld
    systemctl stop firewalld
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0

    # Install Services
    yum install -y epel-release yum-utils wget nano net-tools vim expect

    # Install latest MariaDB version
    wget https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    chmod +x mariadb_repo_setup
    sudo ./mariadb_repo_setup
    yum install -y MariaDB-server

    # Install PHP-FPM 7.1, you can also change to other version including 5.6, 7.1, 7.2, 7.3, 7.4
    yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    yum-config-manager --enable remi-php71 # You can change here for other version
    yum install -y php php-fpm php-mysqlnd php-mysql php-common php-opcache php-mcrypt php-cli php-gd php-curl

    # Install Nginx
    yum install -y nginx
 
    # Config PHP-FPM
    sed -i 's/user = apache/user = nginx/'  /etc/php-fpm.d/www.conf
    sed -i 's/group = apache/group = nginx/'  /etc/php-fpm.d/www.conf
    sed -i 's/;listen.owner = nobody/listen.owner = nginx/'  /etc/php-fpm.d/www.conf
    sed -i 's/;listen.group = nobody/listen.group = nginx/'  /etc/php-fpm.d/www.conf
    sed -i 's/listen = 127.0.0.1:9000/;listen = 127.0.0.1:9000/'  /etc/php-fpm.d/www.conf
    sed -i '39a\\listen = \/run\/php-fpm\/www.sock'  /etc/php-fpm.d/www.conf

    # Enable at start up
    systemctl enable php-fpm
    systemctl enable mariadb
    systemctl enable nginx

    echo "The installation of MYSQLD, PHP, NGINX has been completed!"
}

restart_services() {
    systemctl restart php-fpm
    systemctl restart mariadb
    systemctl restart nginx
}

start_services() {
    systemctl start php-fpm
    systemctl start mariadb
    systemctl start nginx
}

secure_mysql() {
    password=$(cat /var/log/yum.log | grep password | egrep -o "root\@localhost.*$" | cut -d" " -f2)
    echo Mysql: You temporary password for root@locahost is $password
    echo "You need to secure your Mysql Server!!!"
    mysql_secure_installation
}

config_nginx() {
    # Config for connecting NGINX to PHP FPM
    # We must tell NGINX to proxy requests to PHP FPM via the FCGI protocol
    sed -i '43alocation ~ [^/]\.php(/|$) {' /etc/nginx/nginx.conf
    sed -i '44afastcgi_split_path_info ^(.+?\.php)(/.*)$;' /etc/nginx/nginx.conf
    sed -i '45aif (!-f $document_root$fastcgi_script_name) {' /etc/nginx/nginx.conf
    sed -i '46areturn 404;' /etc/nginx/nginx.conf
    sed -i '47a}' /etc/nginx/nginx.conf

    # Mitigate https://httpoxy.org/ vulnerabilities
    sed -i '48afastcgi_param HTTP_PROXY "";' /etc/nginx/nginx.conf
    # for using unix socket
    sed -i '49afastcgi_pass unix:/var/run/php-fpm.sock;' /etc/nginx/nginx.conf
    # fastcgi_pass 127.0.0.1:9000;
    sed -i '50afastcgi_index index.php;' /etc/nginx/nginx.conf

    # include the fastcgi_param setting
    sed -i '51ainclude fastcgi_params;' /etc/nginx/nginx.conf
    sed -i '52afastcgi_param  SCRIPT_FILENAME   $document_root$fastcgi_script_name;' /etc/nginx/nginx.conf
    sed -i '53a}' /etc/nginx/nginx.conf

    restart_services
}

setup_wordpress() {
    user=$1
    cd /home/$user/public_html
    wget http://wordpress.org/latest.tar.gz
    tar -xzvf latest.tar.gz
    rm -rf latest.tar.gz
    
    echo "Your MySQL account for Wordpress will be: "
    echo "Mysql User: $user@localhost"
    echo -n "Mysql Password (please input STRONG one): "
    read password
    echo "Enter root password for creating Database using for Wordpress: "
    mysql -uroot -p -e "CREATE DATABASE wp$user;create user $user@localhost identified by '$password';grant all privileges on wp$user.* to $user@localhost;flush privileges;"
    
    cp wordpress/wp-config-sample.php wordpress/wp-config.php

    sed -i s/database_name_here/wp$user/ wordpress/wp-config.php
    sed -i s/username_here/$user/ wordpress/wp-config.php
    sed -i s/password_here/$password/ wordpress/wp-config.php
  
    echo "Wordpress created!"

}

create_user() {
    username=$1
    echo Creating user $username
    {
        useradd -g nginx -m $username  
        passwd $username
        chmod 710 /home/$username
        echo User $username is created!!
        return 0
    } || {
        echo "Error while creating user!!!"
        return 0
    }
}

create_vhost() {
    user=$1
    domain=$2
    mkdir /home/$user/public_html

    printf 'server {

    listen 80;
    server_name %s;

    root /home/%s/public_html;
    index index.php;
    access_log /var/log/nginx/%s.access.log;
    error_log /var/log/nginx/%s.error.log;

    location = /favicon.ico {
      log_not_found off;
      access_log off;
    }

    location = /robots.txt {
      allow all;
      log_not_found off;
      access_log off;
    }

    location / {
      try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
      try_files $uri =404;
      fastcgi_pass unix:/run/php-fpm/www.sock;
      fastcgi_index   index.php;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      include fastcgi_params;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
      expires max;
      log_not_found off;
    }
    }' $domain $user $domain $domain > /etc/nginx/conf.d/$domain.conf

    echo "<?php phpinfo(); ?>" > /home/$user/public_html/info.php

    # Set up Wordpress
    setup_wordpress $user 

    chown -R $user:nginx /home/$user/public_html
    chmod g+x -R /home/$user/public_html/wordpress
    echo "Your site is set up !!!!"
}

create_vhosts() {
    echo
    echo "SETTING UP DONE, NOW is your time to create your VHOSTs!!!"
    while true; do 
        echo -n "Enter your username (Enter for Cancel): "
        read username

        if [ ${#username} -eq 0 ];
        then
            echo "Cancelled!!!"
            break
        else
            create_user $username
        fi

        echo -n "Your domain: "
        read domain
        create_vhost $username $domain

    done
    echo "Mission completed !!!"
    restart_services
}

main() {
    install_services
    start_services
    secure_mysql
    create_vhosts
    config_nginx
}
main