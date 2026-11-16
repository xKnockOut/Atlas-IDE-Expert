unit Atlas.UI.Debug.Threads.Strings;

// Texte zu Threads: Warteketten, parallele Aufrufstapel, Thread-Marken im Quelltext und Ursprung asynchroner Aufrufe,
// auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasThreadsTextId = (
    DebugWaitsNotStopped, DebugWaitsTitle, DebugWaitsPatterns, DebugWaitsNoPattern, DebugWaitsThreads,
    DebugWaitsMainWaitsForSync, DebugWaitsInDestructor, DebugWaitsSyncBlocked, DebugWaitsSameLock,
    DebugWaitsAllBlocked, DebugWaitsThreadName, DebugWaitsMainThread, DebugWaitsRunning, DebugWaitsIdle, DebugWaitsIn,
    DebugWaitsUnreadable, DebugWaitsThreadItem, DebugWaitsThreadItemNoPlace, DebugWaitsPlace, ParallelStacksCaption,
    ParallelStacksOwnOnly, ParallelStacksWaitingOnly, ParallelStacksNode, ParallelStacksNodeOne,
    ParallelStacksNodeWaiting, ParallelStacksStatus, ParallelStacksReading, ParallelStacksRunning,
    ParallelStacksThreads, ParallelStacksFooter, ThreadMarksTitle, ThreadMarksTitleOne, ThreadMarksWaiting,
    ThreadMarksFrozen, ThreadMarksSwitch, ThreadMarksFrozenOne, ThreadMarksFrozenCount, ThreadMarksAllHere,
    ThreadMarksFreezeFailed, ThreadMarksFlaggedOn, ThreadMarksFlaggedOff, ThreadMarksFrozenOn, ThreadMarksThawed,
    ThreadMarksThawedAll, AsyncOriginTitle, AsyncOriginLibrary, AsyncOriginNone, AsyncOriginStatus, AsyncOriginArmed,
    AsyncOriginNoSites, AsyncOriginFrame);

  TAtlasThreadsStrings = class
  public
    class function Text(AId: TAtlasThreadsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasThreadsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasThreadsTextId] of string = (
    ('„Was wartet worauf?“ braucht ein angehaltenes Programm (Start > Programm Pause).',
     'Was wartet worauf? (%d Threads)',
     'Erkannte Muster',
     'Kein bekanntes Muster einer Verklemmung',
     'Threads',
     'Verklemmung: Der Hauptthread wartet in TThread.WaitFor%s, Thread %s wartet in Synchronize auf den Hauptthread (Regel synchronize-in-destructor)',
     ' im Destruktor eines Threads',
     'Thread %s wartet in Synchronize, der Hauptthread hängt in %s und arbeitet die Warteschlange nicht ab',
     '%d Threads warten an derselben Sperre in %s: %s (wer sie hält, zeigt der Debugger nicht)',
     'Alle %d Threads warten, keiner läuft: mögliche Verklemmung',
     '%s „%s“',
     '%s (Hauptthread)',
     'läuft',
     'wartet auf Nachrichten',
     'wartet in %s',
     'Aufrufstapel nicht lesbar',
     'Thread %s: %s, bei %s',
     'Thread %s: %s',
     '%s (%s:%d)',
     'Parallele Aufrufstapel',
     'Nur eigener Code',
     'Wartend',
     '%s · %d Threads',
     '%s · 1 Thread',
     ' · wartend',
     '%d Threads, %d wartend',
     'Lese Aufrufstapel: %d von %d Threads …',
     'Das Programm läuft; die Aufrufstapel erscheinen beim nächsten Halt.',
     'Threads: %s',
     'Enter oder Doppelklick: zum Thread wechseln und zur Zeile springen',
     '%d Threads stehen hier',
     'Ein Thread steht hier',
     '%s · wartet in %s',
     '%s · eingefroren',
     'Zu %s wechseln',
     '1 Thread eingefroren',
     '%d Threads eingefroren',
     'Alle Threads dieser Zeile',
     'Thread %s ließ sich nicht einfrieren; das geht nur bei Programmen auf diesem Rechner.',
     'Thread %s markiert.',
     'Markierung von Thread %s entfernt.',
     'Thread %s eingefroren: Er läuft beim Fortsetzen nicht weiter.',
     'Thread %s aufgetaut.',
     'Alle Threads aufgetaut.',
     'Eingereiht mit %s von Thread %d',
     '%d Rahmen der Bibliothek',
     'Halt in einer mit %s eingereihten Methode; die Einreihung hat Atlas nicht gesehen.',
     'Herkunft: %d Aufrufstellen',
     'Herkunft eingereihter Methoden (experimentell): %d Aufrufstellen beobachtet; das Programm läuft dadurch langsamer.',
     'Herkunft eingereihter Methoden: keine Aufrufstellen im Projekt gefunden.',
     '%s (%s:%d)'),
    ('“What is waiting for what?” needs a paused program (Run > Program Pause).',
     'What is waiting for what? (%d threads)',
     'Detected patterns',
     'No known deadlock pattern',
     'Threads',
     'Deadlock: the main thread waits in TThread.WaitFor%s, thread %s waits in Synchronize for the main thread (rule synchronize-in-destructor)',
     ' in the destructor of a thread',
     'Thread %s waits in Synchronize while the main thread hangs in %s and does not process the queue',
     '%d threads wait for the same lock in %s: %s (the debugger does not show who holds it)',
     'All %d threads are waiting and none is running: possible deadlock',
     '%s “%s”',
     '%s (main thread)',
     'running',
     'waiting for messages',
     'waiting in %s',
     'call stack not readable',
     'Thread %s: %s, at %s',
     'Thread %s: %s',
     '%s (%s:%d)',
     'Parallel Stacks',
     'Just my code',
     'Waiting',
     '%s · %d threads',
     '%s · 1 thread',
     ' · waiting',
     '%d threads, %d waiting',
     'Reading call stacks: %d of %d threads …',
     'The program is running; the call stacks appear at the next stop.',
     'Threads: %s',
     'Enter or double click: switch to the thread and jump to the line',
     '%d threads are here',
     'One thread is here',
     '%s · waiting in %s',
     '%s · frozen',
     'Switch to %s',
     '1 thread frozen',
     '%d threads frozen',
     'All threads on this line',
     'Could not freeze thread %s; this only works for programs on this computer.',
     'Thread %s flagged.',
     'Removed the flag from thread %s.',
     'Thread %s frozen: it does not run when you continue.',
     'Thread %s thawed.',
     'All threads thawed.',
     'Queued with %s from thread %d',
     '%d library frames',
     'Stopped in a method queued with %s; Atlas did not see it being queued.',
     'Origin: %d call sites',
     'Origin of queued methods (experimental): watching %d call sites; the program runs slower.',
     'Origin of queued methods: no call sites found in the project.',
     '%s (%s:%d)'));

{ TAtlasThreadsStrings }

class function TAtlasThreadsStrings.Text(AId: TAtlasThreadsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasThreadsStrings.Fmt(AId: TAtlasThreadsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
