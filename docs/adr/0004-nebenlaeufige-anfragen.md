# 0004: Lesende Anfragen nebenläufig auf Momentaufnahmen

- Status: Angenommen
- Datum: 2026-10-07
- Bezug: #4 Nachrichtenschleife, #5 Dokumentverwaltung

## Kontext

Hover, Gehe-zu-Definition und Symbolsuche sollen nicht hinter einem langsamen Parse oder einer anderen Anfrage warten. Gleichzeitig müssen `didChange`-Nachrichten in der gesendeten Reihenfolge verarbeitet werden.

## Entscheidung

Benachrichtigungen und schreibende Anfragen laufen nacheinander im Thread der Nachrichtenschleife. Lesende Anfragen registrieren sich mit `RegisterConcurrentRequest` und laufen im Thread-Pool. Sie lesen unveränderliche Momentaufnahmen aus dem Dokumentspeicher und den threadsicheren Symbolindex und prüfen regelmäßig ihr Abbruchsignal. Jede Anfrage hat ein Zeitlimit (`TJsonRpcWatchdog`).

## Alternativen

- Alles in einem Thread: einfach, aber ein langsamer Handler blockiert alle anderen.
- Sperren um gemeinsamen veränderlichen Zustand: fehleranfällig und schwer zu testen.

## Folgen

- Handler müssen ohne gemeinsamen veränderlichen Zustand auskommen oder ihn selbst schützen.
- Antworten können in anderer Reihenfolge als die Anfragen ankommen; LSP erlaubt das.
