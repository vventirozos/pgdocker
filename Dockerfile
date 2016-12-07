FROM ubuntu:latest

MAINTAINER vventirozos@omniti.com

### CHANGE THE FOLLOWING 3 PARAMETERS IF YOU WANNA CHANGE USER, POSTGRES INSTALL AND PGDATA DIRECTORIES ###

ENV PGUSER=postgres
ENV PGBINDIR=/home/$PGUSER/pgsql
ENV PGDATADIR=/home/$PGUSER/pgdata

#Installing packages and creating a OS user

RUN apt-get update && apt-get install -y sudo wget joe less build-essential libreadline-dev zlib1g-dev flex bison libxml2-dev libxslt-dev libssl-dev && \
	useradd -c /home/$PGUSER -ms /bin/bash $PGUSER


#add user postgres to sudoers

run echo "$PGUSER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# The next steps will run as postgres

USER $PGUSER
WORKDIR /home/$PGUSER
#getting the -latest- (always) postgres version compile world and install

RUN wget https://www.postgresql.org/ftp/latest/ -q -O - |grep "tar.gz" |grep -v md5 |grep -v sha256 |awk -F "\"" '{print $2}' |xargs wget && \
	ls -1 *.tar.gz |xargs tar zxfv && \
	cd postgres* ; ./configure --prefix=$PGBINDIR  ; make world ; sudo make install-world

#setting up a decent working env

RUN echo "export PGDATA=$PGDATADIR" >> ~/.bashrc && \
	echo "export PATH=$PATH:$PGBINDIR/bin" >> ~/.bashrc && \
	echo "LD_LIBRARY_PATH=$PGBINDIR/lib">> ~/.bashrc && \
	echo "alias joe='joe -wordwrap -nobackups'"  >> ~/.bashrc 

# PGDATA creation and initdb -WITH- data checksums

RUN mkdir $PGDATADIR && \
	$PGBINDIR/bin/initdb -k -D $PGDATADIR



# setting some postgres configurables

RUN echo "listen_addresses = '*'" >> $PGDATADIR/postgresql.conf && \
	echo "port = 5432" >> $PGDATADIR/postgresql.conf && \
	echo "wal_level = replica" >> $PGDATADIR/postgresql.conf && \
	echo "checkpoint_completion_target = 0.9" >> $PGDATADIR/postgresql.conf && \
	echo "archive_mode = on" >> $PGDATADIR/postgresql.conf && \
	echo "archive_command = '/bin/true'" >> $PGDATADIR/postgresql.conf && \
	echo "max_wal_senders = 16" >> $PGDATADIR/postgresql.conf && \
	echo "wal_keep_segments = 10" >> $PGDATADIR/postgresql.conf && \
	echo "max_replication_slots = 10" >> $PGDATADIR/postgresql.conf && \
	echo "hot_standby = on" >> $PGDATADIR/postgresql.conf && \
	echo "log_destination = 'stderr'" >> $PGDATADIR/postgresql.conf && \
	echo "logging_collector = on" >> $PGDATADIR/postgresql.conf && \
	echo "log_filename = 'postgresql-%Y-%m-%d.log'" >> $PGDATADIR/postgresql.conf && \
	echo "wal_log_hints = on" >> $PGDATADIR/postgresql.conf && \
	echo "log_line_prefix = ''" >> $PGDATADIR/postgresql.conf

## Setting pg_hba.conf for passwordless access for all users and replication

RUN echo "host    all             all             10.0.0.1/16            trust" >> $PGDATADIR/pg_hba.conf && \
	echo "host    replication     repuser         10.0.0.1/16            trust" >> $PGDATADIR/pg_hba.conf

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

RUN echo "standby_mode = 'on' " >$PGDATADIR/recovery.done && \
	echo "primary_conninfo = 'user=repuser host=10.0.0.2 port=5432 application_name=a_slave'" >>$PGDATADIR/recovery.done && \
	echo "trigger_file = '$PGDATADIR/finish.recovery'" >>$PGDATADIR/recovery.done && \ 
	echo "recovery_target_timeline = 'latest'" >>$PGDATADIR/recovery.done 

# copying an easy script for fast replica creation
COPY mk_replica.sh /home/$PGUSER/

#USER root
#Tadah !
