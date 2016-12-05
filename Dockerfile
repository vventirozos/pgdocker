FROM ubuntu:latest

MAINTAINER vventirozos@omniti.com

### CHANGE THE FOLLOWING 2 PARAMETERS IF YOU WANNA CHANGE POSTGRES INSTALL AND PGDATA DIRECTORIES ###

ENV PGBINDIR=/home/postgres/pgsql
ENV PGDATADIR=/home/postgres/pgdata

#Installing packages and creating a OS user

RUN apt-get update && apt-get install -y sudo wget joe less build-essential libreadline-dev zlib1g-dev flex bison libxml2-dev libxslt-dev libssl-dev
RUN useradd -c /home/postgres -ms /bin/bash postgres


#add user postgres to sudoers

run echo "postgres ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# The next steps will run as postgres

USER postgres

#getting the -latest- (always) postgres version compile world and install

RUN cd ; wget https://www.postgresql.org/ftp/latest/ -q -O - |grep "tar.gz" |grep -v md5 |grep -v sha256 |awk -F "\"" '{print $2}' |xargs wget
RUN cd ; ls -1 *.tar.gz |xargs tar zxfv
RUN cd ; cd postgres* ; ./configure --prefix=$PGBINDIR  ; make world ; sudo make install-world

#setting up a decent working env

RUN echo "export PGDATA=$PGDATADIR" >> ~/.bashrc
RUN echo "export PATH=$PATH:$PGBINDIR/bin" >> ~/.bashrc
RUN echo "LD_LIBRARY_PATH=$PGBINDIR/lib">> ~/.bashrc
RUN echo "alias joe='joe -wordwrap -nobackups'"  >> ~/.bashrc

# PGDATA creation and initdb -WITH- data checksums

RUN mkdir $PGDATADIR
RUN $PGBINDIR/bin/initdb -k -D $PGDATADIR



# setting some postgres configurables

RUN echo "listen_addresses = '*'" >> $PGDATADIR/postgresql.conf
RUN echo "port = 5432" >> $PGDATADIR/postgresql.conf
RUN echo "wal_level = replica" >> $PGDATADIR/postgresql.conf
RUN echo "checkpoint_completion_target = 0.9" >> $PGDATADIR/postgresql.conf
RUN echo "archive_mode = on" >> $PGDATADIR/postgresql.conf
RUN echo "archive_command = '/bin/true'" >> $PGDATADIR/postgresql.conf
RUN echo "max_wal_senders = 16" >> $PGDATADIR/postgresql.conf
RUN echo "wal_keep_segments = 10" >> $PGDATADIR/postgresql.conf
RUN echo "max_replication_slots = 10" >> $PGDATADIR/postgresql.conf
RUN echo "hot_standby = on" >> $PGDATADIR/postgresql.conf
RUN echo "log_destination = 'stderr'" >> $PGDATADIR/postgresql.conf
RUN echo "logging_collector = on" >> $PGDATADIR/postgresql.conf
RUN echo "log_filename = 'postgresql-%Y-%m-%d.log'" >> $PGDATADIR/postgresql.conf
RUN echo "log_line_prefix = ''" >> $PGDATADIR/postgresql.conf

## Setting pg_hba.conf for passwordless access for all users and replication

RUN echo "host    all             all             10.0.0.1/16            trust" >> $PGDATADIR/pg_hba.conf
RUN echo "host    replication     repuser         10.0.0.1/16            trust" >> $PGDATADIR/pg_hba.conf

#exposing port
EXPOSE 5432

#install some extensions , create a replication user and a monkey database

RUN $PGBINDIR/bin/pg_ctl -D $PGDATADIR/ start ; sleep 10 && \
	$PGBINDIR/bin/psql -c "create extension pg_buffercache ;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pageinspect;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pg_prewarm;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pg_stat_statements;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pgstattuple;" template1 && \
	$PGBINDIR/bin/psql -c "create extension postgres_fdw;" template1 && \
	$PGBINDIR/bin/psql -c "create user repuser with replication;" template1 && \
	$PGBINDIR/bin/createdb monkey && \
	$PGBINDIR/bin/pg_ctl -D $PGDATADIR/ -m fast stop

#Set a recovery.done so the slaves can find it

RUN echo "standby_mode = 'on' " >$PGDATADIR/recovery.done
RUN echo "primary_conninfo = 'user=repuser host=10.0.0.2 port=5432 application_name=a_slave'" >>$PGDATADIR/recovery.done
RUN echo "trigger_file = '$PGDATADIR/finish.recovery'" >>$PGDATADIR/recovery.done
RUN echo "recovery_target_timeline = 'latest'" >>$PGDATADIR/recovery.done

# copying an easy script for fast replica creation
COPY mk_replica.sh /home/postgres/mk_replica.sh

#USER root
#Tadah !