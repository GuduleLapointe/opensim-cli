<?php

declare(strict_types=1);

namespace OpenSimCli;

use OpenSim\Config\GridConfig;
use OpenSim\Exceptions\ChannelUnavailable;
use OpenSim\Models\Avatar;
use OpenSim\Models\Estate;

/** Builds reviewable SQL and user reports without changing grid databases. */
final class BanPlan
{
    /** @var list<Avatar> */
    public array $users = [];
    /** @var list<string> */
    public array $cleanup = [];
    /** @var list<string> */
    public array $ban = [];
    /** @var list<string> */
    public array $traveling = [];
    /** @var list<string> */
    public array $problems = [];

    /** @param list<string> $targets Names or UUIDs to plan for. */
    public static function make(GridConfig $config, array $targets): self
    {
        $plan = new self();
        foreach ($targets as $target) {
            try {
                $found = Avatar::lookup($config, $target);
            } catch (\InvalidArgumentException $e) {
                $plan->problems[] = $e->getMessage();
                continue;
            }
            if ($found === []) {
                $plan->problems[] = "no user found for '" . trim($target) . "'";
            }
            foreach ($found as $avatar) {
                if (!in_array($avatar->uuid(), array_map(static fn(Avatar $user): string => $user->uuid(), $plan->users), true)) {
                    $plan->users[] = $avatar;
                }
            }
        }

        try {
            $estates = Estate::all($config)->items();
        } catch (ChannelUnavailable $e) {
            $estates = [];
            $plan->problems[] = 'cannot read estates; nobody is banned: ' . $e->getMessage();
        }
        foreach ($plan->users as $user) {
            $leftovers = $user->leftovers();
            $plan->cleanup[] = '-- ' . $user->label() . ' (' . $user->uuid() . ')';
            array_push($plan->cleanup, ...$user->purgeSql($leftovers));
            foreach ($leftovers as $left) {
                $problem = "database of {$left['table']} is unknown; no data is deleted from it";
                if ($left['database'] === null && !in_array($problem, $plan->problems, true)) {
                    $plan->problems[] = $problem;
                }
            }
            foreach ($estates as $estate) {
                if (($statement = $estate->banSql($user->uuid())) !== null) {
                    $plan->ban[] = sprintf('-- %s in estate %s of %s', $user->label(), $estate->id(), $estate->connection()?->database ?? '?');
                    $plan->ban[] = $statement;
                }
            }
            foreach ($user->travelingData() as $row) {
                $plan->traveling[] = implode("\t", array_map('strval', $row));
            }
        }
        return $plan;
    }

    public function deletes(): int { return self::statements($this->cleanup); }
    public function bans(): int { return self::statements($this->ban); }

    /** @return array<string,string> */
    public function files(string $date): array
    {
        $lines = static fn(array $values): string => $values === [] ? '' : implode("\n", $values) . "\n";
        return [
            'users' => $lines(array_map(static fn(Avatar $user): string => implode("\t", [$user->uuid(), $user->firstName(), $user->lastName(), $user->grid()]), $this->users)),
            'cleanup' => $lines(["-- Delete accounts and data $date", ...$this->cleanup]),
            'ban' => $lines(["-- Ban users $date", ...$this->ban]),
            'hg_traveling_data' => $lines(["-- Hypergrid traveling data $date", ...$this->traveling]),
        ];
    }

    /** @param list<string> $lines */
    private static function statements(array $lines): int
    {
        return count(array_filter($lines, static fn(string $line): bool => $line !== '' && !str_starts_with($line, '--')));
    }
}
