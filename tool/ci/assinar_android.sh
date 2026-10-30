#!/usr/bin/env bash
# Configura a assinatura de release do APK a partir dos secrets do GitHub:
#   ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
# Sem eles, o APK sai assinado com uma chave de depuração temporária (instala, mas cada
# versão nova exige desinstalar a anterior). Gere a chave com tool/gerar_keystore.ps1.
set -euo pipefail

if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "::warning::Secrets da keystore não configurados: APK assinado com chave de depuração."
  exit 0
fi

echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/release.jks
cat > android/key.properties <<EOF
storeFile=release.jks
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
keyPassword=$ANDROID_KEY_PASSWORD
EOF

# O flutter create gera build.gradle.kts (versões novas) ou build.gradle (antigas).
# Um segundo bloco android {} no fim do arquivo sobrepõe a assinatura do release.
if [ -f android/app/build.gradle.kts ]; then
  # No .kts, `java.util...` resolve `java` como a extensão do Gradle e não como pacote:
  # a classe precisa vir de um import, que só vale no topo do arquivo.
  sed -i '1i import java.util.Properties' android/app/build.gradle.kts
  cat >> android/app/build.gradle.kts <<'EOF'

// --- Assinatura de release (adicionado pelo CI: tool/ci/assinar_android.sh) ---
val diakoKeyProps = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) arquivo.inputStream().use { load(it) }
}
android {
    signingConfigs {
        create("diakoRelease") {
            storeFile = file(diakoKeyProps.getProperty("storeFile", "release.jks"))
            storePassword = diakoKeyProps.getProperty("storePassword")
            keyAlias = diakoKeyProps.getProperty("keyAlias")
            keyPassword = diakoKeyProps.getProperty("keyPassword")
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("diakoRelease")
        }
    }
}
EOF
else
  cat >> android/app/build.gradle <<'EOF'

// --- Assinatura de release (adicionado pelo CI: tool/ci/assinar_android.sh) ---
def diakoKeyProps = new Properties()
def diakoKeyArquivo = rootProject.file('key.properties')
if (diakoKeyArquivo.exists()) diakoKeyArquivo.withInputStream { diakoKeyProps.load(it) }
android {
    signingConfigs {
        diakoRelease {
            storeFile file(diakoKeyProps['storeFile'])
            storePassword diakoKeyProps['storePassword']
            keyAlias diakoKeyProps['keyAlias']
            keyPassword diakoKeyProps['keyPassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.diakoRelease
        }
    }
}
EOF
fi
echo "Assinatura de release configurada."
