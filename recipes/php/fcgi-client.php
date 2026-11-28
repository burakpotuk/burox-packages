<?php
// Minimal FastCGI client (works on PHP 7.4+), used by the PHP smoke test:
//   php fcgi-client.php <unix-socket> <script-filename> [query-string]
// Prints the raw CGI response (headers + body) returned by PHP-FPM.
if ($argc < 3) { fwrite(STDERR, "usage: fcgi-client.php <socket> <script> [query]\n"); exit(2); }
list(, $socket, $script) = $argv;
$query = $argc > 3 ? $argv[3] : '';

function record($type, $content, $id = 1) {
    return pack('CCnnCx', 1, $type, $id, strlen($content), 0) . $content;
}
function pairs(array $params) {
    $out = '';
    foreach ($params as $k => $v) {
        foreach ([strlen($k), strlen($v)] as $len) {
            $out .= $len < 128 ? chr($len) : pack('N', $len | 0x80000000);
        }
        $out .= $k . $v;
    }
    return $out;
}

$conn = stream_socket_client('unix://' . $socket, $errno, $errstr, 5);
if (!$conn) { fwrite(STDERR, "connect failed: $errstr\n"); exit(1); }
$params = pairs([
    'GATEWAY_INTERFACE' => 'FastCGI/1.0', 'REQUEST_METHOD' => 'GET',
    'SCRIPT_FILENAME' => $script, 'SCRIPT_NAME' => '/' . basename($script),
    'QUERY_STRING' => $query, 'REQUEST_URI' => '/' . basename($script) . ($query !== '' ? "?$query" : ''),
    'SERVER_SOFTWARE' => 'burox-smoke', 'REMOTE_ADDR' => '127.0.0.1', 'SERVER_NAME' => 'localhost',
    'SERVER_PORT' => '80', 'SERVER_PROTOCOL' => 'HTTP/1.1', 'CONTENT_LENGTH' => '0',
]);
fwrite($conn, record(1, pack('nCx5', 1, 0)) . record(4, $params) . record(4, '') . record(5, ''));

$stdout = '';
while (!feof($conn)) {
    $header = fread($conn, 8);
    if (strlen($header) < 8) { break; }
    $h = unpack('Cversion/Ctype/nid/nlength/Cpadding/x', $header);
    $content = $h['length'] > 0 ? stream_get_contents($conn, $h['length']) : '';
    if ($h['padding'] > 0) { fread($conn, $h['padding']); }
    if ($h['type'] === 6) { $stdout .= $content; }          // FCGI_STDOUT
    if ($h['type'] === 7) { fwrite(STDERR, $content); }     // FCGI_STDERR
    if ($h['type'] === 3) { break; }                        // FCGI_END_REQUEST
}
fclose($conn);
echo $stdout;
