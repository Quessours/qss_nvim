# Jira setup

Why each part works the way it does. Built on 2026-09-14 and 2026-09-15. The
create form was added on 2026-09-18.

What the keys and commands are is in `:help jira`. This file is the reasoning
behind them, and the record of what was got wrong on the way.

Everything below was checked against the live instance
(`tea-ebook.atlassian.net`, project `LIS`, board `LIS board`, id 116), not
against documentation. Where a claim comes from a measurement, the number is
given.

The module lives in `lua/qss_nvim/jira/`: 24 files, about 6800 lines, plus
`ftplugin/jira.lua` and `doc/jira.txt`. It is a feature module, not a plugin, so
it follows `qt-class` and `cpp-impl`: required once from the root `init.lua`,
registering its commands as it loads.

## 1. What talks to what

Three transports, because no single one does the whole job.

**jira-cli** for issues. It already holds the credentials, the project and the
custom field metadata, so there is no second thing to set up. Called through
`vim.system` with `--raw`, following `lua/qss_nvim/cmake-tools/tests.lua:380`.

**curl** for everything jira-cli cannot reach: the Jira REST API, the agile and
greenhopper endpoints, and Tempo. Credentials go to curl over stdin as a `-K`
file, never on the command line. An argv is readable by every process on the
machine (`http.lua:39`).

**The Jira REST API for every write.** Not jira-cli. Two reasons, both found by
testing. First, jira-cli resolves a custom field by its label. This instance has 10 pairs
of fields sharing a name, so a write can land on the wrong one.
Second, it refuses several field types outright. Writing by field id has neither
problem.

### Files

| File | Role |
|---|---|
| `config.lua` | Reads jira-cli's own `~/.config/.jira/.config.yml`: server, login, project, board id, and 131 custom fields. Holds this module's options. |
| `cache.lua` | Values with a time to live, kept in `stdpath('cache')/qss_jira.json`. |
| `cli.lua` | The jira-cli runner. |
| `http.lua` | The curl runner: Jira REST, agile, greenhopper, Tempo. |
| `adf.lua` | Atlassian document to markdown and back. The largest file, and the one that earned it. |
| `edit.lua` | Editing one field, in the shape that field takes. |
| `issue.lua` | The `jira://KEY` buffer. |
| `board.lua` | The `jira://board` and `jira://backlog` list views. |
| `sprint.lua` | The `jira://sprint` report and the burndown. |
| `picker.lua` | Every snacks source. |
| `actions.lua` | The action menu behind `<CR>`. |
| `fields.lua` | Pick a field, then edit it. |
| `create.lua` | The form for a new issue, at `jira://new/ID`. |
| `tempo.lua` | Worklogs. |
| `work.lua` | The start-work flow. |
| `git.lua` | Issue key from the branch, branch creation, commit prefix. |
| `links.lua` | Links between issues, in both directions. |
| `timesheet.lua` | The week you logged, drawn. |
| `protocol.lua` | `jira://` as a buffer name. |
| `progress.lua` | A sign that a write is in flight. |
| `completion.lua` | The `/` commands, as an nvim-cmp source. |
| `health.lua` | `:checkhealth qss_nvim.jira`. |
| `init.lua` | 21 user commands, and picking the type of a new issue. |
| `mappings.lua` | The 24 `<leader>j` keys. |

Three existing files were edited: `init.lua` requires the module,
`lua/qss_nvim/mappings/init.lua` merges its mappings, and
`lua/qss_nvim/which-key/config.lua` gains the `<leader>j` group.

## 2. One gesture

`i` and `<CR>` mean the same thing in every buffer this module draws: act on
what the cursor is on. There is nothing else to learn and nothing to aim at.

A line that is none of the things below falls back to the whole issue menu,
rather than reporting that there is nothing here. A dead end is worse than a
menu.

| Line | What opens |
|---|---|
| The title of a ticket | Every action on that issue. |
| A field row | The prompt that field takes. |
| The description, heading or body | The markdown buffer. |
| The Links heading | The relation picker. |
| A link row | Open the other issue, cut the link, add one. |
| The Comments heading | A new comment. |
| A comment, header or body | Edit it, delete it, add another. |
| A row on the board, backlog or report | Every action on that issue. |
| Anything else | Every action on that issue. |

Measured on a sample ticket: 44 of the 49 lines carrying text resolve to
something narrower than the menu.

