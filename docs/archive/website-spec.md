# Boojy Website Spec

## Overview

Minimal landing page for beta launch. Target: beginners who've used GarageBand or want to make their first beat.

**Domain:** boojy.org
**Hosting:** Netlify
**Target launch:** January 20, 2025

---

## Single Page Structure

### Hero

- **Headline:** Boojy Audio
- **Tagline:** Creativity Without Limits
- **Subheadline:** A free, simple music studio for beginners. Available for macOS and Windows.
- **CTA:** Download button (detect OS, show relevant one first)
- **Visual:** 1 screenshot of the main interface

### Features (keep brief)

| Feature          | One-liner                                        |
| ---------------- | ------------------------------------------------ |
| Cross Platform   | macOS and Windows. iPad and Linux coming later.  |
| Plugin Support   | Use VST3 and AU instruments and effects.         |
| Beginner Friendly| Clean interface. No overwhelming menus.          |
| Completely Free  | No subscriptions, no paywalls. Free forever.     |

### Download

```text
[Download for macOS]  [Download for Windows]

v0.1-beta | January 20, 2025
```

**Hosting:** GitHub Releases

### Email Signup

- **Headline:** Stay Updated
- **Description:** Get notified about new releases and features.
- **Form:** Email address field + submit button
- **Service:** Buttondown (free up to 100 subscribers) or Netlify Forms
- **Privacy note:** No spam. Unsubscribe anytime.

### Bug Report

- **Headline:** Found a Bug?
- **Description:** Help improve Boojy by reporting issues.
- **Form fields:**
  - Email (required)
  - Operating System: dropdown (macOS / Windows)
  - Version: dropdown (v0.1-beta, etc.)
  - What happened? (required)
  - Steps to reproduce (optional)
- **Service:** Netlify Forms or Tally (both free)

### Contact

- **Email:** `tyr@boojy.org`
- **GitHub:** Link to repo

---

## Footer

- GitHub link
- "Made by Tyr"
- Copyright 2025

---

## Not included (add post-launch if needed)

- Blog page
- FAQ page (add based on real user questions)
- Tutorials/docs (once you know where users get stuck)

---

## Technical

### OS Detection
Show primary download button based on detected OS:
- macOS user sees: `[Download for macOS]` prominent, Windows link smaller below
- Windows user sees: `[Download for Windows]` prominent, macOS link smaller below

### System Requirements (add to download section or tooltip)
**macOS:** 10.15+ (Catalina or later), Intel or Apple Silicon
**Windows:** Windows 10+, 64-bit

### Meta tags
- Title: "Boojy Audio - Free DAW for Beginners"
- Description: "A free, simple music studio for macOS and Windows. Perfect for making your first beat."
- Open Graph image: Screenshot of the app

---

## Content needed before launch

- [ ] 1 good screenshot of the main interface
- [ ] Final download links (GitHub Releases URLs)
- [ ] `tyr@boojy.org` email set up
- [ ] Email signup form connected (Buttondown or Netlify Forms)
- [ ] Bug report form set up (Netlify Forms or Tally)

---

## Future additions (post-launch)

- "Copy debug info" feature in app for easier bug reports
- In-app tutorial / first-run experience
