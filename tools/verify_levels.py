"""Independent campaign oracle. Search over position, tape phase and device state."""
from collections import deque
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
DIR = {"U": (0, -1), "D": (0, 1), "L": (-1, 0), "R": (1, 0)}


class Room:
    def __init__(self, level, *, freeze_turns=False, freeze_bridges=False, freeze_lava=False):
        self.level = level
        rows = level["rows"]
        assert rows and len({len(row) for row in rows}) == 1
        self.floor, self.switches, self.bridges, marks = set(), set(), {}, {}
        self.lava = {}
        self.lava_groups = level.get("lava_groups", 0)
        self.freeze_lava = freeze_lava
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch == "#":
                    continue
                cell = (x, y)
                self.floor.add(cell)
                if ch == "*":
                    self.switches.add(cell)
                elif ch in "ab":
                    self.bridges[cell] = int(ch == "b")
                elif ch in "1234":
                    assert 0 < int(ch) <= self.lava_groups <= 4
                    self.lava[cell] = int(ch) - 1
                elif ch not in ".!":
                    assert ch in "SXABC@" and ch not in marks
                    marks[ch] = cell
        self.start, self.goal = marks.pop("S"), marks.pop("X")
        self.pads = marks
        self.gates = {}
        self.vacancies = {}
        for gate in level["gates"]:
            edge = self.edge(*gate["a"], *gate["b"])
            assert edge not in self.gates and (gate["requires"] or gate.get("vacant"))
            self.gates[edge] = {marks[key] for key in gate["requires"]}
            self.vacancies[edge] = {marks[key] for key in gate.get("vacant", [])}
            assert not self.gates[edge] & self.vacancies[edge]
        self.turns = {}
        for i, (a, b) in enumerate(level.get("turnstiles", [])):
            edge = self.edge(*a, *b)
            assert edge not in self.turns
            self.turns[edge] = (tuple(a), 2 << i)
        self.controlled = sum(2 << i for i in level.get("controlled_turnstiles", []))
        self.direction_switches = {tuple(c["at"]): sum(2 << i for i in c["turnstiles"])
                                   for c in level.get("direction_switches", [])}
        assert bool(self.switches) == bool(self.bridges)
        self.live_bits = 0 if freeze_bridges else 1
        if not freeze_turns:
            self.live_bits |= sum(bit for _, bit in self.turns.values())
        self.links = {}
        for p in self.floor:
            self.links[p] = []
            for letter, (dx, dy) in DIR.items():
                dest = p[0] + dx, p[1] + dy
                if dest not in self.floor:
                    continue
                edge = frozenset((p, dest))
                turn = self.turns.get(edge)
                bit = turn[1] if turn else 0
                trigger = ((bit & ~self.controlled) | self.direction_switches.get(dest, 0)
                           | int(dest in self.switches)) & self.live_bits
                self.links[p].append((letter, dest, trigger, self.bridges.get(dest),
                                      bit, bool(turn and turn[0] != p), self.gates.get(edge, set()),
                                      self.vacancies.get(edge, set())))

    def edge(self, x, y, u, v):
        a, b = (x, y), (u, v)
        assert a in self.floor and b in self.floor and abs(x-u)+abs(y-v) == 1
        return frozenset((a, b))

    def choices(self, player, occupied, state):
        for letter, dest, trigger, bank, bit, reverse, pads, vacant in self.links[player]:
            next_phase = (0 if self.freeze_lava else ((state >> 6) + 1) % self.lava_groups) if self.lava_groups else -1
            if self.lava.get(dest, -2) == next_phase:
                continue
            if bank is not None and bank != (state & 1):
                continue
            if bit and bool(state & bit) != reverse:
                continue
            if not all(pos in occupied for pos in pads):
                continue
            if any(pos in occupied for pos in vacant):
                continue
            lens = self.pads.get('@')
            if lens not in pads or occupied.count(lens) >= 2:
                yield letter, dest, trigger

    def advance(self, state, events):
        devices = (state ^ events) & 63
        phase = ((state >> 6) + 1) % self.lava_groups if self.lava_groups and not self.freeze_lava else 0
        return devices | (phase << 6)

    def tape_frame(self, recordings, t):
        occupied = [r[t] for r in recordings if t < len(r)]
        triggered = 0
        for route in recordings:
            if t+1 < len(route):
                for _, dest, bits, *_ in self.links[route[t]]:
                    if dest == route[t+1]:
                        triggered |= bits
                        break
        return occupied, triggered

    def replay(self, letters, recordings):
        path, state = [self.start], 0
        for t, letter in enumerate(letters):
            player = path[-1]
            assert player != self.goal, "A completed route cannot continue"
            occupied, events = self.tape_frame(recordings, t)
            move = next((m for m in self.choices(player, occupied + [player], state) if m[0] == letter), None)
            assert move, (self.level["id"], letters, t+1, player, state)
            _, dest, trigger = move
            state = self.advance(state, events | trigger)
            assert (sum(dest)-sum(self.start)) % 2 == (t+1) % 2
            path.append(dest)
        return path

    def finish_options(self, recordings):
        """Map each feasible last approach to its shortest clear with these tapes."""
        end = max((len(r) for r in recordings), default=0)
        frames = [self.tape_frame(recordings, t) for t in range(end+1)]
        q = deque([(self.start, 0, 0, 0)])
        seen = {(self.start, 0, 0)}
        finishes = {}
        while q:
            player, t, state, moves = q.popleft()
            occupied, events = frames[t]
            for _, dest, trigger in self.choices(player, occupied + [player], state):
                if dest == self.goal:
                    finishes.setdefault(player, moves + 1)
                    continue
                node = dest, min(t+1, end), self.advance(state, events | trigger)
                if node not in seen:
                    seen.add(node)
                    q.append((*node, moves+1))
        return finishes

    def shortest_final(self, recordings):
        return min(self.finish_options(recordings).values(), default=None)

    def one_echo_solution(self):
        """Search *all* possible one-echo tapes. Its recording world has its own gates."""
        start = (self.start, self.start, 0, 0)
        parent = {start: None}
        q = deque([start])
        while q:
            node = q.popleft()
            ghost, player, old_state, live_state = node
            if player == self.goal:
                recording, finish = [], []
                while parent[node] is not None:
                    node, old_step, new_step = parent[node]
                    if old_step:
                        recording.append(old_step)
                    finish.append(new_step)
                return ''.join(recording[::-1]), ''.join(finish[::-1])
            old_moves = list(self.choices(ghost, [ghost], old_state)) if ghost is not None else []
            if node != start:
                old_moves.append(('', None, 0))
            current_moves = list(self.choices(player, [player, ghost], live_state))
            for old_step, g, a in old_moves:
                if g == self.goal:
                    continue
                for new_step, p, b in current_moves:
                    child = g, p, self.advance(old_state, a) if g is not None else 0, self.advance(live_state, a | b)
                    if child not in parent:
                        parent[child] = (node, old_step, new_step)
                        q.append(child)
        return None

    def relaxed_reach(self, start, *, fixed_bank=None, fixed_arrows=False, blocked_edge=None):
        """Ignore pressure gates; optionally hold one bank or cut one edge."""
        seen, q = {start}, deque([start])
        while q:
            pos = q.popleft()
            for _, dest, _, bank, bit, reverse, _, _ in self.links[pos]:
                if (fixed_bank is not None and bank is not None and bank != fixed_bank) or (fixed_arrows and bit and reverse):
                    continue
                if blocked_edge and frozenset((pos, dest)) == blocked_edge:
                    continue
                if dest not in seen:
                    seen.add(dest)
                    q.append(dest)
        return seen

    def check(self):
        records = []
        for letters in self.level["recordings"]:
            route = self.replay(letters, records)
            assert len(route) > 1 and route[-1] != self.goal
            records.append(route)
        assert len(records) == self.level["max_echoes"]
        assert self.replay(self.level["final"], records)[-1] == self.goal
        assert self.shortest_final([]) is None, "Unintended solo solution"
        shortest = self.shortest_final(records)
        assert shortest is not None and shortest <= len(self.level["final"])
        if len(records) == 2:
            assert self.one_echo_solution() is None, "This room must require two recordings"
        if len(records) == 2 and self.level["id"] not in ["X04", "21", "24"]:
            entrances = [n for n in self.floor if abs(n[0]-self.goal[0])+abs(n[1]-self.goal[1]) == 1]
            assert len(entrances) == 1
            pre = entrances[0]
            required = self.gates[frozenset((pre, self.goal))]
            assert pre not in required
            if self.turns and self.bridges:
                # Counterpoint: with no bridge swaps, at least one final post is
                # unreachable. With static arrows the first person who can change
                # banks is trapped away from *all three* posts. Two actors remain.
                posts = required | {pre}
                assert posts - self.relaxed_reach(self.start, fixed_bank=0)
                initial = self.relaxed_reach(self.start, fixed_bank=0, fixed_arrows=True)
                assert posts - initial
                first_switches = initial & self.switches
                assert first_switches
                for switch in first_switches:
                    assert not (posts & self.relaxed_reach(switch, fixed_arrows=True))
        if len(records) == 1 and (self.turns or self.bridges):
            solution = self.one_echo_solution()
            assert solution
            tape = self.replay(solution[0], [])
            assert self.replay(solution[1], [tape])[-1] == self.goal
            if self.turns:
                assert Room(self.level, freeze_turns=True).one_echo_solution() is None, "Turn reversal can be skipped"
            if self.bridges:
                assert Room(self.level, freeze_bridges=True).one_echo_solution() is None, "Bridge switching can be skipped"
        if self.level["id"] == "14":
            # At the last lens crossing the player enters bank b and both echoes
            # occupy the lens. With b raised a live traveller there cannot reach
            # either exit plate or the switch, even with all pressure gates open.
            lens = self.pads['@']
            lens_edge, = (edge for edge, pads in self.gates.items() if lens in pads)
            deck, = (cell for cell in lens_edge if self.bridges.get(cell) == 1)
            exit_side = self.relaxed_reach(deck, blocked_edge=lens_edge)
            assert self.goal in exit_side and self.start not in exit_side and not exit_side & self.switches
            assert not self.relaxed_reach(lens, fixed_bank=1) & (required | self.switches)
        print(f'{self.level["id"]} {self.level["title"]}: {len(records)} echo(es), '
              f'recordings {[len(r)-1 for r in records]}, final {shortest} beats for these recordings.')


