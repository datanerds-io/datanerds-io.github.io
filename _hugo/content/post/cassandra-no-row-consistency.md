+++
date = "2016-11-23T19:45:48-07:00"
draft = false
title = "WAT - Cassandra: Row level consistency #$@&%*!"
tags = ["cassandra", "WAT", "inconsistency", "timestamp tie"]
authors = ["Lars"]
+++

**TL;DR** Cassandra **_is not_** row level consistent!!!

We published a [blog post]({{< relref "WAT-cassandra-1.md" >}}) about some surprising and unexpected behaviors while using Apache Cassandra/DataStax Enterprise some weeks back. Recently, we encountered even more WAT moments and I believe this one is the most distressing.

In a nutshell: **We discovered corrupted data** and it took us a while to understand what was happening and why that data was corrupt. Let's dive into the problem:

Imagine a table with a primary key to identify an entity. Each entity can have a boolean state to mark it as locked. Additionally, each entity has a revision counter which is incremented on changes to the entity.

```sql
CREATE TABLE locks (
    id text PRIMARY KEY,
    lock boolean,
    revision bigint
);
```

For an initial lock of the entity 'Tom' we execute an `INSERT`. Since we need to make sure that no one else is obtaining the lock at the same time we make use of a Lightweight transaction (LWT) using `IF NOT EXISTS`. It is possible that something goes wrong or our application even dies before releasing the lock, resulting in deadlocked entities where `lock` stays `true`. To ensure that the lock is released in such a case, we release the lock after a certain amount of time. This is achieved by using Cassandra's Time To Live (`TTL`) feature.

```sql
INSERT INTO locks (id, lock, revision)
VALUES ('Tom', true, 1)
IF NOT EXISTS USING TTL 20;
```

Great! After finishing some other calculations for our entity Tom, we release the lock via a simple UPDATE:

```sql
UPDATE locks SET lock=false, revision=2 WHERE id='Tom';
```

The result should look like this:

```sql
SELECT * FROM locks WHERE id='Tom';

 id  | lock  | revision
-----+-------+----------
 Tom | False |        2
```

To our surprise this was not always the case. In ~0.1% of the rows the result looked like this:

```sql
SELECT * FROM locks WHERE id='Tom';

 id  | lock | revision
-----+------+----------
 Tom | null |        2
```
Given the queries we are using, the row should not be in a state where lock is null and a revision is set at the same time.

After deeper investigations of audit logs and a deep dive into the SSTables it turned out that we did run into a timestamp tie. The cluster node our client is talking to sees a stream of changes with two or more changes happening to the same entry in the lock table at the exact same time. Obviously the calculation we are doing in between acquiring the lock and releasing it is not taking enough time (microseconds). Interesting, so what is the resolution strategy for multiple updates at the same time? *"[...] if there are two updates, the one with the lexically larger value is selected. [...]"* [1]

**lexical larger value? LEXICAL LARGER VALUE??**

So what happens to our statements? When the acquire and release of the lock happen at the same exact time, Cassandra will compare on **_cell level_**, I repeat, **_CELL LEVEL_** which one is greater and will choose the value for this cell from the query for the final state. For the lock column this means: `true > false` so it will take that portion of the `INSERT`. For the revision column the `UPDATE` query will win since `2 > 1`. Due to the usage of `TTL` its content will be removed after 20 seconds... hence the column for lock will become `null`, #$@&%!!! There is no row level consistency in Cassandra, #$@&%!!!

![](/img/wat/wat7.jpg)

### Workaround
The latter release `UPDATE` will also be executed using LWT. When a tie happens using LWT it will return with `applied = false`. In these cases we just retry the release query...

![](/img/mindblown.gif)

### Possible Cassandra Improvements

1. The server should log timestamp ties. We were just lucky to find the glitch in the data: https://issues.apache.org/jira/browse/CASSANDRA-12587
2. Since the origin of the competing query is the same process, a sequence number should be sufficient to define order: https://issues.apache.org/jira/browse/CASSANDRA-6123

[1] - http://cassandra.apache.org/doc/latest/faq/index.html#what-happens-if-two-updates-are-made-with-the-same-timestamp
