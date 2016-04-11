+++
date = "2016-04-10T19:02:35+02:00"
draft = true
title = "wat - Cassandra"
tags = ["cassandra", "WAT"]
authors = ["Frank", "Lars"]
+++

When using Cassandra, you sometimes have these _WAT_ moments. If you don't know what we are talking about, just take a short [detour](https://www.destroyallsoftware.com/talks/wat).

Taking a step back and figuring out what things are built for is usually a good idea, so what was Cassandra envisioned for?

> Cassandra does not support a full relational data model; instead, it provides clients with a simple data model that supports dynamic control over data layout and format.
>
> -- <cite>[Original Cassandra Paper](https://www.facebook.com/notes/facebook-engineering/cassandra-a-structured-storage-system-on-a-p2p-network/24413138919/)</cite>

Cool, sounds like a a reasonable statement. When we started using Cassandra we had to develop an application with a dynamic data model. Amongst other features this made us giving Cassandra a shot. So here's how altering Cassandra tables leads to some funny WAT moments.

# Setting up the environment
First of all we need a keyspace to play around with:
```sql
cqlsh> CREATE KEYSPACE fun WITH replication ={'class': 'SimpleStrategy' ,
    'replication_factor': 1 };
cqlsh> USE fun;
```

# Collection Column re-use
Let's now have a simple table with an identifier and a collection column
```sql
cqlsh:fun> CREATE TABLE hello (id uuid, world list<int>, PRIMARY KEY (id));
```

Damn... we used the wrong type, it rather should be a list of `varchar`. No problem
```sql
cqlsh:fun> ALTER TABLE hello DROP world;
cqlsh:fun> ALTER TABLE hello ADD world list<varchar> ;
Bad Request: Cannot add a collection with the name world because a collection
with the same name and a different type has already been used in the past
```

![](/img/wat/wat1.jpg)

# Prepared Statements
Let's take a look at the java driver. Initially we connect to the cluster and create a simple test table with two columns. The 'id' column being the primary key and an arbitrary text column called 'initial_column'.
```java
Cluster cluster = Cluster.builder().addContactPoints("localhost").build();
Session session = cluster.connect("fun");

Statement create = createTable("test")
            .addPartitionKey("id", DataType.text())
            .addColumn("initial_column", DataType.text())
            .ifNotExists();

session.execute(create);
```

When we prepare a 'SELECT *' statement on that table, bind and execute it the returned column definitions are as expected [id, initial_column].
```java
PreparedStatement prepared = session.prepare("select * from test");
ResultSet result = session.execute(prepared.bind());
logger.info("Columns before alter table: {}", getColumnDefinitions(result));
// Columns before alter table: [id, initial_column]

```
Ok, now we figured we need an additional column. It's as easy as this:
```java
session.execute(alterTable("test").addColumn("new_column").type(DataType.text()));
```

Let's bind the prepared statement again and take a look at the returned columns:
```java
result = session.execute(prepared.bind());
logger.info("Columns after alter table: {}", getColumnDefinitions(result));
// Columns after alter table: [id, initial_column]
```

Hmmm, where's the new column? Nevermind, just re-preparing the statement should fix the problem, shouldn't it?
```java
prepared = session.prepare("select * from test");
result = session.execute(prepared.bind()); // Cassandra Warning: "Re-preparing already prepared query select * from test. Please note that preparing the same query more than once is generally an anti-pattern and will likely affect performance. Consider preparing the statement only once."
logger.info("Columns after re-prepare: {}", getColumnDefinitions(result));
// Columns after re-prepare: [id, initial_column]
```

![](/img/wat/wat1.jpg)

Check whether really the new column got added (without using the prepared statement):
```java
result = session.execute("select * from test");
logger.info("Columns after unprepared execute: {}", getColumnDefinitions(result));
// Columns after unprepared execute: [id, initial_column, new_column]
```

Yup, the column is there. So let's investigate whether re-connecting to the cluster solves this issue:
```java
session.close();
session = cluster.connect("fun");
prepared = session.prepare("select * from test"); // Cassandra Warning: "Re-preparing already prepared query select * from test. Please note that preparing the same query more than once is generally an anti-pattern and will likely affect performance. Consider preparing the statement only once."
result = session.execute(prepared.bind());
logger.info("Columns recreating session via re-connect on cluster: {}", getColumnDefinitions(result));
// Columns recreating session via re-connect on cluster: [id, initial_column]
```

No. Apparently only re-instantiating the cluster does the job:
```java
session.close();
cluster.close();
session = Cluster.builder().addContactPoints("localhost").build().connect("fun");
prepared = session.prepare("select * from test");
result = session.execute(prepared.bind());
logger.info("Columns after recreating session via re-instantiating cluster: {}", getColumnDefinitions(result));
// Columns after recreating session via re-instantiating cluster: [id, initial_column, new_column]
```

# Update &ne; Insert
Datastax' CQL documentation gives the impression that INSERT and UPDATE statements are identical. So let's create an entry via INSERT and update the non key value to be 'null':
```sql
cqlsh:fun> CREATE TABLE IF NOT EXISTS test (
         ...   id int,
         ...   data text,
         ...   PRIMARY KEY (id)
         ...   );
cqlsh:fun> INSERT INTO test (id, data) VALUES (1, 'hello');
cqlsh:fun> UPDATE test SET data=null WHERE id=1;
cqlsh:fun> SELECT * FROM test;

 id | data
----+------
  1 | null
(1 rows)
```

Nothing unusual here. Let's try the same via Cassandra's upsert mechanism:

```sql
cqlsh:fun> UPDATE test SET data = 'hello world' WHERE id=2;
cqlsh:fun> SELECT * FROM test;

id | data
----+-------------
 2 | hello world

cqlsh:fun> UPDATE test SET data = null WHERE id=2;
cqlsh:fun> SELECT * FROM test;

(0 rows)

```

![](/img/wat/wat1.jpg)
