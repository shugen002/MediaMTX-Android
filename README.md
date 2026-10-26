# MTX 控制台

Flutter Android 客户端，完整说明见仓库根目录 [`../README.md`](../README.md)。

```bash
flutter pub get
flutter test
flutter build apk --release
```

## GitHub Actions

仓库内的工作流位于 [`.github/workflows/android.yml`](.github/workflows/android.yml)：

- push / PR / 手动触发：构建 APK，上传为 Actions artifact（含 SHA-256）；
- 推送 `v*` 标签：创建 GitHub Release 并附带 APK。

正式签名通过 Secrets 配置：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`；未配置时回退到 debug 签名。
