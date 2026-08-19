# KOReader Custom Patches 📚
Custom Lua patches for **KOReader** optimized for E-ink devices.

# 📖 Page Browser 
This patch allows you to quickly flip back and forth through the book, with the option to easily return to your original page using the 'x' button or stay on the new page. You can also use the interactive progress bar and bookmark browser. Streamlined, E-ink optimized, based on KOReader's browser architecture and inspired by the native Kindle page picker experience. Compatible with EPUB, CBZ, and PDFs!
   
**Get patch: [**2-page-browser.lua**](./2-page-browser.lua)**

**Features**:
* **3-Page Thumbnail Grid:** Displays a live preview of the previous, current, and next pages side by side, keeping the active page perfectly centered. Features a controlled hold-to-repeat page turning.
* **Quick Access Toolbar:** Top navigation bar with direct buttons for Home, Settings, Bookmarks, Table of Contents. 
* **Progress & Info Bar:** Includes an interactive slider, chapter title, and a precise percentage/page counter. You can algo go to the next/previous chapter with the buttons next to the chapter title.
* **Physical Button Support**: Compatible with devices with physical buttons (D-Pad).
* **Split-View Bookmarks Menu**: Split-screen bookmark, highlight and note manager. Features a dynamic, scrollable bookmark list on the right, a fully interactive high-res page preview on the left, and safely pins the origin page in a rounded bottom container.

> **🌟 NEW: UI Scaling**: Just long-press the Settings (Gear) icon to bring up the slider to resize the menu (e.g., `0.8` makes it 20% smaller).
> You MUST disabled any old or duplicate `.lua` scrubber/browser files from your KOReader folder before installing this. 
 
## 📱 Screenshots: 
| Main Grid View | Split Screen View |
| :---: | :---: |
| <img src="Screenshot_2026-08-19-01-37-32-181_org.koreader.launcher.jpg" width="100%" alt="Main Grid View"/> | <img src="Screenshot_2026-08-19-01-11-42-402_org.koreader.launcher.jpg" width="100%" alt="Split Screen View"/> |
| **Smart Tabs & Filters** | **3 Assignable Gesture Actions** |
| <img src="Screenshot_2026-08-19-01-12-22-868_org.koreader.launcher.jpg" width="100%" alt="Smart Tabs & Filters"/> | <img src="Screenshot_2026-08-19-01-38-32-855_org.koreader.launcher.jpg" width="100%" alt="3 Assignable Gesture Actions"/> |


# 📄 Old Page Scrubbers (Unmaintained)
* [**2-page-scrubber.lua**](./2-page-scrubber.lua): Centered floating window with rounded corners, and quick-access buttons.
 * [**2-page-scrubber-alt.lua**](./2-page-scrubber-alt.lua): Bottom bar with progress, chapter info, and a top navigation toolbar. It's the simplest and more subtle page scrubber of the bunch. 

## ⚙️ Installation
 1. Download the .lua file.
 2. Place it in your KOReader user plugins/patches folder.
 3. Restart KOReader.
   
    
  **Setup & Activation**
 1. Open a book in KOReader.
 2. Go to **Settings** (⚙️) > **Gestures** > **Reader**.
 3. Choose your preferred gesture and bind it to any of the 3 available actions: **Page Scrubber** (Default Grid), **Page Scrubber (Menú / Dividido)** (Direct Split View), or **Page Scrubber (Highlights)** (Direct Highlights View).

> You can only lunch one patch of this collection at a time, if you try to activate more than one it won't work.
