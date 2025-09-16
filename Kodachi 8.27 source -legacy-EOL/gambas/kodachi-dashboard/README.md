# Kodachi Dashboard (Historical - v8.27)

Main graphical user interface for Kodachi OS version 8.27, providing comprehensive system control and monitoring capabilities through a Gambas 3 application.

## Purpose

The Kodachi Dashboard serves as the central control hub for Kodachi OS 8.27, enabling users to manage VPN connections, Tor routing, DNS settings, IP monitoring, and system security through an intuitive graphical interface.

## Main Features

- **VPN Profile Management**: Selection and management of VPN configurations from multiple providers
- **Tor Network Control**: Configuration and management of Tor routing and exit nodes
- **DNS Server Switching**: Dynamic DNS server selection and leak prevention
- **IP Address Monitoring**: Real-time IP address tracking and geolocation display
- **System Health Monitoring**: Comprehensive system status and security monitoring
- **Log File Management**: Centralized log viewing and analysis
- **Sound Notifications**: Audio alerts for network and security events
- **Multi-language Support**: Internationalization with translation support

## Architecture

```
kodachi-dashboard/
├── .project                    # Gambas project configuration
├── .startup                    # Application startup configuration
├── .version                    # Version information
├── .settings                   # Application settings
├── .src/                      # Source code directory
│   ├── FMain.class            # Main form and application controller
│   ├── FMain.form             # Main form UI definition
│   ├── engineX.class          # System engine and backend operations
│   ├── ipengine.class         # IP address and geolocation management
│   ├── globalVars.module      # Global variables and configuration
│   ├── Status.class           # System status monitoring
│   ├── Status.form            # Status display UI
│   ├── logs.class             # Log file management
│   ├── logs.form              # Log viewer UI
│   ├── password.class         # Authentication management
│   ├── password.form          # Password input UI
│   ├── termForm.class         # Terminal interface
│   ├── termForm.form          # Terminal UI
│   ├── md5filecheck.class     # File integrity verification
│   └── pcinfo.module          # System information module
├── .gambas/                   # Compiled Gambas bytecode
├── .lang/                     # Translation files and language support
├── images/                    # Application icons and graphics
└── .hidden/                   # Development reference materials
```

## Key Components

### **FMain.class** - Main Application Controller

**Core Functionality:**
- **Application Initialization**: Sets up engines, UI components, and system monitoring
- **Instance Management**: Prevents multiple dashboard instances
- **Event Coordination**: Manages user interactions and system responses
- **State Management**: Tracks VPN profiles, Tor settings, DNS configurations

**Key Variables:**
- `myEngine`: Instance of EngineX for system operations
- `ipEnginex`: Instance of Ipengine for IP-related operations  
- `VPNprofile`: Currently selected VPN configuration
- `TorProfile`: Active Tor routing configuration
- `dnsEntry`: Selected DNS server configuration
- `currentnetIP`: Current network IP address for monitoring

**Features:**
- Live OS detection and feature limiting
- Automatic UI centering and sizing (1170x790 pixels)
- JSON configuration management
- Sound notification controls
- Real-time IP monitoring toggles

### **EngineX.class** - System Engine

**Purpose**: Backend system operations and script execution interface.

**Responsibilities:**
- Execute system scripts and commands
- Manage VPN connections and profiles
- Control Tor network routing
- Handle DNS server switching
- Monitor system processes and services

### **IPEngine.class** - IP and Geolocation Management

**Purpose**: Handles IP address detection, monitoring, and geolocation services.

**Capabilities:**
- Real-time IP address fetching from multiple providers
- Geolocation data retrieval and processing
- IP change detection and notification
- Provider failover and redundancy
- JSON data processing for location information

### **GlobalVars.module** - Global Configuration

**Purpose**: Centralized configuration management and system variables.

**Functions:**
- `getGlobalVars()`: Loads system configuration
- OS type detection (live/installed)
- Path management for user directories
- System-wide setting coordination

### **Status.class** - System Status Monitoring

**Purpose**: Real-time system status display and monitoring.

**Features:**
- Network connectivity status
- VPN connection monitoring
- Tor routing verification
- DNS leak detection status
- System health indicators

### **Logs.class** - Log Management System

**Purpose**: Centralized log file viewing and management.

**Capabilities:**
- Multi-log file support
- Real-time log monitoring
- Log filtering and search
- Export and archive functionality

### **Security Components**

#### **Password.class** - Authentication Management
- User authentication for sensitive operations
- Password verification and validation
- Security prompt handling

#### **MD5FileCheck.class** - File Integrity Verification
- File hash calculation and verification
- System integrity monitoring
- Tamper detection capabilities

## User Interface Design

### **Main Window Layout**
- **Dimensions**: 1170x790 pixels, centered on screen
- **Component Organization**: Tabbed interface with logical grouping
- **Status Indicators**: Visual feedback for system states
- **Control Panels**: Organized sections for different system aspects

### **Key UI Features**
- **VPN Selection**: Dropdown menus for provider and server selection
- **Tor Controls**: Toggle switches and configuration options
- **DNS Management**: Server selection and leak testing controls
- **IP Display**: Real-time IP address and location information
- **Status Monitoring**: Health indicators and connection status
- **Sound Controls**: Audio notification preferences

## Integration with Kodachi System

