# PHP 8.2 with Apache — serves the php_files/ backend
FROM php:8.2-apache

# mysqli needs to be explicitly installed.
# curl is already pre-compiled in all official PHP Docker images — do NOT install it again.
RUN docker-php-ext-install mysqli \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

# Copy PHP backend files into Apache document root
COPY php_files/ /var/www/html/

# Allow .htaccess overrides — the default apache2.conf sets AllowOverride None
# for /var/www/html, which blocks mod_rewrite rules.
RUN sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

EXPOSE 80

CMD ["apache2-foreground"]
