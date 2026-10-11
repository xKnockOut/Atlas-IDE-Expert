# 0005: Hybrid-Modus mit Embarcadero DelphiLSP

- Status: Offen
- Datum: 2026-10-08
- Bezug: #63 Hybrid-Modus

## Kontext

Embarcaderos DelphiLSP nutzt den echten Compiler und liefert in manchen Fällen genauere Ergebnisse (Überladungen, Generics, Typinferenz), ist aber langsam und stürzt bei großen Projekten ab. AtlasServer ist schneller und robuster, kennt aber nicht jede Typregel.

## Zu entscheiden

- Ob Anfragen, die der eigene Server nicht sicher beantworten kann, an DelphiLSP weitergeleitet werden.
- Wie Antworten zusammengeführt werden und welcher Server Vorrang hat.
- Wie mit Lizenz, Startzeit und Abstürzen von DelphiLSP umgegangen wird.

Die Entscheidung fällt mit #63; bis dahin arbeitet der Server allein.
