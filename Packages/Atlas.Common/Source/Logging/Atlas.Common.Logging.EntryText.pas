unit Atlas.Common.Logging.EntryText;

// Klartext eines Logeintrags (#1478): Der Text eines TLogEntry trägt die
// Kennzeichen für Namen, Pfade und fremden Text (Atlas.Text.LogMarks). Senken,
// die für Menschen am selben Rechner schreiben (stderr, Debug-Ausgabe,
// window/logMessage), entfernen sie hier; Senken für weitergegebene Dateien
// ersetzen sie vorher über den Anonymisierer (TTransformLogSink).

interface

uses
  Atlas.Common.Logging.Contract;

type
  TLogEntryText = record
  public
    /// <summary>Text des Eintrags ohne Kennzeichen.</summary>
    class function Plain(const AEntry: TLogEntry): string; static;
    /// <summary>Einzeilige Darstellung wie TLogEntry.ToText, ohne Kennzeichen.</summary>
    class function PlainLine(const AEntry: TLogEntry): string; static;
  end;

implementation

uses
  Atlas.Text.LogMarks;

class function TLogEntryText.Plain(const AEntry: TLogEntry): string;
begin
  Result := TLogMarks.Plain(AEntry.Text);
end;

class function TLogEntryText.PlainLine(const AEntry: TLogEntry): string;
begin
  Result := TLogMarks.Plain(AEntry.ToText);
end;

end.
