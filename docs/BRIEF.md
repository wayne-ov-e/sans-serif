# To-do app: build brief for Claude Code

Nov 16, 2026 · @Wayne

## Summary

This brief gives Claude Code what it needs to build a minimalist to-do app for iPhone, iPad, and Mac. The app is a page of plain text tasks that you cross off with a pen line, as you would on paper.

The one idea: clean serif type, with the hand-drawn strike as the only human mark on screen. There are no checkboxes, buttons, or tab bars. Every screen is text on paper.

Twelve frames are designed in Figma: six core screens, five first-run steps, and a long task example. Several behaviours are still undecided and are listed under Open questions. Settle those marked as blocking before starting the related build step.

## Start here in Claude Code

1. Create an empty folder for the project and open Claude Code in it.
2. Export this brief as Markdown and save it in the folder as `docs/BRIEF.md`.
3. Connect the Figma file, so Claude Code can read the frames.
4. Answer the five blocking items under Open questions, and write the answers into the brief.
5. Give Claude Code the first prompt below, then work through the build order one step at a time.

The Figma file is [Untitled](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=0-1), file key `YqJ7UOXeabYt4WDIXFP0KW`. The Screens section links every frame.

**First prompt**

```markdown
Read docs/BRIEF.md in full before doing anything.

This is a native SwiftUI to-do app for iPhone, iPad, and Mac. The brief is the source of truth for decisions, and the Figma file linked in it is the source of truth for layout.

Do step 1 of the build order only: project setup, colour and type tokens, and the paper background with system safe areas. Build the page column so it adapts to width from the start.

Before writing code, tell me your plan, anything in the brief that is unclear or contradictory, and anything you want to check in Apple's current documentation. Stop after step 1 so I can run it.
```

**Rules for the whole build**

- One build step per session. Run the app on a device after each.
- When the brief and Apple's current documentation disagree, the documentation wins. Note the change in the brief.
- Do not add features, settings, or visible controls that are not in the brief.
- Items under Not designed yet need a design or an explicit decision before they are built.

## Decisions made

