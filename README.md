# Inline 🎵

> A sleek, floating overlay of time-synced lyrics on your phone powered by [LRCLIB](https://lrclib.net).
> Inspired by the desktop lyrics system on Quickshell Linux bars.

---

## ⚡ How it Works

```
   Media Player (Spotify, YT Music, etc.)
                   │
                   ▼  Android Notification Listener
            Inline Sync Manager
                   │
                   ├─► Cleans track title (strips `(feat. ...)`, `[Remastered]`, etc.)
                   ├─► Queries LRCLIB API with 3-tier fallback strategy
                   ├─► Parses timestamps (`[mm:ss.xx]`) & `[offset: +/-ms]` tags
                   │
                   ▼
     Position Timer (Extrapolates playback every 250ms)
                   │
                   ▼  Matches current timestamp to active lyric line
          System Overlay Window
     ├── Dynamic Island Pill (glassmorphism floating capsule)
     ├── Ticker Bar (ultra-slim minimalist bar)
     ├── Neon Glow (cyberpunk high-contrast style)
     └── Monochrome (e-ink clean style)
```

## 🛠 Features

1. **Title Cleaning & Normalization**: Strips noise like `(feat. ...)`, `[Remaster]`, `Official Audio`, `Deluxe Version`, and trailing tags using regex to maximize LRCLIB lookup hit rates.
2. **LRCLIB 3-Tier Query Engine**:
   - **Step 1**: Exact duration match (`/api/get?track_name=...&artist_name=...&duration=...`)
   - **Step 2**: Search match with duration proximity sorting (`/api/search?track_name=...&artist_name=...`)
   - **Step 3**: Fuzzy search fallback (`/api/search?q=...`)
3. **250ms Extrapolation Timer**: Smoothly interpolates playback position between notification events so lyrics stay in lockstep with the audio.
4. **Floating System Overlay**: Displays synced lyrics on top of any app (Instagram, browser, games, lockscreen/homescreen) with smooth crossfading and slide animations.
5. **Interactive In-App Reel**: Includes a live lyric reel in the main app with real-time autoscroll, playback scrubber, and built-in test tracks for instant simulation.
