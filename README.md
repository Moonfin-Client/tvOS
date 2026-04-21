<h1 align="center">Moonfin tvOS</h1>
<h3 align="center">Enhanced Jellyfin & Emby client for Apple TV</h3>

---
<p align="center">
  <img width="1920" height="1080" alt="moonfin_1920x1080" src="https://github.com/user-attachments/assets/b1d9c7d8-f113-457d-ab5c-1600bbd0600a" />
</p>

[![License](https://img.shields.io/github/license/Moonfin-Client/tvOS.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Moonfin-Client/tvOS)](https://github.com/Moonfin-Client/tvOS/releases)
[![Downloads](https://img.shields.io/github/downloads/Moonfin-Client/tvOS/total?label=Downloads)](https://github.com/Moonfin-Client/tvOS/releases)

<a href="https://www.buymeacoffee.com/moonfin" target="_blank"><img src="https://github.com/user-attachments/assets/fe26eaec-147f-496f-8e95-4ebe19f57131" alt="Buy Me A Coffee" ></a>

> **[← Back to main Moonfin project](https://github.com/Moonfin-Client)**

Moonfin tvOS is a native SwiftUI Apple TV client for Jellyfin and Emby users who want a modern, customizable 10-foot experience with smooth playback and controller-first navigation.

## Supported Servers

| Server | Minimum Version | Status |
|--------|------------------|--------|
| Jellyfin | 10.8.0+ | Full support |
| Emby | 4.8.0.0+ | Full support |

## Platform Support

| Platform | Minimum Version | Status |
|----------|------------------|--------|
| **tvOS (Apple TV)** | 16.0 | Full support |

## Features & Enhancements

### Native tvOS Experience
- Built for Apple TV with Siri Remote and controller-friendly focus navigation
- SwiftUI-based UI tuned for a living-room viewing distance
- Integrated Top Shelf extension support for at-a-glance content on the Apple TV home screen

### Playback Engine - MPV-first Pipeline
Moonfin tvOS uses an MPV-first playback stack, with automatic internal handling for dynamic range and platform decode paths when needed. This keeps behavior consistent while supporting advanced streams and robust fallback behavior.

| Category | Supported Formats |
|----------|-------------------|
| **Video** | H.264, HEVC (H.265), VP8, VP9, AV1, MPEG-2, MPEG-4, VC-1 |
| **Audio** | AAC, MP3, FLAC, Opus, Vorbis, AC3, EAC3, DTS, TrueHD, PCM, ALAC |
| **Containers** | MP4, MKV, WebM, AVI, MOV, TS / M2TS, WMV / ASF |
| **Subtitles** | SRT, ASS / SSA, VTT / WebVTT, TTML, PGS, DVB, VobSub |
| **HDR** | Dolby Vision, HDR10+, HDR10, HLG |
| **HW Accel** | VideoToolbox on Apple TV hardware |

### Featured Media Bar
- Rotating featured hero content on the home screen with backdrop presentation
- Quick-glance metadata including ratings, genres, runtime, and overview
- Designed to highlight trending and library content without leaving home flow

### Ratings Integration (MDBList + TMDB)
- Optional MDBList ratings support with multiple rating sources shown in item details
- TMDB episode ratings support where available
- Rating display can be customized through settings

### Trickplay and Media Segment Controls
- Trickplay preview support for improved scrubbing and seek navigation
- Media segment handling for intros, credits, and detected segments
- Playback controls remain consistent across playback scenarios

### In-App Trailer Previews
- Trailer playback directly from item detail contexts
- Resilient trailer source resolution for better reliability
- Preview content without leaving the Moonfin experience

### Advanced Playback Controls
- Fine-grained subtitle and audio delay adjustment during playback
- Pre-playback track selection and in-session track controls
- Includes still-watching flow support and next-up handling

### Home Row Customization
- Reorder and toggle home sections (for example, Continue Watching, Next Up, Latest)
- Home row preferences are compatible with plugin-backed sync workflows
- Tailor discovery layout to personal viewing habits

### Live TV & DVR
- Built-in Live TV browsing and playback screens
- EPG-style schedule views
- DVR recordings and schedule management integrated in-app

### SyncPlay
- Group watch support with synchronized playback across participants
- SyncPlay entry points in app navigation and settings-driven controls
- Shared viewing sessions with local playback controls preserved

---

# User Guide

## Apple TV Remote Controls

### App-Wide Controls
- **Swipe / D-pad** - Move focus between items
- **Select / Click** - Activate focused item
- **Menu / Back** - Navigate back
- **Play/Pause** - Toggle playback where applicable

### Player Controls
- **Left / Right** - Seek backward or forward
- **Up / Down** - Open player controls and navigate actions
- **Play/Pause** - Pause or resume playback
- **Menu / Back** - Exit fullscreen overlays or return from player

## Subtitle Downloads

Download subtitles directly from item details.

1. Open any Movie or Episode details screen.
2. In the details area, locate the Subtitles section.
3. Select the download icon next to available subtitles.
4. Subtitles are saved with your media organization structure.
5. Downloaded subtitles are available for future playback sessions.

---

# Screenshots
<img width="3840" height="2160" alt="1" src="https://github.com/user-attachments/assets/c85bcedf-58d5-4004-b7a6-7565c6dc7249" />
<img width="3840" height="2160" alt="2" src="https://github.com/user-attachments/assets/2b1c30bf-8d08-409c-8dcb-6386a5eaf62c" />
<img width="3840" height="2160" alt="3" src="https://github.com/user-attachments/assets/034a612d-d633-496c-b8f4-da8b1765e7d1" />
<img width="3840" height="2160" alt="4" src="https://github.com/user-attachments/assets/3c4f2b75-ea62-46df-8e61-4417e5bbce28" />
<img width="3840" height="2160" alt="5" src="https://github.com/user-attachments/assets/85fc924b-3682-4cc4-a4a8-c640863c3786" />
<img width="3840" height="2160" alt="6" src="https://github.com/user-attachments/assets/9c706c2f-b51e-4728-b062-7abf0c2ce692" />
<img width="3840" height="2160" alt="7" src="https://github.com/user-attachments/assets/5ce64e94-fc9d-484b-ba46-1b16c0958093" />
<img width="3840" height="2160" alt="8" src="https://github.com/user-attachments/assets/b8710605-b436-4e77-9ebe-2f2ad0f44e99" />

---
## Installation

### Apple App Store
Stay up to date with the latest releases [here](https://apps.apple.com/app/moonfin/id6761283970)

### Pre-built Releases
Download tvOS artifacts from the [Releases page](https://github.com/Moonfin-Client/tvOS/releases).

### tvOS Artifacts
- Signed IPA output: `Moonfin_tvOS_<version>_signed.ipa`
- Unsigned IPA output: `Moonfin_tvOS_<version>.ipa`

## Building from Source

### Required Toolchain Versions
- Xcode 15+
- tvOS SDK 16.0+
- CocoaPods

### Prerequisites
- [Xcode](https://developer.apple.com/xcode/)
- [CocoaPods](https://cocoapods.org/)
- [Git](https://git-scm.com/)

### Quick Start

```bash
git clone https://github.com/Moonfin-Client/tvOS.git
cd tvOS
pod install
cp build-tvos.private.env.example build-tvos.private.env
# edit TEAM_ID in build-tvos.private.env
./build-tvos.sh
```

### Build Notes
- The build script archives and exports a signed IPA, then generates an unsigned IPA copy for sideload workflows.
- MODE supports `app-store` and `sideload`.
- Set ALLOW_PROVISIONING_UPDATES=1 if you need Xcode to refresh profiles during CI/local builds.

## Development

### Developer Notes
- Keep project settings in sync with project.yml
- Validate navigation and playback behavior on real Apple TV hardware when possible
- Prefer small, focused commits for easier review

## Contributing

We welcome contributions to Moonfin tvOS.

### Guidelines
1. Check existing issues before opening new ones.
2. Discuss major feature changes before implementation.
3. Follow existing code style and project conventions.
4. Test changes on tvOS simulator and, ideally, physical hardware.
5. Keep PR scope focused and clearly documented.

### Pull Request Process
1. Fork the repository.
2. Create a branch (`git checkout -b feature/your-change`).
3. Implement and test your changes.
4. Open a PR with context, screenshots/logs when useful, and test notes.

## Support & Community

- **Issues**: [GitHub Issues](https://github.com/Moonfin-Client/tvOS/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Moonfin-Client/tvOS/discussions)

## Credits

Moonfin tvOS is built on the work of:
- **[Jellyfin Project](https://jellyfin.org)**
- **Jellyfin client contributors**
- **Moonfin contributors**
- **[MakD](https://github.com/MakD)** - Original Jellyfin-Media-Bar concept that inspired the featured media bar

## License

This project is licensed under GPL v2. See [LICENSE](LICENSE) for details.

---

<p align="center">
  <strong>Moonfin tvOS</strong> is an independent project and is not affiliated with the Jellyfin project.<br>
  <a href="https://github.com/Moonfin-Client">← Back to main Moonfin project</a>
</p>
