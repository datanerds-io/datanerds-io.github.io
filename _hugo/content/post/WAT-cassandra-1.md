+++
date = "2016-04-10T19:02:35+02:00"
draft = true
title = "wat - Cassandra"
tags = ["cassandra", "WAT"]
authors = ["Frank", "Lars"]
+++

When using Cassandra, you sometime have these _WAT_ moments. If you don't know what we are talking about, just take a short [detour](https://www.destroyallsoftware.com/talks/wat).

Taking a step back and figuring out what things are built for is usually a good idea, so what was Cassandra envisioned for?

> Cassandra does not support a full relational data model; instead, it provides clients with a simple data model that supports dynamic control over data layout and format.
>
> -- <cite>[Original Cassandra Paper](https://www.facebook.com/notes/facebook-engineering/cassandra-a-structured-storage-system-on-a-p2p-network/24413138919/)</cite>

Cool, sounds like a a reasonable statement.

# Collection Column re-use

Let's create a keyspace
```sql
cqlsh> CREATE KEYSPACE fun WITH replication ={'class': 'SimpleStrategy' ,
    'replication_factor': 1 };
cqlsh> USE fun;
```

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
