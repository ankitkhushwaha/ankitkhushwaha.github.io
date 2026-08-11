---
title: Reverse-Engineer apk/apks files
---

Android applications are distributed as APK files.
An APK is essentially a ZIP archive containing application code,
resources, the manifest, native libraries, and other files required by Android.

This guide describes to reverse-Engineer apk/apks files on linux using `apktool`, Android Build Tools, `zipalign`, `apksigner`, and `adb`.

---

# 1. Install the required tools

This workflow certain tools we need to installed.
`java-17-openjdk` `unzip` `wget`, `adb`, `apktool`.

I recommand you to install `sdkmanager` for installed utility like
`zipalign`, `apksigner` and include its folder path to `$PATH` of `.bashrc`
file.

---

# 2. Decompile an APK

you can use `jadx` decompiler to decompile the code to java/kotline language
to understand the source code.

But to make edits in apk file you need to use `apktool`, which decompiles the
code into `smali` lanuage, which is similar to assembly used for Android's 
Dalvik Virtual Machine.

Decode it:

```bash
apktool d app.apk -o app
```

This creates:

```text
app/
├── AndroidManifest.xml
├── apktool.yml
├── res/
├── smali/
├── smali_classes2/
└── ...
```

The exact directories depend on the application.

The important parts are:

### `AndroidManifest.xml`

Contains application metadata such as:

* package name
* activities
* services
* permissions
* receivers
* providers

### `res/`

Contains Android resources:

```text
res/
├── drawable/
├── layout/
├── mipmap/
├── values/
└── ...
```

### `smali/`

Contains the application's Dalvik bytecode represented as Smali instructions.

For applications containing multiple DEX files, Apktool may create directories such as:

```text
smali/
smali_classes2/
smali_classes3/
```

---

# 3. Recompile the APK

Build the decoded application:

```bash
apktool b app -o unsigned.apk
```

The result is an APK, but it should not yet be treated as the final
installable APK. These APKs are required to be aligned and signing
before installtion. Otherwise it won't install.

# 4. Zipalign the APK

```bash
zipalign -p -f 4 unsigned.apk aligned.apk
```

---

# 5. Create a signing key

For testing purposes, create your own keystore:

```bash
keytool -genkeypair \
    -v \
    -keystore my-release-key.jks \
    -alias mykey \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000
```

You will be asked for a password and certificate information.

This creates:

```text
my-release-key.jks
```

Keep this file safe.If you lose the key, you cannot use it to sign
future versions with the same signing identity.

---

# 6. Sign the APK

```bash
apksigner sign \
    --ks my-release-key.jks \
    --ks-key-alias mykey \
    --out signed.apk \
    aligned.apk
```

You will be asked for the keystore password.

The final APK is:

```text
signed.apk
```
---

# 7. Verify the signature

Always verify the APK after signing:

```bash
apksigner verify --verbose signed.apk
```

You should see successful verification for the APK's signing schemes.

You can also inspect the signing certificate:

```bash
apksigner verify --print-certs signed.apk
```

---

# 8. Install the APK

Connect an Android device with USB debugging enabled.

Check:

```bash
adb devices
```

Then install:

```bash
adb install signed.apk
```

If an older version of the application is already installed and was signed with a different key, Android may reject the installation with a signature mismatch.

In that situation, for an application you are authorized to replace, uninstall the existing package first:

```bash
adb uninstall <package-name>
```

Then:

```bash
adb install signed.apk
```

---

# 9. Working with Split APKs

Modern Android applications are often distributed as multiple APK files instead of a single APK.

For example:

single app extracted as `.apks` file which contians following files.

```text
base.apk
split_config.arm64_v8a.apk
split_config.xxhdpi.apk
```

These are called **split APKs**.

The base APK contains the main application while configuration splits may contain:

* CPU architecture-specific native libraries
* screen-density resources
* language resources
* other configuration-specific resources

You cannot always treat these files as independent applications.

The installation command is:

```bash
adb install-multiple \
    base.apk \
    split_config.arm64_v8a.apk \
    split_config.xxhdpi.apk
```

---

# 10. Modifying a Split APK Set

To install the this apk files, you need to align and sign each apk file,
with `zipalign`, `apksigner`.

---

# 11. Final Note

The most important thing to remember is that **decompilation is not a reversible source-code transformation**. Apktool reconstructs resources and bytecode representations that can be rebuilt into an APK, but the result will not necessarily be identical to the original APK. Compiler-generated details, resource packaging, signing information, and other build metadata can change.
