
# mariadb

The developers of mysql moved to mariadb, a (mostly) backwards compatible fork of mysql, after it had been taken over by oracle.

Installation requires adding a third-party repository.

**MariaDB Sources:**

Register the key & add their repository:

    apt-get install python-software-properties
    apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
    add-apt-repository 'deb http://mirror.jmu.edu/pub/mariadb/repo/5.5/debian wheezy main'

**Installation:**

    aptitude install mariadb-server

Post install you may want to tune it, but I don't have any documentation or advice in that area.


## monit

You may want to add this to your monit scripts at `/etc/monit/monitrc.d/mariadb`:

    check process mysqld with pidfile /var/run/mysqld/mysqld.pid
        start program = "/etc/init.d/mysql start"
        stop program = "/etc/init.d/mysql stop"
        group www-data
        if cpu > 90% for 5 cycles then restart
        if memory > 80% for 5 cycles then restart
        if 3 restarts within 8 cycles then timeout


## personal bias

Recent history of experience with both mariadb and mysql have shown both to be somewhat unstable and resource hungry, even under moderately small loads, and in spite of every attempt to tune them.

With the advent of databases that store any content and organize it by page instead of a type-restricted normalized form, I haven't had a need for relational databases in recent projects.