<div align="center">

<img src="assets/kodachi-logo.png" alt="Kodachi OS" width="170">

# Kodachi OS

**A hardened, privacy-focused Linux distribution built on Debian.**
Failover VPN, Tor routing, DNSCrypt, a kill switch and anti-forensic tooling, pre-wired and working from first boot.

[![Website](https://img.shields.io/badge/kodachi.cloud-Visit-9FEF00?style=flat-square&logo=firefox&logoColor=black)](https://kodachi.cloud/)
[![Download](https://img.shields.io/badge/Download-ISOs%20%26%20binaries-blue?style=flat-square&logo=cloudsmith&logoColor=white)](https://kodachi.cloud/downloads/)
[![Version](https://img.shields.io/badge/Current-Kodachi%209-brightgreen?style=flat-square)](https://kodachi.cloud/)
[![Beta](https://img.shields.io/badge/Beta%20available-Kodachi%2010-orange?style=flat-square&logo=git&logoColor=white)](#kodachi-10--now-in-beta)
[![License](https://img.shields.io/badge/License-KSAN--1.1-lightgrey?style=flat-square)](LICENSE.md)
[![Discord](https://img.shields.io/badge/Discord-Support-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/KEFErEx)

</div>

---

> [!IMPORTANT]
> **Kodachi 10 beta is out. Give it a try.**
>
> The 10.x line is published on the **beta channel** and open for public testing, while Kodachi 9 stays the stable release. Beta gets new work first, including the AmneziaWG and OpenVPN over Cloak transports, and is rebuilt often, so expect rough edges and report what you find.
>
> **There is no beta ISO.** Beta is a package channel, not a separate system image. Install a current ISO, or use a Debian-family system you already run, then point APT at the beta repository:
>
> ```bash
> curl -fsSL https://kodachi.cloud/repo-beta/setup.sh | sudo sh
> sudo apt update && sudo apt install kodachi
> ```
>
> Already running Kodachi from the stable channel? Switching is a different pair of commands, because APT will not move an installed package to beta on its own. Those, the supported releases, and the two commands that put you back on stable are all on the **[Downloads Center](https://kodachi.cloud/downloads/)**.

---

## Download

Three editions, one security core. Pick by how you want to run it.

| Edition | What it is | Get it |
|---|---|---|
| **Desktop (Debian XFCE)** | The full experience: graphical dashboard, every security binary pre-integrated. | [ISO](https://kodachi.cloud/downloads/#desktop) &middot; [Guide](https://kodachi.cloud/docs/desktop-debian.html) |
| **Terminal Server** | Lightweight ISO, all binaries pre-configured, no desktop. For servers and headless boxes. | [ISO](https://kodachi.cloud/downloads/#terminal) &middot; [Guide](https://kodachi.cloud/docs/terminal-version.html) |
| **Standalone binaries** | Add Kodachi's tools to a Debian-based system you already run. Ships with the dashboard GUI. | [Download + install instructions](https://kodachi.cloud/downloads/#binaries) |

Everything lives on the **[Downloads Center](https://kodachi.cloud/downloads/)**, including the install instructions for each edition, the apt repository setup, live download trends and by-country stats. **[Verify what you downloaded](https://kodachi.cloud/docs/security/file-verify.html)** before you boot it, and [check your system is current](https://kodachi.cloud/tools/proof.html) after you do.

> Default login for the Terminal Server and Desktop editions: user `kodachi`, password `Security4All`

---

## Kodachi 10 , now in beta

Kodachi 10 is the next major release, built on the Kodachi 9 foundation: new capabilities, wider feature coverage, and performance and security work across the whole stack (binaries, terminal edition, desktop edition, AI layer, cloud platform).

**You can run it today.** The 10.x packages ship on the beta channel and are open to anyone who wants to test them. Kodachi 9 remains the stable release and is what the Desktop and Terminal ISOs install. Beta is a package channel only, there is no beta ISO, and it is rebuilt often, so run it somewhere a break costs you nothing. Setup, supported releases and the route back to stable are on the **[Downloads Center](https://kodachi.cloud/downloads/)**.

There is no fixed date for the stable Kodachi 10 release. Roadmap items, previews and changelogs are published here and on the [landing page](https://kodachi.cloud/) as they land.

**Feature requests and feedback shape what ships**, and a bug report from a beta tester is the most useful thing anyone can send right now. Open an [issue](https://github.com/WMAL/kodachios/issues) or bring it to [Discord](https://discord.gg/KEFErEx).

| | |
|---|---|
| Live changelog | [kodachi.cloud/docs/changelog.html](https://kodachi.cloud/docs/changelog.html) ([raw](https://kodachi.cloud/apps/os/CHANGELOG.md)) |
| R&D history | [Kodachi-9/v9-behind-scenes-progress](Kodachi-9/v9-behind-scenes-progress) |

---

## Understand it before you trust it

Kodachi asks for a lot of trust. These exist so you do not have to give it blindly.

| | |
|---|---|
| **[Technical Whitepaper](https://kodachi.cloud/tools/whitepaper.html)** | How the whole platform actually works: Rust services, routing, Tor, DNS, hardening, VPS fleet, the RSA-4096 + BLAKE3 signing chain, and an honest threat model including what Kodachi does **not** protect against. |
| **[Architecture , the rack](https://kodachi.cloud/tools/architecture.html)** | An animated command centre: hover a unit to trace its cables, click to pin the detail. 17 signed Rust services, 8 AI binaries, 11 routing protocols, and the link between your device and the cloud fleet, with live platform counters. |
| **[Development Activity](https://kodachi.cloud/tools/architecture.html#activity)** | The live build ledger. What is being worked on right now, as it happens. |
| **[Knowledge Graph](https://kodachi.cloud/tools/architecture.html#graph)** | A live map of how every part of Kodachi connects to every other part. |
| **[Command Library](https://kodachi.cloud/tools/command-library.html)** | Every signed CLI command, searchable by binary, by name, or by plain-language goal such as "erase logs". Destructive commands are flagged. Nothing executes. |
| **[Workflow Simulator](https://kodachi.cloud/tools/workflow-simulator.html)** | Watch a real Kodachi workflow run without running it: control travels a circuit diagram step by step while each command streams sample output. 113 workflows across 13 subsystems, from torrification to the emergency kill switch. |
| **[Dashboard Gallery](https://kodachi.cloud/docs/gallery.html)** | 53 annotated screenshots of the real control plane, captured on a live system. Filter by topic or play it as a reel. See it before you install it. |
| **[Binary Documentation](https://kodachi.cloud/docs/)** | Reference for every service and binary. |
| **[Warrant Canary](https://kodachi.cloud/tools/warrant.html)** | Current signed statement. |

---

## Live tools

Free, no account, run them from a browser:
[Infrastructure status](https://kodachi.cloud/apps/status.php) &middot;
[System freshness checker](https://kodachi.cloud/tools/proof.html) &middot;
[Knowledge graph](https://kodachi.cloud/tools/knowledge-graph-public.html) &middot;
[API docs](https://kodachi.cloud/tools/api-docs.html) &middot;
[User guide](https://kodachi.cloud/tools/user-guide.html) &middot;
[FAQ](https://kodachi.cloud/tools/faq.html) &middot;
[Roll of Honor](https://kodachi.cloud/community/contributors.html)

Included with **[Kodachi Premium](https://kodachi.cloud/docs/support.html)**:
[IP & DNS report](https://kodachi.cloud/apps/ip-report.php) &middot;
[DNS leak test](https://kodachi.cloud/tools/dns.html) &middot;
[Fingerprint / IP analytics](https://kodachi.cloud/tools/ip.html) &middot;
[Domain checker](https://kodachi.cloud/tools/domain-checker.html) &middot;
[Domain info](https://kodachi.cloud/apps/domain-info/)

---

## Kodachi 9 , the current release

Kodachi 9 is finished, released and production-ready. Every component ships: standalone binaries, terminal server edition, desktop edition, the Tauri dashboard GUI, the AI layer (KAICS), and the cloud platform.

The full Kodachi 9 record, the component-by-component roadmap, the release phases, the development timeline and the historical update log, lives in **[Kodachi-9/README.md](Kodachi-9/README.md)**.

Kodachi 8.27 reached end of life and is archived in **[Kodachi-8.27-legacy-EOL](Kodachi-8.27-legacy-EOL)**.

---

## Recognition

- **1st place, [TechRadar](https://www.techradar.com/news/best-linux-distro-privacy-security) Best Linux Distro for Privacy & Security, six years running (2020-2025)**
  [2020](https://www.digi77.com/software/kodachi/TechRadar2020.pdf) &middot; [2021](https://www.digi77.com/software/kodachi/TechRadar2021.pdf) &middot; [2022](https://www.digi77.com/software/kodachi/TechRadar2022.pdf) &middot; [2023](https://www.digi77.com/software/kodachi/TechRadar2023.pdf) &middot; [2024](https://www.digi77.com/software/kodachi/TechRadar2024.pdf) &middot; [2025](https://www.digi77.com/software/kodachi/TechRadar2025.pdf)
- **1st place**, [Linux Format UK](https://www.digi77.com/software/kodachi/Linux_Format_UK_Issue_267_September_2020.pdf) privacy distribution roundup (2020)
- **1st place**, [DistroWatch](https://twitter.com/warith2020/status/1105179632935075840?s=20) privacy-focused distributions (2019)
- **Hot Product**, [APC Magazine](https://www.digi77.com/software/kodachi/APC-Magazine--496-August-2021-Australia.pdf) Australia (2021)

---

## Support the project

Kodachi is free. Keeping it running is not. Donations fund development, infrastructure and user support: crypto (BTC, ETH, XMR, SOL, USDT, DOGE, LTC and more), PayPal, and recurring options on the **[support page](https://kodachi.cloud/docs/support.html)**.

Everyone who helps is named on the **[Roll of Honor](https://kodachi.cloud/community/contributors.html)**. Kodachi was built by one and strengthened by many.

---

## License

Kodachi is **source-available and noncommercial**. It is **not** open source, and not under GPL, MIT, Apache or BSD. It is governed by the **Kodachi Source-Available Noncommercial License v1.1 (KSAN-1.1)**: [LICENSE.md](LICENSE.md) &middot; [online](https://kodachi.cloud/docs/license.html)

Except where KSAN-1.1 grants otherwise, all Kodachi materials by Warith Al Maawali, source, binaries, scripts, artwork, documentation and branding, are © 2013-2026 Warith Al Maawali, all rights reserved. Bundled third-party software stays under its own licenses.

**Disclaimer.** Kodachi exists to protect privacy. It is not for illegal activity, and its developers accept no liability for what users do with it. Complying with the law where you live is your responsibility.

---

## Contact

**Warith Al Maawali** , [digi77.com](https://www.digi77.com) &middot; [GitHub](https://github.com/WMAL) &middot; [Twitter](https://twitter.com/warith2020) &middot; [LinkedIn](https://www.linkedin.com/in/warith-al-maawali/)

[Website](https://kodachi.cloud/) &middot; [Discord support](https://discord.gg/KEFErEx) &middot; [Contact form](https://www.digi77.com/contact/)

<div align="center">

© 2013-2026 Warith Al Maawali, Muscat, Sultanate of Oman. All rights reserved.

</div>
