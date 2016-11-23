+++
date = "2016-11-23T14:03:48-07:00"
draft = true
title = "WAT - Cassandra: Row level consistency"
tags = ["cassandra", "WAT", "inconsistency", "timestamp tie"]
authors = ["Lars"]
+++

**TL;DR** Cassandra **_is not_** row level consistent!!!

We published a [blog post]({{< relref "WAT-cassandra-1.md" >}}) about some surprising behaviors while using Apache Cassandra/ DataStax Enterprise some weeks back. Despite that we have a few more items on the list we would like to present this particular _WAT_ is worth sharing right away.

In a nutshell: **We discovered corrupt data** and it took us a while to understand what was happening and what the reasoning of the data corruption was. Let's dive into the problem:

Imagine a table where a primary key is used to identify an entity. Each entity can have a boolean state to mark it as locked. Additionally, each entity has a revision counter.

```sql
CREATE TABLE locks (
    id text PRIMARY KEY,
    lock boolean,
    revision bigint
);
```

For an initial lock of the entity 'Tom' we execute an `INSERT`. Since one needs to make sure that no one else is obtaining the lock at the same time we make use of a Lightweight transaction (LWT) using `IF NOT EXISTS`. In order to prevent entities to be locked forever we automatically want to release the lock after some time. This can be achieved using a Time To Live `TTL`.

```sql
INSERT INTO locks (id, lock, revision)
VALUES ('Tom', true, 1)
IF NOT EXISTS USING TTL 20;
```

Great, after we are done with other calculations for our entity Tom, we will release the lock via a simple UPDATE:

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

Instead, in some rare cases (~0.1%) the result looked like the following:

```sql
SELECT * FROM locks WHERE id='Tom';

 id  | lock | revision
-----+------+----------
 Tom | null |        2
```
Given the used queries, the row should not be in a state where lock is null and a revision is set at the same time.

After deeper investigations of audit logs &amp; SSTables it turns out that we did run into a timestamp tie, which means that the cluster node sees a stream of changes where two or multiple changes happen at the exact same time. So what is Cassandra's resolution strategy for multiple updates happening at the same time? *"[...] if there are two updates, the one with the lexically larger value is selected. [...] [1]"*

**lexical order? LEXICAL ORDER??**

So what happens to our statements? When the acquire and release of the lock happen at the same time Cassandra will compare on **cell level** which one is greater and choose this cell for the final state. For the `lock` column this means: `true > false` so it will take that portion of the `INSERT`. For `revision` the second query will define the state since `2 > 1`. Since the first query has a `TTL` it's content will be removed after the defined 20 seconds.

![](/img/wat/wat7.jpg)

### Workaround
The latter `UPDATE` will also be executed using LWT. When a tie happens using LWT it will return with `applied = false`. In these cases we just retry the release query...

![](/img/mindblown.gif)

### Possible Cassandra Improvements

1. The server should log timestamp ties. We were just lucky to find the glitch in the data: https://issues.apache.org/jira/browse/CASSANDRA-12587
2. Since the origin of the competing query is the same process, a sequence number should be sufficient to define order: https://issues.apache.org/jira/browse/CASSANDRA-6123



[1] - http://cassandra.apache.org/doc/latest/faq/index.html#what-happens-if-two-updates-are-made-with-the-same-timestamp
