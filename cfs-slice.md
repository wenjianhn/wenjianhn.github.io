# A simple test on CFS slices

I did a simple test to understand CFS slices of CPU-bound processes
with the same priority.

## The background
The number of CPUs determines `sched_latency_ns` and `sched_min_granularity_ns`.  
`CONFIG_HZ` determines tick period.  
`HRTICK`, disabled by default, provides high-resolution preemption tick.  

`sched_latency_ns: 6ms * (1 + ilog(ncpus))`  
It is 24000000 ns on my notebooks with 8 CPUs.

`sched_min_granularity_ns: 0.75 msec * (1 + ilog(ncpus))`  
It is 3000000 ns on my notebook.

Tick period is 1000/CONFIG_HZ ms.  
It is 4 ms when `CONFIG_HZ` is 250.

The regular scheduler tick that runs at 1/HZ can be too coarse.  
The HRTICK feature is useful to preempt SCHED_FAIR tasks on-the-dot  
(just when they would have exceeded their ideal_runtime).

## The script
[cfs_slice.sh](https://wenjianhn.github.io/cfs_slice.sh)

## The result
```
Number of CPUs:  8
Sched latency:  24 ms
Tick period:     4 ms

Sched latency:      24000000 ns
No. of processes:   2
Expected run time:  12000000 ns
Allocated run time: 11999992 ns
Actual run time:
           time    cpu  task name                       wait time  sch delay   run time
                        [tid/pid]                          (msec)     (msec)     (msec)
--------------- ------  ------------------------------  ---------  ---------  ---------
   13294.640051 [0000]  python[5364]                        0.000      0.000      0.000 
   13294.656051 [0000]  python[5365]                        0.000      0.000     15.999 
   13294.672050 [0000]  python[5364]                       15.999      0.000     15.998 
   13294.688050 [0000]  python[5365]                       15.998      0.000     16.000 

Sched latency:      24000000 ns
No. of processes:   6
Expected run time:  4000000 ns
Allocated run time: 3999995 ns
Actual run time:
           time    cpu  task name                       wait time  sch delay   run time
                        [tid/pid]                          (msec)     (msec)     (msec)
--------------- ------  ------------------------------  ---------  ---------  ---------
   13298.448028 [0000]  python[5421]                        0.000      0.000      0.000 
   13298.456027 [0000]  python[5425]                        0.000      0.000      7.999 
   13298.464026 [0000]  python[5420]                        0.000      0.000      7.999 
   13298.472027 [0000]  python[5422]                        0.000      0.000      8.000 
   13298.480030 [0000]  python[5423]                        0.000      0.000      8.002 
   13298.488026 [0000]  python[5424]                        0.000      0.000      7.995 
   13298.496031 [0000]  python[5421]                       39.997      0.000      8.005 
   13298.504025 [0000]  python[5425]                       40.010      0.000      7.988 
   13298.512025 [0000]  python[5420]                       39.999      0.000      7.999 
   13298.520025 [0000]  python[5422]                       39.998      0.000      7.999 
   13298.528025 [0000]  python[5423]                       39.995      0.000      7.999 
   13298.536025 [0000]  python[5424]                       39.999      0.000      8.000 

Sched latency:      24000000 ns
No. of processes:   10
Expected run time:  3000000 ns
Allocated run time: 2999996 ns
Actual run time:
           time    cpu  task name                       wait time  sch delay   run time
                        [tid/pid]                          (msec)     (msec)     (msec)
--------------- ------  ------------------------------  ---------  ---------  ---------
   13302.344005 [0000]  python[5486]                        0.000      0.000      0.000 
   13302.348003 [0000]  python[5483]                        0.000      0.000      3.997 
   13302.352003 [0000]  python[5479]                        0.000      0.000      3.999 
   13302.356002 [0000]  python[5482]                        0.000      0.000      3.999 
   13302.360003 [0000]  python[5484]                        0.000      0.000      4.000 
   13302.364002 [0000]  python[5477]                        0.000      0.000      3.999 
   13302.368002 [0000]  python[5480]                        0.000      0.000      3.999 
   13302.372002 [0000]  python[5485]                        0.000      0.000      4.000 
   13302.376002 [0000]  python[5478]                        0.000      0.000      3.999 
   13302.380002 [0000]  python[5481]                        0.000      0.000      3.999 
   13302.384003 [0000]  python[5486]                       35.996      0.000      4.001 
   13302.388001 [0000]  python[5483]                       36.000      0.000      3.998 
   13302.392002 [0000]  python[5479]                       35.998      0.000      4.000 
   13302.396001 [0000]  python[5482]                       35.999      0.000      3.999 
   13302.400004 [0000]  python[5484]                       35.998      0.000      4.002 
   13302.404004 [0000]  python[5477]                       36.001      0.000      4.000 
   13302.408002 [0000]  python[5480]                       36.001      0.000      3.997 
   13302.412001 [0000]  python[5485]                       35.999      0.000      3.999 
   13302.416001 [0000]  python[5478]                       35.999      0.000      3.999 
   13302.420002 [0000]  python[5481]                       35.999      0.000      4.000 

=============
Enable HRTICK
Sched latency:      24000000 ns
No. of processes:   2
Expected run time:  12000000 ns
Allocated run time: 11999992 ns
Actual run time:
           time    cpu  task name                       wait time  sch delay   run time
                        [tid/pid]                          (msec)     (msec)     (msec)
--------------- ------  ------------------------------  ---------  ---------  ---------
   13306.107217 [0000]  python[5542]                        0.000      0.000      0.000 
   13306.119219 [0000]  python[5543]                        0.000      0.000     12.002 
   13306.131221 [0000]  python[5542]                       12.002      0.000     12.002 
   13306.143224 [0000]  python[5543]                       12.002      0.000     12.002 

Sched latency:      24000000 ns
No. of processes:   6
Expected run time:  4000000 ns
Allocated run time: 3999995 ns
Actual run time:
           time    cpu  task name                       wait time  sch delay   run time
                        [tid/pid]                          (msec)     (msec)     (msec)
--------------- ------  ------------------------------  ---------  ---------  ---------
   13309.920364 [0000]  python[5595]                        0.000      0.000      0.000 
   13309.924367 [0000]  python[5599]                        0.000      0.000      4.002 
   13309.928370 [0000]  python[5596]                        0.000      0.000      4.002 
   13309.929338 [0000]  python[5598]                        0.000      0.000      0.968 
   13309.933345 [0000]  python[5597]                        0.000      0.000      4.002 
   13309.937348 [0000]  python[5600]                        0.000      0.000      4.002 
   13309.941351 [0000]  python[5595]                       16.983      0.000      4.002 
   13309.945353 [0000]  python[5598]                       12.012      0.000      4.002 
   13309.949356 [0000]  python[5599]                       20.986      0.000      4.002 
   13309.953358 [0000]  python[5596]                       20.985      0.000      4.002 
   13309.957361 [0000]  python[5597]                       20.013      0.000      4.002 
   13309.961363 [0000]  python[5600]                       20.013      0.000      4.002 

Sched latency:      24000000 ns
No. of processes:   10
Expected run time:  3000000 ns
Allocated run time: 2999996 ns
Actual run time:
           time    cpu  task name                       wait time  sch delay   run time
                        [tid/pid]                          (msec)     (msec)     (msec)
--------------- ------  ------------------------------  ---------  ---------  ---------
   13313.737295 [0000]  python[5654]                        0.000      0.000      0.000 
   13313.740297 [0000]  python[5660]                        0.000      0.000      3.001 
   13313.743300 [0000]  python[5659]                        0.000      0.000      3.002 
   13313.746303 [0000]  python[5663]                        0.000      0.000      3.003 
   13313.749306 [0000]  python[5662]                        0.000      0.000      3.003 
   13313.752309 [0000]  python[5661]                        0.000      0.000      3.002 
   13313.755312 [0000]  python[5658]                        0.000      0.000      3.003 
   13313.758315 [0000]  python[5655]                        0.000      0.000      3.002 
   13313.761317 [0000]  python[5656]                        0.000      0.000      3.002 
   13313.764320 [0000]  python[5657]                        0.000      0.000      3.002 
   13313.767323 [0000]  python[5654]                       27.024      0.000      3.003 
   13313.770326 [0000]  python[5660]                       27.026      0.000      3.002 
   13313.773329 [0000]  python[5659]                       27.026      0.000      3.002 
   13313.776331 [0000]  python[5663]                       27.025      0.000      3.002 
   13313.779333 [0000]  python[5662]                       27.025      0.000      3.002 
   13313.782336 [0000]  python[5661]                       27.024      0.000      3.002 
   13313.785338 [0000]  python[5658]                       27.024      0.000      3.002 
   13313.788341 [0000]  python[5655]                       27.023      0.000      3.002 
   13313.791344 [0000]  python[5656]                       27.023      0.000      3.002 
   13313.794347 [0000]  python[5657]                       27.023      0.000      3.003 
```
