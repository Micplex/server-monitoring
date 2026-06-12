# Simple Linux Server Alerting & Monitoring Setup

> **Know when your server needs attention — before your users notice.** I set up lightweight, native Bash alert scripts directly on your VPS that check disk space, memory, critical system services, and Docker containers, then ping your Slack or email the second a threshold is breached. No cloud platforms. No monthly SaaS subscriptions. Just cron, curl, and clean logic.

---

## Overview

I'm a computer science student building practical Linux and server administration skills through real projects. I configure server environments, harden SSH, deploy Docker workloads, configure Nginx reverse proxies, and wire up lightweight alerting — all at rates that make sense for small businesses, startups, and solo developers.

This is a **one-time configuration service.** I install and test the alerting script framework on your server and hand it over. You own the ongoing execution. There are no recurring fees or software contracts with me.

I work remotely and perform all configurations directly on your infrastructure via SSH.

---

## What Problem This Solves

Without basic alerting, a full storage disk or a crashed application service goes completely unnoticed until an angry client complains. A background log file quietly fills up your root storage, your primary database stops writing, and your whole deployment crashes.

I handle the baseline configuration to eliminate this blind spot. You get immediate visibility inside the communication tools you already use daily, allowing you to catch server faults before they turn into major downtime.

---

## Services Offered

I deploy an optimized set of targeted Bash check-scripts to `/opt/monitoring/` on your server and schedule them natively using system `cron` jobs.

### 1. Hardware Resource Monitoring
- **Disk Space Watchdog:** Monitors partition capacity across your drive. Fires an immediate alert if storage utilization crosses a safe threshold (default: 85% full) so you can rotate logs before database locks occur.
- **Memory Utilization Tracker:** Monitors available system RAM, throwing a notification if free memory drops dangerously low.
- **CPU Load Watchdog:** Monitors system load averages to warn you if a runaway terminal process is locking up your processor cores.

### 2. Service & Container Auditing
- **Systemd Service Monitors:** Tracks critical systemd software layers that you specify (such as Nginx, PostgreSQL, MySQL, or your custom app runtime). If a service drops offline, an alert fires.
- **Docker Engine Watchdog:** Monitors your local Docker socket. If a critical application container exits or crashes, you receive an immediate alert detailing the failing container name.

### 3. Log Records & Housekeeping
- **Plain-Text Status Logs:** Consolidated warning records are appended directly to a local, text-based log file (`/var/log/server-health.log`) for fast diagnostic inspections.
- **Automated Log Rotation:** Deploys custom rules to your system `logrotate` engine to compress old health logs weekly, ensuring your alert data never crowds out your server's disk space.

---

## What You Receive at Handoff

When the deployment window closes, you receive:
- **An Active, Native Alert Script Framework:** Automated tracking scripts executing cleanly inside your server's system scheduler (`cron`).
- **Wired Notification Routing:** Verified integration using either an Incoming Slack Webhook or your machine's local mail utility.
- **A Simple Plain-Text Reference Note:** A short markdown guide detailing exactly where your scripts live, what thresholds trigger notifications, where the logs are appended, and the exact commands to run to execute a manual test alert.
- **Pre-Change Crontab Backups:** A manual safety copy of your system's existing schedules preserved prior to configuration.

### What You Do NOT Receive:
- Source code distribution, resale rights, or asset replication licensing for my internal utility scripts, macro variables, or deployment workflow templates.
- A downloadable, standalone software app or interactive graphical user interface (GUI).
- Centralized metrics databases, time-series data storage stacks, or web-based reporting dashboards (Grafana, Prometheus, or HTML front-ends).
- Free threshold alterations or recurring script adjustments once the support window closes.

---

## Supported Systems

### Operating Systems
- Ubuntu Server (20.04 LTS, 22.04 LTS, 24.04 LTS)
- Debian Linux (11, 12)
- Standard 64-bit (amd64) server instances

