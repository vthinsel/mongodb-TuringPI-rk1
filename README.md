# 🚀 Building an amazingly small Beast: MongoDB on TuringPi ARM Cluster

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Ansible](https://img.shields.io/badge/Ansible-automation-black.svg)
![MongoDB](https://img.shields.io/badge/MongoDB-replica%20set-green.svg)
![ARM64](https://img.shields.io/badge/Architecture-ARM64-red.svg)

> *When you want to prove that ARM doesn't just mean your laptop battery lasts longer...*

This README tells two connected stories:

1. [Part I — The four-node ARM build](#part-i--the-four-node-arm-build): hardware,
   deployment, PLGM load tests, power, and what makes the platform fun to run.
2. [Part II — MongoDB memory-management deep dive](#part-ii--mongodb-memory-management-deep-dive):
   THP, TCMalloc, WiredTiger, measurement method, and the small- and
   large-dataset YCSB experiments.

## Part I — The four-node ARM build

Part I is about building and operating the machine. Part II asks the more
interesting question: when this tiny replica set is busy, does the ARM64 memory
stack actually help? Keep reading for the THP A/B tests—there is a surprise in
how differently the two dataset sizes behave.

## What's This All About? 🤔

Ever wondered what happens when you take four tiny ARM computers, stuff them into a mini-ITX sized board, and ask them to handle enterprise database workloads? Well, grab some coffee ☕ and step into the world of distributed ARM computing !

We're building a **MongoDB replica set** on the **TuringPi 2** platform using **RK1 compute modules** - basically creating a data center that fits in your backpack. 

## Meet the TuringPi 2: The ARM Avengers' Headquarters 🦾

The TuringPi 2 is like the Tony Stark of single-board computers - it takes regular compute modules and turns them into something extraordinary. Think of it as a **4-slot carrier board** that lets you cluster ARM-based compute modules together, including NVIDIA Jetson modules if you fancy.

The `img/` directory contains the hero artwork, the software-stack diagram, and
the captured benchmark chart used throughout this article. Feel free to check it out !


### Why TuringPi is Cool:

- **Compact Design**: Mini-ITX form factor (same size as the smallest PC motherboard)
- **Modular Architecture**: Hot-swappable compute modules
- **Real Networking**: Gigabit Ethernet switching between nodes
- **Storage**: NVMe dedicated to each module
- **Enterprise Features**: BMC (Baseboard Management Controller) for remote management
![Compact platform](./img/turingpi2-rk1-vignette.jpg)

## The Hardware Squad 💪

### Shopping list for our MongoDB Cluster:

| Component | Quantity | Specs | Role |
| --- | --- | --- | --- |
| **TuringPi 2** | 1x | Mini-ITX carrier board | The foundation 🏗️ |
| **RK1 Modules** | 4x | ARM64 RK3588, 16GB RAM | The workhorses 🐎 |
| **NVMe SSDs** | 4x | 400GB each | Speed demons ⚡ |
| **Heatsinks** | 4x | Active cooling | Chill vibes 🧊 |
| **24-pin PSU** | 1x | Standard ATX power | The juice ⚡ |



### RK1 Module Deep Dive 🔍

Each RK1 is basically a **smartphone SoC** on steroids. Here's what makes it tick:

- **CPU**: ARMv8-A RK3588 (4x Cortex-A76 + 4x Cortex-A55)
- **GPU**: Mali-G610 MP4 (yes, it can game!)
- **NPU**: Built-in AI acceleration providing 6TOPS (we will come to this in a next chapter...)
- **Memory**: 16GB LPDDR4 (exists in 8/16/32 flavor)
- **Storage**: 32G eMMC and NVMe support
- **Form Factor**: 260-pin SO-DIMM connector (Nvidia Jetson Compatible)
- **Networking**: 1x Gigabit Ethernet
- **Power**: ~9W per module including NVME (40W total cluster max!)

## The Software Stack: From Zero to Hero 🛠️

### Our Technology Choices:

![Software Stack Overview](./img/soft-stack.png)

### MongoDB Deployment Architecture:

```
┌─────────────┬─────────────┬─────────────┬─────────────┐
│  rk1-node1  │  rk1-node2  │  rk1-node3  │  rk1-node4  │
│   PRIMARY   │ SECONDARY   │ SECONDARY   │  CONTROL    │
├─────────────┼─────────────┼─────────────┼─────────────┤
│ MongoDB     │ MongoDB     │ MongoDB     │ Ansible     │
│ Data Node   │ Data Node   │ Data Node   │ Monitoring  │
│             │             │             │ Prometheus  │
│             │             │             │ Grafana     │
│             │             │             │ LoadTest    │
│             │             │             │             │
│ 16GB RAM    │ 16GB RAM    │ 16GB RAM    │ 16GB RAM    │
│ 256GB NVMe  │ 256GB NVMe  │ 256GB NVMe  │ 256GB NVMe  │
│ /data       │ /data       │ /data       │ /monitoring │
└─────────────┴─────────────┴─────────────┴─────────────┘
                            │
                   ┌────────┴────────┐
                   │   Replica Set   │
                   │  "turingpi_rs"  │
                   └─────────────────┘
```

### Connection Strings and Primary Failover

Applications should connect to all three data-bearing nodes and include the
replica set name. The MongoDB driver will discover the current primary and
automatically select a secondary after a primary failure and election:

```text
# Normal deployment with authentication enabled
mongodb://<user>:<password>@rk1-node1:27017,rk1-node2:27017,rk1-node3:27017/admin?authSource=admin&replicaSet=turingpi_rs

# Optional non-production/testing deployment after disable_mongodb_auth.yml
mongodb://rk1-node1:27017,rk1-node2:27017,rk1-node3:27017/test?replicaSet=turingpi_rs
```

Do not use `directConnection=true` or list only the current primary when you
need automatic failover. `rk1-node4` is the Ansible control and monitoring
host, not a MongoDB replica-set member, so it should not be included as an
application connection target. Replace the hostnames with the nodes' reachable
IP addresses or DNS names when connecting from outside the cluster network.

## Performance: David vs Goliath 📊

### Platform-capacity snapshots (PLGM and earlier YCSB workloads)

These are **illustrative results from separate workload profiles**, not the
controlled THP comparison in Part II. Do not compare their ops/s directly with
the 500k/50M YCSB sweeps: operation mixes, acknowledgement settings, and
measurement scopes differ.

#### 🔥 The ARM Crusher (50% Write Workload)

- **Throughput**:  6100 ops/sec
- **Avg Write Latency **: &lt;10 ms
- **Power Consumption**: 42W total cluster
- **Performance/Watt**:   145 ops/sec/watt

#### 🏃‍♂️ ARM Endurance Test (25% Write Workload)

- **Throughput**:  6700 ops/sec
- **Avg Read Latency **: &lt;1 ms
- **Power Consumption**: 36W total cluster
- **Performance/Watt**:   180 ops/sec/watt

![Performance Chart](./img/Grafana-TuringPi-MongoDB-Cluster.png)

The important comparison here is within the RK1 platform: how much useful work
it performs at its observed cluster power. No matched x86 benchmark was run,
so x86 performance, savings, and cooling claims are not inferred from these
snapshots.


## The Installation Journey 🗺️

### Phase 1: Hardware Assembly (The Fun Part!)

```bash
# Step 1: Insert RK1 modules into TuringPi 2
# Step 2: Attach heatsinks (ARM modules run cool, but better safe!)
# Step 3: Install NVMe drives
# Step 4: Connect power and networking
# Step 5: Power on and watch the ARM magic happen! ✨
```

### Phase 2: Software Deployment (The Ansible Way!)

```bash
# Clone our automation repository
gh repo clone vthinsel/mongodb-TuringPI-rk1

# Run on rk1-node4 (facility/control node): installs & validates Ansible, then sets up SSH keys
./setup_facility-node.sh

# Deploy MongoDB cluster
ansible-playbook --ask-vault-pass -i inventory.yml deploy_mongodb_cluster.yml

# Optional: remove MongoDB login/password requirements for convenience or tests
# Run this only on non-production clusters; it disables authentication entirely.
ansible-playbook --ask-vault-pass -i inventory.yml disable_mongodb_auth.yml -e disable_mongodb_auth=true

# Update all RK1 nodes (including rk1-node4), one node at a time
ansible-playbook --ask-vault-pass -i inventory.yml update_rk1cluster.yml -e reboot=true

# Set up monitoring
ansible-playbook --ask-vault-pass -i inventory.yml setup_monitoring.yml

# Run the first unauthenticated mixed YCSB test against the primary
ansible-playbook --ask-vault-pass -i inventory.yml ycsb_load_test.yml -e confirm_unauthenticated_ycsb=true

```

The three MongoDB nodes format and mount `/dev/nvme0n1` as `/data` for database
files. `rk1-node4` is not a MongoDB member: its `/dev/nvme0n1` is formatted and
mounted as `/monitoring` by `setup_monitoring.yml`. Prometheus time-series data
is stored at `/monitoring/prometheus/data`, Grafana state at
`/monitoring/grafana/data`, and the monitoring configuration and dashboard are
kept alongside them. The playbook uses XFS with `noatime,nodiratime,logbufs=8`
and persists the mount in `/etc/fstab` through Ansible's `mount` module.

Grafana loads the dedicated **TuringPi MongoDB Cluster** dashboard
automatically into the `TuringPi` folder. Its source is
`grafana/turingpi-mongodb-dashboard.json`; the playbook copies it to
`/monitoring/grafana/provisioning/dashboards/` and provisions the Prometheus
datasource at `http://prometheus:9090`. No manual dashboard import is needed.
Feel free to add or import any other dashboards from [Grafana](https://grafana.com/grafana/dashboards/?dataSource=nobl9agent%2Cprometheus%2Cvictorialogs-datasource)


### First YCSB Load Test

`ycsb_load_test.yml` runs the pinned ARM64 `redis/go-ycsb` image from
`rk1-node4` against the primary, `rk1-node1`, using an unauthenticated direct
connection. It first loads the YCSB dataset, then runs a common mixed profile:
The playbook bypasses the image's incompatible bundled init wrapper and invokes
the native ARM64 `/go-ycsb` binary directly. Note that the results can't be directly compared with other ycsb release, but can be used to compare different settings such as THP on/off, zippy Vs std, different wiredtiger cache size, etc.

- 50% reads
- 30% updates
- 20% scans/searches

The default test loads 100,000 records and runs 100,000 operations with four
threads. Adjust the workload without editing the playbook:

```bash
ansible-playbook --ask-vault-pass -i inventory.yml ycsb_load_test.yml \
  -e confirm_unauthenticated_ycsb=true \
  -e ycsb_record_count=1000000 \
  -e ycsb_operation_count=500000 \
  -e ycsb_threads=8
```

This test is intended only for isolated, non-production use. The confirmation
flag is required, and the direct connection keeps operations on the primary. This quick and simple test doesn't hit memory limits, thus wiredtiger settings don't come into the game as there is no pressure, we are in-memory workload scenario.

### Six-Hour YCSB Endurance Test

Run the separate endurance playbook after the unauthenticated cluster is ready:

```bash
ansible-playbook --ask-vault-pass -i inventory.yml ycsb_endurance_test.yml \
  -e confirm_unauthenticated_ycsb=true
```

It loads the dataset once, then runs the same 50% read, 30% update, and 20%
scan/search profile for six hours (`21600` seconds) against the primary.

### Percona Load Generator MongoDB

PLGM is the **platform-capacity stress test** in this part of the story. The
sample below is a three-hour configuration with 50 workers, running against
the replica set. It demonstrates the cluster sustaining a varied operation
mix; it does **not** isolate THP, TCMalloc, or WiredTiger effects. A 32 GB RK1
could be an interesting follow-up for memory-heavy workloads, but its benefit
has not been measured here.

```bash
ubuntu@rk1-node4:~/rk1-ansible/plgm-workloads$ ./percona-load-generator-mongodb-4.6.0/bin/plgm config.std-3hours-50workers.yaml 
  [INFO] Performance: Automatically disabled driver compression (compressors=none)
Enter MongoDB Username: 
Warning: Collections path 'resources/collections' not found. Using embedded default.json.
Warning: Queries path 'resources/queries' not found. Using embedded default.json.

  plgm dev
  --------------------------------------------------
  Target URI:     mongodb://rk1-node1:27017,rk1-node2:27017,rk1-node3:27017?compressors=none
  Namespaces:     airline.flights
  Workers:        50 active
  Duration:       3h
  Workload Mode:  Default (Only default.json)

  WORKLOAD DEFINITION
  --------------------------------------------------
  Distribution:  Select (79%)  Update (11%)
                 Insert (3%)   Delete (5%)
                 Agg    (0%)   Trans  (0%)

2026/08/28 06:18:07 [Lifecycle] Phase=initializing: preparing collections, indexes, sharding setup, and optional seed data
2026/08/28 06:18:07 [Lifecycle] Init Step 1/3: preparing collections
  [INFO] Skipping sharding for 'flights': Cluster is not sharded (Replica Set)
2026/08/28 06:18:07 [Lifecycle] Init Step 2/3: creating indexes (declared indexes=6)
  [INFO] Created 6 indexes on 'airline.flights'
2026/08/28 06:18:07 [Lifecycle] Init Step 3/3: optional seed (skip_seed=true, documents_count=100000)
2026/08/28 06:18:07 [Lifecycle] Initialization completed in 210ms
2026/08/28 06:18:07 [Lifecycle] Phase=running: execution timers now track query workload only
2026/08/28 06:18:07 Starting Standard Workload iteration 1 of 1

> Starting Workload...
 TIME    | TOTAL OPS |  SELECT |  INSERT |  UPSERT |  UPDATE |  DELETE |    AGG | TRANS
 -----------------------------------------------------------------------------------------
 00:01   |     4,462 |   2,568 |   1,390 |       0 |     336 |     168 |      0 |     0
 00:02   |     8,796 |   4,904 |   2,950 |       0 |     638 |     304 |      0 |     0
 00:03   |     7,559 |   4,095 |   2,610 |       0 |     604 |     250 |      0 |     0
 00:04   |     6,973 |   3,680 |   2,570 |       0 |     480 |     243 |      0 |     0
 00:05   |     5,890 |   3,105 |   2,150 |       0 |     433 |     202 |      0 |     0
 00:06   |     5,384 |   3,026 |   1,760 |       0 |     414 |     184 |      0 |     0
 00:07   |     5,782 |   3,007 |   2,170 |       0 |     428 |     177 |      0 |     0
 00:08   |     5,310 |   2,911 |   1,810 |       0 |     418 |     171 |      0 |     0
 00:09   |     4,772 |   2,659 |   1,590 |       0 |     350 |     173 |      0 |     0
 00:10   |     5,613 |   3,117 |   1,920 |       0 |     400 |     176 |      0 |     0
 00:11   |     4,831 |   2,632 |   1,630 |       0 |     387 |     182 |      0 |     0

```
### Updating the RK1 Cluster

Use `update_rk1cluster.yml` to refresh the OS and container images on all cluster nodes, including the control node `rk1-node4`. The playbook runs one host at a time (`serial: 1`) to avoid rolling reboots or package conflicts during the upgrade window.

```bash
ansible-playbook --ask-vault-pass -i inventory.yml update_rk1cluster.yml
ansible-playbook --ask-vault-pass -i inventory.yml update_rk1cluster.yml -e reboot=true
```

What it does:
- updates the apt cache and performs a full `apt upgrade` on every managed RK1 node
- pulls all currently tagged Docker images from the local Docker daemon on each host
- checks whether a reboot is needed because of kernel or package updates
- reboots only when the `reboot=true` flag is set and `/var/run/reboot-required` exists

This is intended for regular maintenance windows and is especially useful after the cluster has been running for a while and Docker image versions need refreshing.

### Ansible Vault Variables

The playbooks load encrypted variables from `group_vars/all/vault.yml`. Create
or edit this file with Ansible Vault; do not store a plaintext copy in Git.
The file must define the following variables:

| Variable | Purpose |
| --- | --- |
| `vault_ansible_user` | SSH user used to connect to the RK1 nodes |
| `vault_ansible_ssh_private_key_file` | Path to the SSH private key used by Ansible |
| `vault_bmc_base_url` | TuringPi BMC HTTPS URL |
| `vault_bmc_user` | BMC login user |
| `vault_bmc_password` | BMC login password |
| `vault_bmc_validate_certs` | Whether Ansible validates the BMC TLS certificate |
| `vault_mongodb_admin_user` | MongoDB administrator username |
| `vault_mongodb_admin_password` | MongoDB administrator password |
| `vault_mongodb_admin_password_uri` | URL-encoded MongoDB password for connection URIs |
| `vault_mongodb_keyfile` | Replica-set internal authentication key |
| `vault_grafana_admin_password` | Grafana administrator password |
| `vault_mongodb_monitoring_uri` | Authenticated connection URI used by the MongoDB exporters on rk1-node1..3 |

Initialize the encrypted file, or update it after rotating credentials:

```bash
ansible-vault create group_vars/all/vault.yml
ansible-vault edit group_vars/all/vault.yml
ansible-vault view group_vars/all/vault.yml
```

Use the vault password when running any playbook that loads the inventory:

```bash
ansible-playbook --ask-vault-pass -i inventory.yml deploy_mongodb_cluster.yml
```

The vault password is separate from all service passwords. Store it in a
password manager or provide it through a protected `ANSIBLE_VAULT_PASSWORD_FILE`
that is excluded by `.gitignore`. Rotate any credentials that were previously
exposed before using this setup in production.


## ⏻ Stopping & Starting the Whole Platform

Two playbooks manage the full lifecycle of the cluster, useful for power savings overnight or just saving the planet:

```bash
# Graceful stop: step down primary → stop mongod containers → stop monitoring
# → shutdown rk1-node1..3's OS → cut power to rk1-node1..3 via the BMC
# (rk1-node4 is left running - it's the Ansible control node)
ansible-playbook --ask-vault-pass -i inventory.yml stop_platform.yml

# Power rk1-node1..3 back on via the BMC → wait for SSH → (re)start mongod containers
# → wait for a PRIMARY to be elected → start the monitoring stack
ansible-playbook --ask-vault-pass -i inventory.yml start_platform.yml
```

Power control goes through the TuringPi 2 BMC's REST API (`bmcd`), not the OS, so rk1-node1..3 are fully de-powered between runs. **rk1-node4 is intentionally excluded from both shutdown and BMC power-off** since it's the Ansible control and monitoring host running these very playbooks - the node itself always stays on. BMC connection settings and credentials are stored in Ansible Vault.

![powersequence](./img/seq_diagram-on-off.png)

## Monitoring: Keeping an Eye on Our ARM Warriors 👁️

We've got a comprehensive monitoring setup running on `rk1-node4`:

### Metrics We Track:

- **System Metrics**: CPU, Memory, Disk I/O, Network
- **MongoDB Metrics**: Operations/sec, Connections, Replica Set Health, and WiredTiger cache usage
- **Power Consumption**: Via IoT smart plug integration with metrics fetched from HomeAssistant (full configuration not covered here)
- **Custom ARM Metrics**: Temperature, frequency scaling

### Dedicated Grafana Dashboard

The provisioned dashboard is designed for the three MongoDB data nodes and
uses a six-hour default time range with five-second refresh available. Panels
are grouped into three practical areas:

- **Hardware and host health**: cluster power, per-node CPU load, RK1
  temperature, NVMe read/write throughput, and node memory pressure.
- **MongoDB workload**: cluster-wide total operations/sec plus insert,
  read/query, and update rates.
- **MongoDB engine and cluster health**: WiredTiger cache used, configured
  cache size, cache utilization, current connections, and replica-set state.

The MongoDB exporter is Percona `0.40.0` with `--collect-all`. The dashboard
uses its emitted metric families, including `mongodb_ss_opcounters`,
`mongodb_ss_wt_cache_bytes_currently_in_the_cache`,
`mongodb_ss_wt_cache_maximum_bytes_configured`, and
`mongodb_ss_connections`. Replica state is read from the `rs_state` label:
`1` means PRIMARY and `2` means SECONDARY.

Grafana's image renderer is also enabled and available for the dashboard.
Use Grafana's panel or dashboard share controls to generate rendered PNG
images for reports, issue tickets, and quick status updates. The renderer is
deployed automatically as `grafana-image-renderer` by `setup_monitoring.yml`
and is secured with a shared authentication token between Grafana and the
renderer service.

To install or refresh the dashboard and monitoring stack:

```bash
ansible-playbook --ask-vault-pass -i inventory.yml setup_monitoring.yml
```

## Real-World Performance Stories 📈

### Story 1: The Endurance Test

We ran our cluster for **72 hours straight** with mixed workloads:

- **Zero downtime**: Replica set handled failovers gracefully
- **Consistent performance**: No degradation over time
- **Power consumption**: Averaged &lt;40 Watts 

### Story 2: The Scalability Surprise

- **Memory efficiency**: 16GB proved to be sufficient, but is workload dependent of course.
- **Storage performance**: NVMe drives delivered consistent latency

### Story 3: The Failover Test

Deliberately powered off `rk1-node1` (primary):

- **Failover time**: &lt;5 seconds
- **Data consistency**: Zero data loss
- **Recovery**: Automatic rejoin/resync/take-over when node returned

## Operations per Watt: The Little Board's Superpower ⚡

There is more to the platform than peak ops/s. The dashboard divides MongoDB
server-side operations per second by the **measured total cluster power**. It
is a useful live efficiency indicator while the three-node replica set, NVMe,
and monitoring stack are all running.

![MongoDB operations per second per watt](./img/opsperwatt.png)

| Phase in this capture | Approximate MongoDB ops/s/W | Reading the graph |
| --- | ---: | --- |
| 50M-document loading | ~200–550 | Fast inserts; not comparable with the mixed benchmark |
| Mixed benchmark campaigns | Typically ~180–320 | Useful sustained operating band, with short higher peaks |
| Between runs | ~20–50 | Background activity divided by baseline cluster power |

This is **MongoDB server operations**, not completed YCSB requests. A YCSB
SCAN can generate multiple server operations, and the graph does not by itself
rank thread counts or prove an ON/OFF THP energy advantage. Part II keeps the
power story honest by separating application throughput, server-side
operations, and latency.

## The Economics: Compact, Not a Matched x86 Shootout 💰

The carrier board is mini-ITX sized, and the four RK1 modules provide three
database members plus a dedicated control/monitoring node. The parts list
below gives an indicative build budget; prices and power tariffs vary. We did
not benchmark a like-for-like x86 system, so no quantified TCO or percentage
savings against x86 are claimed here.

## Lessons Learned &amp; Pro Tips 🎓

### What Worked Amazingly:

1. **ARM Performance**: Way better than expected for database workloads
2. **Power Efficiency**: Game-changer for edge deployments
3. **Ansible Automation**: Made deployment reproducible, idempotent and fast
4. **Container Strategy**: Docker simplified MongoDB management - probably slightly better performance on bare metal.
5. **Monitoring Stack**: Node Exporter + Prometheus + Grafana provided excellent visibility, and easy connection to external datasource (HomeAssistant for power)
6. **Percona Load Generator for MongoDB (PLGM)** : Excellent load/stress test coming with a web UI, insights, and lots of stuff. Got easily recompiled for ARM from the go source from github.
7. **YCSB**: Old load testing application, quite complex to run on a recent ARM Linux distro. Using a container image simplified this considerably, while also making results less directly comparable to existing benchmarks.

### Gotchas We Hit:

1. **ARM Docker Images**: Make sure you pull `arm64` variants
2. **Memory Management**: Tune MongoDB for ARM's memory characteristics
3. **NVMe Formatting**: XFS with specific mount options crucial for performance
4. **Transparent Huge Pages**: Since MongoDB 8, THP is recommended. The issue is that the RK1 default kernel is not built with THP. Recompiling the kernel is mandatory and quite time consuming....
5. **The 500k record-count trap**: An earlier 500,000-document load was followed
   by reuse runs with the playbook's 50,000,000 default `recordcount`. YCSB
   generated keys for documents that did not exist; one observed run recorded
   3,876 successful READs and 490,899 failed READs. Those runs were discarded.
   The playbook now checks the actual `usertable` document count against
   `ycsb_record_count` before benchmarking and passes that value explicitly to
   go-ycsb. Always specify `-e ycsb_database=ycsbsmall -e
   ycsb_record_count=500000` for the 500k collection.
6. **No reliable dataset drop in the bundled go-ycsb workflow**: A load against
   an existing collection produced duplicate-key errors instead of a clean
   replacement. When `load_dataset=true`, the playbook explicitly drops
   MongoDB's `usertable` collection on the primary (with majority write
   concern) **before** running go-ycsb `load`. This destroys the old test
   collection; use it only when a fresh benchmark load is intended.
7. **No effective `maxexecutiontime` in this go-ycsb build**: A very large
   `operationcount` keeps the workload from ending early. The playbook uses
   GNU `timeout` to end each `run` after 600 seconds, sending `SIGINT` and
   allowing a 30-second shutdown grace period. The loader is a separate,
   untimed preparation phase.

## Where the Cluster Fits ⭐

This build is particularly interesting for edge computing, IoT ingestion,
development replica sets, and teaching distributed systems. The RK1 is not a
drop-in substitute for a high-end x86 server: analytics, legacy x86 software,
and workloads that need maximum single-thread performance deserve separate
capacity tests.

## Your Turn: Build and Operate It 🚀

The indicative parts list is one TuringPi 2 board, four 16 GB RK1 modules,
four NVMe drives, heatsinks, an ATX PSU, cables, and a case. See the hardware
table above for roles and specifications; confirm current prices and storage
capacity before buying.

```bash
gh repo clone vthinsel/mongodb-TuringPI-rk1
cd mongodb-TuringPI-rk1
./setup_facility-node.sh
ansible-playbook --ask-vault-pass -i inventory.yml deploy_mongodb_cluster.yml
ansible-playbook --ask-vault-pass -i inventory.yml setup_monitoring.yml
```

To power down or bring the cluster back, use `stop_platform.yml` and
`start_platform.yml`. Authentication should remain enabled outside an isolated
benchmark environment. Contributors are welcome to bring another workload,
ARM platform, or real-world power measurement to the
[GitHub repository](https://github.com/vthinsel/mongodb-TuringPI-rk1).

### What Part I Proves—and What It Does Not

Four compact RK1s can host a three-node MongoDB replica set plus its own
facility node, survive deliberate primary failover, and run meaningful PLGM
stress workloads within a small power envelope. The platform story does not
tell us *why* performance changes when the working set grows. That is the
question for Part II: does THP help once WiredTiger starts evicting pages,
what is TCMalloc doing with memory, and where do extra YCSB threads stop
paying for themselves?

## Part II — MongoDB memory-management deep dive

This part separates **mechanism** from **measurement**. It documents the
kernel and allocator settings, the WiredTiger working sets, the controlled THP
ON/OFF procedure, and results from the 500k and 50M datasets. Claims
about causal THP effects are limited to what the repeated application-level
measurements and telemetry support.

### THP and TCMalloc deployment prerequisites

Enabling **Transparent Huge Pages** on RK1 requires a kernel compiled with the
appropriate option. The stock kernel does not expose the THP interface, so the
custom kernel packages must be installed before enabling THP through Ansible.
`setup_rk1cluster.yml` installs the two custom kernel packages from the repository
root and holds them so the package upgrade cannot replace them. Both `.deb` files
must be present beside the playbook before running the setup.

```bash
# MongoDB 8 on ARM64: enable THP and upgraded TCMalloc per-CPU caches
ansible-playbook --ask-vault-pass -i inventory.yml thp_enable.yml

# Optional A/B comparison: disable THP and restart MongoDB one node at a time
ansible-playbook --ask-vault-pass -i inventory.yml thp_disable.yml

# MongoDB 8 THP values: always, defer+madvise, 0, and 1
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag
cat /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
cat /proc/sys/vm/overcommit_memory

# MongoDB nodes: /dev/nvme0n1 is mounted at /data by deploy_mongodb_cluster.yml
mount -o noatime,nodiratime /dev/nvme0n1 /data

# Monitoring node (rk1-node4): /dev/nvme0n1 is mounted at /monitoring by setup_monitoring.yml
mount -o noatime,nodiratime,logbufs=8 /dev/nvme0n1 /monitoring

# Tune network buffers for ARM
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
```

MongoDB 8 uses upgraded TCMalloc on supported ARM64 Linux systems. The
deployment enables THP before Docker starts MongoDB, sets the required
`always`, `defer+madvise`, `max_ptes_none=0`, and `vm.overcommit_memory=1`
values, and sets `GLIBC_TUNABLES=glibc.pthread.rseq=0` in the container so
TCMalloc can use per-CPU caches. The `thp_enable.yml` and `thp_disable.yml`
playbooks provide a serial, restart-and-report A/B comparison for benchmarks.
Run the enable playbook again after comparison benchmarks to restore the
MongoDB 8-recommended configuration.

The RK1 kernel must expose `/sys/kernel/mm/transparent_hugepage` with `CONFIG_TRANSPARENT_HUGEPAGE` enabled. The playbooks
cannot enable THP when the kernel omits that interface; install or boot a
kernel built with that option first. Check the active kernel with:

```bash
uname -r
zgrep CONFIG_TRANSPARENT_HUGEPAGE /proc/config.gz 2>/dev/null || \
  grep CONFIG_TRANSPARENT_HUGEPAGE "/boot/config-$(uname -r)"
ls -ld /sys/kernel/mm/*transparent_hugepage
```

### Controlled THP evaluation on ARM64

Starting with MongoDB 8, Transparent Huge Pages (THP) are recommended on
supported Linux systems. Because the stock RK1 kernel does not expose the
required THP interface, this cluster uses a custom kernel built with
`CONFIG_TRANSPARENT_HUGEPAGE=y`.

The objective of this benchmark is to determine whether MongoDB's use of THP
produces a measurable application-level benefit on the RK3588 ARM64 platform.
Two complementary datasets are used:

| Dataset | Records | Purpose |
| --- | ---: | --- |
| Small | 500,000 | Observe THP with a relatively small working set |
| Large | 50,000,000 | Exercise WiredTiger eviction and storage under cache pressure |

The tests compare identical MongoDB, Docker, YCSB, storage, and hardware
configurations. Only the host THP state changes. Docker does not isolate a
container from host kernel memory management, so THP applies directly to the
containerized `mongod` process. The MongoDB containers have no CPU, memory, or
CPU-affinity limits, and `/data/db` is a host bind mount rather than Docker's
writable overlay filesystem.

### Test Environment

| Component | Configuration |
| --- | --- |
| MongoDB | 8.3.8, three-node replica set |
| Architecture | ARM64, Rockchip RK3588 |
| Memory | 16 GB per MongoDB node |
| Storage | Local NVMe, XFS |
| Deployment | Docker, without resource limits |
| WiredTiger cache | Approximately 7.2 GiB |
| YCSB client | `redis/go-ycsb` ARM64 container on `rk1-node4` |
| Target | Direct connection to the primary |
| Measured write concern | `majority` |

### Memory-stack interpretation: THP, TCMalloc, and WiredTiger

The three layers answer different questions. THP is a **host-kernel page
mapping** feature; TCMalloc manages `mongod`'s **user-space allocations**; and
WiredTiger manages **database pages in its own cache**. Seeing activity in one
layer does not establish a throughput benefit in another.

| Layer | What it changes | Evidence examined | Limit of the evidence |
| --- | --- | --- | --- |
| THP | Backs eligible anonymous memory with larger pages | Host `AnonHugePages`, fault allocations/fallbacks, collapse/split telemetry | Host-level huge pages do not, by themselves, quantify exactly how many belong to `mongod` |
| TCMalloc | Reuses memory in allocator caches and per-CPU structures | Allocated/free/unmapped memory and cache breakdown | Free memory retained by the allocator is not identical to WiredTiger cache occupancy |
| WiredTiger | Reads, dirties, and evicts database pages | Cache fill, read/eviction rates, dirty ratio, eviction triggers | Cache churn and NVMe I/O can dominate translation-overhead improvements |

The dashboard is interpreted as follows:

- In the **500k** campaign, host `AnonHugePages` grows to roughly
  4–5 GiB under THP ON, while cache fill rises over time without the sustained
  high-rate NVMe reads seen in the 50M campaign. The TCMalloc free/unmapped and
  cache panels evolve during both campaigns; they indicate allocator state
  changes, not a standalone THP performance result.
- In the **50M** campaign, THP-backed anonymous memory grows further, to
  roughly 6–7 GiB per data node. WiredTiger cache sits around 80% full, with
  sustained reads, eviction, and dirty-page cycles. These are distinct sources
  of latency variability that must be considered alongside the YCSB numbers.

The THP dashboard counters and `AnonHugePages` are host measurements. A
process-specific `smaps_rollup`/`smaps` check for `mongod` would strengthen the
attribution of huge-page coverage to MongoDB. No separate TCMalloc ON/OFF or
WiredTiger-cache-size A/B test was performed here: THP is the controlled
variable; the other two subsystems provide explanatory telemetry.

### Workload and Measurement Method

Both datasets use the same mixed workload:

- 60% READ, 25% UPDATE, and 15% SCAN
- Zipfian request distribution
- uniform scan-length distribution
- `readPreference=primary`
- `directConnection=true`
- 4, 8, 16, 32, and 64 YCSB client threads
- 600 seconds per concurrency level

The configured operation count is deliberately much larger than can be
completed during a run. The playbook uses an external timeout to terminate
each test after 600 seconds, making the comparison time-bound instead of
operation-count-bound. The go-ycsb limitation and shutdown behavior are
documented in the Part I gotchas.

Dataset creation is separate from the measured workload. Loading uses 32
threads and `writeConcern=1` to reduce preparation time; measured runs use
`writeConcern=majority`. The load phase is not included in benchmark results.

### Benchmark Procedure

1. Enable THP and reboot if requested:

  ```bash
  ansible-playbook --ask-vault-pass -i inventory.yml thp_enable.yml
  ```

2. Confirm the reported THP settings, then run the benchmark and give it a
  descriptive prefix:

  ```bash
  ansible-playbook --ask-vault-pass -i inventory.yml ycsb_cache_pressure_test.yml \
    -e confirm_unauthenticated_ycsb=true \
    -e load_dataset=true \
    -e file_prefix=thpon
  ```

3. Disable THP and reboot if requested:

  ```bash
  ansible-playbook --ask-vault-pass -i inventory.yml thp_disable.yml
  ```

4. Confirm the reported THP settings and repeat the benchmark with a different
  prefix:

  ```bash
  ansible-playbook --ask-vault-pass -i inventory.yml ycsb_cache_pressure_test.yml \
    -e confirm_unauthenticated_ycsb=true \
    -e file_prefix=thpoff
  ```

The dataset load is opt-in. Load it once before the first comparison run with
`-e load_dataset=true`; subsequent runs reuse the existing dataset and should
leave that option unset. Loading uses 32 client threads and primary-only write
acknowledgement for faster preparation. The measured workload uses majority
write concern and direct primary connections.

For **every** reuse run, pass the intended `ycsb_record_count` and database
explicitly (for example, `-e ycsb_database=ycsbsmall -e
ycsb_record_count=500000`). The protected playbook compares the actual
collection document count with the configured record count before the timed
thread sweep and refuses to run on a mismatch. The attached summary CSVs
still omit READ error counters, so raw thread logs remain necessary for a
final request-validity audit. The record-count failure that motivated this
safeguard is described in the Part I gotchas.

### Playbook Parameters

The main parameters are defined near the top of
`ycsb_cache_pressure_test.yml` and can be overridden with `-e`:

| Parameter | Default | Purpose |
| --- | ---: | --- |
| `ycsb_record_count` | `50000000` | Number of documents in the dataset |
| `ycsb_operation_count` | `50000000000` | Deliberately unreachable operation limit |
| `ycsb_run_duration_seconds` | `600` | Duration of each concurrency level |
| `ycsb_threads_sweep` | `4, 8, 16, 32, 64` | Client concurrency levels |
| `load_dataset` | `false` | Load or reuse the dataset |
| `ycsb_load_threads` | `32` | Concurrent clients used during loading |
| `ycsb_load_write_concern` | `1` | Load-phase acknowledgement level |
| `ycsb_cache_pressure_write_concern` | `majority` | Measured-run acknowledgement level |
| `file_prefix` | Current `YYYYMMDD_HHMMSS` | Prefix for all result files |

The workload is read/update/scan only: 60% reads, 25% updates, and 15% scans.
Inserts are disabled when reusing a populated dataset, avoiding duplicate-key
errors. The measured runs use `mongodb.write_concern=majority` and
`mongodb.read_preference=primary`.

### Generated Results

Results are written to `ycsb_results/` on the control node. For a prefix of
`nothp`, the playbook creates one raw file per thread level:

```text
ycsb_results/nothp-threads-4.txt
ycsb_results/nothp-threads-8.txt
ycsb_results/nothp-threads-16.txt
ycsb_results/nothp-threads-32.txt
ycsb_results/nothp-threads-64.txt
```

When `load_dataset=true`, the loader output is also saved as
`nothp-load.txt`. The thread files contain YCSB throughput, operation counts,
average latency, and percentile latency for READ, UPDATE, SCAN, and TOTAL.

### Python Report Generator

`ycsb_report.py` parses the raw thread files and generates an aggregate CSV and
PNG chart. Matplotlib is installed by `setup_facility-node.sh` as
`python3-matplotlib`.

The playbook runs the report generator automatically. To regenerate a report
manually or process an existing run:

```bash
python3 ycsb_report.py \
  --results-dir ycsb_results \
  --prefix nothp \
  --output-prefix nothp
```

This creates `ycsb_results/nothp-summary.csv` and
`ycsb_results/nothp-report.png`. The chart contains throughput, average
latency, p95 latency, and operation-count panels plotted against client
threads. The CSV is intended for further comparison or archival.

### Small Dataset: 500,000 Documents

The **500,000-document campaign** contains four repetitions under each THP
setting. The load logs confirm `recordcount=500000` and report 500,000
inserts. Run 1 is excluded consistently as the post-load transient/warm-up
repetition; the tables use the arithmetic mean of the final CSV totals from
runs 2-4.

**Figure 1 — Small-dataset Grafana overview (THP OFF and THP ON campaigns).**

![MongoDB RK1 THP small-dataset benchmark](./img/ycsb_thpoff_thpon_smallds.png)

| Threads | THP OFF ops/s | THP ON ops/s | ON vs. OFF | Average total latency OFF/ON | P95 OFF/ON |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 561.3 | 560.2 | -0.2% | 7.10 / 7.12 ms | 32.02 / 32.09 ms |
| 8 | 972.5 | 976.8 | +0.4% | 8.21 / 8.17 ms | 32.28 / 32.39 ms |
| **16** | **1,287.3** | **1,292.0** | **+0.4%** | **12.41 / 12.37 ms** | **51.89 / 52.15 ms** |
| 32 | 1,341.7 | 1,335.9 | -0.4% | 23.83 / 23.94 ms | 123.92 / 121.90 ms |
| 64 | 1,335.0 | 1,335.8 | +0.1% | 47.91 / 47.89 ms | 304.38 / 297.21 ms |

THP effects on throughput are mixed in sign and within roughly 0.5% across
these stabilized repetitions. Neither average nor P95 total latency shows a
consistent THP advantage. In Figure 1, THP-backed anonymous memory rises to
roughly 4-5 GiB on the enabled nodes; allocation and collapse activity appears
after THP is switched on, while flow control remains inactive. THP is thus
visibly in use, but not associated with a material YCSB performance gain in
this campaign.

The summary CSVs contain completed-operation throughput and latency, **not
READ success/error counters**. The load size and configured `recordcount` are
aligned, but a complete request-validity audit requires the raw YCSB thread
logs. Error-free READs should be confirmed there before treating these
numbers as final.

**Sixteen threads is the practical throughput/latency sweet spot for this
small-dataset workload.** Averaging the THP OFF and ON results exposes the
cost of pushing concurrency past the knee:

| Threads | Mean throughput | Mean average latency | Throughput vs. 16 | Latency vs. 16 | Mean P95 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 560.8 ops/s | 7.11 ms | -56.5% | -42.6% | 32.06 ms |
| 8 | 974.7 ops/s | 8.19 ms | -24.4% | -33.9% | 32.34 ms |
| **16** | **1,289.6 ops/s** | **12.39 ms** | **baseline** | **baseline** | **52.02 ms** |
| 32 | 1,338.8 ops/s | 23.89 ms | +3.8% | ~1.9x | 122.91 ms |
| 64 | 1,335.4 ops/s | 47.90 ms | +3.5% | ~3.9x | 300.80 ms |

From 16 to 32 threads, throughput rises by only 3.8% while mean latency
almost doubles; at 64 threads throughput slips slightly below the 32-thread
level while mean latency nearly quadruples relative to 16 threads. P95 also
rises by roughly 2.4x and 5.8x respectively. **The 32- and 64-thread settings
are poor latency trade-offs for this specific small-dataset profile.**

### Large Dataset: 50 Million Documents

The large dataset is intentionally much greater than the effective WiredTiger
cache. It creates sustained cache churn and exercises the full path through
WiredTiger eviction, NVMe I/O, dirty-page processing, checkpointing, and
replica-set acknowledgement.

**Figure 2 — Large-dataset Grafana overview (50M documents, THP OFF followed by
THP ON).**

![MongoDB RK1 THP large-dataset benchmark](./img/ycsb_thpoff_thpon_largeds.png)

The table below uses the arithmetic mean of the final YCSB totals from repeated
runs 2-4. Run 1 is excluded consistently as the transient/warm-up repetition.
Latency values are total-operation latency.

| Threads | THP OFF ops/s | THP ON ops/s | Throughput change | Avg latency OFF/ON | P95 OFF/ON |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 77.7 | 79.0 | +1.7% | 51.4 / 50.6 ms | 341.8 / 337.4 ms |
| 8 | 144.6 | 150.6 | +4.1% | 55.3 / 53.1 ms | 369.8 / 356.9 ms |
| 16 | 257.9 | 261.9 | +1.6% | 62.0 / 61.1 ms | 424.4 / 411.9 ms |
| 32 | 411.1 | 440.4 | +7.1% | 77.8 / 72.7 ms | 535.9 / 493.7 ms |
| 64 | 605.4 | 638.4 | +5.5% | 105.6 / 100.1 ms | 718.0 / 670.7 ms |

Unlike the small dataset, the repeated large-dataset results show a modest THP
advantage at every tested concurrency level. The largest mean throughput gain
is approximately 7.1% at 32 threads, while average and P95 latency are also
lower with THP enabled at all five thread counts. The gain is not linear, so it
should be interpreted as a workload-level effect rather than a fixed THP
improvement factor.

The dashboard confirms that this is a genuine cache-pressure workload:

- WiredTiger cache remains around 80% full on the active data nodes.
- eviction is sustained throughout the campaigns;
- NVMe reads frequently reach approximately 150-200 MiB/s;
- dirty-cache ratios rise and fall with checkpoint and writeback cycles;
- replication lag adds occasional latency variability.

Flow control requires a separate interpretation. The flow-control activity in
Figure 2 occurs **only during the 50M-document loading step**, when documents
are initially inserted. It is absent from the measured 4/8/16/32/64-thread
YCSB sweeps. Flow control is therefore evidence of pressure during dataset
creation, but it is **not a limiting factor in the reported benchmark results**.

THP use is also much greater than in the small experiment. The MongoDB nodes
reach approximately 6-7 GiB of `AnonHugePages` each. THP allocations are
continuous, fallbacks remain rare, and collapse/split activity does not show a
pathological storm. Docker therefore does not prevent THP from operating, and
the measured benefit is not accompanied by an obvious THP allocation failure
or compaction problem.

The 50M-record workload continues to gain throughput through 64 client threads,
unlike the small workload. That gain comes with rapidly increasing latency.
The following table averages THP ON and OFF values to isolate the concurrency
trade-off from the THP comparison:

| Threads | Mean throughput | Mean average latency | Throughput vs. 16 | Latency vs. 16 | Operating interpretation |
| ---: | ---: | ---: | ---: | ---: | --- |
| 4 | 78.4 ops/s | 51.0 ms | -69.8% | -17.1% | Under-utilized |
| 8 | 147.6 ops/s | 54.2 ms | -43.2% | -11.9% | Conservative |
| **16** | **259.9 ops/s** | **61.6 ms** | **baseline** | **baseline** | **Sweet spot** |
| 32 | 425.8 ops/s | 75.3 ms | +63.8% | +22.2% | Throughput-oriented |
| 64 | 621.9 ops/s | 102.9 ms | +139.3% | +67.0% | Maximum throughput, high latency |

At 32 and especially 64 threads, average latency rises much faster in absolute
terms and P95 latency reaches roughly 494-536 ms and 671-718 ms respectively.
Those settings remain useful when batch throughput is the priority, but they
are no longer the most balanced choice. **Sixteen threads is a reasonable
latency-conscious operating point for this large-dataset profile, but not its sweet spot**: unlike the small dataset, 32 and 64 threads provide
substantial additional throughput. Select those higher settings when the
extra completed work justifies the measured latency cost.

![Threads](./img/threads.png)

**Figure 3 — Concurrency operating regions observed on the RK1 cluster.**

### Global Conclusion

Together, the two datasets show that MongoDB 8.3.8 successfully and extensively
uses Transparent Huge Pages on RK1/RK3588 ARM64, including when `mongod` runs
inside Docker. Allocation fallbacks remain very low, so the comparison is not
between an effective THP OFF configuration and a nominal-but-nonfunctional THP
ON configuration.

The performance effect depends on the working set:

- With the 500,000-document workload, THP ON and OFF differ by less
  than approximately 0.5% in mean throughput across the tested thread counts.
  The 16-thread knee is clear: moving to 32 or 64 adds only 3.8% or 3.5%
  throughput on average, while average total latency rises by roughly 1.9x or
  3.9x, respectively. Raw READ error counters should be checked before final
  publication of this new campaign.
- With 50 million documents and sustained WiredTiger cache pressure, repeated
  runs 2-4 show a small but consistent THP benefit: approximately 1.6-7.1%
  higher mean throughput, accompanied by lower mean and P95 total latency at
  every tested concurrency level. Throughput continues to scale above 16
  threads, but average and P95 latency rise sharply, making 16 threads the most
  balanced operating point and 32-64 threads throughput-oriented choices.

The evidence therefore supports a more nuanced conclusion than either "THP
always improves MongoDB" or "THP has no effect":

> **On this RK1 ARM64 cluster, THP is neutral for the small, relatively
> cache-resident workload and modestly beneficial for the 50M-document
> cache-pressure workload in these repeated runs. The larger workload shows
> both greater THP-backed memory and higher mean throughput with THP ON;
> these measurements do not isolate the memory-coverage increase as the cause.
> WiredTiger, NVMe I/O, replication,
> and concurrency remain the dominant determinants of overall performance.
> Sixteen client threads is the small-dataset throughput/latency sweet spot;
> on the large dataset, 32 and 64 threads can offer substantial additional
> throughput, but also increase average and P95 latency.**

The operations-per-watt chart in Part I describes the platform's power
envelope, but it is based on **server-side** MongoDB operations rather than
YCSB requests. A per-thread and time-aligned power comparison would be
required to establish whether THP improves completed YCSB work per watt.

These findings are specific to this RK3588 hardware, MongoDB 8.3.8, custom
Linux kernel, Docker deployment, WiredTiger configuration, NVMe subsystem,
replica-set topology, and YCSB workload. They should not be generalized into a
universal MongoDB THP rule. For this project, the MongoDB 8-recommended
THP-enabled configuration remains the operational default, while THP OFF is
retained for controlled A/B testing.

### Further Performance Optimizations Worth Testing

- A/B test MongoDB in Docker versus bare metal to quantify the actual
  containerization overhead on RK1. The current container has no resource
  limits, `/data/db` is a host bind mount, and the metrics confirm that THP is
  already active for the containerized `mongod`, so Docker is not expected to
  prevent THP operation.
- Benchmark `mongodb_wiredtiger_cache_size_gb` at `4`, `6`, and `8` on the
  16 GB RK1 nodes. The system currently defaults to `6` to keep more RAM
  available for Linux page cache, Docker overhead, and monitoring while still
  preserving a useful WiredTiger working set.
- A/B test `mongodb_wiredtiger_collection_compressor` between `zstd` and
  `snappy`. The current `zstd` default is space-efficient, but `snappy` often
  improves CPU-bound write throughput on ARM.
- Consider pinning the `mongod` container to the RK3588 Cortex-A76 cores during
  write-heavy benchmarks. The big.LITTLE topology can otherwise mix
  latency-sensitive database threads with background tasks.
- Compare the current direct-primary workload with a replica-set-aware client
  profile to quantify driver-routing and failover behavior. The present
  measured workload already uses `writeConcern=majority`.
- Pin the monitoring containers away from `:latest` before long benchmark
  campaigns so exporter behavior and Prometheus/Grafana feature changes do not
  skew repeatability.
