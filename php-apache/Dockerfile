FROM php:8.3-apache

RUN a2enmod rewrite

COPY ./vhost.conf /etc/apache2/sites-available/000-default.conf
COPY ./public /var/www/html

EXPOSE 80
