# arm64 iOS Simulator build

`bin/MailCore2.xcframework.zip` is the 2020 framework from `bin/MailCore2-2020-09-24.xcframework.zip` with an arm64 iOS Simulator slice added. The device and macOS frameworks are unchanged.

To rebuild it on an Apple silicon Mac:

```bash
bash Rebuild/build.sh
```

It builds ctemplate, tidy, Cyrus SASL, libetpan and MailCore for the arm64 simulator (iOS 15+) with the fixes in `patches/`, and writes `Rebuild/output/MailCore2.xcframework.zip`. License notices for the bundled libraries are in `Notices/`.
