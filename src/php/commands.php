<?php

declare(strict_types=1);

namespace OpenSimCli;

use OpenSim\Archives\ArchiveRunner;
use OpenSim\Archives\BackupService;
use OpenSim\Archives\DatabaseDump;
use OpenSim\Archives\Rotation;
use OpenSim\Config\GridConfig;
use OpenSim\Data\Connections;
use OpenSim\Models\Avatar;
use OpenSim\Models\Estate;
use OpenSim\Models\Grid;
use OpenSim\Network\Ports;
use OpenSim\Provisioning\DatabaseService;
use OpenSim\Provisioning\GridOptions;
use OpenSim\Provisioning\GridRegistry;
use OpenSim\Provisioning\LocationFinder;
use OpenSim\Provisioning\NullUi;
use OpenSim\Provisioning\Places;
use OpenSim\Provisioning\Slug;
use OpenSim\Provisioning\Web\HelpersConfig;
use OpenSim\Provisioning\Web\Services;
use OpenSim\Provisioning\Web\Snippets;
use OpenSim\Runtime\Environment;

/** The local commands that use the engine's services and models. */
final class Commands
{
    /** @param list<string> $args */
    public static function toggle(string $verb, Environment $environment, array $args): int
    {
        if ($args === []) {
            fwrite(STDERR, "usage: opensim $verb <instance...> | <grid> <search|economy|profiles> [variant] [url prefix]\n");

            return 2;
        }
        $grids = Grid::all($environment)->items();
        $grid = null;
        foreach ($grids as $candidate) {
            if (strcasecmp($candidate->nick(), $args[0]) === 0) {
                $grid = $candidate;
                break;
            }
        }
        if ($grid !== null && isset($args[1]) && ($option = (new GridOptions($grid))->resolve($args[1])) !== null) {
            $more = array_slice($args, 2);
            $variant = isset($more[0]) && !str_contains($more[0], '/') ? strtolower(array_shift($more)) : '';
            $options = new GridOptions($grid);
            $option = $options->resolve($args[1], $variant);
            if ($option === null || count($more) > 1) {
                fwrite(STDERR, "usage: opensim $verb <grid> <search|economy|profiles> [variant] [url prefix]\n");

                return 2;
            }
            $result = $verb === 'enable'
                ? $options->enable($option->name(), $more === [] ? [] : ['prefix' => $more[0]])
                : $options->disable($option->name());
            if ($result['error'] !== null) {
                fwrite(STDERR, "$verb: {$result['error']}\n");

                return 1;
            }
            $state = $verb . 'd';
            fwrite(STDOUT, "{$option->name()} $state for {$grid->nick()}\n");
            foreach ($result['notes'] as $note) {
                fwrite(STDOUT, "note: $note\n");
            }

            return 0;
        }

        $instances = [];
        foreach ($grids as $candidate) {
            if ($candidate->robustIni() !== null) {
                $entry = ['type' => 'grid', 'model' => $candidate];
                $instances[$candidate->nick()] = $entry;
                $instances[Slug::snake($candidate->nick())] = $entry;
            }
            foreach ($candidate->simulators() as $simulator) {
                $entry = ['type' => 'simulator', 'model' => $simulator];
                $name = basename($simulator->ini(), '.ini');
                $instances[$name] = $entry;
                $instances[Slug::snake($name)] = $entry;
            }
        }
        $enable = $verb === 'enable';
        $failed = false;
        foreach ($args as $name) {
            $key = Slug::snake($name);
            if (!isset($instances[$key])) {
                fwrite(STDERR, "$verb: no grid or simulator called $name\n");
                $failed = true;
                continue;
            }
            $entry = $instances[$key];
            $model = $entry['model'];
            if ($model->isEnabled() === $enable) {
                fwrite(STDOUT, "{$entry['type']} $name is already {$verb}d\n");
                continue;
            }
            if ($enable ? $model->enable() : (function () use ($model): bool { $model->disable(); return !$model->isEnabled(); })()) {
                fwrite(STDOUT, "{$entry['type']} $name {$verb}d" . ($enable ? ": opensim start $name" : '') . "\n");
            } else {
                fwrite(STDERR, "$verb: could not update $name\n");
                $failed = true;
            }
        }

        return $failed ? 1 : 0;
    }

