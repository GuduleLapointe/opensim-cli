<?php

/**
 * What the commands that act on this machine ask of the engine (run by the scripts of libexec/, not by hand):
 *
 *   run.php status
 *   run.php start [--simulators] [target...]
 *   run.php stop|restart [--simulators] [now] [target...]
 *   run.php console <instance>
 *   run.php install-dotnet [-y] [MAJOR]
 *
 * The engine says what it does on the error output, the answer is on the standard output. The status is 0 for a success, 1 for a
 * problem, 2 for a command that is not understood.
 */

declare(strict_types=1);

ini_set('display_errors', 'stderr');
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);

use OpenSim\Console\RestConsole;
use OpenSim\Exceptions\InstanceFailed;
use OpenSim\OpenSim;
use OpenSim\Provisioning\UiInterface;
use OpenSim\Runtime\DotnetInstaller;
use OpenSim\Runtime\PendingReporterInterface;
use OpenSim\Runtime\Status;

foreach ([__DIR__ . '/../../vendor/autoload.php', __DIR__ . '/../../../../autoload.php'] as $autoload) {
    if (is_file($autoload)) {
        require $autoload;

        break;
    }
}
if (!class_exists(OpenSim::class)) {
    fwrite(STDERR, "opensim: the engine is not installed (composer install)\n");
    exit(2);
}

/** What the engine says, on the error output as `opensim: <message>`; the details with DEBUG=yes. */
final class CliReporter implements PendingReporterInterface
{
    private bool $pending = false;

    public function __construct(private readonly bool $debug = false) {}

    public function info(string $message): void
    {
        fwrite(STDERR, "opensim: $message\n");
    }

    public function error(string $message): void
    {
        fwrite(STDERR, "opensim: error: $message\n");
    }

    public function debug(string $message): void
    {
        $this->debug && fwrite(STDERR, "opensim: $message\n");
    }

    public function step(string $text): void
    {
        fwrite(STDERR, ($this->pending ? "\r\033[K" : '') . "opensim: $text\n");
        $this->pending = false;
    }

    /** What the wait is on, on one line a terminal replaces with the next. */
    public function pending(string $text): void
    {
        if (stream_isatty(STDERR)) {
            fwrite(STDERR, "\r\033[Kopensim: $text");
            $this->pending = true;
        }
    }

    public function stepEnd(): void {}

    public function isTerminal(): bool
    {
        return stream_isatty(STDERR);
    }
}

/** No questions: the notes go to the standard output, the problems to the error output, every question gets its default. */
final class StdUi implements UiInterface
{
    public function intro(string $title): void {}

    public function note(string $message): void
    {
        fwrite(STDOUT, "$message\n");
    }

    public function entity(string $name): string
    {
        return $name;
    }

    public function warn(string $message): void
    {
        fwrite(STDERR, "$message\n");
    }

    public function error(string $message): void
    {
        fwrite(STDERR, "$message\n");
    }

    public function outro(string $message): void {}

    public function choose(string $label, array $options, ?string $default = null, ?string $hint = null): string
    {
        return $default ?? (string) array_key_first($options);
    }

    public function checklist(string $label, array $options, array $defaults = [], ?string $hint = null): array
    {
        return $defaults;
    }

    public function text(string $label, string $default = '', ?\Closure $validate = null, ?string $hint = null): string
    {
        return $default;
    }

    public function secret(string $label, ?\Closure $validate = null, ?string $hint = null): string
    {
        return '';
    }

    public function form(array $fields, string $title = ''): array
    {
        return [];
    }

    public function confirm(string $label, bool $default = true): bool
    {
        return $default;
    }

    public function spin(\Closure $callback, string $message): mixed
    {
        return $callback();
    }
}

