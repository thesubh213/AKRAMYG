// crypto.ts for zero-knowledge browser-side encryption

export async function deriveKey(passphrase: string): Promise<CryptoKey> {
  const encoder = new TextEncoder();
  const keyMaterial = encoder.encode(passphrase);
  
  // Calculate SHA-256 hash of the passphrase to get 256 bits of key material
  const hash = await crypto.subtle.digest('SHA-256', keyMaterial);
  
  return crypto.subtle.importKey(
    'raw',
    hash,
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt']
  );
}

export async function deriveChannelId(passphrase: string): Promise<string> {
  const encoder = new TextEncoder();
  const keyMaterial = encoder.encode(passphrase);
  const hashBuffer = await crypto.subtle.digest('SHA-256', keyMaterial);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex.substring(0, 32); // Return 32 hex characters
}

export async function encryptPayload(payload: string, passphrase: string): Promise<string> {
  const key = await deriveKey(passphrase);
  const encoder = new TextEncoder();
  const data = encoder.encode(payload);
  
  // Generate random 12-byte initialization vector (IV)
  const iv = crypto.getRandomValues(new Uint8Array(12));
  
  // Encrypt data with AES-GCM.
  // The output ciphertext in Web Crypto automatically includes the 16-byte authentication tag at the end!
  const ciphertextBuffer = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    data
  );
  
  const ciphertext = new Uint8Array(ciphertextBuffer);
  
  // Package as: IV (12 bytes) + Ciphertext (includes Tag)
  const combined = new Uint8Array(iv.length + ciphertext.length);
  combined.set(iv, 0);
  combined.set(ciphertext, iv.length);
  
  // Base64 encode the combined package
  return arrayBufferToBase64(combined);
}

function arrayBufferToBase64(buffer: Uint8Array): string {
  let binary = '';
  const len = buffer.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(buffer[i]);
  }
  return btoa(binary);
}