Editing and deleting a comment is offered only on comments you wrote, which is
decided by the account id, not by the name.

## 3. Addresses

Every view has a name, and a `BufReadCmd` turns the name into the thing that
loads it: >

	jira://LIS-1234   jira://board   jira://backlog
	jira://sprint     jira://sprint/3973    jira://tempo
	jira://new/10001

Each view used to build itself: make a scratch buffer, name it, fill it, put it
in a window. Only this module ever opened it that way, and nvim has a hundred
other ways to open a name. None of them worked. All of them do now: `gf` on an
issue key, a quickfix entry, a session being restored, `:bufdo`, the command
line.

It also removed four copies of the same buffer-creation code.

						*what belongs in a name*
The rule the bugs of section 9 taught: anything that changes what a view shows
must live in the view's name, or must not survive the view's buffer. A sprint
id belongs in the name, because a report of another sprint is another thing. A
week does not, because it is where you are in the timesheet rather than which
timesheet it is.

## 4. The views

### `jira://KEY`, one issue

Drawn by this module rather than by `jira issue view --plain`. Every field sits
on its own line, and that line knows which field it is.

The prompt matches the field:

- an option gets a picker of its real allowed values.
- a user field gets a picker of the people who can be assigned.
- rich text gets a markdown buffer.
- a number or a date gets a plain prompt.

The list of fields comes from `editmeta`, so it is what Jira accepts on that
issue right now.

No single letter other than `i` and `q` is bound. The buffer holds prose, so
`w`, `e`, `l`, `y`, `f` and `t` stay the motions they are everywhere else.

### `jira://board`, the running sprint

Columns come from the board's own configuration, and a column is a set of status
ids rather than of status names. That matters here: this board puts eight
statuses in "To Do" alone. Grouping by name draws eight columns the board does
not have. Your own rows are marked.

### `jira://backlog`

Read to the end rather than cut off: 364 issues on this board. The picker it
replaced stopped at 200 and hid the rest silently.

Kept in rank order, because that order is what a backlog is for. The status
rides in the row instead of being a column.

### `jira://sprint`, report and burndown

The report comes from the greenhopper endpoints the Jira board itself calls.
They are not part of the documented REST API, so the code checks the shape of
what comes back rather than trusting it.

The burndown is rebuilt, not read: the endpoint reports changes, not a curve.
Each change says an issue entered the sprint, left it, crossed into a done
column, or had its estimate moved. Replaying them in order gives the remaining
work at every moment, which is the line. The guide line is flat across
non-working days, taken from the board's own working-rate calendar.

The chart sizes itself to the window, from 68 columns wide on an 80-column
terminal to 186 on a 200-column one, and never exceeds it.

### `jira://new/ID`, a new issue

Creating one used to be three windows in a row: a type picker, a summary
prompt, a markdown buffer. One question at a time shows nothing of what the
form asks, gives no way back, and lets nothing be left for later. It also sent
three fields, so this project refused every ticket it made: `LIS` requires
`Track`, and nothing was ever asking for it.

The whole issue is drawn at once instead, one field per row, and nothing is
sent until `<C-s>`. `i` on a row opens the prompt that field takes, which is
the same prompt the issue view uses. A required field left empty stops the
create and is named.

```
# New Story in LIS
  i or <CR> fills the field under the cursor · <C-s> creates · q drops

* Summary                   —
* Track                     Feature
  Description               —
  Epic Link                 —
  Clients Vivlio            —
  Story                     —

  * is one of the 2 fields Jira requires here.
```

						*createmeta*
Which fields exist, which are required and which values they take come from
`createmeta`, per project and per issue type. It is to creating an issue what
`editmeta` is to editing one, so the same argument holds: no guessing from a
label, and no list here to keep in step.

Measured on the live instance: Story, Task and Technical story require
`summary` and `Track`. A Bug requires those two, plus `reporter` and `Bug
Origin`. The create screen is small, 11 fields for a Story against 18 for a
Bug. The form therefore shows all of them rather than a chosen few.

The type id is in the address because the type decides which fields the form
has. The draft is not: it dies with the buffer, by the rule in section 3.

A field no prompt can fill is left out unless Jira requires it. A row that
answers "use the browser" is the dead end of section 9. What can be filled is
now one function, `edit.writable`, read by both the prompt and the form. Two
lists drift apart.

