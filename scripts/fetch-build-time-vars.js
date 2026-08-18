#!/usr/bin/env node

const fs = require('node:fs');

/**
 * Authenticates with Infisical using Universal Auth.
 */
async function authenticate(apiBaseUrl, clientId, clientSecret) {
  console.log(`🔑 Authenticating with Infisical (${apiBaseUrl})...`);
  const loginRes = await fetch(`${apiBaseUrl}/api/v1/auth/universal-auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ clientId, clientSecret })
  });

  if (!loginRes.ok) {
    const errText = await loginRes.text();
    console.error(`❌ Authentication failed: ${loginRes.status} ${loginRes.statusText}\n${errText}`);
    process.exit(1);
  }

  const { accessToken } = await loginRes.json();
  console.log(`✓ Authenticated successfully.`);
  return accessToken;
}

/**
 * Resolves project slug or ID to a verified UUID.
 */
async function resolveProjectId(apiBaseUrl, accessToken, projectSlugOrId) {
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(projectSlugOrId);

  if (!isUuid) {
    console.log(`🔍 Resolving project slug "${projectSlugOrId}" to ID...`);
    const projectRes = await fetch(`${apiBaseUrl}/api/v1/projects/slug/${projectSlugOrId}`, {
      headers: { 'Authorization': `Bearer ${accessToken}` }
    });

    if (projectRes.ok) {
      const projectData = await projectRes.json();
      const projectObj = projectData.project || projectData.workspace || projectData;
      const resolvedId = projectObj.id || projectObj._id || projectSlugOrId;
      console.log(`✓ Resolved project slug to ID: ${resolvedId}`);
      return resolvedId;
    } else {
      const errText = await projectRes.text();
      console.log(`⚠ Failed to resolve slug via API, falling back to slug value: ${errText}`);
      return projectSlugOrId;
    }
  }

  console.log(`✓ Using project ID: ${projectSlugOrId}`);
  return projectSlugOrId;
}

/**
 * Fetches the secret list from the targeted Infisical environment and path.
 */
async function fetchSecrets(apiBaseUrl, accessToken, projectId, envSlug, secretPath) {
  console.log(`📥 Fetching variables from path "${secretPath}" [env: ${envSlug}]...`);
  const secretsUrl = `${apiBaseUrl}/api/v4/secrets?projectId=${encodeURIComponent(projectId)}&environment=${encodeURIComponent(envSlug)}&secretPath=${encodeURIComponent(secretPath)}&viewSecretValue=true`;

  const secretsRes = await fetch(secretsUrl, {
    headers: { 'Authorization': `Bearer ${accessToken}` }
  });

  if (!secretsRes.ok) {
    const errText = await secretsRes.text();
    console.error(`❌ Failed to fetch secrets: ${secretsRes.status} ${secretsRes.statusText}\n${errText}`);
    process.exit(1);
  }

  const { secrets } = await secretsRes.json();
  if (!secrets || !Array.isArray(secrets)) {
    console.error('❌ Invalid secrets response format.');
    process.exit(1);
  }

  console.log(`✓ Successfully fetched ${secrets.length} variables.`);
  return secrets;
}

/**
 * Exports secrets to GITHUB_ENV or write to a target file (e.g. .env).
 */
function exportSecrets(secrets) {
  const githubEnvFile = process.env.GITHUB_ENV;
  const outputFile = process.env.OUTPUT_FILE;

  // Only mask true secrets, sensitive API keys, tokens, and private credentials in GitHub logs.
  // Non-sensitive configuration (domains, public URLs, app IDs, bundle IDs, redirect URIs) remain unmasked.
  const keysToMask = [
    // Sensitive API Keys & Service Credentials
    'GOOGLE_PLACES_API_KEY',
    'FIREBASE_ANDROID_API_KEY',
    'FIREBASE_IOS_API_KEY',
    'SUPABASE_URL',
    'SUPABASE_PUBLISHABLE_KEY',
    'SUPABASE_DEV_URL',
    'SUPABASE_DEV_PUBLISHABLE_KEY',

    // Telemetry & Security Tokens
    'SENTRY_FLUTTER_DSN',

  ];

  // Explicit non-sensitive public configuration values (IDs, URLs, domains, redirect URIs)
  const keysToOmitFromMasking = [
    'APP_DOMAIN',
    'BACKEND_URL',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_STORAGE_BUCKET',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_ANDROID_APP_ID_NEXUS',
    'FIREBASE_IOS_APP_ID_NEXUS',
    'FIREBASE_ANDROID_APP_ID_NEXUS_MEC',
    'FIREBASE_IOS_APP_ID_NEXUS_MEC',
    'FIREBASE_IOS_BUNDLE_ID_NEXUS',
    'FIREBASE_IOS_BUNDLE_ID_NEXUS_MEC',
    'GOOGLE_WEB_CLIENT_ID',
    'GOOGLE_IOS_CLIENT_ID_NEXUS',
    'GOOGLE_IOS_CLIENT_ID_NEXUS_MEC',
    'SPOTIFY_CLIENT_ID',
    'SPOTIFY_REDIRECT_URI_NEXUS',
    'SPOTIFY_REDIRECT_URI_NEXUS_MEC'
  ];

  if (outputFile) {
    console.log(`📝 Writing secrets to ${outputFile}...`);
    let content = '';
    for (const secret of secrets) {
      content += `${secret.secretKey}=${secret.secretValue}\n`;
    }
    fs.appendFileSync(outputFile, content);
    console.log(`✓ Written secrets to ${outputFile}`);
  }

  // Dynamically generate mobile/firebase.json if secret map includes required Firebase parameters
  generateFirebaseJson(secrets);

  if (githubEnvFile) {
    console.log(`📝 Exporting variables to GITHUB_ENV...`);
    for (const secret of secrets) {
      if (
        keysToMask.includes(secret.secretKey) &&
        !keysToOmitFromMasking.includes(secret.secretKey) &&
        secret.secretValue
      ) {
        console.log(`::add-mask::${secret.secretValue}`);
      }
      fs.appendFileSync(githubEnvFile, `${secret.secretKey}=${secret.secretValue}\n`);
      console.log(`   + ${secret.secretKey}`);
    }
    console.log(`🎉 Variables exported successfully!`);
  } else if (!outputFile) {
    console.log(`ℹ️ GITHUB_ENV and OUTPUT_FILE are not set. Loaded keys:`);
    for (const secret of secrets) {
      if (
        keysToMask.includes(secret.secretKey) &&
        !keysToOmitFromMasking.includes(secret.secretKey)
      ) {
        console.log(`   ${secret.secretKey}=[MASKED]`);
      } else {
        console.log(`   ${secret.secretKey}=${secret.secretValue}`);
      }
    }
  }
}

/**
 * Dynamically generates mobile/firebase.json from Infisical secrets or process.env.
 */
function generateFirebaseJson(secrets = []) {
  const envMap = {};
  for (const s of secrets) {
    envMap[s.secretKey] = s.secretValue;
  }
  const getVar = (key) => envMap[key] || process.env[key] || '';

  const projectId = getVar('FIREBASE_PROJECT_ID');
  const androidAppIdNexus = getVar('FIREBASE_ANDROID_APP_ID_NEXUS');
  const iosAppIdNexus = getVar('FIREBASE_IOS_APP_ID_NEXUS');
  const androidAppIdNexusMec = getVar('FIREBASE_ANDROID_APP_ID_NEXUS_MEC');
  const iosAppIdNexusMec = getVar('FIREBASE_IOS_APP_ID_NEXUS_MEC');

  if (!projectId || !androidAppIdNexus) {
    console.log('ℹ️ Skipping mobile/firebase.json generation (missing Firebase project/app IDs).');
    return;
  }

  const firebaseJson = {
    flutter: {
      platforms: {
        android: {
          default: {
            projectId: projectId,
            appId: androidAppIdNexus,
            fileOutput: "android/app/google-services.json"
          }
        },
        dart: {
          "lib/firebase_options_nexus.dart": {
            projectId: projectId,
            configurations: {
              android: androidAppIdNexus,
              ios: iosAppIdNexus || androidAppIdNexus
            }
          },
          "lib/firebase_options_nexus_mec.dart": {
            projectId: projectId,
            configurations: {
              android: androidAppIdNexusMec || androidAppIdNexus,
              ios: iosAppIdNexusMec || iosAppIdNexus || androidAppIdNexus
            }
          }
        }
      }
    }
  };

  const targetPath = 'mobile/firebase.json';
  try {
    fs.writeFileSync(targetPath, JSON.stringify(firebaseJson, null, 2) + '\n');
    console.log(`✓ Dynamically generated ${targetPath}`);
  } catch (err) {
    console.warn(`⚠️ Could not write ${targetPath}:`, err.message);
  }
}

/**
 * Validates essential /public build-time variables.
 * Fails the process with exit code 1 if critical configuration is missing or malformed.
 */
function validatePublicVariables(secrets) {
  const secretMap = {};
  for (const s of secrets) {
    secretMap[s.secretKey] = s.secretValue;
  }

  const errors = [];

  // Required core configuration
  if (!secretMap['APP_DOMAIN'] || secretMap['APP_DOMAIN'].trim() === '') {
    errors.push('APP_DOMAIN is required and cannot be empty.');
  }

  if (!secretMap['SUPABASE_URL'] || !secretMap['SUPABASE_URL'].startsWith('https://')) {
    errors.push('SUPABASE_URL is required and must start with "https://".');
  }

  if (secretMap['ALLOWED_SIGNUP_DOMAINS']) {
    try {
      const parsed = JSON.parse(secretMap['ALLOWED_SIGNUP_DOMAINS']);
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
        errors.push('ALLOWED_SIGNUP_DOMAINS must be a valid JSON dictionary/object.');
      }
    } catch (e) {
      errors.push(`ALLOWED_SIGNUP_DOMAINS is not valid JSON: ${e.message}`);
    }
  }

  if (errors.length > 0) {
    console.error('❌ Validation of /public variables failed:');
    for (const err of errors) {
      console.error(`   - ${err}`);
    }
    process.exit(1);
  }

  console.log('✓ Public variables validated successfully.');
}

/**
 * Main application entrypoint.
 */
async function main() {
  const clientId = process.env.INFISICAL_CLIENT_ID;
  const clientSecret = process.env.INFISICAL_CLIENT_SECRET;
  const projectSlugOrId = process.env.INFISICAL_PROJECT_SLUG || process.env.INFISICAL_PROJECT_ID;
  const envSlug = process.env.INFISICAL_ENV_SLUG || 'prod';
  const secretPath = process.env.INFISICAL_SECRET_PATH || '/public';
  const apiBaseUrl = process.env.INFISICAL_API_URL || 'https://app.infisical.com';

  if (!clientId || !clientSecret || !projectSlugOrId) {
    console.error('❌ Missing required Infisical credentials (INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET) or project identifier.');
    process.exit(1);
  }

  const accessToken = await authenticate(apiBaseUrl, clientId, clientSecret);
  const projectId = await resolveProjectId(apiBaseUrl, accessToken, projectSlugOrId);
  const secrets = await fetchSecrets(apiBaseUrl, accessToken, projectId, envSlug, secretPath);
  validatePublicVariables(secrets);
  exportSecrets(secrets);
}

module.exports = {
  validatePublicVariables,
  generateFirebaseJson,
  exportSecrets,
  fetchSecrets,
  resolveProjectId,
  authenticate,
};

if (require.main === module) {
  main().catch(err => {
    console.error('❌ Script failed:', err);
    process.exit(1);
  });
}
