unit Atlas.Core.Files.TextDiff;

// Zeilenvergleich zweier Texte für „Vergleichen“ im Sammeldialog (#536):
// gleicher Anfang und gleiches Ende fallen weg; bei gleicher Zeilenzahl nur die
// geänderten Zeilen, sonst der geänderte Block. Zeilen mit Nummer im alten
// Text, "- " alt, "+ " neu. Zerlegen (CRLF, LF, CR) und Vergleichen kommen aus
// Atlas.Text (ADR 0012); eine zusätzliche letzte Zeilenschaltung zählt als
// Unterschied.

interface

uses
  System.SysUtils;

type
  TAtlasTextDiff = class
  public const
    MaxLines = 400;
  public
    /// <summary>Unterschied von AOld (z. B. Puffer) zu ANew (z. B. Platte); leer, wenn gleich.</summary>
    class function Lines(const AOld, ANew: string): TArray<string>; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Text.Diff;

class function TAtlasTextDiff.Lines(const AOld, ANew: string): TArray<string>;
begin
  Result := TTextDiff.ChangedLines(TTextLines.SplitLines(AOld), TTextLines.SplitLines(ANew), MaxLines);
end;

end.