Asking for a value and writing it became two things on the way: `edit.ask`
runs the prompt and hands the value back, `edit.field` writes what it hands
back. The form collects a whole issue before anything is sent, so it calls the
first and never the second.

### `jira://tempo`, the week you logged

A list of worklogs answers what was written down. It does not answer what is
asked of a timesheet: is a day short, which ticket took the week, is anything
missing before it is submitted. Those are comparisons, and a shape shows a
comparison where a list does not.

A bar per day against the working day, the week against the week, and every
issue ranked by the time it took.

						*holidays*
What a day asks for is read from Tempo rather than counted here. `/4/user-
schedule` reports the working pattern and the public holidays: over 2026 on
this account, 255 working days, 102 non-working, 6 holidays on working days and
2 falling on a weekend. A holiday asks for nothing, says so, and leaves the
week asking for four days.

That also replaced a guess. The day was set to 7 hours because the weeks
already logged came to that. Tempo reports 25200 seconds, the same number read
instead of inferred. Where Tempo will not answer, `daily_hours` is the
fallback.

## 5. Rich text

Jira Cloud stores a description as a tree of typed nodes. Editing it as markdown
means converting both ways, and markdown cannot express every node.

The first version refused any description holding such a node. That was the
wrong trade. Now:

- Panels and task lists are real markdown, in both directions.
- A block markdown still cannot write becomes a comment line. The block is kept
  aside and put back exactly where that line ended up on save.
- Saving is gated on a **proven** round trip: render it, read it back, compare.
  Nothing is lost, or the edit does not open.

Measured on 30 real descriptions: 28 convert exactly. The two refusals hit a
nested-list and a code-block edge, and they refuse rather than corrupt.

### The slash commands

In a Jira edit buffer, and only there, `/` completes. `/success` writes a
success panel and `/task` writes a task list. The rest are `/info`, `/note`,
`/tip`, `/warning`, `/error`, `/done`, `/code`, `/quote` and `/rule`.

The canonical form is the alert block (`> [!SUCCESS]`). GitHub and other
renderers understand it, so a description stays readable outside Neovim.

### Links

A link is one object seen from two sides. Viewing `LIS-2311` it reads
`outwardIssue: LIS-2228`, and viewing `LIS-2228` the same link reads
`inwardIssue: LIS-2311`. Both sides were read from the live instance before any
of this was written. The rule that follows decides which way every new link
points: the side carrying `outwardIssue` is the subject of the outward phrase.

```
from LIS-2311:   blocks          LIS-2228
from LIS-2228:   is blocked by   LIS-2311
```

The ticket buffer shows them under `## Links`, phrased from its own side. Press
`i` on a link line to follow it, cut it, or add another. All 18 relations of the
instance are offered, each in both directions, which is 35 phrasings: `blocks`,
`is blocked by`, `has to be done before`, `has to be done after`, `relates to`,
`duplicates`, `causes`, `tests`, `split to` and the rest.

### Finding an issue

`<leader>jk` takes four shapes. `LIS-2431` and `lis-2431` open straight away. A
bare `2431` takes the project of the instance, because that is what a person
reads off a branch. Anything else becomes a search on `text ~`, which covers the
summary, the description, the comments and the text custom fields.

The results keep jira-cli's own ordering rather than relevance, so the picker's
matcher is what narrows them.

## 6. Tempo

Tempo is a separate product with a separate API and a separate token. On Jira
Cloud its worklogs and the native Jira worklogs are two different stores, so
`jira issue worklog add` writes a record the timesheet never shows. Only
`tempo.lua` feeds the timesheet.

Two lookups happen before anything is sent, and both are cached for good. One is
your account id, which `jira me` does not give. The other is the numeric issue
id, which version 4 of the API takes in place of the issue key.

A worklog names its issue by numeric id and nothing else. Reading a week
therefore resolves the keys with one batched Jira search, not one call per row.

## 7. Keys

Leader is `<Space>`. 21 keys under `<leader>j`, all listed by which-key.

No multi-key sequence sits under a key that is also a mapping of its own:
`ja`, `jc`, `jm` and `js` are prefixes and nothing else, so none of them waits
out `timeoutlen` wondering whether another key is coming.

