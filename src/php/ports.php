<?php

declare(strict_types=1);

use OpenSim\OpenSim;
use OpenSim\Runtime\Environment;

/** Render the engine's configured listeners as a table, publish options or UFW rules. */
function showPorts(Environment $environment, array $arguments): int
{
    $mode = 'table';
    $address = '127.0.0.1';
    $targets = [];
    $options = true;
    for ($index = 0; $index < count($arguments); $index++) {
        $argument = $arguments[$index];
        if ($options && $argument === '--') {
            $options = false;
        } elseif ($options && in_array($argument, ['--publish', '--ufw'], true)) {
            $requested = substr($argument, 2);
            if ($mode !== 'table' && $mode !== $requested) {
                $environment->reporter->error(_('choose either --publish or --ufw'));
                return 2;
            }
            $mode = $requested;
        } elseif ($options && $argument === '--private-address') {
            $address = $arguments[++$index] ?? '';
        } elseif ($options && str_starts_with($argument, '--private-address=')) {
            $address = substr($argument, strlen('--private-address='));
        } elseif ($options && str_starts_with($argument, '-')) {
            $environment->reporter->error(sprintf(_('unknown ports option: %s'), $argument));
            return 2;
        } else {
            $targets[] = $argument;
        }
    }
    $address = trim($address, '[]');
    if (filter_var($address, FILTER_VALIDATE_IP) === false) {
        $environment->reporter->error(_('private address must be an IPv4 or IPv6 address'));
        return 2;
    }
    $bindAddress = str_contains($address, ':') ? "[$address]" : $address;
    $instances = [];
    if ($targets === []) {
        $instances = OpenSim::enabled($environment);
    } else {
        foreach ($targets as $target) {
            $instance = OpenSim::instance($environment, $target);
            if ($instance === null) {
                $environment->reporter->error(sprintf(_('no ini file found for %s'), $target));
                return 1;
            }
            $instances[$instance->name()] = $instance;
        }
    }
    if ($instances === []) {
        $environment->reporter->error(_('no enabled instance'));
        return 1;
    }
    $rows = [];
    foreach ($instances as $instance) {
        foreach ($instance->ports() as $port) {
            $rows[] = $port + ['instance' => $instance->name(), 'type' => $instance->type()];
        }
    }
    if ($mode === 'publish') {
        $mappings = [];
        foreach ($rows as $row) {
            if ($row['use'] === 'off') {
                continue;
            }
            $bind = $row['use'] === 'public' ? '' : "$bindAddress:";
            $mappings[] = "-p $bind{$row['port']}:{$row['port']}" . ($row['proto'] === 'tcp' ? '' : "/{$row['proto']}");
        }
        echo implode(' ', array_unique($mappings)), "\n";
    } elseif ($mode === 'ufw') {
        foreach ($rows as $row) {
            if ($row['use'] === 'off') {
                continue;
            }
            echo $row['use'] === 'public'
                ? "ufw allow {$row['port']}/{$row['proto']}    # {$row['instance']}: {$row['role']}\n"
                : "# {$row['port']}/{$row['proto']} ({$row['instance']}: {$row['role']}): " .
                    _('only from the machines that need it, e.g.') .
                    " ufw allow from <address> to any port {$row['port']} proto {$row['proto']}\n";
        }
    } else {
        $table = [[_('INSTANCE'), _('TYPE'), _('PORT'), _('PROTO'), _('USE'), _('FOR')]];
        foreach ($rows as $row) {
            $table[] = [$row['instance'], $row['type'], (string) $row['port'], $row['proto'], $row['use'], $row['role']];
        }
        $widths = [];
        foreach ($table as $cells) {
            foreach ($cells as $column => $value) {
                $widths[$column] = max($widths[$column] ?? 0, strlen($value));
            }
        }
        foreach ($table as $cells) {
            foreach ($cells as $column => $value) {
                echo $column === 5 ? "$value\n" : str_pad($value, $widths[$column] + 2);
            }
        }
    }
    return 0;
}
