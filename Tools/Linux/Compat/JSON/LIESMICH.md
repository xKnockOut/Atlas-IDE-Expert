# System.JSON der vcl-compat (FPC)

Kopie von `packages/vcl-compat/src/system.json.pp` aus Free Pascal im Stand `FPC_COMMIT` von
`Tools/Linux/Build-AtlasServer.sh` (Lizenz: modifizierte LGPL von FPC, siehe COPYING.FPC im FPC-Quelltext).

Warum hier: Die Unit steht unter `{$mode objfpc}{$h+}`, dort ist `String` ein AnsiString. `GetValue<string>`,
`TryGetValue<string>` und `AsType<string>` gehen über `CreateTValue(S : String; …)` und wandeln jeden Text in die
Codepage des Systems: Zeichen außerhalb davon werden zu `?` oder umschrieben (`→` zu `->`). Unter Delphi und mit
`(… as TJSONString).Value` bleibt der Text erhalten. Betroffen waren alle Lesestellen mit `GetValue<string>` im
Linux-Server und unter FPC der Test `TCompletionDetailsTests.DescribesMethodWithXmlDoc`.

Eigene Korrekturen gegenüber FPC (bei einem neuen Stand prüfen, ob sie noch nötig sind): `CreateTValue` nimmt
`UnicodeString`; der Pfad in Fehlermeldungen des Parsers (`lPath`, `AddToPath`) ebenso.

Build-AtlasServer.sh und Test-Fpc.sh übersetzen die Unit aus dem Quelltext statt der vorkompilierten.