def check_extra(level):
    room = Room(level)
    room.check()
    legacy_id = level.get("legacy_id", level["id"])
    if legacy_id == "X01":
        # The exact one-echo searches in Room.check also freeze each device family.
        return

    if level["id"] == "X04":
        entrances = {dest for _, dest, *_ in room.links[room.goal]}
        assert len(entrances) == 3
        alternatives = json.loads((ROOT / "tests/switchyard_routes.json").read_text())
        used = set()
        for plan in [level, *alternatives]:
            tapes = []
            for letters in plan["recordings"]:
                tapes.append(room.replay(letters, tapes))
            path = room.replay(plan["final"], tapes)
            assert path[-1] == room.goal
            # A legal win at this entrance; even unlimited extra beats cannot
            # make the other two entrances work with this exact recording pair.
            assert room.finish_options(tapes) == {path[-2]: len(plan["final"])}
            used.add(path[-2])
        assert used == entrances
        return

    if level["id"] == "X05":
        # Recording B needs A; recording C needs two older actors on A and B.
        # The final cut needs two on L, one on C, plus a live traveller at
        # neither location. This rules out every two-echo solution.
        def without(edges):
            seen, q = {room.start}, deque([room.start])
            while q:
                p = q.popleft()
                for _, dest, *_ in room.links[p]:
                    if frozenset((p, dest)) not in edges and dest not in seen:
                        seen.add(dest)
                        q.append(dest)
            return seen

        a_doors = {e for e, pads in room.gates.items() if pads == {room.pads['A']}}
        assert room.pads['B'] not in without(a_doors)
        chamber, = (e for e, pads in room.gates.items() if pads == {room.pads['A'], room.pads['B']} and not room.vacancies[e])
        assert room.pads['C'] not in without({chamber})
        assert not chamber & {room.pads['A'], room.pads['B']}
        meeting, = (e for e, pads in room.gates.items() if pads == {room.pads['@'], room.pads['C']})
        assert room.goal not in without({meeting})
        assert not meeting & {room.pads['@'], room.pads['C']}
        # Leaving the lens requires crossing bank a. The only entrance to
        # the exit region is bank b, so a live traveller could not make the
        # recorded gallery departures on that same beat.
        assert all(room.bridges.get(p) == 0 for _, p, *_ in room.links[room.pads['@']])
        assert any(room.bridges.get(p) == 1 for p in meeting)
        plans = [level, *json.loads((ROOT / 'tests/paradox_routes.json').read_text())]
        used = set()
        for plan in plans:
            tapes = []
            for letters in plan['recordings']:
                tapes.append(room.replay(letters, tapes))
            path = room.replay(plan['final'], tapes)
            assert path[-1] == room.goal
            assert room.finish_options(tapes) == {path[-2]: len(plan['final'])}
            assert Room(level, freeze_bridges=True).shortest_final(tapes) is None
            used.add(path[-2])
        assert used == {p for _, p, *_ in room.links[room.goal]}
        return

    def gate_cut(required, destination):
        # Even ignoring every device, cutting this gate disconnects its destination.
        edge, = (edge for edge, posts in room.gates.items()
                 if posts == {room.pads[name] for name in required}
                 and destination not in room.relaxed_reach(room.start, blocked_edge=edge))
        return edge

    assert room.goal not in room.relaxed_reach(room.start, fixed_bank=0)
    if legacy_id == "X02":
        # The second recording cannot reach B alone. Both recordings are also
        # required on the final trip, as exhaustively checked by Room.check.
        gate_cut("@", room.pads["B"])
        gate_cut("AB", room.goal)
        return

    # The third recording cannot visit C until two *other* actors hold A and B.
    vault = gate_cut("AB", room.pads["C"])
    assert not vault & {room.pads["A"], room.pads["B"]}
    # A mandatory edge checks two actors on L plus a third on C. Neither
    # endpoint holds any of them. This rules out every two-echo solution.
    meeting = gate_cut("@C", room.goal)
    assert not meeting & {room.pads["@"], room.pads["C"]}
    # Later, both plate holders must leave the upper gallery. With the arrows
    # frozen, the two actors at L cannot reach either plate, even in a recording.
    split = gate_cut("AB", room.goal)
    assert not split & room.relaxed_reach(room.start, blocked_edge=meeting)
    assert not {room.pads["A"], room.pads["B"]} & room.relaxed_reach(room.pads["@"], fixed_arrows=True)


