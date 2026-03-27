import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const R2_ACCOUNT_ID = Deno.env.get('R2_ACCOUNT_ID')!
const R2_ACCESS_KEY_ID = Deno.env.get('R2_ACCESS_KEY_ID')!
const R2_SECRET_ACCESS_KEY = Deno.env.get('R2_SECRET_ACCESS_KEY')!
const R2_BUCKET = 'eidos-images'
const R2_HOST = `${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`
const R2_PUBLIC_BASE = 'https://pub-9682c785f96b466a80a82b94f48c0765.r2.dev'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ── AWS Sig V4 helpers ────────────────────────────────────────────────────────

async function hmac(key: ArrayBuffer | string, msg: string): Promise<ArrayBuffer> {
  const rawKey = typeof key === 'string'
    ? new TextEncoder().encode(key)
    : new Uint8Array(key)
  const cryptoKey = await crypto.subtle.importKey(
    'raw', rawKey, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  )
  return crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(msg))
}

function hex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('')
}

async function sha256Hex(s: string): Promise<string> {
  return hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))
}

async function signingKey(secret: string, date: string): Promise<ArrayBuffer> {
  const k1 = await hmac('AWS4' + secret, date)
  const k2 = await hmac(k1, 'auto')   // R2 region = "auto"
  const k3 = await hmac(k2, 's3')
  return hmac(k3, 'aws4_request')
}

// Generates a presigned PUT URL valid for `expiresIn` seconds.
async function presignedPut(objectKey: string, expiresIn = 3600): Promise<string> {
  const now = new Date()
  const date    = now.toISOString().slice(0, 10).replace(/-/g, '')            // YYYYMMDD
  const datetime = date + 'T' + now.toISOString().slice(11, 19).replace(/:/g, '') + 'Z' // YYYYMMDDTHHmmssZ

  const credential = `${R2_ACCESS_KEY_ID}/${date}/auto/s3/aws4_request`

  // Query parameters must be sorted lexicographically by key
  const params: [string, string][] = [
    ['X-Amz-Algorithm',    'AWS4-HMAC-SHA256'],
    ['X-Amz-Credential',   credential],
    ['X-Amz-Date',         datetime],
    ['X-Amz-Expires',      expiresIn.toString()],
    ['X-Amz-SignedHeaders', 'host'],
  ]
  params.sort((a, b) => a[0].localeCompare(b[0]))

  const canonicalQS = params
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&')

  const canonicalRequest = [
    'PUT',
    `/${R2_BUCKET}/${objectKey}`,
    canonicalQS,
    `host:${R2_HOST}\n`,
    'host',
    'UNSIGNED-PAYLOAD',
  ].join('\n')

  const stringToSign = [
    'AWS4-HMAC-SHA256',
    datetime,
    `${date}/auto/s3/aws4_request`,
    await sha256Hex(canonicalRequest),
  ].join('\n')

  const key = await signingKey(R2_SECRET_ACCESS_KEY, date)
  const signature = hex(await hmac(key, stringToSign))

  return `https://${R2_HOST}/${R2_BUCKET}/${objectKey}?${canonicalQS}&X-Amz-Signature=${signature}`
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Verify auth
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )

  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const { sightingId, fileType } = await req.json() as {
      sightingId: string
      fileType: 'original' | 'annotated'
    }

    const ext = fileType === 'original' ? 'jpg' : 'png'
    const objectKey = `${user.id}/${sightingId}/${fileType}.${ext}`

    const uploadUrl = await presignedPut(objectKey)
    const publicUrl = `${R2_PUBLIC_BASE}/${objectKey}`

    return new Response(JSON.stringify({ uploadUrl, publicUrl, objectKey }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
