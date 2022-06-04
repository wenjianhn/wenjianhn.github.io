# Reproducing the container throttling problem

Per https://danluu.com/cgroup-throttling, exhausting the cpu quota rapidly negatively impacts tail latency.

## CPUQuota: 400%, threads: 4
```text
$ sudo systemd-run --scope -p CPUQuota=400%  /home/w/code/github.com/akopytov/sysbench/src/sysbench --threads=4 cpu --percentile=99 run
Running scope as unit: run-rbfc36982fb854d6986880d8320e9fb0c.scope
sysbench 1.1.0-df89d34c410a (using bundled LuaJIT 2.1.0-beta3)

Running the test with following options:
Number of threads: 4
Initializing random number generator from current time


Prime numbers limit: 10000

Initializing worker threads...

Threads started!

CPU speed:
    events per second:  6459.19

Throughput:
    events/s (eps):                      6459.1925
    time elapsed:                        10.0006s
    total number of events:              64596

Latency (ms):
         min:                                    0.60
         avg:                                    0.62
         max:                                    1.35
         99th percentile:                        0.64
         sum:                                39994.67

Threads fairness:
    events (avg/stddev):           16149.0000/18.12
    execution time (avg/stddev):   9.9987/0.00

```

## CPUQuota: 400%, threads: 8
```text
$ sudo systemd-run --scope -p CPUQuota=400%  /home/w/code/github.com/akopytov/sysbench/src/sysbench --threads=8 cpu --percentile=99 --histogram run
sysbench 1.1.0-df89d34c410a (using bundled LuaJIT 2.1.0-beta3)

Running the test with following options:
Number of threads: 8
Initializing random number generator from current time


Prime numbers limit: 10000

Initializing worker threads...

Threads started!

Latency histogram (values are in milliseconds)
       value  ------------- distribution ------------- count
       0.619 |**************************************** 60564
       0.630 |*                                        2156
       0.642 |                                         214
       0.654 |                                         66
       0.665 |                                         60
       0.677 |                                         39
       0.690 |                                         22
       0.702 |                                         11
       0.715 |                                         16
       0.728 |                                         21
       0.741 |                                         20
       0.755 |                                         13
       0.768 |                                         7
       0.782 |                                         12
       0.797 |                                         10
       0.811 |                                         32
       0.826 |                                         607
       0.841 |                                         19
       0.856 |                                         27
       0.872 |                                         15
       0.888 |                                         31
       0.904 |                                         43
       0.920 |                                         11
       0.937 |                                         5
       0.989 |                                         1
       9.560 |                                         5
      13.460 |                                         1
      13.704 |                                         2
      49.213 |                                         577
      50.107 |                                         92
      52.889 |                                         1
      53.850 |                                         25
      56.839 |                                         2
      57.871 |                                         95
 
CPU speed:
    events per second:  6481.13

Throughput:
    events/s (eps):                      6481.1278
    time elapsed:                        10.0017s
    total number of events:              64822

Latency (ms):
         min:                                    0.62
         avg:                                    1.23
         max:                                   57.69
         99th percentile:                       49.21
         sum:                                79991.86

Threads fairness:
    events (avg/stddev):           8102.7500/156.76
    execution time (avg/stddev):   9.9990/0.00
```