if __name__ == "__main__":
    levels = json.loads((ROOT / "data/levels.json").read_text())
    assert [r["id"] for r in levels] == [f'{n:02d}' for n in range(1, len(levels)+1)]
    for level in levels:
        if level.get("legacy_id"):
            check_extra(level)
        else:
            Room(level).check()
        if level["id"] == "21":
            room = Room(level)
            tapes = []
            for tape in level["recordings"]:
                tapes.append(room.replay(tape, tapes))
            assert Room(level, freeze_turns=True).shortest_final(tapes) is None
            for final in [level["final"], "UUDDRRRRDRRURR"]:
                assert room.replay(final, tapes)[-1] == room.goal
            # Complementary doors enclose the ride. No control exists inside;
            # the outer echo must flip the direction again after entry.
            assert room.controlled == 6 and set(room.direction_switches) == {(0, 0)}
    for plan in json.loads((ROOT / "tests/inferno_routes.json").read_text()):
        room = Room(levels[int(plan["id"]) - 1])
        tapes = []
        for route in plan["recordings"]:
            tapes.append(room.replay(route, tapes))
        assert room.replay(plan["final"], tapes)[-1] == room.goal
    extras = json.loads((ROOT / "data/extra.json").read_text())
    assert [r["id"] for r in extras] == ["X04", "X05"]
    for level in extras:
        check_extra(level)
