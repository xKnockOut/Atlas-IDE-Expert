unit Atlas.UI.Popup.Strings;

// Oberflächentexte des Features Popup auf Deutsch und Englisch, bisher nur die Kennzahlen-Karte der
// Brotkrumen. Die Sprache bestimmt `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit
// die Karte nicht die Texte der Gliederung braucht (die Gliederung verwendet die Karte).

interface

{$SCOPEDENUMS ON}

type
  TAtlasPopupTextId = (
    MetricsLines, MetricsCyclomatic, MetricsNesting, MetricsParameters, MetricsMembers, MetricsInheritance,
    MetricsLimit, MetricsMissing);

  TAtlasPopupStrings = class
  public
    class function Text(AId: TAtlasPopupTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasPopupTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Plugin.Localization.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasPopupTextId] of string = (
    ('Zeilen',
     'Zyklomatische Komplexität',
     'Verschachtelungstiefe',
     'Parameter',
     'Mitglieder',
     'Vererbungstiefe',
     '%s (Grenze %d)',
     'Kennzahlen noch nicht verfügbar'),
    ('Lines',
     'Cyclomatic complexity',
     'Nesting depth',
     'Parameters',
     'Members',
     'Inheritance depth',
     '%s (limit %d)',
     'Metrics not available yet'));

{ TAtlasPopupStrings }

class function TAtlasPopupStrings.Text(AId: TAtlasPopupTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasPopupStrings.Fmt(AId: TAtlasPopupTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