| Key | Action |
|---|---|
| `jcs` | Current sprint board. |
| `jS` | Show a sprint report. |
| `jB` | Backlog. |
| `jmt` | My tickets in the sprint. |
| `jE` | Epics. |
| `jp` | Project issues, unresolved. |
| `jT` | Timesheet of the week. |
| `jf` | Find an issue by key or by words. |
| `jq` | Run a JQL query. |
| `jQ` | Re-run a query already used. |
| `jv` | View the issue. |
| `jW` | Web: open it in the browser. |
| `jsw` | Start working on an issue. |
| `jmi` | Move the issue to another state. |
| `jac` | Add a comment. |
| `jat` | Add a ticket. |
| `jas` | Assign the issue to anyone. |
| `jF` | Fields of the issue. |
| `jL` | Labels of the issue. |
| `jw` | Work logged in Tempo. |
| `jr` | Reload the issue view. |

						*which issue*
Which issue a key acts on, in order:

1. the key under the cursor.
2. the issue a link row names, from anywhere on that row.
3. the issue this buffer shows.
4. the issue in the branch name.
5. otherwise a picker opens.

The cursor comes first because pointing at something is the clearest way of
naming it. Reading one ticket and logging an hour against another it
mentions is an ordinary thing to want. There is no other way to say it. Every
prompt therefore names the issue it is about, so the choice is visible before
anything is written.

Editing the description, the summary and the links has no key on purpose. All
three are edited with `i` on the line that shows them. A key for each is a
second way to do what the first way already does.

In a `gitcommit` buffer the message is prefilled with the issue key of the
branch.

There are 21 `Jira*` commands for the same actions. `JiraGoto`, `JiraView`,
`JiraOpen` and `JiraStart` complete from the keys already listed this session.

## 8. Options

In `config.lua`:

- `cache_ttl`, five minutes for lists.
- `branch_prefix`, `start_work_transition`, `start_work_steps`. Each step of the
  start-work flow is a boolean: assign, sprint, transition, branch, yank.
- `commit_prefix`, whether an empty commit message is prefilled.
- `create`, per project, by field id. `defaults` is the value each field of a
  new issue opens with, `order` the rows that come first, `hidden` the rows
  never drawn. Nothing about which fields exist or which are required is in it,
  because createmeta answers that. An option default is written as the label
  you read, and resolved against the values createmeta reports.
- `hidden_fields`, the fields never worth a line. This instance carries 131
  custom fields and most belong to another team. Seeded with `Projet Commerce`,
  `Rank`, the Checklist fields and the service-desk fields.
- `daily_hours`, the fallback used only where Tempo gives no schedule.

## 9. Things that were wrong, and what they taught

These are worth keeping. Each one is easy to make a second time.

**`vim.NIL` is truthy.** Jira returns an empty field as JSON null, which
`vim.json.decode` turns into `vim.NIL`, which is userdata. Every
`fields.assignee and fields.assignee.displayName` guard therefore passed, then
crashed. Both decoders now pass `luanil`.

**Three names for one idea.** A person is `displayName`, an option is `value`, a
priority or a version is `name`. The renderer knew two of the three, so every
user field read as empty.

**`--no-input` is not general.** Only `issue edit`, `issue comment add` and
`issue create` take it. `issue assign`, `issue move`, `sprint add` and
`epic add` fail on an unknown flag.

**A transition is not a status.** This workflow has "To Test" landing on "To
Accept". Sending a status name is ambiguous where a transition id never is.

**A `string` is not always a string.** Jira types both a one-line box and a
whole rich-text area as `string`. Only `schema.custom` tells them apart. Sending
an Atlassian document through a one-line prompt printed the word `nil`.

**`issue list --raw` is not the API response.** It is jira-cli's own struct: no
numeric id, and the type is spelled `issueType`, against `issuetype` in
`issue view --raw`.

**The agile API caps a first page, three times over.** The backlog stopped at
200 of 364. The sprint list stopped at 50, oldest first, which hid every sprint
after `LIS 21`. Worklogs page the same way. Assume pagination on any agile
endpoint here.

**A sprint named `LIS-41` reads exactly like an issue key.** The heading line of
a list view had to be excluded from the key match.

**Single letters cost motions.** The first ticket buffer bound `e s l f c a o y
w t r`. That took six motions away in a buffer full of prose, and showed no
legend. Every view now carries a visible key legend.

**A dead end is worse than a menu.** `i` on a line holding no field used to
report "no field on this line". That is true and useless. It opens the issue
menu instead. For the same reason `i` answers on the board, where it once did
nothing at all while `<CR>` worked.

