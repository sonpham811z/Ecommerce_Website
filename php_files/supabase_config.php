<?php
// Supabase project credentials — read from environment variables when containerised.
// Set SUPABASE_URL and SUPABASE_KEY in docker-compose.yml / .env
define('SUPABASE_URL', getenv('SUPABASE_URL') ?: 'https://yqbaaipksxorhlynhmfd.supabase.co');
define('SUPABASE_KEY', getenv('SUPABASE_KEY') ?: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxYmFhaXBrc3hvcmhseW5obWZkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc1NDA3NDAsImV4cCI6MjA2MzExNjc0MH0.W7bgKUJmSuMS9YcmQlLK8Ol1ZOSeRcaHICECY6HWk1k');

/**
 * Makes an authenticated request to the Supabase REST API.
 *
 * @param string      $endpoint  e.g. '/auth/v1/user'
 * @param string      $method    HTTP method: GET | POST | PUT | DELETE
 * @param array|null  $data      Request body (will be JSON-encoded)
 * @param string|null $token     User JWT — if provided, used as Bearer token;
 *                               falls back to the anon key for unauthenticated calls
 * @return array{status: int, data: array}
 */
function makeSupabaseRequest(string $endpoint, string $method = 'GET', ?array $data = null, ?string $token = null): array {
    $url = SUPABASE_URL . $endpoint;

    $headers = [
        'Content-Type: application/json',
        'apikey: ' . SUPABASE_KEY,
        'Authorization: Bearer ' . ($token ?? SUPABASE_KEY),
    ];

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

    if ($data !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
    }

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    return [
        'status' => $httpCode,
        'data'   => json_decode($response, true) ?? [],
    ];
}