    /** @param list<string> $args */
    public static function web(Environment $environment, array $args): int
    {
        $options = ['grid' => '', 'docroot' => '', 'socket' => ''];
        $words = [];
        for ($i = 0; $i < count($args); $i++) {
            if (preg_match('/^--(grid|docroot|socket)(?:=(.*))?$/', $args[$i], $m)) {
                if (isset($m[2])) {
                    $options[$m[1]] = $m[2];
                } elseif (isset($args[$i + 1])) {
                    $options[$m[1]] = $args[++$i];
                } else {
                    return self::error('web', "--{$m[1]} needs a value", 2);
                }
            } else {
                $words[] = $args[$i];
            }
        }
        $actions = ['show', 'snippet', 'check'];
        $action = 'show';
        if ($words !== [] && !in_array($words[0], $actions, true)) {
            $options['grid'] = $options['grid'] ?: array_shift($words);
        }
        if ($words !== []) {
            $action = array_shift($words);
            if (!in_array($action, $actions, true)) {
                return self::error('web', "unknown action $action", 2);
            }
        }
        $grids = [];
        foreach (Grid::all($environment)->items() as $grid) {
            if ($grid->robustIni() !== null) {
                $grids[$grid->nick()] = $grid;
            }
        }
        if ($options['grid'] === '' && count($grids) === 1) {
            $options['grid'] = (string) array_key_first($grids);
        }
        $grid = $grids[$options['grid']] ?? null;
        if ($grid === null) {
            return self::error('web', $grids === [] ? 'no local grid' : 'select a grid: ' . implode(', ', array_keys($grids)), 2);
        }
        $directory = $grid->directory();
        $services = HelpersConfig::services($directory);
        $webUrl = HelpersConfig::webUrl($directory);
        if ($action === 'snippet') {
            try {
                fwrite(STDOUT, Snippets::render(
                    $words[0] ?? '',
                    $grid->nick(),
                    $directory,
                    $options['docroot'],
                    $options['socket'],
                    $webUrl,
                ));
                return 0;
            } catch (\InvalidArgumentException $e) {
                return self::error('web', $e->getMessage(), 2);
            }
        }
        $rows = [];
        foreach (array_keys(Services::SCRIPTS) as $service) {
            $rows[$service] = [$services->url($webUrl, $service), Services::SCRIPTS[$service]];
        }
        foreach (array_keys(Services::PAGES) as $page) {
            $rows[$page] = [$services->url($webUrl, $page), "@$page"];
        }
        if ($action === 'check') {
            $failed = false;
            foreach ($rows as $service => [$url]) {
                $headers = @get_headers($url, false, stream_context_create(['http' => ['timeout' => 5, 'ignore_errors' => true]]));
                $status = $headers === false ? 'no answer' : (string) ($headers[0] ?? '?');
                $ok = $headers !== false && !preg_match('# (404|403|50[234]) #', $status);
                $failed = $failed || !$ok;
                printf("%-15s %-50s %s\n", $service, $url, $ok ? "ok ($status)" : "FAILED ($status)");
            }
            return $failed ? 1 : 0;
        }
        printf("Grid:      %s\nWeb URL:   %s\nHelpers:   %s\n", $grid->nick(), $webUrl !== '' ? $webUrl : '(none)', $services->base());
        foreach ($rows as $service => [$url]) {
            printf("  %-15s %s\n", $service, $url);
        }
        fwrite(STDOUT, "\nThe web server needs: opensim web {$grid->nick()} snippet <caddy|nginx|apache>\n");
        return 0;
    }

