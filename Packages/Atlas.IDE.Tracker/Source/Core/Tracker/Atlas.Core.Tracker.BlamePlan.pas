unit Atlas.Core.Tracker.BlamePlan;

// Entscheidungen der Issues in der Zeilenhistorie (#1275) ohne IDE prüfbar (#1967); die IDE
// (Atlas.IDE.Tracker.BlameLinks) ruft nur noch Editor, Menü, Versionsverwaltung und Vorschau:
// - Stand je Kennung im Hover: nach der Antwort des Trackers (gefunden, nicht gefunden, Fehler) und was der Hover
//   zeigt (ohne Netz bleibt ein vorhandener Stand stehen).
// - Schlüssel der Stände und der Zählung je Bereich und Stand der Arbeitskopie.
// - Menüeinträge als Zahl (Kennung und Befehl) und welche Klicks auf die Randanzeige Atlas abfängt.

interface

uses
  Atlas.Core.CiBuild.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Stand einer Kennung im Hover.</summary>
  TAtlasBlameKeyState = (Loading, Found, NotFound, Failed);
{$SCOPEDENUMS OFF}

  TAtlasBlamePlan = class
  public const
    cMenuShow = 1;
    cMenuBrowse = 2;
    cMenuCopy = 3;
    cMenuScope = 4;
    /// <summary>Menüeintrag = Kennung * cMenuStride + Befehl.</summary>
    cMenuStride = 8;
  public
    /// <summary>Schlüssel des Stands einer Kennung (Muster|Kennung, Kennung ohne Groß-/Kleinschreibung).</summary>
    class function StateKey(const APatternKey, AKey: string): string; static;
    /// <summary>Schlüssel der Zählung: Bereich, Stand der Arbeitskopie (AMarker) und Muster; ein Commit oder Wechsel
    /// des Branchs zählt neu.</summary>
    class function CountKey(const AFileName: string; AFirst, ALast: Integer; const AName, AMarker,
      APatternKey: string): string; static;
    /// <summary>Stand nach der Antwort des Trackers.</summary>
    class function LookupState(ASucceeded: Boolean; AError: TAtlasCiFetchError): TAtlasBlameKeyState; static;
    /// <summary>Was der Hover zeigt: AKnown/AState: gemerkter Stand, ACached: Details im Speicher der Vorschau.
    /// „Nicht gefunden“ geht vor, ein vorhandener Stand vor einem Fehler.</summary>
    class function ShownState(AKnown: Boolean; AState: TAtlasBlameKeyState; ACached: Boolean): TAtlasBlameKeyState;
      static;
    /// <summary>Fehler zur Anzeige: nur bei „nicht gefunden“ und Fehler der gemerkte AError.</summary>
    class function ShownError(AShown: TAtlasBlameKeyState; AError: TAtlasCiFetchError): TAtlasCiFetchError; static;
    class function MenuTag(AKey, ACommand: Integer): Integer; static;
    class function MenuCommand(ATag: Integer): Integer; static;
    class function MenuKey(ATag: Integer): Integer; static;
    /// <summary>Fängt Atlas den Klick ab? Wie bei den Kennungen im Code (TAtlasCodeLinkPlan.Catches).</summary>
    class function Catches(ALeft, ARight, ACtrl, AShift: Boolean): Boolean; static;
    /// <summary>Befehl zum Strg+Klick: Vorschau, mit Umschalt der Browser.</summary>
    class function ClickCommand(AShift: Boolean): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.CodeLinkPlan;

class function TAtlasBlamePlan.StateKey(const APatternKey, AKey: string): string;
begin
  Result := APatternKey + #1 + UpperCase(AKey);
end;

class function TAtlasBlamePlan.CountKey(const AFileName: string; AFirst, ALast: Integer; const AName, AMarker,
  APatternKey: string): string;
begin
  Result := AFileName + #1 + IntToStr(AFirst) + #1 + IntToStr(ALast) + #1 + AName + #1 + AMarker + #1 + APatternKey;
end;

class function TAtlasBlamePlan.LookupState(ASucceeded: Boolean; AError: TAtlasCiFetchError): TAtlasBlameKeyState;
begin
  if ASucceeded then
  begin
    Result := TAtlasBlameKeyState.Found;
  end
  else if AError = TAtlasCiFetchError.NotFound then
  begin
    Result := TAtlasBlameKeyState.NotFound;
  end
  else
  begin
    Result := TAtlasBlameKeyState.Failed;
  end;
end;

class function TAtlasBlamePlan.ShownState(AKnown: Boolean; AState: TAtlasBlameKeyState;
  ACached: Boolean): TAtlasBlameKeyState;
begin
  if AKnown and (AState = TAtlasBlameKeyState.NotFound) then
  begin
    Result := TAtlasBlameKeyState.NotFound;
  end
  else if ACached then
  begin
    Result := TAtlasBlameKeyState.Found;
  end
  else if AKnown and (AState = TAtlasBlameKeyState.Failed) then
  begin
    Result := TAtlasBlameKeyState.Failed;
  end
  else
  begin
    Result := TAtlasBlameKeyState.Loading;
  end;
end;

class function TAtlasBlamePlan.ShownError(AShown: TAtlasBlameKeyState;
  AError: TAtlasCiFetchError): TAtlasCiFetchError;
begin
  Result := TAtlasCiFetchError.None;
  if AShown in [TAtlasBlameKeyState.NotFound, TAtlasBlameKeyState.Failed] then
  begin
    Result := AError;
  end;
end;

class function TAtlasBlamePlan.MenuTag(AKey, ACommand: Integer): Integer;
begin
  Result := AKey * cMenuStride + ACommand;
end;

class function TAtlasBlamePlan.MenuCommand(ATag: Integer): Integer;
begin
  Result := ATag mod cMenuStride;
end;

class function TAtlasBlamePlan.MenuKey(ATag: Integer): Integer;
begin
  Result := ATag div cMenuStride;
end;

class function TAtlasBlamePlan.Catches(ALeft, ARight, ACtrl, AShift: Boolean): Boolean;
begin
  Result := TAtlasCodeLinkPlan.Catches(ALeft, ARight, ACtrl, AShift);
end;

class function TAtlasBlamePlan.ClickCommand(AShift: Boolean): Integer;
begin
  Result := cMenuShow;
  if AShift then
  begin
    Result := cMenuBrowse;
  end;
end;

end.
