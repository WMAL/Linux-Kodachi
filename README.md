## Overview

# Linux Kodachi - Kodachi 9 soon 🚀

**Linux Kodachi** is a **security-focused operating system** designed for users who value **privacy, anonymity,** and a **secure computing experience**. Developed by **Warith Al Maawali**, Kodachi provides all the tools necessary for anonymous online activities while maintaining ease of use. Built on top of **Xubuntu 18.04.6** and further customized for enhanced privacy and security, Kodachi serves as a **live system** that leaves **no trace** on the host machine.

## Features at a Glance

- 🔒 **Secure by Default:** Kodachi ensures that from the moment you boot up, you're protected. With a **pre-configured VPN**, **Tor network**, and **DNSCrypt** service, your internet traffic is encrypted and anonymized without requiring any configuration.
- 🛡️ **Privacy Focused:** All your online connections are routed through a multi-layered protection stack, including **VPN** and **Tor**, making your identity extremely difficult to trace.
- 🖥️ **Live System:** Kodachi operates directly from **RAM**, ensuring that no data is written to your hard disk unless explicitly saved. Once the session is over, all traces of your activity are erased.
- 🌐 **User-Friendly:** Kodachi is designed for users of all levels. Whether you're an experienced Linux user or a beginner, you can enjoy the benefits of Kodachi with minimal setup.
- 🔑 **Cryptographic Tools:** Built-in tools for **file encryption**, **secure email communication**, and **instant messaging** help you maintain control over your data and communications.
- 🕵️‍♂️ **Anti-Forensic Features:** Includes measures to thwart forensic analysis, ensuring your activities remain private even if your system is physically compromised.
- 📊 **System Monitoring:** Real-time monitoring tools provide insights into your **network connections**, **system performance**, and **security status**.

<div align="center">

# 🛡️ Linux Kodachi 9

<img src="https://www.digi77.com/wp-content/uploads/2024/07/kodachi-green-128.png" alt="Kodachi Logo" width="200">

