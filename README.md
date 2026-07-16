# Mac Usage Meter

Mac Usage Meter is a macOS menu bar app for monitoring power consumption and network usage on your Mac.

## Features

- Records Mac-wide power usage in watts and kWh through `powermetrics`
- Tracks Wi-Fi traffic and provides daily and monthly summaries
- Shows traffic grouped by application and destination host
- Visualizes destination traffic with pie and bar charts
- Exports raw samples and daily rollups as CSV

Traffic is collected from macOS connection statistics. The app does not decrypt HTTPS traffic or store page contents; destination host names may therefore be CDN hosts. Per-destination power is an estimate that allocates the Mac-wide measured power by network activity.

## Requirements

- macOS 13 or later
- Swift 5.9 or later

Power measurement requires the included privileged helper and administrator permission. Network monitoring remains available without it.

## Development

```sh
swift test
swift build
```

## License

This project is available under the [MIT License](LICENSE).
