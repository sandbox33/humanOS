package com.altair.humanos

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small encrypted files for what the phone needs while the app is closed:
 * zones to re-register after a reboot, pending reminders, alarms and the
 * transitions not yet read by the app. AES-256-GCM with a key that never
 * leaves the Android Keystore. The source of truth stays in the encrypted
 * user database; these files are rewritten from it on every app start.
 */
object SecureStore {
    private const val KEY_ALIAS = "humanos_native_store_v1"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    /** One lock for every read-modify-write, from any receiver. */
    val lock = Any()

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun file(context: Context, name: String) = File(context.noBackupFilesDir, "$name.bin")

    fun write(context: Context, name: String, text: String) {
        synchronized(lock) {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val sealed = cipher.iv + cipher.doFinal(text.toByteArray(Charsets.UTF_8))
            val target = file(context, name)
            val temp = File(target.parentFile, "${target.name}.tmp")
            temp.writeBytes(sealed)
            if (!temp.renameTo(target)) {
                target.delete()
                temp.renameTo(target)
            }
        }
    }

    /** Null when missing or unreadable (the app writes it again). */
    fun read(context: Context, name: String): String? {
        synchronized(lock) {
            val source = file(context, name)
            if (!source.exists()) return null
            return try {
                val bytes = source.readBytes()
                if (bytes.size <= IV_BYTES) return null
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(
                    Cipher.DECRYPT_MODE,
                    key(),
                    GCMParameterSpec(TAG_BITS, bytes.copyOfRange(0, IV_BYTES)),
                )
                String(cipher.doFinal(bytes.copyOfRange(IV_BYTES, bytes.size)), Charsets.UTF_8)
            } catch (e: Exception) {
                null
            }
        }
    }
}
