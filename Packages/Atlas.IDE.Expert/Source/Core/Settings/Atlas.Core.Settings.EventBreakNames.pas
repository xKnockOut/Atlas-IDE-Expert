unit Atlas.Core.Settings.EventBreakNames;

// Liste der häufigen Ereignisse für debug.breakOnNextEvent.excluded (#856):
// Vorgabe, Zerlegen und Normalisieren. Liegt bei den Einstellungen, damit
// der Parser ohne den Debug-Kern auskommt (A-09, wie
// Atlas.Core.Settings.VisualizerKinds); die Auswahl der Handler rechnet
// Atlas.Core.Debug.EventBreak.

interface

uses
  System.SysUtils;

type
  TAtlasEventBreakSettings = class
  public const
    DefaultExcluded = 'OnPaint, OnMouseMove, OnUpdate';
  public
    /// <summary>Namen aus einer durch Komma, Semikolon oder Leerraum getrennten Liste: getrimmt, ohne Leere und
    /// Doppelte (ohne Rücksicht auf Groß-/Kleinschreibung), Reihenfolge bleibt.</summary>
    class function ExcludedList(const AText: string): TArray<string>; static;
    /// <summary>Kommagetrennte Liste aufgeräumt wie ExcludedList, mit „, “ verbunden.</summary>
    class function NormalizeExcluded(const AText: string): string; static;
  end;

implementation

{ TAtlasEventBreakSettings }

class function TAtlasEventBreakSettings.ExcludedList(const AText: string): TArray<string>;
var
  Part, Name: string;
  Found: Boolean;
  Existing: string;
begin
  Result := nil;
  for Part in AText.Split([',', ';', ' ', #9, #13, #10]) do
  begin
    Name := Trim(Part);
    if Name = '' then
      Continue;
    Found := False;
    for Existing in Result do
      if SameText(Existing, Name) then
        Found := True;
    if not Found then
      Result := Result + [Name];
  end;
end;

class function TAtlasEventBreakSettings.NormalizeExcluded(const AText: string): string;
begin
  Result := string.Join(', ', ExcludedList(AText));
end;

end.