**A parameter has to live in the name.** Every view computed its result, found
no buffer, redirected through `:edit`, and threw the result away. The address
then loaded it a second time.

For the sprint report that lost the sprint id. The first pick always showed the
running sprint, and the second showed the right one. For the board and the
backlog nothing was lost, only time: the backlog made eight page requests in place of
four.

The buffer is now claimed before anything is fetched, and the sprint id travels
in the name.

**State that outlives its buffer is a surprise.** The timesheet kept its week in
a module variable. Closing the sheet while looking at November and reopening it
landed back in November, with nothing on screen saying why. A fresh sheet now
starts at this week.

**The same mistake was made again immediately.** A `jira://tempo/2026-09-07`
address added while fixing the above was itself an instance: the buffer lookup
matched only the exact name, so the dated buffer was never found. It was removed
rather than patched, because a week is not an identity. See |what belongs in a
name| in section 3.

**A read is not a write.** The progress spinner is started by the transport
rather than by each caller. It shows only for a method that changes something.
The
work was in the failure path. `cli.run` called back only on success, so a failed
save left the spinner turning for ever. It takes a `finally` now.

**Nvim already has a shape for most of this.** Following a link is a jump, so
it is `gd` and `<C-]>`. Coming back is `<C-t>`, the tag stack. Sending a list
somewhere is `<C-q>` and the quickfix list. That then works with `:cnext`,
because the entries are `jira://` addresses.

Buffer-local options belong in an ftplugin. Documentation belongs in `doc/` with
tags. None of it is decoration: each one replaced something hand-made that did
less.

## 10. Setting it up

Two shell variables have to be exported, not merely set. In fish,
`set NAME value` creates a variable no child process ever sees, which is why
`jira` first reported no API token at all:

```fish
set -gx JIRA_API_TOKEN "..."
set -gx TEMPO_API_TOKEN "..."
```

The first comes from `id.atlassian.com`, the second from the Tempo API
integration page. Both sit in clear text in `config.fish`. A separate file with
mode 600 is safer.

Then `:checkhealth qss_nvim.jira` reports on jira-cli, curl, both tokens, the
instance and snacks. It also names the 10 custom fields that share a name with
another one.

## 11. How it was checked

Headless, against the live instance, with `pcall` and a file for the result: a
raised error in headless mode hangs on a message prompt.

- Every module loads, with 21 keys and 21 commands registered.
- Every address opens the right view on the first try, `jira://sprint/3697`
  included, and a wrong one says so rather than guessing.
- The requests made on a first open are counted, not assumed: six for the
  backlog, two for the board.
- Reads: sprint query, epics, transitions, sprints, backlog, custom fields,
  comments, Tempo worklogs, burndown, sprint report.
- Writes, on the test ticket `LIS-2431`: assign, transition, comment, summary,
  labels, description, a custom field, sprint, epic, unassign.
- More writes on the same ticket: a Tempo worklog, a link created and cut again,
  a comment edited in place.
- `:help jira` and its tags resolve.
- `lua-language-server --check` over the whole configuration: no problems found. Point
  it at the root of the configuration, never at a subdirectory. Otherwise
  `.luarc.json` is not picked up, and every `vim` use is reported as undefined.

`JiraCreate` was checked without making a ticket: the POST is replaced by one
that records the body it was given, and the body is compared against the shape
Jira takes. Nine checks, all passing:

- every module loads, and 21 commands are registered.
- `jira://new/10001` draws the Story form, with `Track` defaulted and the
  hidden fields gone.
- `jira://new/1` marks `Reporter` and `Bug Origin`.
- `jira://new/99999` says the type is unknown.
- the create screen is read once and then remembered.
- an empty `Summary` stops the create, and is named.
- a filled form builds
  `{"fields":{"project":{"key":"LIS"},"issuetype":{"id":"10001"},"summary":…,"customfield_11912":{"id":"11600"}}}`.
- editing an existing issue still goes through `ask` and then `write`.

The one path left to a person is the last one: pressing `<C-s>` for real, which
makes a ticket.

That first run found a bug worth keeping here. **A view is unmodifiable
between draws.** The form set `modifiable` to false, then wrote its "asking
Jira…" line straight into the buffer. Every path that puts a line in a view has
to say so, so there is one writer now and no caller that forgets.

`LIS-2431` was left renamed, labelled `neovim, throwaway`, and under epic
`LIS-2339`.
