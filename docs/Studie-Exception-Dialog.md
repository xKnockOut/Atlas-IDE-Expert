# Studie: Exception-Dialog der IDE (#517, #783)

Die Open Tools API meldet einen Halt wegen einer Exception (`psException`, `nrException`), aber weder Klasse noch Meldung. Atlas liest beide deshalb aus dem Exception-Dialog der IDE: Nach dem Halt sieht es bis zu 3 s lang alle 100 ms die sichtbaren Fenster der IDE durch und erkennt den Dialog am Text („… raised exception class … with message …“ bzw. „… der Klasse … mit der Meldung … aufgetreten“) und an den Knöpfen „Anhalten“/„Break“ und „Fortsetzen“/„Continue“. „Klasse künftig ignorieren“ im Exception-Verlauf schließt den Dialog über seinen Knopf „Fortsetzen“.

Ob das in jeder IDE-Version trägt, klärt diese Studie. Sie entscheidet auch, ob #783 den Dialog durch eine Leiste ersetzen kann.

## Aufbau

- Delphi 12 und Delphi 13, jeweils Win32 (klassischer Debugger) und Win64 (Delphi 13: LLDB).
- Atlas mit `debug.exceptionHistory` an, Diagnosemodus an (Protokoll `Atlas.IDE.Expert370.log` neben dem Plugin bzw. `%LOCALAPPDATA%\Atlas\Logs`).
- Testprogramm (VCL, ein Formular, vier Knöpfe):

```pascal
procedure TForm1.Button1Click(Sender: TObject);   // abgefangen, zehnmal
var
  I: Integer;
begin
  for I := 1 to 10 do
    try
      StrToInt('x');
    except
      on EConvertError do ;
    end;
end;

procedure TForm1.Button2Click(Sender: TObject);   // nicht abgefangen
begin
  raise EInvalidOp.Create('Nicht erlaubt: ''Wert''');
end;

procedure TForm1.Button3Click(Sender: TObject);   // Zugriffsverletzung
begin
  PInteger(nil)^ := 1;
end;

procedure TForm1.Button4Click(Sender: TObject);   // in einem benannten Thread
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.NameThreadForDebugging('Lader');
      try
        raise EAbort.Create('im Thread');
      except
      end;
    end).Start;
end;
```

## Punkte

| Nr. | Frage | Vorgehen | Ergebnis D12 Win32 | D12 Win64 | D13 Win32 | D13 Win64 (LLDB) |
|---|---|---|---|---|---|---|
| S1 | Meldet die IDE Exceptions, die in *Tools › Optionen › Debugger › Sprach-Exceptions* ignoriert werden, noch an Plugins? | `EConvertError` dort eintragen, Knopf 1. Erscheint ein Eintrag im Fenster „Atlas: Exceptions“? Steht „Exception-Dialog der IDE erkannt“ im Protokoll? | | | | |
| S2 | Fensterklasse und Knöpfe des Dialogs | Knopf 2; im Protokoll steht einmal je Sitzung „Exception-Dialog der IDE erkannt: <Klasse>, Knöpfe: …, Fortsetzen möglich: …“ | | | | |
| S3 | Nennen die Zustandstexte (`IOTAThread.GetStatusString`, `IOTAProcess.GetStatusString`) die Klasse? | Knopf 2; im Protokoll steht einmal je Sitzung „Exception-Halt: Klasse aus dem Zustandstext von Thread/Prozess/keinem“. Ohne Dialog und ohne Zustandstext steht im Fenster „Exception“ bzw. „Fehler des Betriebssystems“ | | | | |
| S4 | Wirkt das stille Fortsetzen? | Im Fenster Rechtsklick auf `EConvertError` › „Klasse künftig ignorieren“, Programm neu starten, Knopf 1: kein Dialog bleibt stehen, der Eintrag ist grau und zählt bis 10 | | | | |
| S5 | Reihenfolge Halt und Dialog | Knopf 2: Steht der Eintrag mit Klasse und Meldung im Fenster, sobald der Dialog offen ist? (Kommt der Dialog vor oder nach `ProcessStateChanged`?) | | | | |
| S6 | Aufrufstapel bei LLDB | Knopf 3 unter Win64: Stimmt der Ort (Unit und Zeile von `Button3Click`), oder steht nur eine Routine ohne Datei (Stapel `csWait`)? | | | | |
| S7 | Thread | Knopf 4: Spalte Thread zeigt „Lader (<Kennung>)“ | | | | |
| S8 | Hängt etwas? | Während der Dialog offen ist, IDE bedienen; nach „Fortsetzen“ und „Anhalten“ läuft bzw. steht der Prozess wie ohne Atlas | | | | |

## Entscheidung (nach der Studie in #783 eintragen)

- Trägt das Erkennen (S2, S5) in allen vier Varianten, bleibt der Weg „Dialog erkennen, auslesen, über ‚Fortsetzen‘ schließen“. #783 kann dann die Leiste zeigen und den Dialog sofort schließen (Fortsetzen bzw. Anhalten über die Knöpfe).
- Fehlt der Dialog in einer Variante oder heißen die Knöpfe anders, ergänzt Atlas die Erkennung (`Atlas.Core.Debug.ExceptionDialog`, Test dazu) und prüft erneut.
- Meldet die IDE ignorierte Klassen nicht (S1), steht das in der Doku: Der Verlauf zeigt nur, wobei der Debugger anhält.
