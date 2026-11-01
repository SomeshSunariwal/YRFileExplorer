# Static APK tracker inspection

APK: `ES File Explorer.apk`

SHA-256: `d00d35bc2bd07e9d6c8cb402b6c139b59798cea11dee80987aaa49575af60a62`

This is a static inventory of defined DEX classes. It establishes bundled code presence, not execution, initialization, data transmission, or a complete runtime privacy assessment. Obfuscated or downloaded code can escape signature matching. The original APK was not executed.

| Component found | Defined classes | Example evidence |
|---|---:|---|
| Google Advertising ID client | 6 | `Lcom/google/android/gms/ads/identifier/AdvertisingIdClient$Info;` |
| AppsFlyer | 201 | `Lcom/appsflyer/AFDateFormat;` |
| Umeng analytics / common SDK | 443 | `Lcom/umeng/analytics/AnalyticsConfig;` |
| Baidu advertising / analytics | 224 | `Lcom/baidu/mobads/proxy/BuildConfig;` |
| Tencent Bugly | 127 | `Lcom/tencent/bugly/Bugly;` |
| Tencent GDT ads | 226 | `Lcom/qq/e/ads/ADActivity;` |
| ByteDance / Pangle ads | 1730 | `Lcom/bytedance/sdk/openadsdk/AdSlot$1;` |
| ByteDance embedded AppLog analytics | 132 | `Lcom/bytedance/embedapplog/AppLog;` |
| ByteDance Tea crash reporting | 94 | `Lcom/bytedance/tea/crash/a/a$a;` |
| Win OpenSDK advertising | 196 | `Lcom/win/opensdk/A0;` |
| DU Apps advertising statistics | 6 | `Lcom/duapps/ad/stats/CallbackAReceiver;` |
| ES first-party statistics / diagnostics | 8 | `Lcom/estrongs/android/statistics/TraceRoute$a;` |
| Stripe payment analytics classes | 13 | `Lcom/stripe/android/AnalyticsDataFactory$Companion;` |
| Kwai / Kuaishou ads | 3812 | `Lcom/kwad/sdk/KsAdSDKImpl$1;` |
| Alibaba UTDID device identification | 28 | `Lcom/ta/utdid2/a/a/a;` |

The Google Advertising ID client alone is not proof of a complete AdMob SDK. UTDID is an identifier library. ES statistics/diagnostics and Stripe payment analytics are listed separately by their explicit class evidence; their presence alone does not establish advertising tracking. Payment and cloud-storage libraries are not otherwise automatically classified as trackers.

See `tracker_evidence.json` for examples and URL origins and `defined_classes.txt` for the full defined-class list.
