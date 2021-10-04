---
title: "Integrating Asyncronous iperf3 Tests in Android 11+"
date: 2021-09-30
draft: true
description: "C++ also builds character"
tags: [
    "android",
    "seattle-community-network",
    "networks",
    "ICTD",
]
categories: [
    "software-development",
    "cellular",
    ]
type: "post"
---

## Preamble

I've been helping out the [Seattle Community
Network](https://seattlecommunitynetwork.org) (SCN), with an ongoing project to
build a crowdsourced network performance measurement application for Android.
While understanding modern network performance, particularly wireless networks,
is *extremely* subtle, "speedtests" offer a crude yet popular way to measure a
network's performance, and are easy for general audiences to interpret.

Unsurprisingly, SCN sought to include a "speedtest" capability in their app! A
team of volunteer undergraduate researchers ([Zhennan(John)
Zhou](https://johnnzhou.github.io/) & [Ashwin
Chintalapati](https://www.linkedin.com/in/ashwin-chintalapati-a54936222/))
organized by [Esther Jang](https://infrared-ether.medium.com/) got started on
the project, and started integrating [iperf3](https://github.com/esnet/iperf)
(C, [BSD-3](https://github.com/esnet/iperf/blob/master/LICENSE) into the
application. Due to its maturity, consistent history of open source activity,
and explicit offer of "a library version of the functionality that can be used
in other programs," I thought it was a reasonable choice. After a couple of
weeks their efforts stalled though, and I was asked for some input.

This marked the beginning of the journey...

For part one, see my prior post [Building iperf3 For Android 11+]({{< relref
"building-iperf.md" >}})

## Integrating iperf3 with an Android Application

Once we had a stable way to build libiperf, it was time to actually integrate
its functionality into our application to provide the "speedtest" capability.
Since the test would run for 10s of seconds, we needed it to operate
asynchronously and not block the main UI thread. The team also wanted the test
to be able to complete if the user switches away from the application while the
test is running. Android has a [great flowchart in their developer
documentation](https://developer.android.com/guide/background) for deciding
where and how to run tasks in modern Android. Since the test needed to be
decoupled from the main application context (to allow switching), the team
selected AndroidX's `WorkManager`
([Overview](https://developer.android.com/topic/libraries/architecture/workmanager)
[Ref](https://developer.android.com/reference/androidx/work/WorkManager)).

At a high-level, `WorkManager` allows the application to schedule work requests
for either one-time work or periodic work. It has some cool capabilities to put
constraints on when tasks run (like requiring a WiFi connection, when not on
battery, when the device is idle, etc.), and an entire process for managing work
windows for periodic maintenance tasks. Fortunately our task is relatively
straightforward: we want to immediately run a test in response to user input,
allow users to chancel running tests if they start one by mistake, and get the
results of the test upon completion.

The `Worker` class
([Ref](https://developer.android.com/reference/androidx/work/Worker)) provides a
synchronous interface for running work in its `doWork()` method and can be
enqueued in the `WorkManager` to execute immediately. Since libiperf is a C
library, we call a native C function across the Java Native Interface which
initializes the iperf test c-struct with the intended test parameters and starts
the test. All of this works well enough, and allows us to run a single iperf
test to completion. At this point things start to get a bit more interesting...

## Stopping iperf3 tests

It was an important feature that in-progress tests could be cancelled in case a
heavyweight test was started accidentally! The WorkManager provides a
[straightforward
API](https://developer.android.com/topic/libraries/architecture/workmanager/how-to/managing-work#cancelling)
to cancel enqueued or in-progress work. The `Worker` class presents a
synchronous interface though-- how does the stop signal get to the worker? It
turns out there are two ways, either by providing an override for the
`onStopped()` callback, or by polling the `isStopped()` property in the main
`doWork()` method. Since our `doWork()` method just indirectly wraps the
underlying libiperf `run_client()` function, which is also synchronous and
blocks on an underlying select(), there would not be an easy way to regularly
poll `isStopped()` during the test without extensively modifying libiperf.

Examining the source code for the [main iperf3 command line
program](https://github.com/esnet/iperf/blob/master/src/main.c), which is
implemented with libiperf and supports cancellation, we saw that they handle
test cancellation by intercepting SIGINT, SIGTERM, and SIGHUP and calling
`iperf_got_sigend()` from the libiperf api whenever one of the signals is
received. This looked promising and easy to integrate with the `isStopped()`
worker callback! So we connected the callbacks, started a test, pressed the
cancel button, and...

watched our app crash.

Well not exactly crash, just, close? Digging into the implementation of
`iperf_got_sigend()` quickly reveals a surprising twist for an embeddable api...
a call to `exit()`!

### Process assumptions in the libiperf API

It turns out that the iperf API wasn't quite as embeddable as we had originally
hoped, and really was designed for implementing iperf-like command line
programs instead of providing iperf as a part of a larger application. In
Android the entire application is kept within the same process, including our
background workers and the foreground UI. Calling exit doesn't just stop the
background worker, but terminates the entire process/application! We wouldn't be
able to stop our test the same way, and would have to figure out something else.

### Manually setting the done flag

Deep into the libiperf source at this point, we noticed a boolean `done` flag
being checked in the client loop, but no high-level api to set it outside
`iperf_got_sigend()`. Setting it to true appeared to cause the client to break
out of its main run loop and return, exactly the behavior we wanted! Setting it
directly required extending the libiperf API, and we're planning to upstream
these changes for future integrators.

But there is no magic-- since the `done` flag is only checked at each iteration
of the run loop, we still have to work around the blocking select at its heart.
For uplink tests the loop runs with every transmitted packet, providing plenty
of responsiveness. In downlink though the loop only runs when a packet is
*received*, which could stall if there is a problem in the network. Fortunately
the iperf authors anticipated this problem, and provide a fallback timeout!

Unfortunately, this timeout defaults to (a very conservative) two minutes : /

Configuring the timeout was also not exposed in the high-level API yet, but we
were able to add an extension easily along with our earlier efforts. We chose a
value of 5 seconds, which should be long enough for the types of connections we
hope to measure, but still responsive enough for acceptable UX.

This approach of polling the done flag is eerily similar to just checking
`is_stopped()` (the high-level Java function provided by Worker), but has the
advantage of not needing to make a heavyweight JNI call for each received packet
during the test, and not needing to add JNI code directly into libiperf.
Unfortunately though, this approach now requres us to now reason about threading
and concurrent access to a value in C/C++, something that is not needed in
the regular single-threaded with signals iperf client!

### Setting done from a different thread

The done flag in particular is polled from the main worker thread, which blocks
on `select()`, but will need to be set from a different worker thread provided
by the app's WorkManager running `onStopped()`. To make matters even more
complicated, done is part of the internal to libiperf iperf_test struct, which
is allocated at the beginning of the test and freed at the end of the test. We
need to protect access to the memory in this struct to ensure it is still valid
when accessing it from `onStopped()`.

Since we only run one test at a time (by design, to prevent the tests from
interfering), it is relatively straightforward to make a singleton holding a
pointer to the current test and a mutex protecting access to the test struct. If
multiple concurrent tests were needed this approach could be extended to
implenting a store of the currently running tests, with some kind of ID system
to get access to the correct test instance.

Tracking the test instance across threads with a singleton test manager is not
particularly elegent or optimized for maximum performance, but is robust,
performant enough, and safe.

So we finally have it all. A means to run iperf tests in the background of our
application, and a means to stop them on demand from the foreground UI. In
testing I start some tests, and stop some tests, and start a test, and then...
nothing happens. The UI is responsive, but no traffic is being generated for the
latest tests.

### Learning to better understand the Worker contract

It turns out that this is where things get even more complicated. After adding
extensive debug logging and an hour or so of narrowing down on where things get
hung up, it becomes apparent that the mutex protecting the singleton test
manager is locked, preventing new tests from starting without a full restart of
the app. But being modern C++ programmers we were using `std::lock_guard`, an
[RAII](https://en.wikipedia.org/wiki/Resource_acquisition_is_initialization)-based
wrapper for scoped mutex ownership. This should be impossible!

After much head scratching and many dead ends, we generate a new hypothesis:
what if the worker thread is somehow "killed" uncleanly, leaving the process
memory in an invalid state? We add more debug telmetry building an RAII function
entry/exit logger to validate our assumptions and verify that both the main
worker thread and stop signal thread are returning correctly. After around a
dozen tests, it becomes clear that our logging in the cleanup of the JNI
function consistently appears, but the logs at the end of the main function do
not!

At this point, being neither an expert in Java nor Android's latest Java
runtime, it's extremely counter-intuitive to me why background worker threads
would be killed "mid-function" while the parent process (the application)
remains running. On a hunch, and reading between the lines of the `onStopped()`
method documentation, we add a
[CountDownLatch](https://developer.android.com/reference/java/util/concurrent/CountDownLatch)
to our Worker implementation to count down when the native run_test function has
completed, and hold our `onStopped()` implementation from returning until the
latch is triggered. Lo and behold, our main function exit logging now
consistently appears, and the mutex returns to expected operation.

The [documentation for onStopped() in the managing work
guide](https://developer.android.com/topic/libraries/architecture/workmanager/how-to/managing-work#onstopped_callback)
says:

> WorkManager invokes ListenableWorker.onStopped() as soon as your Worker has
> been stopped. Override this method to close any resources you may be holding
> onto.

It may be an implementation detail, or a quirk of the interaction between the
JNI and WorkManager, but should be something to be aware of if you find yourself
using RAII principles to manage long-lived native state in a JNI function. At
the point onStopped() returns it seems *all* resources must be released,
including resources managed with RAII in your main thread!

## Epilogue: gracefully handling errors

After all this, we finally were able to complete our integration of the iperf
tool into our high-level Android testing app. We did encounter one more issue,
which was libiperf 3.10.1 handling test errors (like an unreachable server or
timeout) with and internal call to `exit()` rather than returning an error code
from the `run_client()` function! This appears to have been accidental, and was
[concurrently fixed](https://github.com/esnet/iperf/pull/1202) by [Joakim
Sørensen](https://github.com/ludeeus).

Hopefully as more folks use libiperf externally we can continue to improve the
stability and test coverage of this valuable open-source resource!