### **Script Integration**
The dashboard integrates with Kodachi system scripts through:
- **Direct Execution**: Shell commands to system scripts
- **JSON Communication**: Configuration exchange via JSON files
- **File Monitoring**: Watching configuration and status files
- **Process Management**: Starting and stopping system services

### **Configuration Management**
- **Global Config**: Integration with `Globalconfig` system script
- **JSON Storage**: User preferences in `kodachi.json` and `kodachiweb.json`
- **Backup System**: Automatic configuration backups
- **Profile Management**: VPN and system profile storage

### **System Monitoring**
- **Real-time Updates**: Continuous monitoring of system status
- **Event Notifications**: Sound and visual alerts for state changes
- **Health Checking**: Integration with system health monitoring
- **Log Aggregation**: Centralized log collection and display

## Dependencies

### **Gambas 3 Components**
- **gb.image**: Image processing and display
- **gb.gui**: GUI framework and controls
- **gb.form**: Form management and dialogs
- **gb.dbus**: D-Bus system integration
- **gb.desktop**: Desktop environment integration
- **gb.form.dialog**: Dialog boxes and user prompts
- **gb.settings**: Configuration management
- **gb.term**: Terminal integration
- **gb.form.terminal**: Terminal widget support
- **gb.gui.trayicon**: System tray integration
- **gb.sdl2.audio**: Audio notification support
- **gb.util.web**: Web utilities for IP services
- **gb.web**: Web service integration

### **System Dependencies**
- **Kodachi Scripts**: Core system scripts in `~/.kbase/`
- **Network Tools**: VPN clients, Tor, DNS utilities
- **Configuration Files**: JSON configuration storage
- **Audio System**: Sound notification support

## Usage Instructions

### **Application Launch**
```bash
# From desktop
./Kodachi_Dashboard.desktop

# Direct execution
cd gambas/kodachi-dashboard
gbx3
```

### **Primary Operations**

#### **VPN Management**
1. Select VPN provider from dropdown
2. Choose server location
3. Click connect/disconnect controls
4. Monitor connection status

#### **Tor Configuration**
1. Enable/disable Tor routing
2. Select exit node preferences
3. Configure Tor-over-VPN settings
4. Monitor Tor circuit status

#### **DNS Management**
1. Select DNS server provider
2. Configure leak protection
3. Test for DNS leaks
4. Monitor DNS performance

#### **IP Monitoring**
1. Enable automatic IP checking
2. Set monitoring intervals
3. Configure change notifications
4. View geolocation information

## Historical Context

### **Version Information**
- **Application Version**: 0.0.220
- **Kodachi OS Version**: 8.27
- **Development Era**: 2021-2022
- **Architecture**: Gambas 3 GUI application

### **Evolution to Modern Kodachi**
This dashboard represents the foundation that evolved into the current Kodachi 9.0.1 architecture:

**Preserved Concepts:**
- Centralized system control
- Multi-provider VPN support
- Tor integration and routing
- DNS leak prevention
- Real-time monitoring
- User-friendly GUI interface

**Architectural Evolution:**
- **Script Backend**: Evolved into Rust service architecture
- **JSON Configuration**: Enhanced with structured configuration management
- **Monitoring System**: Improved with dedicated health services
- **Security Features**: Enhanced with cryptographic signing and verification

## Development Features

### **Internationalization**
- **Translation Support**: `.pot` files for multiple languages
- **Language Framework**: Gambas native translation system
- **User Locale**: Automatic locale detection and application

### **Development Tools**
- **Profiling**: Performance profiling with `.prof` files
- **Documentation**: Automatic documentation generation
- **Version Control**: Git integration with `.gitignore`
- **Build System**: Gambas native compilation

### **Testing and Debugging**
- **Debug Integration**: Built-in debugging support
- **Error Handling**: Comprehensive error management
- **Logging**: Detailed application logging
- **State Monitoring**: Real-time state tracking

## Security Considerations

### **Authentication**
- Password protection for sensitive operations
- User session management
- Privilege escalation controls

### **Data Protection**
- Configuration file security
- Sensitive data obfuscation
- Secure temporary file handling

### **System Integration**
- Safe script execution
- Process isolation
- Resource management

## Legacy Value

### **Historical Significance**
This dashboard represents a critical milestone in Kodachi development:
- **User Interface Evolution**: Foundation for modern GUI design
- **Feature Development**: Proof of concept for core privacy features
- **Integration Patterns**: Established patterns for system integration
- **User Experience**: Defined user interaction patterns

### **Reference Value**
- **Feature Mapping**: Understanding feature evolution to current system
- **Architecture Study**: Analysis of GUI-to-system integration patterns
- **Configuration Management**: Study of configuration evolution
- **User Interface Design**: Reference for GUI design decisions

## License and Attribution

**Author**: Warith Al Maawali  
**Copyright**: © 2021 Eagle Eye Digital Solutions  
**License**: See `/home/kodachi/LICENSE` for complete terms

### **Contact Information**
- **Website**: https://digi77.com  
- **GitHub**: https://github.com/WMAL
- **Discord**: https://discord.gg/KEFErEx
- **LinkedIn**: https://www.linkedin.com/in/warith1977
- **X (Twitter)**: https://x.com/warith2020

---

*This documentation is based on analysis of the actual Gambas 3 source code and project files from Kodachi OS version 8.27, preserved for historical reference and development study.*