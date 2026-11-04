unit Atlas.Common.Rules.Catalog.Data.De.Threads;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  CatalogLinesDeThreads: array[0..112] of string = (
    '{',
    '      "id": "thread-vcl-access",',
    '      "name": "VCL-Zugriff aus einem Thread",',
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread oder TTask greift außerhalb von Synchronize oder Queue auf die VCL zu (Application, Screen, ShowMessage, MessageDlg …). Die VCL ist' +
    ' nicht threadsicher."',
    '    },',
    '{',
    '      "id": "lock-without-finally",',
    '      "name": "Sperre ohne try/finally",',
    '      "description": "Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPair' +
    's) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.",',
    '      "options": [',
    '        {',
    '          "name": "lockPairs",',
    '          "description": "Weitere Sperrpaare als [[\"Sperren\", \"Freigeben\"]]."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "thread-use-after-free-on-terminate",',
    '      "name": "Thread nach dem Start mit FreeOnTerminate benutzt",',
    '      "description": "Ein Thread mit FreeOnTerminate := True kann sich gleich nach dem Start selbst freigeben; danach greift die Variable womöglich auf ein freigegebenes Objekt zu."',
    '    },',
    '{',
    '      "id": "thread-free-with-free-on-terminate",',
    '      "name": "Free auf einem Thread mit FreeOnTerminate",',
    '      "description": "Free auf einem Thread mit FreeOnTerminate := True gibt ihn doppelt frei."',
    '    },',
    '{',
    '      "id": "synchronize-in-destructor",',
    '      "name": "Synchronize im Destruktor eines Threads",',
    '      "description": "Synchronize im Destruktor eines TThread-Nachfahren (oder in einer Methode, die er aufruft) verklemmt sich: Der Hauptthread wartet in WaitFor, der Thread auf Synchronize."',
    '    },',
    '{',
    '      "id": "thread-resume-suspend",',
    '      "name": "Veraltetes TThread.Resume/Suspend",',
    '      "description": "TThread.Resume und Suspend sind veraltet. Einen erzeugten Thread mit Start starten; Suspend hat keinen sicheren Ersatz, stattdessen mit einem Ereignis warten. Still, wenn der dek' +
    'larierte Typ des Empfängers eine vollständige Vorfahrenkette ohne TThread hat (eigene Klassen mit Methoden Resume/Suspend)."',
    '    },',
    '{',
    '      "id": "threadvar-managed",',
    '      "name": "threadvar mit verwaltetem Typ",',
    '      "description": "Delphi finalisiert threadvar-Variablen nicht. Ein String, Interface, dynamisches Array oder Variant in einer threadvar (auch in einem Record oder statischen Array) leckt in jedem' +
    ' Thread, der endet. Typen werden in der Datei und im Index aufgelöst. Konfidenz hoch. Keine Schnellkorrektur: den Wert am Thread-Ende freigeben (etwa in TThread.Execute auf '''' bzw. nil setzen) oder st' +
    'attdessen einen Zeiger bzw. Puffer fester Größe ablegen."',
    '    },',
    '{',
    '      "id": "processmessages-in-loop",',
    '      "name": "Application.ProcessMessages in Schleifen",',
    '      "description": "Application.ProcessMessages in einer for-, while- oder repeat-Schleife oder direkt in einem Ereignis-Handler (Methode mit Parameter Sender) öffnet die Tür für Wiedereintritt: Der' +
    ' Benutzer klickt erneut, schließt das Formular oder startet den Vorgang doppelt. Aufrufe in anonymen Methoden überlässt die Regel thread-vcl-access; ProcessMessages anderer Objekte zählt nicht. Konfid' +
    'enz mittel, keine Schnellkorrektur: die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum Ende sperren. Die Option allowIn nennt Methoden, in denen es erlaubt ist.",',
    '      "options": [',
    '        {',
    '          "name": "allowIn",',
    '          "description": "Methoden, in denen ProcessMessages erlaubt ist, als Name oder Klasse.Name."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "queue-nil-in-package",',
    '      "name": "TThread.Queue(nil, …) in einem Package",',
    '      "description": "TThread.Queue(nil, …) oder TThread.ForceQueue(nil, …) in einer Unit eines Design-Time- oder Laufzeit-Packages: Der Eintrag gehört keinem Thread, beim Entladen des Packages räumt ' +
    'ihn niemand weg, und CheckSynchronize ruft ihn womöglich danach in fremdem Speicher auf. Package-Units erkennt die Regel über die .dpk bzw. .dproj des geladenen Projekts (eine .dpk ohne Projekt für si' +
    'ch). Eine Zeile mit dem Kommentar aus okMarker (Vorgabe mainthread-ok) ist ausgenommen. Sicherheit hoch. Korrektur: auf den Wrapper aus der Option wrapper umschreiben (Vorgabe TAtlasMainThread.Queue, ' +
    'bei ForceQueue ForceQueue); mit Klammer steht der Text so vor den übrigen Argumenten. ForceQueue mit Verzögerung bekommt keine Korrektur. Der Kommandozeilen-Linter liest die .dpk-Dateien unter dem gep' +
    'rüften Ordner. Leistet für jedes Plugin-Projekt dasselbe wie Tools/Check-MainThreadQueue.ps1; das Skript bleibt für Prüfungen ohne Atlas-Server.",',
    '      "options": [',
    '        {',
    '          "name": "wrapper",',
    '          "description": "Ersatz für TThread.Queue(nil, in der Schnellkorrektur."',
    '        },',
    '        {',
    '          "name": "okMarker",',
    '          "description": "Kommentar, der eine Zeile ausnimmt."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "blocking-call-in-main-thread",',
    '      "name": "Blockierender Aufruf im Hauptthread",',
    '      "description": "Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects oder Wait in Methoden von Formularen und Frames (Klassen, die von TForm, TCustomForm, TFrame oder TCustomFrame erben) ' +
    'und in Ereignis-Handlern (Methoden mit Parameter Sender) außerhalb von Thread-Klassen. Die Oberfläche friert ein, solange der Aufruf wartet; wartet der andere Thread auf Synchronize, hängt das Program' +
    'm. WaitFor ohne Timeout auf einer Variablen nennt die Gefahr der Synchronize-Verklemmung. Sleep, WaitForSingleObject und WaitForMultipleObjects zählen nur ohne Empfänger (oder mit Winapi.Windows), Wai' +
    'tFor und Wait nur mit Empfänger. Ein Literal-Timeout unter maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) bleibt still, außer ein kurzes Sleep in einer Warteschleife ohne Application.ProcessMessage' +
    's. Anonyme Methoden sind ausgenommen (TTask.Run, TThread.Queue), eingebettete Routinen gehören zu ihrer Methode. Konfidenz mittel. Keine Schnellkorrektur: die Arbeit in TTask.Run auslagern und das Erg' +
    'ebnis mit TThread.Queue melden.",',
    '      "options": [',
    '        {',
    '          "name": "maxSleepMs",',
    '          "description": "Literal-Timeouts unter diesem Wert (Millisekunden) werden nicht gemeldet; ein kurzes Sleep in einer Warteschleife schon."',
    '        },',
    '        {',
    '          "name": "calls",',
    '          "description": "Aufrufe, die blockieren. Andere Namen werden unabhängig von ihren Argumenten gemeldet."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "thread-loop-without-terminated",',
    '      "name": "Thread-Schleife ohne Terminated",',
    '      "description": "Eine while- oder repeat-Schleife in TThread.Execute oder in einer Methode der Thread-Klasse, die nur von dort aufgerufen wird (auch über andere solche Methoden, eingebettete Rout' +
    'inen eingeschlossen), prüft Terminated nicht. Terminate wirkt dann nicht, und WaitFor bzw. Free hängen beim Beenden. Gemeldet für Endlosschleifen (while True, until False) und für Warteschleifen mit S' +
    'leep, WaitFor, WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait oder Yield, deren Bedingung und Rumpf Terminated bzw. CheckTerminated nie erwähnen. Thread-Klassen kommen au' +
    's der Unit und dem Index. Begrenzte Schleifen, for-Schleifen, anonyme Methoden und Klassen, die TerminatedSet überschreiben (sie beenden ihre Schleifen auf anderem Weg), bleiben still. Konfidenz hoch.' +
    ' Korrektur: Terminated in die Schleifenbedingung aufnehmen (while True → while not Terminated, sonst and not Terminated; until False → until Terminated, sonst or Terminated)."',
    '    },',
    '{',
    '      "id": "anonymous-thread-not-started",',
    '      "name": "Anonymer Thread nie gestartet",',
    '      "description": "TThread.CreateAnonymousThread(…) legt den Thread angehalten und mit FreeOnTerminate an. Ohne Start läuft er nie, und weil er nie endet, wird er auch nie freigegeben. Gemeldet für' +
    ' den Aufruf als eigene Anweisung und für eine lokale Variable (auch Inline-Variable), die weder mit Start oder Resume gestartet noch weitergegeben wird (Argument, Zuweisung, Result, Feld). Eigenschaft' +
    'en wie FreeOnTerminate oder OnTerminate zu setzen gilt nicht als Weitergabe. Konfidenz hoch. Korrektur: .Start anhängen; bei einer Variablen T.Start; nach der letzten Anweisung desselben Blocks, die s' +
    'ie erwähnt."',
    '    },',
    '{',
    '      "id": "task-exception-unobserved",',
    '      "name": "Exception in TTask geht verloren",',
    '      "description": "TTask.Run(…) bzw. TTask.Create(…).Start, dessen Ergebnis nicht gespeichert und nie mit Wait, Status o. ä. abgefragt wird und dessen anonyme Methode kein try … except hat. Eine Ex' +
    'ception im Task verschwindet still. Auch gemeldet für eine lokale Variable, die nie wieder vorkommt (bei TTask.Create nur in V.Start). Still bei gespeicherten Ergebnissen (Felder, Result, jede andere ' +
    'Verwendung der Variablen) und bei Methodenzeigern, deren Rumpf die Regel nicht sieht. Konfidenz mittel. Korrektur: den Rumpf in try … except einschließen und die Meldung über TThread.Queue mit ShowMes' +
    'sage im Hauptthread zeigen (ergänzt Vcl.Dialogs, in FireMonkey-Units FMX.Dialogs, und System.SysUtils im uses, wenn sie fehlen); nur, wenn begin und end der anonymen Methode auf eigenen Zeilen stehen.' +
    '"',
    '    },',
    '{',
    '      "id": "parallel-for-shared-write",',
    '      "name": "Gemeinsame Variable in TParallel.For geschrieben",',
    '      "description": "Der Rumpf von TParallel.For bzw. eines TTask.Run/Create/Future, der in einer Schleife entsteht, schreibt eine Variable von außerhalb ohne Sperre: Summe := Summe + …, Inc/Dec oder' +
    ' eine andere Zuweisung, oder er verändert eine Sammlung von außerhalb (Add, Delete, Clear, Insert, Remove …). Die Durchläufe laufen gleichzeitig; Additionen gehen verloren oder die Liste wird beschädi' +
    'gt. Von außerhalb heißt: lokale Variable oder Parameter der umgebenden Routine, Feld ihrer Klasse oder globale Variable der Unit; Namen unbekannter Herkunft bleiben still. Rümpfe mit Sperre (TMonitor,' +
    ' Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked), Zugriffe über Index (Werte[I] := …) und verschachtelte anonyme Methoden (Synchronize, Queue) zählen nicht. Typen aus threadSafeTypes gelten ' +
    'als threadsicher. Sicherheit mittel. Korrekturen: TInterlocked.Add/Increment/Decrement bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs), System.TMonitor.Enter/Exit in try … finally um den Sam' +
    'mlungsaufruf.",',
    '      "options": [',
    '        {',
    '          "name": "threadSafeTypes",',
    '          "description": "Typen, die als threadsicher gelten; ihre Sammlungsaufrufe bleiben still."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "thread-unsafe-increment",',
    '      "name": "Zähler im Thread ohne TInterlocked",',
    '      "description": "Inc, Dec, X := X + 1 oder X := X - 1 ohne Sperre auf einer globalen Variablen in Execute eines TThread-Nachfahren bzw. auf einem Feld oder einer globalen Variablen im Rumpf von T' +
    'Task.Run/Create/Future außerhalb von Schleifen und von TThread.CreateAnonymousThread. Inc ist nicht atomar: zählen mehrere Threads gleichzeitig, gehen Erhöhungen verloren. Thread-Klassen kommen aus de' +
    'r Unit (auch über Zwischenklassen) und aus dem Index. Eigene Felder des Threads in Execute und eingefangene lokale Variablen eines einzelnen Tasks haben nur einen Schreiber und bleiben still, ebenso R' +
    'ümpfe mit Sperre (TMonitor, Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked) und verschachtelte anonyme Methoden (Synchronize, Queue). Tasks in Schleifen und TParallel.For meldet parallel-for' +
    '-shared-write. Sicherheit mittel. Korrektur: TInterlocked.Increment/Decrement/Add bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs)."',
    '    }');

implementation

end.
