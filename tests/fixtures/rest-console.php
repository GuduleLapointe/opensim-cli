<?php

declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
header('Content-Type: text/xml');

if ($path === '/StartSession/') {
    parse_str(file_get_contents('php://input'), $input);
    if (($input['USER'] ?? '') !== 'admin' || ($input['PASS'] ?? '') !== 'secret') {
        http_response_code(401);
        exit;
    }
    echo '<?xml version="1.0"?><ConsoleSession><SessionID>fixture-session</SessionID><Prompt>Region (Test) # </Prompt></ConsoleSession>';
} elseif ($path === '/CloseSession/') {
    echo '<?xml version="1.0"?><ConsoleSession><Result>OK</Result></ConsoleSession>';
} else {
    http_response_code(404);
}
