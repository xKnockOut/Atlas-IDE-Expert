unit Atlas.Core.Files.TextDiff;

// Zeilenvergleich zweier Texte für „Vergleichen“ im Sammeldialog (#536):
// gleicher Anfang und gleiches Ende fallen weg; bei gleicher Zeilenzahl nur die
// geänderten Zeilen, sonst der geänderte Block. Zeilen mit Nummer im alten
// Text, "- " alt, "+ " neu. Zerlegen (CRLF, LF, CR) und Vergleichen kommen aus
// Atlas.Text; eine zusätzliche letzte Zeilenschaltung zählt als
// Unterschied.

interface

uses
  System.SysUtils;

type
  TAtlasTextDiff = class
  public const
    cMaxLines = 400;
  public
    /// <summary>Unterschied von AOld (z. B. Puffer) zu ANew (z. B. Platte); leer, wenn gleich.</summary>
    class function Lines(const AOld, ANew: string): TArray<string>; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TTextDiffText = (Line, FromLine);

const
  cTexts: array[TAtlasLanguage, TTextDiffText] of string = (
    ('Zeile %d:', 'ab Zeile %d:'),
    ('Line %d:', 'from line %d:'));

{$SCOPEDENUMS OFF}

{ TAtlasTextDiff }

class function TAtlasTextDiff.Lines(const AOld, ANew: string): TArray<string>;
var
  mLabels: TTextDiffLabels;
begin
  mLabels.Line := cTexts[TAtlasTextLanguage.Current, TTextDiffText.Line];
  mLabels.FromLine := cTexts[TAtlasTextLanguage.Current, TTextDiffText.FromLine];
  Result := TTextDiff.ChangedLines(TTextLines.SplitLines(AOld), TTextLines.SplitLines(ANew), mLabels, cMaxLines);
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Files.TextDiff', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