### Alert Destinations
- Slack Channels (via custom Incoming Webhooks)
- Standard System Email Relays

*Note: I do not support RedHat/CentOS/Fedora alternatives, ARM hardware (Raspberry Pi), Kubernetes container orchestration layers, or Windows Server systems.*

---

## The Setup Process

1. **Intake & Scope:** We discuss your system specifications, the exact systemd service paths or Docker container names you want tracked, and your target Slack webhook URL or destination email address.
2. **Access & Preparation:** You grant temporary SSH root or sudo access to your machine via an SSH public key. (Taking a full provider snapshot or backup in your hosting panel before I log in is highly recommended.)
3. **Script Installation & Tuning (20–30 minutes):** I build out the tracking directory under `/opt/monitoring/`, adjust the execution thresholds to align with your normal server workload, and apply the background `cron` tasks.
4. **Handoff & Verification:** We execute a manual parameter change to force a test alert, confirming a message successfully arrives in your Slack channel or email inbox. Once verified, you immediately revoke my SSH credentials.

---

## Fixed Pricing

Simple, one-time flat rates. No ongoing SaaS licensing fees, hidden platform charges, or unexpected hourly tracking bills.

- **Starter Tier ($75):** Automated script configuration watching core CPU, RAM, and Disk space targets. Includes routing to a single chosen notification channel (Slack or Email).
- **Standard Tier ($125):** Everything in the Starter tier, plus integration for native systemd service tracking, live Docker container runtime monitoring, and automated `logrotate` housekeeping tasks.

*All prices are quoted in USD. Cloud hosting bills, domain registration fees, external SMTP mail routing costs, and your third-party software platform fees are billed directly by your providers and are not included here.*

---

## What Is NOT Included

To prevent scope creep and maintain strict, realistic commitments, the following items are completely **out of scope**:
- Ongoing system monitoring as a managed service. The script generates the notification; managing and diagnosing the root system failure remains entirely your responsibility.
- Database maintenance, manual query tracking, database backup configurations, indexing fixes, or data schema optimizations.
- Designing cloud system architectures, structural firewalls, or cloud provider routing schemes.
- Custom application development, backend source code debugging, web development, or code refactoring.
- Uptime service-level agreements (SLAs), on-call availability guarantees, or emergency incident responses.

---

## Support Boundaries & Terms

### 3-Day Fix Window
I stand by my baseline setups. If an alerting script throws a syntax error, fails to execute on its schedule, or encounters a configuration bug within 3 days of handoff, I will log back in and recalibrate it at zero cost.

**This courtesy window is instantly voided if any of the following occur:**
- The `/opt/monitoring/` directory or its core scripts are moved, renamed, or deleted.
- Server SSH credentials are changed or revoked before technical inspection occurs.
- A configuration file is edited after handoff and introduces a custom formatting or script syntax typo.
- The server runs out of primary disk space, causing `cron` to stall or script files to become corrupted.
- User roles or file system permissions within `/opt/monitoring/` are modified.
- Core utilities the environment relies on (`cron`, `curl`, `gawk`, `sed`, `grep`) are uninstalled or altered.

### After the Fix Window
All structural modifications, additional service configurations, alert threshold changes, or environment troubleshooting sessions are treated as entirely separate, billable technical tasks.

### No Data Recovery or Uptime Guarantees
I configure an automated script system to track host parameters. I cannot guarantee data preservation or prevent infrastructure crashes resulting from underlying hardware corruptions, malicious software security breaches, or unexpected operating system panics.

---

## Contact

**Email:** [your-email@example.com]
**Upwork Profile:** [Link to verified Upwork Profile]

If you want a simple, un-killable alert framework running smoothly on your machine, send me a message with:
1. Your server operating system and hosting provider.
2. The specific list of systemd service scripts or Docker container names you need to watch.
3. Your preferred alert destination type (Slack Webhook or Email).

*I respond to all professional inquiries within one business day.*