| Area | Decision |
| --- | --- |
| Platforms | iPhone, iPad, and Mac, built natively for Apple systems. One layout adapts to the space available. See Layout by device. |
| Font | New York, Apple's system serif. Use the system serif design in code. Do not bundle the font file. |
| Completing a task | Drag across it to strike it. It holds for about a second, then leaves for the archive. Drag back across it during that second to undo. |
| Adding a task | Tap the empty paper below the last task and type. Return starts the next task. |
| Lists | Named by the user, such as life, work, home. Lists are permanent and do not reset each day. Shown as plain text names at the bottom of the screen, near the thumb. |
| Counts | A small raised number after each list name shows tasks left. A setting turns it off. |
| Archive | One per list. Opened by dragging up. Kept forever. The current month is open, and past months fold into one line each. |
| Settings, as built in step 7 | Built Nov 17, 2026, not yet confirmed by Wayne: dragging the page about 64 pt past its top brings the four lines down from the top edge and pushes the page down, blurred and faded, as in Figma frame 04. Drag across a line to strike it off and back across it to turn it on. Dragging up, tapping the blurred page, or tapping a list name puts settings away. VoiceOver reaches settings through a "Show settings" action on each list name, and each line is a toggle. Not built yet: the Gestures, Privacy, and Contact lines (they need the first-run page, a policy URL, and a contact address), Cmd+comma on Mac (step 9). iCloud sync is stored but does nothing until step 10. Dark paper is stored but does nothing until it has colour values. |
| Bundle ID and icon | Decided by Wayne, Nov 17, 2026: the bundle ID is app.sans-serif, under his individual team, and the app name is sans-serif, all lower case. The icon, as asked for by Wayne on Nov 17, 2026 after five earlier tries: a stand-in. It reads "temporary logo" on two lines, small, in the page's serif in ink on paper. The app has no real icon yet. It has light, dark and tinted versions, drawn by `docs/icon/icon.swift`. No Mac sizes yet. |
| Crash in build 5, and tests | Nov 17, 2026. Build 5 stopped on Wayne's phone right after the first page. Most likely cause, from reading the code and not from a crash log (TestFlight had none): the Core Haptics engine's stopped and reset handlers were written inside a main-actor method, so the system calling them from its own thread stopped the app. The simulator has no haptics and never showed it. Fixed in build 6 by making the handlers nonisolated. Not confirmed on a device. Tests added the same day: the pull logic is now plain data (`PullTracker`) with unit tests, including the false pull found earlier; unit tests for finishing the guide, the drag ticks, the pen haptics being safe to call, and the setting defaults (33 unit tests). A UI test target (`UITests/WalkthroughTests.swift`) walks the first page to begin and then the page: writing, editing, striking and undoing, the archive, turning lists from the bottom only, both menus, delete, move, and every settings line. It launches with `-inMemoryStore`, which also resets settings. Not covered by any test: haptics on a device, reordering, renaming or deleting a list, Mac and iPad, VoiceOver. The hold before a task's menu opens is shorter: about 0.6 s in all (0.35 s to lift, 0.25 s more). Wayne is not happy with how that menu appears; to be revisited. |
| iCloud sync, as built in step 10 | Built Nov 17, 2026. Not tested between two devices. With the iCloud sync line on, lists and tasks are stored with SwiftData in the private database of the container `iCloud.app.sans-serif` (created by Claude in the developer portal with Wayne's go-ahead; iCloud with CloudKit and Push Notifications are on for the app ID). The setting is read at launch, so a change takes effect the next time the app opens. If the store cannot open with iCloud it opens without, so sync can never stop the app from launching. Each device makes life, work and home on its first launch; when two devices meet, the later copy of each is folded into the earliest, tasks and archive included, at launch and whenever changes arrive. Lists the user named are never merged. Known gaps: the lines of the first page are archived once per device, so they can appear twice; settings stay per device; there is no sign of offline, syncing or errors. TestFlight builds use the production side of iCloud, which has no record types until the schema is deployed from the CloudKit Console . To create it: run a development build once on a device signed in to iCloud with the launch argument `-initCloudKitSchema`, then press Deploy Schema Changes in the console. Not done yet: the simulator and this Mac are not signed in to iCloud, so build 8 runs but does not sync. Sharing (step 11): Apple's forums say SwiftData cannot share with other people, so the plan is a Core Data layer on the same store. |
| Changes after the first TestFlight build | Built Nov 17, 2026 at Wayne's request, checked on the iPhone simulator only. **Pulls:** a page that fits no longer scrolls under the status bar (it used to move 62 pt before a pull up counted). A pull counts after 40 pt with the finger down, or 14 pt when it is a quick pull that began at the edge. With settings down, any drag up of 20 pt puts them away. One drag does one thing (Wayne found, Nov 18, 2026, that the drag which put settings away went on to open the archive): a pull counts only if it was on offer when the finger came down. **Switching lists:** a sideways swipe turns the page only when it starts at the bottom, on the list names or the paper just above them; higher up a sideways drag only strikes. The incoming page covers the swap at the end of a turn, to stop a blink Wayne saw; the blink itself was not reproduced. On Mac the two-finger swipe still works anywhere. **Striking several:** struck tasks leave together, a hold after the last strike, and none leaves while a finger is crossing a task, so lines do not move under the finger (not proven in the simulator). **Done:** while the keyboard is up, the word "done" stands where the list names were and puts the pen down. **Settings:** a tap on a line strikes it or turns it on; dragging still works. A fifth line, Gestures, replays the first page. **Dark paper:** on by default and follows the system. The colours flip: paper #1C1B19, ink #F4F1EA, faded ink #9C968B, red #E07A6A (the last two proposed by Claude). The strike uses a screen blend on dark paper. **Haptics:** a strike is felt during the drag, not at its end (Wayne, Nov 17, 2026). On iPhone it is one continuous texture (`PenHaptics`, Core Haptics): a firm landing, a rumble that follows the speed of the hand and smooths toward the end of the line, one crisp click where letting go starts to count, a flick on the lift, and a small tap for each further line of a long task. A drag let go too early ends in one soft tap. Where that cannot play (iPad, Mac) it falls back to a heavy tap on landing and six along the line. The same for undoing by drag and for settings lines. A swipe to another list ticks where letting go will turn the page.  Tuned by Wayne on Nov 18, 2026. Moving between views is one short, crisp haptic at the instant the change is asked for (a tap on a list name, a swipe let go, a pull that counts), over in about a tenth of a second, with nothing after it. The strike keeps its shape but is weaker, the drag most of all: landing 0.7, drag 0.12 to 0.42 by speed, commit click 0.8, lift 0.25 to 0.6. Every single tap is light: menu, pick up, put down, delete, copy, page edge. The delete-list question keeps the system warning. Taken out as noise: the archive and settings coming and going, a month folding. A strike made without a drag is one light tap. Also: undo a strike without a drag (soft), menu open, line picked up (medium), each place passed (selection), line put down, task deleted or moved away, list deleted, the question before deleting a list (warning), copy (success), turning to a list (selection), archive and settings coming or going (soft), a turn past the first or last list (rigid), a month folding (selection). All obey the Haptics setting. Not felt on a device yet. **Motion:** named springs in `Design/Motion.swift`: sheet, turn, settle, shuffle, quick. The pen keeps its own timing. **First run:** built from frames 07 to 11 as its own page (`GuideView`), shown until begin or skip, and again from Gestures. Lines: cross, write, hold, swipe, pull up, pull down, end. "Circle what matters." is left out until the circle gesture exists. The swipe line now reads "Swipe along the bottom for the next list." (wording by Claude), with its guide beside skip. The pulls show a real archive of the struck lines and the real settings. After begin, the first time, the struck lines go to the first list's archive; the user's own task goes to the first list either way. Not built: shortcuts beside each line on Mac. The begin path and VoiceOver actions were not run. |
| Widgets and the Live Activity, as built in step 12 | Built Nov 18, 2026 at Wayne's request, before shared lists. Checked on the iPhone simulator only: the Live Activity on the Lock Screen, a tap there striking a task, and the settings line. The Home Screen and Lock Screen widgets were not looked at on a device or in the simulator. **Live Activity is back** (Wayne, Nov 18, 2026): this overrides "Widgets replace the Live Activity" below and the App Review row that says none is used. During working hours the open list lies on the Lock Screen and in the Dynamic Island: up to three tasks, the list name and count, and a tap on a task strikes it. Working hours are Monday to Friday, 9 to 5 by default (weekdays only is Claude's choice). **Limits set by the system:** an app can start a Live Activity only while it is open, so it starts when the app is used during working hours; from iOS 26 the app also books the next working day's start each time it is used, and that one arrives with the system's alert sound, which cannot be turned off. Nothing can end it on the hour without the app running: it is marked stale and dims at the end, the app ends it the next time it runs, and the system removes it after eight hours at most, so hours longer than eight are cut short. **Settings:** a sixth line, Work hours (iPhone and iPad), struck to turn it off, with the hours under it as words, "9 AM to 5 PM". A tap on an hour brings up the number keys and the hour is typed (Wayne, Nov 18, 2026: tapping through the hours was too much work); one key is enough for most hours, and on a twelve-hour clock a typed end means the first such hour after the start, so 5 after a 9 AM start is 5 PM. A drag across an hour still runs through the hours. The end always stays after the start. **Widgets:** one widget, List, in small, medium and large for the Home Screen and rectangular, circular and inline for the Lock Screen. Editing it picks the list. Tasks are one line each, a tap strikes one with the same pen line and a second tap undoes it; the struck line leaves after about 2.5 s. Task text is marked privacy sensitive. A tap elsewhere opens the list (`sansserif://list/<id>`). **Data:** not the same store through an app group, as first planned. The app writes a small snapshot of each list (first eight lines and the count) to the app group `group.app.sans-serif`, and a strike made outside the app is queued there and taken into the store when the app next runs (at once for the Live Activity, whose taps run in the app). This avoids moving the store and a second process writing to a store that syncs. The cost: a strike made in a widget reaches other devices only after the app has run. **Not built:** Mac desktop widgets, the circle gesture and circled tasks first, the accessibility pass. |
| iPad and Mac, as built in step 9 | Built Nov 17, 2026. On the iPhone simulator nothing regressed, and the iPad simulator shows the 600 pt centred column in portrait. Nothing else here has been run: the Mac build compiles and launches but was not driven, and no hardware keyboard, trackpad or Apple Pencil was available. Menu bar and keyboard: Cmd+1 to 9 turn to a list, Cmd+comma opens and closes settings, and typing with nothing selected starts a task on the empty line. Escape puts away a menu, the cursor, settings or the archive, one at a time. Pointer: a right click, or Control and click, on a task or a list name opens its menu; a two-finger swipe to the side on a trackpad turns the page and follows the fingers; click and drag across a task strikes it. Apple Pencil: the mean pressure of the drag sets the thickness of the first line, between 0.7 and 1.8 times the nominal width. Proposed by Claude and not confirmed: a List menu in the menu bar holding the list names, Show Archive on Shift+Cmd+A, and Strike Task on Cmd+D; Strike Task strikes the task the cursor is in, because no selected-task state is designed. Not built: Scribble handwriting on the empty paper, pressure that varies along one line, a two-page iPad landscape, arrow keys moving between tasks. |
| Menus, as built in step 8 | Built Nov 17, 2026. Wayne confirmed the task menu matches the list menu's plain-text style. Task menu, changed the same day at Wayne's request: hold a task still and the menu opens under the finger after about three quarters of a second, without lifting; moving the finger before then reorders instead. The menu floats over the page beside the task, to the right of its text, and nothing on the page moves. When the text leaves no room beside it the menu shows below the task, on its left edge (Wayne, Nov 17, 2026), and near the bottom of the page it grows upward. Its lines: Move to (the other lists, in the same menu), Copy, Delete in red. Edit was removed the same day at Wayne's request as redundant: a tap on the task already edits it. Delete has no confirmation and is undone with a shake or Cmd+Z. List menu: hold a list name. The menu grows upward from it, as in Figma frame 05: Rename (the name is rewritten in place, above the keyboard) and Delete list in red, which then asks "Yes, delete" or "Keep". The last remaining list cannot be deleted. A tap on the blurred page puts a menu away. Not built yet: Share list (step 11), right click on Mac (step 9), creating a list (open question). Proposed by Claude and not confirmed: the Move to submenu and the delete wording. |
| Archive, as built in step 6 | Built Nov 17, 2026, not yet confirmed by Wayne: dragging the page about 64 pt past its end opens the archive, which comes up from the bottom edge; dragging the archive down past its top goes back. A short page now gives a little when pulled, so the pull can be felt. Tapping a month opens or folds it. Dragging back across a struck task, right to left, restores it to its old place on the page. Tapping any list name leaves the archive. An empty archive is blank paper. VoiceOver reaches the archive through a "Show archive" action on each list name. |
| Settings | Opened by dragging down. Four toggles as lines of text: Show counts, iCloud sync, Haptics, Dark paper. App Store rules add three more lines that open pages: Gestures, Privacy, Contact. Striking a line turns it off. The page below blurs. |
| Task menu | Long press a task for edit, move to, copy, delete. |
| Reordering | Hold a task to pick it up, then drag it up or down to a new place in the list. |
| List menu | Long press a list name for Rename, Share list, Delete list. The menu is plain text growing from the name, with the page blurred. Delete is in red ink. |
| Sync | iCloud sync is required. |
| Shared lists | A list can be shared by sending an invite link through Messages or Mail. |
| Page length | A list scrolls when it has more tasks than fit one screen, so the number of tasks is not limited. At the end of the list, dragging up again opens the archive. Decided by Wayne, Nov 17, 2026. |