    /** @param list<string> $args */
    public static function next(Environment $environment, array $args): int
    {
        $what = array_shift($args) ?? '';
        $gridFirst = null;
        if (!in_array($what, ['port', 'location'], true) && ($args[0] ?? '') === 'location') {
            $gridFirst = $what;
            array_shift($args);
            $what = 'location';
        }
        if (!in_array($what, ['port', 'location'], true)) {
            return self::error('next', 'usage: opensim next port [MIN] [COUNT] | opensim next <grid> location [X,Y] [COUNT]', 2);
        }
        $exclude = [];
        $words = $gridFirst === null ? [] : [$gridFirst];
        while ($args !== []) {
            $arg = array_shift($args);
            if ($arg === '-e' || $arg === '--exclude') {
                if ($args === []) return self::error('next', "$arg needs a value", 2);
                $exclude[] = array_shift($args);
            } else {
                $words[] = $arg;
            }
        }
        $number = static fn(?string $value, int $default): int => $value === null ? $default : (ctype_digit($value) ? (int) $value : -1);
        if ($what === 'port') {
            $min = $number($words[0] ?? null, 9010);
            $count = $number($words[1] ?? null, 1);
            if ($min < 1 || $count < 1 || count($words) > 2 || array_filter($exclude, static fn(string $e): bool => !ctype_digit($e)) !== []) {
                return self::error('next', 'MIN, COUNT and excluded ports must be positive numbers', 2);
            }
            $known = (new GridRegistry(new DatabaseService(new NullUi())))->knownPorts($environment);
            fwrite(STDOUT, implode("\n", (new Ports($environment))->nextFree($min, $count, [...array_map('intval', $exclude), ...$known])) . "\n");
            return 0;
        }
        $nick = $words[0] ?? '';
        $wish = isset($words[1]) ? LocationFinder::parse($words[1]) : [];
        $count = $number($words[2] ?? null, 1);
        if ($nick === '' || $wish === null || $count < 1 || count($words) > 3) {
            return self::error('next', 'usage: opensim next <grid> location [X,Y] [COUNT] [-e X,Y]', 2);
        }
        $grid = Grid::find($environment, $nick);
        if ($grid === null) return self::error('next', "no grid named '$nick'");
        $known = (new GridRegistry(new DatabaseService(new NullUi())))->locations($grid);
        foreach ($exclude as $place) {
            if (($taken = LocationFinder::parse($place)) === null) return self::error('next', "'$place' is not a place, use x,y", 2);
            LocationFinder::take($known, $taken[0], $taken[1]);
        }
        $wish = $wish ?: $grid->centerPlace();
        $unreachable = false;
        for ($i = 0; $i < $count; $i++) {
            [$x, $y] = Places::nearestFree($grid, $known, $wish[0], $wish[1], null, $unreachable);
            fwrite(STDOUT, "$x,$y\n");
            LocationFinder::take($known, $x, $y);
        }
        if ($unreachable) {
            fwrite(STDERR, "next: the grid does not answer at {$grid->baseHostname()}:{$grid->privatePort()}, its regions are not all known here\n");
        }
        return 0;
    }

