PGDATA=/home/postgres/pgdata
PGBIN=/home/postgres/pgsql/bin
$PGBIN/pg_ctl -m immediate stop
rm -rf $PGDATA/*
$PGBIN/pg_basebackup -h 10.0.0.2 -D $PGDATA/ -Xs -P -U repuser
mv $PGDATA/recovery.done $PGDATA/recovery.conf
$PGBIN/pg_ctl start
sleep 10
echo ""
echo ""
psql -x -c "SELECT pg_xlog_location_diff(pg_current_xlog_insert_location(), flush_location) AS lag_bytes,
      pid, application_name FROM pg_stat_replication; " -h 10.0.0.2 postgres
    