[![Version](https://img.shields.io/badge/Version-9.0--beta-brightgreen?style=for-the-badge)](https://github.com/WMAL/Linux-Kodachi)
[![Based on](https://img.shields.io/badge/Based%20on-Debian-red?style=for-the-badge&logo=debian)](https://www.debian.org)
[![Privacy](https://img.shields.io/badge/Privacy-Focused-blue?style=for-the-badge&logo=tor)](https://www.kodachi.cloud)
[![License](https://img.shields.io/badge/License-Proprietary-yellow?style=for-the-badge)](https://github.com/WMAL/Linux-Kodachi/blob/main/LICENSE)

**🚀 A New Era of Privacy-Focused Computing**

</div>

### 🚀 **Kodachi 9: A New Era is Coming!** 🚀

**Kodachi 9** is currently under development and will be based on **<span style="color:blue;">Debian</span>**. The project is approximately **<span style="color:green;">70% complete</span>** (as of August 12, 2025). Every script has been rewritten from scratch to enhance performance and functionality. This effort has taken time, but the result will significantly improve the Kodachi experience.

Stay tuned for more updates! 🚀 Check out the [behind-the-scenes progress](https://github.com/WMAL/Linux-Kodachi/tree/main/v9-behind-scenes-progress) for Kodachi 9.

---

# Kodachi Development Roadmap

This roadmap provides an overview of the current status of key components in the Kodachi project. All code and infrastructure have been written from scratch; however, I have integrated the working code from the old version to avoid reinventing the wheel and accelerate development.

| Component                                                    | Status            | Completion                                                                          |
| ------------------------------------------------------------ | ----------------- | ----------------------------------------------------------------------------------- |
| **Kodachi Workers VPS**                                      | ✅ Completed      | ![100%](https://img.shields.io/badge/Progress-100%25-brightgreen?style=flat-square) |
| **Kodachi Master VPS**                                       | ✅ Completed      | ![100%](https://img.shields.io/badge/Progress-100%25-brightgreen?style=flat-square) |
| **[Kodachi Anonymity Verifier](https://www.kodachi.cloud/)** | ✅ Completed      | ![100%](https://img.shields.io/badge/Progress-100%25-brightgreen?style=flat-square) |
| **Kodachi Client-Side Scripts**                              | ⚙️ In Development | ![80%](https://img.shields.io/badge/Progress-80%25-blue?style=flat-square)          |
| **Kodachi Dashboard GUI**                                    | ⚙️ In Development | ![65%](https://img.shields.io/badge/Progress-65%25-orange?style=flat-square)        |

---

## Component Progress Breakdown

| Feature / Utility        | Backend           | Frontend   | Notes                                                                                                                  |
| ------------------------ | ----------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Login Manager**        | ✅ Done           | ✅ Done    | Completed both authentication logic and UI integration.                                                                |
| **Internet Fix Utility** | ✅ Done           | ✅ Done    | Network diagnostics and recovery utilities implemented.                                                                |
| **Application Launcher** | ✅ Done           | ✅ Done    | Modular app launch system for privacy tools.                                                                           |
| **Security Tools**       | ✅ Done           | ✅ Done    | Includes firewall toggles and protection utilities.                                                                    |
| **IP Fetch Utility**     | ✅ Done           | ✅ Done    | Full location + ASN lookup integrated.                                                                                 |
| **MAC Address Utility**  | ✅ Done           | ✅ Done    | Automatic and manual MAC spoofing supported.                                                                           |
| **Hostname Changer**     | ✅ Done           | ✅ Done    | Persistent and session-based hostname updates handled.                                                                 |
| **Time Zone Utility**    | ✅ Done           | ✅ Done    | Geo-based adjustment; includes IP-based firewall re-evaluation.                                                        |
| **Command Guide**        | ✅ Done           | ✅ Done    | CLI helper with context-aware command suggestions.                                                                     |
| **Tor Manager**          | ✅ Done           | ✅ Done    | Backend development spanned ~6 weeks; frontend finalized in 2 weeks. Complete Tor lifecycle management now functional. |
| **System Information**   | ✅ Done           | ✅ Done    | Backend and frontend both completed with dynamic hardware and OS data parsing.                                         |
| **DNS Manager**          | ✅ Done           | ⏳ Pending | Backend fully implemented; GUI frontend under development (Task #5).                                                   |
| **Secure Connectivity**  | ⏳ Pending        | ⏳ Pending | Card System decryption and patching (Task #1, starts Aug 12).                                                         |
| **Project Connector**    | ⏳ Pending        | ⏳ Pending | Rust implementation (Task #2, starts Aug 17).                                                                         |
| **Blender System**       | ⏳ Pending        | ⏳ Pending | Rust backend (Task #3, starts Aug 19) and GUI frontend (Task #6, starts Aug 27).                                      |
| **Settings Manager**     | ✅ Done           | ⏳ Pending | Core settings logic ready; GUI still under development.                                                                |
| **CLI-Core Library**     | ✅ Done           | N/A        | Unified command-line interface foundation for all services.                                                            |
| **Dependencies Checker** | ✅ Done           | N/A        | Comprehensive system dependency verification and management.                                                           |
| **Auth-Shared Library**  | ✅ Done           | N/A        | Centralized authentication framework for all backend services.                                                         |
| **Rust-Updater**         | ✅ Done           | N/A        | Automated dependency updating and API compatibility management.                                                        |

### System-Wide Improvements

- **📋 Unified Help Menus**: All 10+ Rust services now feature consistent `--help` and `--examples` output formats
- **🔧 JSON-First Configuration**: Complete migration from YAML to JSON for all configuration and output files
- **⚙️ Standardized CLI Options**: Unified `-e`, `-n`, `-v`, `-h`, and `--json` flags across all backend services
- **🔗 Cross-Service Communication**: Seamless integration between all services using shared libraries and protocols
- **🎨 GUI Enhancements**: Modern interface updates with real-time status integration and improved error handling
- **🔐 Security Improvements**: Enhanced authentication, session management, and platform hardening measures
- **⚡ Performance Optimization**: Improved error handling, memory management, and cryptographic integrity verification

---

## Finalization & Release Status

| Stage                             | Status     | Timeline                    | Notes                                                                                  |
| --------------------------------- | ---------- | --------------------------- | -------------------------------------------------------------------------------------- |
| **Tor Manager IP Login GUI Fix**  | ⏳ Pending | Aug 21-23 (Task #4)         | Fix IP login functionality in Tor Manager GUI                                          |
| **Gambas Command Line & Debug**   | ⏳ Pending | Sep 1 (Task #7)             | Command line integration and debugging for Gambas applications                         |
| **Binary Testing Phase**          | ⏳ Pending | Sep 1-5 (Task #8)           | Test all compiled binaries across different environments                               |
| **Legacy Feature Verification**   | ⏳ Pending | Sep 5-8 (Task #9)           | Recheck and ensure all Kodachi 8.27 features are properly implemented                 |
| **Documentation Review**          | ⏳ Pending | Sep 8-10 (Task #10)         | Check and update reference documentation and general MD files                          |
| **Final Research Phase**          | ⏳ Pending | Sep 10-17 (Task #11)        | Testing edge-case behaviors, hardening, and fallback options                          |
| **ISO Build Process**             | ⏳ Pending | Sep 17-22 (Task #12)        | Final step before beta; creating the live bootable ISO                                |
| **Beta Release**                  | ⏳ Pending | September 22, 2025          | Public beta release with enhanced authentication and security features                 |

---

Each of the above components is now integrated or in final testing stages. Kodachi 9 will support both GUI-based control and CLI command-driven interaction.

## Development Approach

- **From Scratch with Legacy Integration:**  
  Every component has been re-engineered from the ground up to ensure modern, robust architecture. That said, the working code from the previous version was utilized where applicable to maintain proven functionality and save valuable development time.

## Next Steps (Following Timeline Tasks)

- **Immediate Priority (Aug 12-17):**  
  Complete Card System decryption and patching (Task #1) to enable secure connectivity features.

- **Backend Development (Aug 17-21):**  
  Implement Project Connector in Rust (Task #2) and Blender backend system (Task #3) for advanced traffic management.

- **GUI Enhancements (Aug 21-31):**  
  Fix Tor Manager IP login functionality (Task #4), complete DNS GUI (Task #5), and implement Blender GUI frontend (Task #6).

- **Testing & Validation (Sep 1-10):**  
  Debug Gambas command line integration (Task #7), test all binaries (Task #8), verify legacy features (Task #9), and review documentation (Task #10).

- **Final Phase (Sep 10-22):**  
  Conduct comprehensive research and testing (Task #11), build and sign the ISO (Task #12) for beta release on September 22, 2025.

## Updated Timeline (August 2025)

*Current Date: August 12, 2025*

|  #  | Task                             | Duration (Days) | Cumulative Days |    Estimated Completion Date     |
| :-: | :------------------------------- | :-------------: | :-------------: | :------------------------------: |
|  1  | Card System (Decryption & Patch) |        5        |        5        |     Saturday, August 17, 2025    |
|  2  | Project Connector in Rust        |        2        |        7        |     Monday, August 19, 2025      |
|  3  | Blender in Rust                  |        2        |        9        |    Wednesday, August 21, 2025    |
|  4  | Tor Manager IP Login GUI fix     |        2        |       11        |     Friday, August 23, 2025      |
|  5  | DNS GUI                          |        4        |       15        |     Tuesday, August 27, 2025     |
|  6  | Blender in GUI                   |        4        |       19        |    Saturday, August 31, 2025     |
|  7  | Gambas Command Line & Debug      |        1        |       20        |     Sunday, September 1, 2025    |
|  8  | Test all binaries                |        4        |       24        |    Thursday, September 5, 2025   |
|  9  | Recheck 8.27 features            |        3        |       27        |     Sunday, September 8, 2025    |
| 10  | Check Reference General MD       |        2        |       29        |    Tuesday, September 10, 2025   |
| 11  | Research                         |        7        |       36        |    Tuesday, September 17, 2025   |
| 12  | Build ISO                        |        5        |       41        | **Sunday, September 22, 2025**   |

---

The new final estimated completion date is **Sunday, September 22, 2025**.

Stay tuned for further updates.

---

## Why Choose Kodachi?

Kodachi was born out of a need to bridge the gap between **user-friendly operating systems** and the increasingly sophisticated world of **digital privacy threats**. With Kodachi, you can:

- 🕵️‍♀️ **Browse the web anonymously** through layers of encryption and the **Tor network**.
- 💾 **Leave no trace** on the hardware you're using, making it perfect for environments where **privacy is critical**.
- 🔒 **Use cutting-edge cryptographic tools** for secure communication and data storage.
- 🛡️ **Stay protected against malware** and network attacks with built-in **security features**.

Kodachi is more than just another Linux distribution—it's a **robust**, **lightweight operating system** that puts your **security and privacy first**.

---

## Achievements

Kodachi has been critically acclaimed by global publications and consistently recognized as one of the most secure Linux distributions available:

- 🏆 **1st Place** at **TechRadar** for Best Linux Distro for Privacy & Security for **four consecutive years** (2020–2025).

  - **[Original Article: TechRadar - Best Linux Distro for Privacy & Security](https://www.techradar.com/news/best-linux-distro-privacy-security)**
  - [TechRadar 2020](https://www.digi77.com/software/kodachi/TechRadar2020.pdf)
  - [TechRadar 2021](https://www.digi77.com/software/kodachi/TechRadar2021.pdf)
  - [TechRadar 2022](https://www.digi77.com/software/kodachi/TechRadar2022.pdf)
  - [TechRadar 2023](https://www.digi77.com/software/kodachi/TechRadar2023.pdf)
  - [TechRadar 2024](https://www.digi77.com/software/kodachi/TechRadar2024.pdf)
  - [TechRadar 2025](https://www.digi77.com/software/kodachi/TechRadar2025.pdf)

- 🥇 **1st Place** in **Linux Format UK Magazine's** Privacy Distribution Roundup (2020).
  - [Linux Format 2020](https://www.digi77.com/software/kodachi/Linux_Format_UK_Issue_267_September_2020.pdf)
- 🥇 **1st Place** in **DistroWatch** for privacy-focused distributions (2019).
  - [DistroWatch 2019](https://twitter.com/warith2020/status/1105179632935075840?s=20)
- 🏅 **The Lab Hot Product** in **August 2021** by Australian APC Magazine.
  - [APC Magazine 2021](https://www.digi77.com/software/kodachi/APC-Magazine--496-August-2021-Australia.pdf)

---

## Getting Started

You don't need to be a cybersecurity expert to use Kodachi. Simply follow these steps:

1. **[Download Kodachi](https://sourceforge.net/projects/linuxkodachi/files/latest/download)** from the official site.

### Option 1: Use with Virtual Machine

2. **VMware Workstation:**
   1. Open VMware Workstation and create a new virtual machine.
   2. Select "Installer disc image file (iso)" and browse to the Kodachi ISO file you downloaded.
   3. Follow the prompts to configure the virtual machine settings (e.g., memory, disk size).
   4. Finish the setup and start the virtual machine.
   5. Kodachi will boot in live mode, allowing you to start using it immediately.
3. **VirtualBox:**
   1. Open VirtualBox and create a new virtual machine.
   2. Select "Linux" as the type and "Debian (64-bit)" as the version.
   3. Follow the prompts to configure the virtual machine settings (e.g., memory, disk size).
   4. In the "Storage" settings, add the Kodachi ISO file as a virtual optical disk.
   5. Start the virtual machine and Kodachi will boot in live mode.

### Option 2: Create Bootable Media

4. **Create Bootable Media:** Use a USB stick or DVD to create bootable media. Tools like **Rufus** (for Windows) or **Etcher** (for Linux/Mac) can help.
5. **Boot Your System:** Restart your computer and boot from the USB/DVD. You may need to adjust your BIOS settings.
6. **Start Using Kodachi:** The operating system will load in live mode, allowing you to immediately start browsing and working securely.

---

## Tutorials and Resources

To learn how to use Kodachi, explore the following resources:

- **YouTube Tutorials:**
  - Search for **Linux Kodachi** on YouTube or visit [this link](https://www.youtube.com/results?search_query=linux+kodachi) for a collection of video tutorials.
- **Official Documentation:** Visit the [Kodachi Documentation](https://www.digi77.com/linux-kodachi/) for detailed guides.
- **Community Support:** Join the **[Kodachi support](https://discord.gg/KEFErEx)** to ask questions and share insights.

---

## Support and Donations

Linux Kodachi is free, but maintaining a project of this magnitude takes time and resources. If you find Kodachi valuable and want to support its future development, consider making a donation.

**Donation Options:**

- **<a href="https://nowpayments.io/donation/linuxkodachi" target="_blank" rel="noopener noreferrer">Donate with Cryptocurrency</a>**
- **<a href="https://www.paypal.com/ncp/payment/TJZSGR6452HS4" target="_blank" rel="noopener noreferrer">Donate with PayPal direct</a>**
- **<a href="https://donorbox.org/kodachi" target="_blank" rel="noopener noreferrer">Donate with PayPal via Donorbox</a>**

Your donations will be used to fund future development, improve user support, and ensure Kodachi remains the **most secure operating system available**.

---

## Conclusion

Linux Kodachi is more than just a privacy tool—it's a **comprehensive solution** for those who need **advanced security and anonymity**. Whether you're a **journalist**, **activist**, or an **everyday user** who values privacy, Kodachi is tailored to protect you in the most hostile digital environments.

**Download it today and experience privacy without compromise!**

---

## ⚠️ Disclaimer

By using Kodachi, you acknowledge and agree that its primary purpose is to protect your privacy and ensure secure online activities. Kodachi should **not** be used for any illegal activities or to commit crimes. If your intention is to engage in unlawful actions or violate any applicable laws, you are advised to discontinue usage immediately. **Kodachi and its developers disclaim all liability for any violations of applicable laws committed by individuals using this software**. It is **your responsibility** to ensure compliance with the laws of your country or jurisdiction when using Kodachi or any other software or tool.

---

## Developed By

**Warith Al Maawali**

- **Website:** [Digi77](https://www.digi77.com)
- **GitHub:** [WMAL](https://github.com/WMAL)
- **Twitter:** [@warith2020](https://twitter.com/warith2020)
- **LinkedIn:** [Warith Al Maawali](https://www.linkedin.com/in/warith-al-maawali/)

Follow Kodachi on social media to stay updated on the latest developments.

---

# Linux Kodachi OS/Software/Code License Agreement

This is a legal agreement between you and Warith AL Maawali regarding the use of Linux Kodachi (the "OS/Software/Code").

- **Private Use**: Linux Kodachi is freeware for private, non-commercial use only.
- **Commercial Use**: Government, companies, and organizations require a user/device license. Contact for pricing.
- **License**: A purchased license grants a perpetual, worldwide, non-exclusive license for internal business use.
- **Prohibited**: You may not distribute, modify, decompile, or reverse-engineer the software.
- **Warranty**: Linux Kodachi is provided "as is" without any warranty. Use at your own risk.

For the full version, visit: [Full License](https://github.com/WMAL/Linux-Kodachi/blob/main/Kodachi%208.27%20source/LICENSE)

## Warrant Canary

As of August 8, 2025:

- No National Security Letters, gag orders, or warrants received.
- Kodachi remains uncompromised and secure.
- For more details, visit the [official Warrant Canary page](https://www.kodachi.cloud/warrant.html).

---

## Acknowledgements

Special thanks to all the contributors and the open-source community for their invaluable support and contributions to the project.

---

## Contact & Support

For any queries or support, please contact:

- **Kodachi Website:** [Kodachi page](https://www.digi77.com/linux-kodachi/)
- **Kodachi Anonymity Verifier:** [https://www.kodachi.cloud](https://www.kodachi.cloud)
- **Discord Support:** [Kodachi support](https://discord.gg/KEFErEx)
- **Contact:** [Contact page](https://www.digi77.com/contact/)

---

© 2025 by Warith AL Maawali, Sultanate of Oman, Muscat. All rights reserved.

[⬆ Back to Overview](#overview)
