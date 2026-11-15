unit Atlas.Core.Tracker.CodeLinkPlan;

// Entscheidungen der Issue-Kennungen im Editor (#1265) ohne IDE prüfbar (#1967); die IDE
// (Atlas.IDE.Tracker.CodeLinks) ruft nur noch Editor, Zeitgeber, Maus und Menü:
// - welche Dateien Kennungen zeigen und wann ein Stand neu gerechnet wird (Datei, Pufferstand, Muster);
// - welche Zeile des Stands eine gezeichnete Zeile des Editors ist;
// - welche Klicks Atlas vor dem Editor abfängt und welcher Befehl ein Strg+Klick ist.

interface

uses
  Atlas.Core.Tracker.Contract;

type
  TAtlasCodeLinkPlan = class
  public const
    cMenuShow = 1;
    cMenuBrowse = 2;
    cMenuCopy = 3;
    cMenuStart = 4;
  public
    /// <summary>Schlüssel des Musters: Tracker ATarget und Commit-Präfix ACommit.</summary>
    class function PatternKey(const ATarget: TAtlasTrackerTarget; const ACommit: string): string; static;
    /// <summary>Zeigt AFileName Kennungen (Pascal-Quelltext)?</summary>
    class function IsPascal(const AFileName: string): Boolean; static;
    /// <summary>Gilt der gemerkte Stand (AFileName, AVersion, APatternKey) noch für den Puffer ASnapshotFile mit
    /// ASnapshotVersion und das Muster AKey? Dateinamen ohne Groß-/Kleinschreibung.</summary>
    class function Unchanged(ASnapshotVersion: Cardinal; const ASnapshotFile, AKey: string; AVersion: Cardinal;
      const AFileName, APatternKey: string): Boolean; static;
    /// <summary>Zeile (0-basiert) von ALines, die der Editor als logische Zeile ALineNum (1-basiert) mit dem Text
    /// AText zeichnet; -1, wenn sie außerhalb liegt oder der Text (ohne Leerraum am Ende) abweicht.</summary>
    class function PaintedLine(ALineNum: Integer; const AText: string; const ALines: TArray<string>): Integer;
      static;
    /// <summary>Fängt Atlas den Klick ab? Strg+Linksklick oder Rechtsklick ohne Umschalt (Umschalt+Rechtsklick:
    /// Kontextmenü der IDE).</summary>
    class function Catches(ALeft, ARight, ACtrl, AShift: Boolean): Boolean; static;
    /// <summary>Befehl zum Strg+Klick: Vorschau, mit Umschalt der Browser.</summary>
    class function ClickCommand(AShift: Boolean): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

class function TAtlasCodeLinkPlan.PatternKey(const ATarget: TAtlasTrackerTarget; const ACommit: string): string;
begin
  Result := ATarget.Provider + #1 + ATarget.Url + #1 + ATarget.Project + #1 + ACommit;
end;

class function TAtlasCodeLinkPlan.IsPascal(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc', '.lpr', '.pp']);
end;

class function TAtlasCodeLinkPlan.Unchanged(ASnapshotVersion: Cardinal; const ASnapshotFile, AKey: string;
  AVersion: Cardinal; const AFileName, APatternKey: string): Boolean;
begin
  Result := (ASnapshotVersion = AVersion) and SameText(ASnapshotFile, AFileName) and (AKey = APatternKey);
end;

class function TAtlasCodeLinkPlan.PaintedLine(ALineNum: Integer; const AText: string;
  const ALines: TArray<string>): Integer;
begin
  Result := ALineNum - 1;
  if (Result < 0) or (Result >= Length(ALines)) or (TrimRight(AText) <> TrimRight(ALines[Result])) then
  begin
    Result := -1;
  end;
end;

class function TAtlasCodeLinkPlan.Catches(ALeft, ARight, ACtrl, AShift: Boolean): Boolean;
begin
  Result := (ALeft and ACtrl) or (ARight and not AShift);
end;

class function TAtlasCodeLinkPlan.ClickCommand(AShift: Boolean): Integer;
begin
  Result := cMenuShow;
  if AShift then
  begin
    Result := cMenuBrowse;
  end;
end;

end.