    /** @param list<string> $args */
    public static function ban(Environment $environment, array $args): int
    {
        $output = getcwd() ?: '.';
        $words = [];
        for ($i = 0; $i < count($args); $i++) {
            if (preg_match('/^--output(?:=(.*))?$/', $args[$i], $m)) {
                $output = $m[1] ?? ($args[++$i] ?? '');
            } else {
                $words[] = $args[$i];
            }
        }
        $grids = array_values(array_filter(Grid::all($environment)->items(), static fn(Grid $grid): bool => !$grid->isRemote()));
        $nicks = array_map(static fn(Grid $grid): string => $grid->nick(), $grids);
        $grid = null;
        if ($words !== [] && in_array($words[0], $nicks, true)) {
            $grid = $grids[array_search(array_shift($words), $nicks, true)];
        } elseif (count($grids) === 1) {
            $grid = $grids[0];
        }
        if ($grid === null) {
            return self::error('ban', $grids === [] ? 'no local grid' : 'select a grid: opensim ban <grid> NAME|UUID... (' . implode(', ', $nicks) . ')', 2);
        }
        if ($words === [] || $output === '') {
            return self::error('ban', 'usage: opensim ban [GRID] NAME|UUID... [--output DIR]', 2);
        }
        if (!is_dir($output) || !is_writable($output)) {
            return self::error('ban', "cannot write in $output");
        }
        $config = GridConfig::fromFolder($grid->directory());
        if (Connections::key($config, 'UserAccountService') === null) {
            return self::error('ban', "no account database in {$grid->nick()} Robust config");
        }
        if (Connections::pdo($config, 'UserAccountService') === null) {
            return self::error('ban', 'cannot read account database: ' . (Connections::reason($config, 'UserAccountService') ?? '?'));
        }

        $plan = BanPlan::make($config, $words);
        foreach ($plan->problems as $problem) {
            fwrite(STDERR, "ban: $problem\n");
        }
        if ($plan->users === []) {
            return 1;
        }
        $files = [];
        foreach ($plan->files(date('Y-m-d H:i:s')) as $suffix => $text) {
            $files[$suffix] = rtrim($output, '/') . "/ban.$suffix";
            if (file_put_contents($files[$suffix], $text) === false) {
                return self::error('ban', "cannot write {$files[$suffix]}");
            }
        }
        foreach ($plan->users as $user) {
            fwrite(STDOUT, "{$user->uuid()}\t{$user->label()}\n");
        }
        fwrite(STDOUT, sprintf("%d delete and %d ban statements in %s and %s (users: %s; hypergrid data: %s)\n", $plan->deletes(), $plan->bans(), $files['cleanup'], $files['ban'], $files['users'], $files['hg_traveling_data']));
        if ($plan->deletes() + $plan->bans() > 0) {
            fwrite(STDOUT, "The databases are unchanged. Back them up, stop the simulators, review the files, then run:\n    cat {$files['cleanup']} {$files['ban']} | mysql\n");
        }
        return 0;
    }

    /** @param list<string> $args */
    public static function archives(string $verb, Environment $environment, array $args): int
    {
        if ($args === []) return self::error($verb, "usage: opensim $verb iar|oar ...", 2);
        [$code, $file] = ArchiveRunner::system($environment)->run($verb, $args);
        if ($file !== null) fwrite(STDOUT, "$file\n");
        return $code;
    }

    /** @param list<string> $args */
    public static function backup(Environment $environment, array $args): int
    {
        $refs = [];
        $options = [];
        while ($args !== []) {
            $arg = array_shift($args);
            if ($arg === '--logs' || $arg === '--archives') {
                $options[substr($arg, 2)] = true;
            } elseif (preg_match('/^--(output|keep)(?:=(.*))?$/', $arg, $m)) {
                $value = $m[2] ?? (array_shift($args) ?? '');
                if ($value === '') return self::error('backup', "--{$m[1]} needs a value", 2);
                if ($m[1] === 'output' && !str_starts_with($value, '/')) $value = getcwd() . '/' . $value;
                if ($m[1] === 'keep') {
                    try { $value = Rotation::count($value); } catch (\InvalidArgumentException $e) { return self::error('backup', $e->getMessage(), 2); }
                }
                $options[$m[1]] = $value;
            } elseif (str_starts_with($arg, '-') && $arg !== '_') {
                return self::error('backup', "unknown option $arg", 2);
            } else {
                $refs[] = $arg;
            }
        }
        try {
            $files = (new BackupService($environment, DatabaseDump::write(...), static fn(string $message) => fwrite(STDERR, "$message\n")))->run($refs, $options);
            fwrite(STDOUT, implode("\n", $files) . "\n");
            return 0;
        } catch (\InvalidArgumentException|\RuntimeException $e) {
            return self::error('backup', $e->getMessage());
        }
    }

    /** @param list<string> $args */
    public static function rest(array $args): int
    {
        $script = dirname(__DIR__, 2) . '/vendor/magicoli/opensim-rest-php/opensim-rest-cli.php';
        if (!is_file($script)) return self::error('rest', 'opensim-rest-php is not installed');
        $process = proc_open([PHP_BINARY, $script, ...$args], [0 => STDIN, 1 => STDOUT, 2 => STDERR], $pipes);
        return is_resource($process) ? proc_close($process) : 1;
    }

    private static function error(string $command, string $message, int $code = 1): int
    {
        fwrite(STDERR, "$command: $message\n");
        return $code;
    }
}
