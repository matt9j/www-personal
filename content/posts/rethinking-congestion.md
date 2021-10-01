---
title: "Rethinking network congestion (Especially in community networks)"
date: 2021-01-27
draft: false
description: "Crosspost from the UW ICTD Lab's medium account"
tags: [
    "Common Pool Resources",
    "LTE",
    "Bandwidth",
    "Community Network",
    "ICTD",
]
categories: [
    "cellular",
    ]
type: "post"
---

### What is congestion in a network anyway?

A network link suffers from congestion when demand for the link’s resources
exceeds the amount of service it can supply within some reasonable duration of
time, resulting in data being dropped on the floor or delayed. Both the
“resources” and “reasonable duration of time” are highly situational and vary by
application and type of network.[^1] Ultimately this becomes “ugh, why is the
WiFi so slow today!”

**In the presence of resource congestion, everyone on the network cannot get
everything that they want.**

I argue that networking practitioners, myself included, need to rethink how we
reason about network behavior in the presence of congestion. *We need to consider
how humans on their computers and phones experience congestion and how those
humans expect to resolve these fundamentally resource allocation problems.* The
answers are not apparent.

## Hidden Mechanisms with Hidden Assumptions

Most users don’t get much visibility into, or control over, the congestion in
their networks that causes slow service at their device. The most congested
link, known as the bottleneck, could be very distant from the user, deep in the
heart of the network, or directly connected to the user (“at the edge”). To make
matters worse, congestion can sometimes cause even more network congestion: when
a bottleneck link drops packets it cannot forward in time, those packets must be
re-transmitted, resulting in even more traffic, which leads to even more
congestion… and eventually total network failure (This tragic fate, *congestion
collapse*, is as terrible as it sounds. See [Congestion Avoidance and Control,
Jacobson 1988](https://dl.acm.org/doi/10.1145/52324.52356))!

The Internet relies on *congestion control protocols* (like TCP, BBR, or Timely)
to help traffic sources know when the network is congested and scale back the
amount of data they transmit accordingly. Congestion control protocols have
evolved extensively over the lifetime of the Internet, using a variety of
different congestion signals and strategies for managing the congestion, but all
protocols seek to accomplish this same basic task. **Ultimately, congestion
management is a resource allocation problem — there is more demand for network
resources (i.e. bandwidth) than can be supplied, creating scarcity.** The
available resources must somehow be allocated between the competing flows in the
network. In this context, though, modern internet networks fall woefully short
of expectations.

For many years academics have relied on the notion of *flow rate fairness* to
conceptualize how resources are divided in the Internet. The idea is that all
flows should altruistically follow compatible rules, and thus will evenly share
the network resources naturally in a distributed fashion. For anyone who has
worked with real systems, however, there are two immediately apparent problems
with this approach:

* Relying on altruistic behavior from all sources is unrealistic (whether by
  malicious intent, negligence, or honest mistakes in applications).
* It’s unclear how flows (which are concretely visible on the network) map to
  actual users (real-world entities outside the network).

Researchers and engineers have articulated and argued these (and other)
drawbacks for decades (see [Flow Rate Fairness: Dismantling a Religion, Briscoe
2007](https://api.semanticscholar.org/CorpusID:6260388) for a well-written
example, [Charging and Rate Control for Elastic Traffic, Kelly
1997](https://api.semanticscholar.org/CorpusID:7818839) for an early theoretical
analysis, and [On the Future of Congestion Control for the Public Internet,
Brown et al.
2020](https://www.microsoft.com/en-us/research/publication/on-the-future-of-congestion-control-for-the-public-internet/),
which addresses congestion in the core of the modern Internet). Whole fields of
study have developed around solving these challenges (Check out the terms
[“Weighted Proportional Fairness”](https://www.semanticscholar.org/search?q=Weighted%20Proportional%20Fairness&sort=relevance) and [“Quality of Service”](https://www.semanticscholar.org/search?q=Quality%20of%20Service&sort=relevance) or [“QoS”](https://www.semanticscholar.org/search?q=QoS&sort=relevance)). **Yet the
public and hobbyist discourse around network traffic management is negligible,
limiting the exposure community network operators have to the possible tradeoffs
and options available.**

## Challenges to Transparency and Control

Experienced system administrators have access to some sophisticated tools for
designing and deploying network rules via professional network management suites
(with both software and network hardware components). Yet real-world local,
community, and/or mesh networking tools (in our experience) lack the capability
for enforcing meaningful resource allocation outside flow-rate fairness. **A
range of factors combine to make meaningful congestion management incredibly
hard,** including but not limited to:

* The large number of abstractions between traffic “on the wire” and the actual
  applications creating that traffic.
* Poor choices for network equipment defaults which tend toward not enforcing
  any policy.
* The inherent complexity of network performance, especially with wireless links
  serving multiple devices.
* No reliable way to map network traffic to a real-world entity without extra
  outside information.
* The proliferation of transport layer encryption (which is a good thing!), but
  which limits visibility and makes it hard to understand how the network is
  actually used.
* A lack of support of meaningful QoS tagging, even in sophisticated
  applications, depending on the device operating system and network medium.
* Non-linear and time-varying real economic costs such as monthly data caps or
  wireless promotions that make it hard to decide on an optimal usage strategy.

Computer networks are engineered to account for *flows* of traffic, streams of
data sent from one application to another through the network’s layers and many
links. **Network engineers reason about flows because they are easy to measure
on the network itself, but in reality flows have limited meaning.** Flows on
their own don’t reveal how to allocate network resources to real people and
their activities on the net.

## Understanding Resources in Community Networks

Community networks in particular pose unique resource allocation challenges. In
community networks, a group of people organize and run their own network for
their own benefit. **The goal is to maximize the utility of the network’s
physical capabilities for all members.** This is in contrast to commercial
networks that seek to maximize profit, providing the least costly amount of
acceptable service while maximizing the return from end-user subscriptions.
Commercial operators often mask the fundamental capabilities of the underlying
network infrastructure for competitive advantage, and their immediate profit
motive overshadows messy concerns around resource allocation and fairness.

A community can be defined in as many ways as you can imagine, but importantly,
a community network is bigger than a single person or household. **Community
networks care about achieving equitable division of underlying resources, and
rely on human governance structures to make decisions about fairness.** The unit
entity of resource consumption in community networks can be surprisingly
complex: should resources be allocated between families, households, devices,
individuals, or other possibly overlapping identity groups (elders, students,
government workers, etc.)? Current implementations lack the flexibility to
handle all cases.

Beyond just allocating bandwidth proportionally between entities, community
networks may wish to incorporate other values into network management. Examples
could be prioritizing certain classes of applications over others (like
relatively lightweight real-time audio calls over bulk media consumption), or
encouraging using the network during off-peak hours to improve utilization.[^2]
Additionally the metric of interest may not be bandwidth at all, but could be
latency (as real-time digital communication has grown in importance with the
ongoing COVID pandemic), or subjective application performance. **While these
ideas are easy to express abstractly, they are extremely difficult to encode in
concrete and enforceable network policies with existing systems.**

Reconceptualizing congestion management as resource allocation opens a frontier
of new possibilities for system designs and correspondingly new requirements on
the network to support resource allocations in an efficient manner. **While there
is much theory to draw from, both in computer science and economics, the
challenge now is to move meaningfully beyond the status quo and actually realize
the potential of congestion management to improve the predictability,
understandability, and performance of networks for *everyday* people in the real
world.** This will involve both the creation of new systems as well as improving
the availability and accessibility of existing techniques, lowering the
threshold to effective use.

---

[^1] A video call requires ~3mbps of bandwidth with a maximum latency of a few
hundred ms. Browsing the web can tolerate longer latencies and smaller amounts
of bandwidth.

[^2] The implementation details of traffic management could easily have negative
implications for *Net Neutrality*, the principle that all traffic on the network
should be treated equally. I want to emphasize the difference between
prioritizing a few specific popular applications, versus prioritizing an entire
class of applications, regardless of which specific application each user should
choose to use. Unfortunately, current affordances make the former easier to
implement than the latter, which can lead to reinforcement of incumbent market
positions and lead to long-term harm to the Internet ecosystem. I hope to enable
communities to implement the latter via more general and even-handed forms of
class-based prioritization should they desire to do so.

---

(See original post [on medium](https://medium.com/uw-ictd/rethinking-network-congestion-ed122ba8ef7f))