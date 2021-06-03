#!/bin/bash

# Auto Host multiple wordpress site on one Apache server using multiple PHP-FPM version
# Made by: tehv1007
# Date: 31/05/2021

install_services() {

    # Disable firewall
    systemctl disable firewalld
    systemctl stop firewalld
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0

    # Install Services
    # Install required packages
    yum install -y httpd epel-release yum-utils wget nano net-tools vim
    yum update -y
    cd /usr/src 
    wget http://dev.mysql.com/get/mysql57-community-release-el7-9.noarch.rpm
    rpm -Uvh mysql57-community-release-el7-9.noarch.rpm
    yum install -y mysql-server

    # Install PHP multiple versions
    yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum repolist remi-safe
    yum-config-manager --enable remi-php70
    yum install php php-common php-opcache php-mcrypt php-cli php-gd php-curl php-mysql -y

    # Enable at start up
    systemctl enable httpd
    systemctl enable mysqld
}

create_multiphp() {
    echo "Setup multiple PHP versions!!!"
    while true; do 
        echo "Enter PHP version will be install (Enter for Cancel)"
        echo "It corresponds to one of the numbers 56,70,71,72,73,74"
        echo -n "Let's choose your number:"
        read version

        if [ ${#version} -eq 0 ];
        then
            echo "Cancelled!!!"
            break
        else
            config_PHP $version
        fi
done
}

# Config PHP-FPM for multi version
config_PHP() {
    version=$1
    echo Creating PHP version $version
    yum install php$version-php-fpm php$version-php-mysql -y
    sed -i s/:9000/:90$version/ /etc/opt/remi/php$version/php-fpm.d/www.conf
    echo "#!/bin/bash exec /bin/php$version-cgi" > /var/www/cgi-bin/php$version.fcgi
    systemctl enable php$version-php-fpm
    systemctl start php$version-php-fpm
}

restart_services() {
    systemctl restart httpd
    systemctl restart mysqld
}

setup_vhost() {
    mkdir /etc/httpd/vhost.d 
    echo "IncludeOptional vhost.d/*.conf" >> /etc/httpd/conf/httpd.conf
    restart_services
}

start_services() {
    systemctl start httpd
    systemctl start mysqld
}

secure_mysql() {
    password=$(cat /var/log/mysqld.log | grep password | egrep -o "root\@localhost.*$" | cut -d" " -f2)
    echo Mysql: You temporary password for root@locahost is $password
    echo "You need to secure your Mysql Server!!!"
    mysql_secure_installation
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
        useradd -g apache -m $username
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
    version=$3
    mkdir /home/$user/public_html
    mkdir -p /home/logs/httpd
    printf '<VirtualHost *:80>
    ServerName %s
    DocumentRoot /home/%s/public_html
    ErrorLog /home/logs/httpd/error_%s.com
    CustomLog /home/logs/httpd/access_%s.com combined
    ProxyPassMatch ^/(.*\.php)$ fcgi://127.0.0.1:9000/home/%s/public_html/$1
    #SetHandler "proxy:fcgi://127.0.0.1:9000
    <Directory /home/%s/public_html>
    AllowOverride All
    Require all granted
    </Directory>\n</VirtualHost>' $domain $user $user $user $user $user > /etc/httpd/vhost.d/$domain.conf
    
    echo "Select PHP version for this user"
    echo "You need to remember which versions you have installed and select one!"
    read version
    sed -i s/:9000/:90$version/ /etc/httpd/vhost.d/$domain.conf
    echo "<?php phpinfo(); ?>" > /home/$user/public_html/info.php
    
    systemctl restart php$version-php-fpm

    # Set up Wordpress
    setup_wordpress $user 

    chown -R $user:apache /home/$user
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
    create_multiphp
    secure_mysql
    setup_vhost
    create_vhosts
}

main