Hacking sysbench to report checkpoints at 20, 40, 60, 80, 100, 120, 140 ms:
```text
$ sudo systemd-run --scope -p CPUQuota=400%  /home/w/code/github.com/akopytov/sysbench/src/sysbench --threads=8 cpu --percentile=99 --histogram --time=1 --report-checkpoints=20,40,60,80,100,120,140 run
sysbench 1.1.0-df89d34c410a (using bundled LuaJIT 2.1.0-beta3)

Running the test with following options:
Number of threads: 8
Report checkpoint(s) at 20, 40, 60, 80, 100, 120, 140 ms
Initializing random number generator from current time


Prime numbers limit: 10000

Initializing worker threads...

Threads started!

[ 20ms ] Checkpoint report:
CPU speed:
    events per ms:    10.95

Throughput:
    events/ms (epms):                    10.9463
    time elapsed:                        20.0981ms
    total number of events:              220

Latency (ms):
         min:                                    0.62
         avg:                                    0.72
         max:                                    0.85
         99th percentile:                        0.83
         sum:                                  165.98

Threads fairness:
    events (avg/stddev):           29.0000/4.00
    execution time (avg/stddev):   0.0207/0.00

[ 40ms ] Checkpoint report:
CPU speed:
    events per ms:    11.27

Throughput:
    events/ms (epms):                    11.2720
    time elapsed:                        40.0592ms
    total number of events:              225

Latency (ms):
         min:                                    0.62
         avg:                                    0.71
         max:                                    0.82
         99th percentile:                        0.83
         sum:                                  158.02

Threads fairness:
    events (avg/stddev):           28.0000/4.00
    execution time (avg/stddev):   0.0198/0.00

[ 60ms ] Checkpoint report:
CPU speed:
    events per ms:     6.89

Throughput:
    events/ms (epms):                    6.8866
    time elapsed:                        60.0980ms
    total number of events:              138

Latency (ms):
         min:                                    0.62
         avg:                                    0.70
         max:                                    0.85
         99th percentile:                        0.83
         sum:                                   88.78

Threads fairness:
    events (avg/stddev):           15.8750/3.33
    execution time (avg/stddev):   0.0111/0.00

[ 80ms ] Checkpoint report:
CPU speed:
    events per ms:     5.90

Throughput:
    events/ms (epms):                    5.9028
    time elapsed:                        80.0887ms
    total number of events:              118

Latency (ms):
         min:                                    0.62
         avg:                                    1.80
         max:                                   21.55
         99th percentile:                       21.50
         sum:                                  233.43

Threads fairness:
    events (avg/stddev):           16.2500/2.28
    execution time (avg/stddev):   0.0292/0.00

[ 100ms ] Checkpoint report:
CPU speed:
    events per ms:    11.30

Throughput:
    events/ms (epms):                    11.3012
    time elapsed:                        100.0865ms
    total number of events:              226

Latency (ms):
         min:                                    0.62
         avg:                                    0.70
         max:                                    0.83
         99th percentile:                        0.83
         sum:                                  158.99
		 
Threads fairness:
    events (avg/stddev):           28.2500/4.02
    execution time (avg/stddev):   0.0199/0.00

[ 120ms ] Checkpoint report:
CPU speed:
    events per ms:    10.87

Throughput:
    events/ms (epms):                    10.8651
    time elapsed:                        120.0588ms
    total number of events:              217

Latency (ms):
         min:                                    0.62
         avg:                                    0.69
         max:                                    0.82
         99th percentile:                        0.83
         sum:                                  148.00

Threads fairness:
    events (avg/stddev):           26.7500/6.16
    execution time (avg/stddev):   0.0185/0.00
	
Latency histogram (values are in milliseconds)
       value  ------------- distribution ------------- count
       0.619 |**************************************** 3343
       0.630 |**                                       143
       0.642 |                                         15
       0.654 |                                         5
       0.665 |                                         4
       0.677 |                                         5
       0.690 |                                         1
       0.702 |                                         1
       0.728 |                                         1
       0.755 |                                         1
       0.768 |                                         1
       0.797 |                                         1
       0.811 |******************                       1468
       0.826 |                                         21
       0.856 |                                         3
       0.872 |                                         1
       0.937 |                                         1
      49.213 |                                         38
      50.107 |                                         21
      53.850 |                                         4
      57.871 |                                         9
 
CPU speed:
    events per ms:     5.77

Throughput:
    events/ms (epms):                    5.7749
    time elapsed:                        1001.6388ms
    total number of events:              5091

Latency (ms):
         min:                                    0.62
         avg:                                    1.39
         max:                                   57.70
         99th percentile:                       49.21
         sum:                                 7047.88

Threads fairness:
    events (avg/stddev):           635.2500/59.99
    execution time (avg/stddev):   0.8810/0.00

```
