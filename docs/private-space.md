# Private Space

Private Space uses the device's system authentication prompt. Android 12 and newer
can unlock it using a strong enrolled biometric or the screen-lock PIN, pattern,
or password. No app-specific password is collected or saved.

Files and the filename/path index are encrypted with Tink Streaming AEAD
(`AES256_GCM_HKDF_1MB`). Its keyset is wrapped with an authentication-bound AES-256
GCM key in Android Keystore. Each encrypted object has a random identifier used
as associated data. The wrapped keyset and encrypted index use atomic writes.
Vault storage is inside `noBackupFilesDir`, outside shared storage and backups.

Moving into Private Space encrypts and verifies each file before committing the
encrypted index and removing its original. If the source changes or removal
fails, the encrypted copy remains and the operation reports the failure. A move
does not securely erase flash storage or remove copies/backups made earlier.

Private Space locks when leaving its tab, explicitly locking it, or putting the
app in the background. Its keyset and index are discarded from the session.
Private tabs never get window-preview screenshots. Private viewers block screen
capture and recents snapshots. Temporary decrypted previews stay in app-private
cache, cannot be read by other apps through the file provider, and are removed on
lock and next startup. Private media playback stops on lock even if ordinary
background music playback is enabled.

Copy, cut and paste inside the vault keep data encrypted. **Copy to** and
**Remove from Private Space** explicitly export readable files to a chosen local
folder. Export never silently overwrites an existing file. Removal from the vault
only happens after export succeeds. Private deletion is permanent and bypasses
the ordinary Recycle Bin.

Uninstalling the app, clearing its data, or resetting device security can make
the data unrecoverable. There is no cloud recovery or backdoor. This implementation
has not undergone an independent security audit and does not protect against a
compromised/rooted operating system or someone who can unlock the device.

References:
- [Tink Streaming AEAD](https://developers.google.com/tink/encrypt-large-files-or-data-streams)
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Device authentication](https://developer.android.com/identity/sign-in/biometric-auth)