## Screens

The Figma file is the source of truth: [Untitled in Figma](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=0-1). An earlier draft is on the [preview canvas](https://claude.ai/artifact/RVxvDucSrZLid2czPt29gL).

| Frame | Size | Shows | Used by build step |
| --- | --- | --- | --- |
| [01 Page](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=1-2) | 402 x 874 | The life list with six tasks and the list names at the bottom. | 1, 3, 5 |
| [02 Struck](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-47) | 402 x 874 | Two tasks crossed off in faded ink. Counts drop from 6 to 4. | 4 |
| [03 Archive](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-83) | 402 x 874 | November 2026 open with five struck tasks. Three earlier months folded. | 6 |
| [04 Settings](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-135) | 402 x 874 | Four settings at the top, one struck. The page and list names blurred below. | 7 |
| [05 Share list](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-173) | 402 x 874 | Long press menu above the home list name. The rest of the page blurred. | 8, 11 |
| [06 Mac window](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-202) | 560 x 640 | The work list in a small window with rounded corners and window controls. | 9 |
| [07 First run: Cross off](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-43) | 402 x 874 | The first line with a dotted guide across it, and skip at the bottom. | 12 |
| [08 First run: Write](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-60) | 402 x 874 | Line one struck, the second line, a cursor, and a dotted tap ring. | 12 |
| [09 First run: Circle](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-83) | 402 x 874 | The user's own task, and a dotted loop around the third line. | 12 |
| [10 First run: Pull up](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-117) | 402 x 874 | A circled task in ink, five struck lines, and a dotted path rising. | 12 |
| [11 First run: Begin](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-162) | 402 x 874 | Every line struck, the closing line, and begin at the bottom. | 12 |
| [12 Long task](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=27-38) | 402 x 874 | Two tasks that wrap to two lines. One is struck line by line. | 3, 4 |
| [List tab component](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-19) | Component | Active and Inactive states with Name, Count, and Show count properties. | 5 |

**How this brief links to Figma**

- Every frame name above is a link that opens that frame. The frame names in Figma match the names used in this brief.
- Each section below that has a design starts with a Figma line naming its frames.
- The colour variables and text styles in the file use the same names as the tokens in Design tokens.
- A section with no Figma line has no design yet. Check Not designed yet before building it.

The file also holds a List tab component with Active and Inactive states and three properties: Name, Count, and Show count.

In Claude Code, connect the Figma file and read each frame before building its view. Treat the Figma layout as a reference for spacing and type, and build with native SwiftUI layout.

## Interaction model

Figma: [01 Page](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=1-2), [03 Archive](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-83), [04 Settings](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-135), [05 Share list](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-173).

Six gestures cover the whole app, and each has a Mac equivalent. iPad uses the iPhone gestures by touch and the Mac ones with a keyboard and trackpad. A seventh gesture, circling a task, puts it first in the widgets and is described under Widgets.

| Action | iPhone | Mac |
| --- | --- | --- |
| Strike a task | Drag across the task | Click and drag across it, or a keyboard shortcut on the selected task |
| Undo a strike | Drag back across it, right to left | Same, or Cmd+Z |
| Add a task | Tap empty paper, then type | Start typing |
| Switch list | Tap a list name, or swipe sideways along the bottom of the page | Click a name, two-finger swipe, or Cmd+1, 2, 3 |
| Open archive | Drag up on the page | Scroll up past the page edge |
| Open settings | Drag down on the page | Cmd+comma, with scroll down as a second route |
| Open a menu | Long press a task or list name | Right click |

**Conflict rules**

- Strike and switch list are both horizontal. A swipe that starts on a task strikes it. A swipe on empty paper or on the list names switches lists. Built this way in step 5 (Nov 17, 2026): swipe left for the next list, right for the one before, no wrap at either end, and no switching while writing or carrying a task. Changed the same day at Wayne's request so it feels like turning a page: the page follows the finger with the next list beside it, pales as it leaves, and finishes the turn when let go past about a third of the width or flicked; short of that it settles back. Past the first or last list the page gives a little and returns. Tapping a list name plays the same turn. With Reduce Motion the new page fades in instead. Wayne said to start step 5 on this rule; treat it as accepted unless changed after trying it on a device.
- The drag down must start below the top edge, which belongs to Notification Centre.
- The drag up must start above the home indicator.
- A list that fits one screen does not scroll, so a vertical drag on it has only two meanings: up for archive, down for settings. A longer list scrolls first. Dragging up at the end of the list opens the archive. Dragging down at the top of the list opens settings in the same way. Confirmed by Wayne, Nov 17, 2026.

**Deleting**

Delete removes a task with no trace in the archive. Use undo instead of a confirmation: shake on iPhone, Cmd+Z on Mac. Deleting a list asks for confirmation, because it removes the tasks and the archive.

## First run

Figma: [07 Cross off](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-43), [08 Write](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-60), [09 Circle](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-83), [10 Pull up](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-117), [11 Begin](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=26-162).

The first page teaches the app by being a to-do list about itself. Each line is an instruction, and doing what it says crosses it off. There are no overlays, arrows, or pop-ups.

**The lines, in order**

| Step | Line on the page | The user does | What the guide shows |
| --- | --- | --- | --- |
| 1 | Cross me off. | Drags across the line | A dotted path across the text |
| 2 | Tap below and write your own. | Taps the empty paper and types a task | A cursor on the next line and a dotted ring |
| 3 | Circle what matters. | Draws a loop around the line | A dotted loop around the text |
| 4 | Hold a line for more. | Long presses, then dismisses the menu | A dotted ring on the line |
| 5 | Swipe for the next list. | Swipes sideways on empty paper and comes back | A dotted path across the lower page |
| 6 | Pull up for what is done. | Drags up, sees the archive, returns | A dotted path rising from the lower page |
| 7 | Pull down for settings. | Drags down, sees settings, returns | A dotted path falling from the upper page |
| End | That is all. The page is yours. | Taps begin | Nothing |

**The guide marks**

- A guide is pencil, not ink: a small faded dot where the finger lands and a dotted path to follow. It uses the faded ink colour.
- The dot pulses once and the path draws itself once, then both rest. If the user waits five seconds, they play again.
- When the user starts the gesture, the guide fades and real ink takes over.
- Only one guide is on screen at a time.

**How it flows**

- Lines appear one at a time. Completing a line strikes it and writes in the next, as if being written by hand.
- Struck lines stay on the page, so the page fills like a finished list.
- The task the user writes in step 2 stays live and is carried into their first list.
- The bottom of the page shows "skip" in faded italic where the list names will be. At the end it becomes "begin" in ink.
- Tapping begin sends the struck lines to the archive, and the list names fade in. The user's first lists are life, work, and home, and can be renamed.
- Skip goes straight to the empty first list.
- The Gestures line in settings replays this page at any time. This also satisfies Apple's rule that gestures be documented in the app.

**Other input**

- Mac: the lines read the same, and the guides show the pointer gesture. Keyboard users see the shortcut beside each line.
- VoiceOver: each line is read with its action, and each step can be completed through the action menu.
- Reduce Motion: guides appear without drawing or pulsing.

Steps 4, 5, and 7 follow the same pattern and have no frame yet.

## Design tokens

Figma: variables and text styles in the [file](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=0-1), and the [List tab component](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-19).

These match the variables and text styles in the Figma file.

**Colours**

| Token | Value | Use |
| --- | --- | --- |
| paper | #F4F1EA | Screen background |
| ink | #1C1B19 | Tasks, active list name, strikes |
| ink-faded | #6F6A60 | Struck tasks, inactive list names, archive text, month labels |
| ink-red | #8E2A1E | Delete actions only |

Dark paper flips the two main colours: paper #1C1B19 and ink #F4F1EA, with faded ink #9C968B and red #E07A6A. Built Nov 17, 2026; the faded and red values are proposed and not confirmed.

**Type**

All text is New York. Line height is 125 percent.

| Style | Size | Use |
| --- | --- | --- |
| Task | 25 pt | Tasks and settings lines on iPhone |
| List name | 20 pt | List names and menu options |
| Count | 12 pt | Raised number after a list name |
| Month label | 16 pt italic | Archive month headings |
| Mac/Task | 21 pt | Tasks on Mac |
| Mac/List name | 17 pt | List names on Mac |

Map these to Dynamic Type text styles so they scale with the user's setting.

**Spacing on iPhone (402 x 874)**

| Measure | Value |
| --- | --- |
| Side margins | 32 pt |
| Top safe area | 62 pt. Content starts at 96 pt. |
| Bottom safe area | 34 pt. List names sit 48 pt from the bottom edge. |
| Gap between tasks | 26 pt |
| Gap between list names | 24 pt |
| Touch height for names and menu options | 44 pt minimum |

Read safe areas from the system at run time. The numbers above are for the design frame only.

**Blur**

When settings or a menu is open, the rest of the page is blurred and faded to about 60 percent.

The same blur applies where a long list scrolls underneath the list names: the list runs to the bottom edge, and tasks passing under the names are blurred and faded instead of being cut off by a solid strip. Decided by Wayne, Nov 17, 2026.

## Layout by device

Figma: [01 Page](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=1-2) for iPhone portrait and [06 Mac window](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-202) for Mac. iPad and iPhone landscape have no frames yet.

The app runs on iPhone, iPad, and Mac from one layout that adapts to the space it is given. Drive the layout from available width and size class, never from the device name, so split view and resized windows work without special cases.

**The rule**

The page is a single column of text, like a sheet of paper. On narrow screens the column fills the width inside the margins. On wide screens the column stops growing at a comfortable reading width and sits centred, with empty paper on both sides. The list names always sit at the bottom of that column, on its left edge.

| Context | Width | Column | Margins | Task size | List names |
| --- | --- | --- | --- | --- | --- |
| iPhone portrait | 375 to 440 pt | Full width | 32 pt | 25 pt | Bottom, 48 pt from the edge |
| iPhone landscape | 667 to 956 pt | Capped at 560 pt, centred | Safe area plus 32 pt | 25 pt | Bottom of the column |
| iPad split view or Slide Over, narrow | Under 500 pt | Full width, same as iPhone | 32 pt | 25 pt | Bottom |
| iPad portrait | 744 to 1032 pt | Capped at 600 pt, centred | At least 64 pt | 28 pt | Bottom of the column |
| iPad landscape | 1024 to 1376 pt | Capped at 600 pt, centred | At least 64 pt | 28 pt | Bottom of the column |
| Mac window | 360 pt minimum, resizable | Capped at 560 pt, centred | 44 pt | 21 pt | Bottom of the column |

The widths are approximate ranges for current devices. The column caps and type sizes are proposals to tune on real hardware.

**What changes with space**

- Tasks per page. The page holds as many tasks as fit the height. A taller screen fits more. This ties to the page length question under Open questions.
- Archive and settings. They use the same column and the same drags on every device.
- Menus. The text menu grows from the item that was held, on every device.
- Blur. It covers the whole window, including the empty paper beside the column.
- Rotation and resizing. The column reflows live, with no jump and no loss of an in-progress strike or edit.

**iPad specifics**

- All orientations, split view, Slide Over, and Stage Manager windows are supported.
- Apple Pencil strikes a task with real pressure driving the line width. Handwriting in the empty space adds a task through Scribble.
- A hardware keyboard and trackpad use the Mac shortcuts and pointer gestures.
- Touch gestures are the same as iPhone.

**Mac specifics**

- The window has a minimum size of about 360 x 480 pt and remembers its size and position.
- The title bar is hidden. The list names act as the title.
- Text does not scale with window width. A wider window shows more empty paper.

## The strike

Figma: [02 Struck](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-47) for single lines, [12 Long task](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=27-38) for wrapped tasks, and [03 Archive](https://www.figma.com/design/YqJ7UOXeabYt4WDIXFP0KW/Untitled?node-id=11-83) for faded strikes.

The strike is the app's signature and deserves the most care. It should look like a confident pen line: natural but affirmative, with an ink feel.

**How it looks**

- One nearly straight line with a slight tilt. It may rise, fall, or sag a little.
- It lands with a small rounded start, swells just after landing, thins through the middle, and tapers to a point on the lift.
- It overshoots the text by 4 to 13 pt on each side.
- It sits at the middle of the lowercase letters.
- It has a soft edge where ink bleeds into paper, and a darker pool at the start.
- It darkens where it crosses letters, as wet ink does. In Figma this is a multiply blend.
- No two strikes look the same.

**How to build it**

1. Draw the line as a filled path that follows the user's drag, so each strike comes from the gesture.
2. Smooth the raw touch points into the tapered shape described above. Vary width along the stroke using speed or a fixed pressure curve.
3. Animate the line following the finger. Commit when the drag passes most of the text width. Cancel and retract if it stops short.
4. For strikes made by keyboard or VoiceOver, generate a line from a seeded random variation of tilt, weight, and overshoot.
5. Store the stroke shape or its seed with the task, one per line of text, so the same line appears in the archive and on other devices.
6. Fire a light haptic when the strike commits, if Haptics is on.

The Figma file has six reference strikes as editable vectors. A later option is to scan real pen strokes and use them as the source shapes.

**Struck state**

The task text turns to faded ink. On the live page the line is ink black. In the archive the line is faded ink.

**Tasks longer than one line**

A long task wraps onto a second line, and the strike crosses it off line by line. Each line of text gets its own pen line. One line never runs through both.

- One drag across any part of the task completes it. The pen draws through the first line, lifts, then draws through the second, top to bottom.
- Each line's stroke is sized to that line's text. The last line is usually shorter, so its stroke is shorter.
- The strokes differ from each other in tilt, weight, and overshoot, like two separate passes of a pen. Frame 12 Long task shows this.
- The second stroke starts as the first one ends, so the whole strike still takes well under a second.
- Undo lifts the lines in reverse order, last line first.
- Text wraps at word boundaries inside the column. Wrapped lines keep the 125 percent line height, and the gap between tasks stays larger than the gap between lines so tasks remain distinct.
- Limit: three lines per task. Longer text is cut with an ellipsis on the page and shown in full when editing.
- A wrapped task takes two lines of the page, so fewer tasks fit on one screen.
- Store one stroke shape or seed per line.
- In widgets a task shows on one line and is cut if it is too long, with a single stroke.
- With Reduce Motion, all the lines appear together.

One gesture strikes the whole task. Confirmed by Wayne, Nov 17, 2026.

## Widgets

Figma: no frames yet. Widgets are listed under Not designed yet.

The app offers widgets in several sizes for the Home Screen, the Lock Screen, and the Mac desktop. Tapping a task in a widget strikes it without opening the app. Widgets replace the Live Activity from the earlier draft, so the eight-hour limit no longer applies.

**Sizes**

| Size | Where | Shows | Tap |
| --- | --- | --- | --- |
| Small | iPhone, iPad, Mac | The list name and up to 3 tasks | A task strikes it |
| Medium | iPhone, iPad, Mac | The list name, its count, and up to 4 tasks with room for longer text | A task strikes it |
| Large | iPhone, iPad, Mac | The list name, its count, and up to 9 tasks | A task strikes it |
| Extra large | iPad. Check whether the Mac offers it. | Two lists side by side, like an open notebook | A task strikes it |
| Lock Screen, rectangular | iPhone, iPad | Up to 2 tasks in one colour | Check whether a task can be struck here. If not, the tap opens the list. |
| Lock Screen, circular | iPhone, iPad | The number of tasks left | Opens the list |
| Lock Screen, inline | iPhone, iPad | The next task as one line | Opens the list |

The task counts per size are proposals to tune once real text is in place.

**How a widget behaves**

- Each task is its own tap target. Tapping it strikes it: the text fades and the pen line appears.
- A struck task stays visible, struck, until the widget next refreshes. Then it leaves for the archive. Tapping it again before that undoes the strike.
- Tapping the list name or the empty paper opens the app at that list.
- An empty list shows its name on blank paper.
- A widget cannot follow a finger, so there is no drag to strike here. The line is drawn for the user. Keep the same stroke shapes as the app.

**Choosing what a widget shows**

- Editing the widget lets the user pick the list it shows. Several widgets can show different lists.
- Circled tasks come first. Circling a task in the app, by drawing a loop around it, marks it as the one that matters and moves it to the top of every widget for its list. Circle it again to clear the mark. The circle was approved as the Live Activity gesture and is carried over here, so confirm it still belongs.
- After circled tasks, the widget shows tasks in list order.

**Appearance**

- Paper background, New York type through the system serif, and ink colours, matching the app.
- Text sizes follow the app's styles: Task for large sizes, List name for small ones.
- The system can recolour widgets, for example tinted or clear Home Screen styles and the single-colour Lock Screen. Each widget must stay readable in every rendering mode, and the strike must stay visible.
- Dark paper applies when the system is in dark mode.

**Privacy**

Lock Screen widgets show task text on a locked device. Mark task text as privacy sensitive so the system can hide it when the device is locked, according to the user's settings.

**How to build it**

- A WidgetKit extension with one widget that supports every size above, and a layout per size.
- An App Intent behind each task, so a tap strikes it without opening the app. Apple's guidance is that a widget button should do more than open the app, and this does.
- A configuration intent for choosing the list.
- The same data store as the app, shared through an app group.
- The app asks the system to reload widgets after every change. Changes that arrive from another device through sync appear when the system next refreshes the widget, so a short delay is normal.
- On the Mac, widgets sit on the desktop and in Notification Centre.

Sizes and tap support are from Apple's WidgetKit documentation and secondary sources. Have Claude Code confirm the current list of sizes per platform before building.

## Data model and sync

The model is small: lists hold tasks, and a task is either live or struck.

| Entity | Fields |
| --- | --- |
| List | id, name, order, created date, shared or private |
| Task | id, list, text, order, created date, struck date (empty while live), stroke shape or seed, struck by (for shared lists) |
| Settings | show counts, haptics, iCloud sync, dark paper |

**Rules**

- A live task has no struck date. Striking sets the date and moves the task to the archive after the one-second hold.
- Restoring a task from the archive clears the struck date.
- The archive is a query: tasks in a list with a struck date, grouped by month, newest first.
- The count beside a list name is its number of live tasks.
- Deleting a task removes the record. Deleting a list removes its tasks and archive.

**Sync and sharing**

iCloud sync and shared lists point to CloudKit, which supports private data and shared records with invite links. The suggested approach is SwiftData or Core Data with CloudKit, using CloudKit sharing for shared lists. This is a suggestion from general knowledge, so check Apple's current documentation before committing to it.

Settings can sync through iCloud key-value storage or stay per device. That is undecided.

The app must work offline and merge changes when it reconnects.

## Architecture and build order

Build one SwiftUI multiplatform app for iPhone, iPad, and Mac with a shared core, plus a widget extension. Keep the model, the strike renderer, and the list logic in shared code. Keep gestures and window setup per platform.

**Before starting**

- Xcode with an Apple developer account, needed for iCloud capabilities.
- The Figma file connected to Claude Code, so it can read frames and tokens.
- This brief in the repository, for example as a docs file that the project instructions point to.

**Build order**

1. Project setup. Create the multiplatform project, the colour and type tokens, and the paper background with system safe areas.
2. Local model. Lists and tasks stored on the device, with no sync yet.
3. The page. Show tasks as text, add by tapping empty paper, edit in place.
4. The strike. Gesture, path drawing, commit and cancel, the one-second hold, and undo. Get this right on a real device before moving on.
5. List names. The bottom row, switching by tap and swipe, counts, and the gesture conflict rule.
6. Archive. Drag up, grouping by month, folded months, and restore.
7. Settings. Drag down, the four lines, strike to turn off, and the blur.
8. Menus. Long press on tasks and list names, in the custom text style.
9. iPad and Mac. The adaptive column from Layout by device, rotation and split view, window sizing, keyboard shortcuts, menu bar commands, pointer gestures, and Apple Pencil.
10. iCloud sync. Move storage to CloudKit and test across two devices.
11. Shared lists. Invite links, accepting an invite, and showing shared state.
12. Widgets. Every size, tap to strike, choosing the list, and the circle gesture. Then an accessibility pass and the gaps listed under Not designed yet.

Steps 1 to 8 give a working single-device iPhone app. Build the column to adapt to width from step 1, so step 9 is refinement and not a rewrite. Sync and sharing come after the feel is right, because they change the storage layer and not the interface.

**Working with Claude Code**

- Ask for one step at a time and run the app after each.
- Test gestures on a device. The simulator does not show how the strike feels.
- Keep the strike renderer in its own module with a preview screen, so it can be tuned alone.

## Accessibility

A gesture-only app with no visible controls must offer another route for every action.

| System setting or need | What the app does |
| --- | --- |
| VoiceOver | Each task is one element with custom actions: strike, edit, move, delete. Archive and settings are reachable without a drag. |
| Dynamic Type | Text scales. When tasks no longer fit one screen, the list scrolls. |
| Reduce Motion | The strike appears without the drawing animation. Tasks leave without sliding. |
| Reduce Transparency | The blur becomes a flat dim of the page. |
| Increase Contrast | Faded ink darkens. |
| Switch Control and keyboard | Every action has a tap or key route. |
| Contrast | Faded ink on paper is about 4.7 to 1. Keep any new colour at 4.5 to 1 or better for text. |
| Touch targets | 44 pt minimum for list names, menu options, and month labels. |

The custom text menus replace the system context menu, so they need their own VoiceOver labels, focus handling, and dismissal by tapping the blurred area.

## App Store review

Apple reviews every build against its App Review Guidelines, and the design must pass them on iPhone, iPad, and Mac. Three rules change the design: gestures must be explained and must not override the system, a privacy policy must be reachable inside the app, and a tap in a widget must do real work.

The points below are my summary of Apple's published guidelines. The guidelines change, so read the current text before each submission.

**What each rule means for this app**

| Guideline | What Apple requires | What the app does |
| --- | --- | --- |
| 2.1 App completeness | A final build with no placeholder content, working links, and no crashes. | Everything under Not designed yet is either finished or removed before submission. Test on real devices. |
| 2.3.1 and 2.5.19 Hidden features | Review notes must describe non-obvious features. Hidden or undocumented features are not allowed. | The app has no visible controls, so every gesture is taught on the first-run page, listed under a Gestures line in settings, and written out in the review notes. |
| 2.3 Accurate metadata | Screenshots show the app in use. The name is unique and at most 30 characters. | Screenshots show real lists and a strike in progress. |
| 2.4.1 iPad | iPhone apps should run on iPad where possible. | iPad is in scope with an adaptive layout. |
| 2.4.5 Mac App Store | The app is sandboxed, packaged with Xcode, and does not launch itself or run in the background without consent. | Standard sandboxed Mac target with the iCloud entitlement only. |
| 2.5.1 Public APIs | Only public APIs, used for their intended purpose. | SwiftUI, SwiftData or Core Data, CloudKit, WidgetKit, and App Intents. No private APIs for gestures or blur. |
| 2.5.5 IPv6 | Networking works on IPv6-only networks. | All networking goes through CloudKit. No custom networking code. |
| 2.5.9 System behaviours | Custom gestures must not override standard system behaviours. | Drags start inside the page. The app never captures the top edge, the home indicator, Control Centre, the back swipe, or iPad multitasking gestures. |
| 2.5.16 and 4.4 Extensions | Widgets and extensions relate to the app, carry no marketing, and include some functionality. | The widgets show only the user's own tasks and let them strike one. |
| 4.1 Copycats | Original work, with no borrowed names, icons, or brands. | Original design. Choose a name and icon that do not resemble an existing to-do app. |
| 4.2 Minimum functionality | More than a trivial app or a simple list. | This is the main risk for a deliberately simple app. Sync, shared lists, interactive widgets, Pencil support, and the Mac app carry the case. Say so in the review notes. |
| 4.5.3 and 4.5.4 Notifications | Live Activities and push are not used for promotion, and the app works without them. | The app sends no notifications and uses no Live Activities. |
| 5.1.1(i) Privacy policy | A privacy policy link in App Store Connect and inside the app, stating what is collected, how it is used, and how to delete it. | A Privacy line in settings opens the policy. The policy says tasks are stored in the user's iCloud and that the app collects no analytics. |
| 5.1.1 Data collection | Collect only what the core features need, with consent. | No account, no analytics, no tracking, no third-party SDKs. The privacy labels in App Store Connect match this. |
| 5.1.2(v) Invitations | The user starts each invitation and sees it before it is sent. No bulk selection of contacts. | Sharing uses the system share sheet, one invite at a time. The app never reads Contacts. |
| 1.2 Content shared between users | Apps with user-generated content need ways to report content and block users. | A shared list is text passed between invited people. The safe reading is to treat it as covered: the owner can remove a person, anyone can leave a list, and a Contact line in settings takes reports. |
| 1.5 Developer information | A working way to contact the developer. | A support URL in App Store Connect and the Contact line in settings. |

**Changes this makes to the design**

- Settings gains three lines below the four toggles: Gestures, Privacy, and Contact. They open a page and are not struck on or off.
- The first-run page that teaches the gestures is required, not optional.
- Shared lists need Remove person for the owner and Leave list for a guest.
- Widgets replace the Live Activity, so a circled task has no time limit and stays circled until it is struck or the circle is cleared.

**Before submitting**

- [ ] Privacy policy published at a working URL and linked in the app.
- [ ] Support URL and contact address working.
- [ ] Privacy labels completed in App Store Connect, matching what the app does.
- [ ] Privacy manifest file included if the build uses any API that Apple requires a declared reason for. This comes from secondary sources, so confirm it in Apple's documentation.
- [ ] Review notes written: what the app is, every gesture with steps to try it, how to test sync and a shared list, and how to add and use the widgets.
- [ ] No placeholder text, empty screens, or unfinished settings in the build.
- [ ] Tested on iPhone, iPad in portrait, landscape and split view, and Mac.
- [ ] Screenshots for each device size show the app in use.
- [ ] Age rating answered. Name is unique and within 30 characters.
- [ ] Font check: New York is called through the system serif design, with no font file in the bundle.

**Sources**

- [App Review Guidelines](https://developer.apple.com/support/downloads/terms/app-review-guidelines/App-Review-Guidelines-English-UK.pdf), Apple. I read the first five sixths of the document, up to part of section 5.1.4.
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities.md), Apple.

## Open questions

Settle the blocking ones before the build step they affect.

**Blocking**

- [ ] Strike versus switch list. Confirm the rule that a swipe on a task strikes and a swipe on empty paper or the list names switches. Affects steps 4 and 5. Steps 4 and 5 are built to the proposed rule. Wayne started step 5 on it, Nov 17, 2026. Still to be tried on a real device.
- [x] Page length. Decided by Wayne, Nov 17, 2026: the list scrolls, and dragging up at the end of the list opens the archive. This also covers large text. See Decisions made.
- [x] Long tasks. Decided: tasks wrap, and each line gets its own strike. See The strike. Confirmed by Wayne, Nov 17, 2026: one drag strikes every line, and a task shows at most three lines.
- [ ] Keyboard. When adding a task, do the list names hide or move above the keyboard? Affects step 3. Built as: the list names hide while the keyboard is up. Not yet confirmed.
- [ ] Daily reset. Lists are assumed permanent, with no fresh page each day. Confirmed by Wayne, so this is decided.

* [ ] Circle gesture. It was approved for the Live Activity, which widgets have replaced. Confirm it stays as the way to put a task first in the widgets. Affects step 12.
* [ ] Column width and type size on iPad. Confirm the 600 pt column and 28 pt tasks after seeing them on a device. Affects step 9.
* [ ] iPad landscape. One centred page, or two lists side by side like an open notebook? One page is assumed. Affects step 9.
* [ ] iPhone landscape. Support it, or lock the iPhone to portrait? Support is assumed.

**Can wait**

- [ ] Shared list marker. How a shared list looks different from a private one. Italic name is the suggestion.
- [ ] Attribution. Whether the archive of a shared list shows who struck each task.
- [ ] Leaving a shared list. Menu wording for the owner and for a guest.
- [ ] Offline conflicts. What wins when two people change the same task.
- [ ] Many lists. How the bottom row behaves past four or five names.
- [ ] Creating a list. Swiping past the last list to a blank page was suggested and not confirmed.
- [x] Reordering. Decided by Wayne, Nov 17, 2026: hold a task to pick it up, then drag it to a new place. The long press menu in step 8 has to share the hold: holding without moving opens the menu, holding and dragging reorders.
- [x] Task menu style. Confirmed by Wayne, Nov 17, 2026: it matches the list menu, plain text growing from the task.
- [ ] Settings sync. Whether settings follow the user across devices.
- [ ] App name and icon.
- [ ] Font for marketing. New York is licensed for Apple platform apps and mockups, so a website or print needs another serif.

## Not designed yet

The build will reach these with no Figma frame to follow. Each needs a design, or a decision to let Claude Code propose one.

| Gap | Note |
| --- | --- |
| Empty list | What a list with no tasks shows. |
| First run | Designed. See First run and Figma frames 07 to 11. Steps 4, 5, and 7 still need frames. |
| Adding a task | The cursor and keyboard state. |
| Mid-strike | The line partway across, following the finger. |
| Task menu | Move to, copy, delete, in the text menu style. No Edit: a tap on the task edits it. |
| Dark paper | Colour values and how the strike looks on a dark ground. |
| Mac archive and settings | Only the main Mac window is designed. |
| Mac minimum window size | And how text reflows when the window is resized. |
| Share flow | The system share sheet, the invite a recipient sees, and the accept step. |
| Shared list state | Marker, attribution, and leaving. |
| Sync states | Offline, syncing, and errors. Suggested: stay silent unless something fails. |
| iPad | Now in scope. Needs frames for portrait, landscape, and split view. The rules are in Layout by device. |
| Widget and lock screen | Widgets are now in scope. They need frames for each size, the Lock Screen versions, each system colour style, and the circled task in the app. |
| Delete list confirmation | The one place the app asks before acting. |