/** The table of the instances, then the summary line. */
function render(Status $status): string
{
    $rows = [['INSTANCE', 'TYPE', 'PID', 'USER', '%CPU', '%MEM', 'RSS']];
    foreach ($status->instances as $item) {
        $p = $item->process();
        $rows[] = $p === null
            ? [$item->name(), $item->type(), '[down]']
            : [$item->name(), $item->type(), (string) $p->pid, $p->user, sprintf('%.1f', $p->cpu), sprintf('%.1f', $p->memory), (string) $p->rss];
    }
    $widths = [];
    foreach ($rows as $row) {
        foreach ($row as $i => $cell) {
            $widths[$i] = max($widths[$i] ?? 0, strlen($cell));
        }
    }
    $text = '';
    foreach ($rows as $row) {
        $cells = [];
        foreach ($row as $i => $cell) {
            $cells[] = $i === count($row) - 1 ? $cell : str_pad($cell, $widths[$i] + 2);
        }
        $text .= implode('', $cells) . "\n";
    }
    $t = $status->totals();
    $line = $status->up() . ' up' . ($status->down() > 0 ? ', ' . $status->down() . ' down' : '');

    return $text . sprintf("%s - cpu %.1f%% - mem %.1f%% - rss %d\n", $line, $t['cpu'], $t['memory'], $t['rss']);
}

/** 1 when an instance failed (one still loading did not), else 0. */
function outcome(array $results): int
{
    foreach ($results as $result) {
        if ($result instanceof InstanceFailed) {
            return 1;
        }
    }

    return 0;
}

$args = array_slice($argv, 1);
$command = array_shift($args) ?? '';
// The user the instances run as, empty when the install has none (the commands then run as whoever calls them)
if ($command === 'system-user') {
    echo \OpenSim\Config\Layout::resolve()->systemUser(), "\n";
    exit(0);
}
$simulators = in_array('--simulators', $args, true) || in_array('--sims', $args, true);
$words = array_values(array_filter($args, static fn(string $a): bool => $a === '' || $a[0] !== '-'));
$engine = OpenSim::environment(new CliReporter(in_array(strtolower((string) getenv('DEBUG')), ['yes', 'true', '1'], true)));
$now = ($words[0] ?? '') === 'now';
$targets = $now ? array_slice($words, 1) : $words;

switch ($command) {
    case 'status':
        echo render(OpenSim::status($engine));
        exit(0);
    case 'start':
        exit(outcome(OpenSim::start($words ?: null, $engine, $simulators)));
    case 'stop':
        exit(outcome(OpenSim::stop($targets ?: null, $now, $engine, $simulators)));
    case 'restart':
        exit(outcome(OpenSim::restart($targets ?: null, $now, $engine, $simulators)));
    case 'console':
        $name = $words[0] ?? '';
        $instance = $name === '' ? null : OpenSim::instance($engine, $name);
        if ($instance === null) {
            $engine->reporter->error($name === '' ? 'usage: opensim console <instance>' : "no ini file found for $name");
            exit(1);
        }
        $screen = $engine->consoles->screen($instance->name());
        if ($screen->exists()) {
            $engine->reporter->info("console of {$instance->name()}, Ctrl-A D to leave it running");
            exit($screen->attach());
        }
        // The remote console: a prompt, every line typed goes to it
        $console = $instance->console();
        $session = $console instanceof RestConsole ? $console->session() : null;
        if ($session === null) {
            $engine->reporter->error("{$instance->name()} is not running");
            exit(1);
        }
        $engine->reporter->info("remote console of {$instance->name()}, Ctrl-D to leave it running");
        while (true) {
            echo $session->prompt !== '' ? $session->prompt : '> ';
            $line = fgets(STDIN);
            if ($line === false) {
                echo "\n";
                break;
            }
            $result = $session->command(rtrim($line, "\r\n"), RestConsole::WAIT);
            foreach ($result['lines'] as $text) {
                echo $text, "\n";
            }
            if ($result['closed']) {
                break;
            }
        }
        $session->close();
        exit(0);
    case 'install-dotnet':
        $major = $words[0] ?? '8';
        if (count($words) > 1 || !ctype_digit($major)) {
            fwrite(STDERR, "usage: opensim install-dotnet [-y] [MAJOR]\n");
            exit(2);
        }
        // Every question gets its default: the command asks nothing
        exit((new DotnetInstaller(new StdUi()))->install((int) $major) ? 0 : 1);
}
fwrite(STDERR, "opensim: unknown command $command\n");
exit(2);
