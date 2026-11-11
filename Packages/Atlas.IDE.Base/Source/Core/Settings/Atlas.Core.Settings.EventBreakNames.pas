unit Atlas.Core.Settings.EventBreakNames;

// Liste der häufigen Ereignisse für debug.breakOnNextEvent.excluded (#856):
// Vorgabe, Zerlegen und Normalisieren. Liegt bei den Einstellungen, damit
// der Parser ohne den Debug-Kern auskommt (wie
// Atlas.Core.Settings.VisualizerKinds); die Auswahl der Handler rechnet
// Atlas.Core.Debug.EventBreak.

interface

uses
  System.SysUtils;

type
  TAtlasEventBreakSettings = class
  public const
    cDefaultExcluded = 'OnPaint, OnMouseMove, OnUpdate';
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
  mPart, mName: string;
  mFound: Boolean;
  mExisting: string;
begin
  Result := nil;
  for mPart in AText.Split([',', ';', ' ', #9, #13, #10]) do
  begin
    mName := Trim(mPart);
    if mName = '' then
    begin
      Continue;
    end;
    mFound := False;
    for mExisting in Result do
    begin
      if SameText(mExisting, mName) then
      begin
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TAtlasEventBreakSettings.NormalizeExcluded(const AText: string): string;
begin
  Result := string.Join(', ', ExcludedList(AText));
end;

end.
