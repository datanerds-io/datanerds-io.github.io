+++
date = "2016-03-24T20:48:27+01:00"
draft = false
title = "LACK - Consensus via Cassandra"
tags = ["java", "Cassandra", "consensus", "LACK"]
author = "Lars"

+++

In late 2014 DataStax published a [blog post](http://www.datastax.com/dev/blog/consensus-on-cassandra) in which they explain how Cassandra can be leveraged in order to reach consensus in a distributed environment. A detailed explanation can be found in mentioned article.

Inspired by said article _LACK [luhk]_ was implemented, a very thin Java API on top of a few Cassandra queries. Disclaimer: It is not meant as a consensus library such as libraft or atomix. We just needed something implemented fast and on top of Cassandra.

# Creating a keyspace
In order to run LACK you have to point it to a keyspace in which it can create necessary table.
```sql
CREATE KEYSPACE lack
    WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 1 };
```
# Locking
The configuration of LACK is done via the `LackConfig` POJO, e.g. using this constructor: `LackConfig(String username, String password, String[] nodes, String keyspace, int ttlInSeconds)`.

Connecting to a a local cluster using the previously created keyspace and a TTL of 42 seconds:
```java
LackConfig config = new LackConfig("user", "pass", new String[]{"127.0.0.1"}, "lack", 42);
Lack lack = new Lack(config, "owner-1");

// Locking the resource:
lack.acquire("user-1");
...
// Renewing the lock in case we need longer than 42 seconds:
lack.renew("user-1");
...
// Releasing the lock in case we have finished our operation:
lack.release("user-1");
```

In case one of the above mentioned methods can not be executed since e.g. a resource might already be locked, a `LackException` will be thrown. To make sure you implement a logic for such cases, it is a checked exception.

To find some more resource take a look here: [GitHub](https://github.com/datanerds-io/lack/), [Maven Central](http://search.maven.org/#search%7Cga%7C1%7Cg%3A%22io.datanerds%22%20a%3A%22lack%22)
