unit Atlas.Tests.SlashHost;

// Testhilfe für Schnellbefehle: ein Editor-Host ohne Projekt, der Hinweise
// (Notify) und Cursorziele (MoveCursor) mitschreibt. Einstellungen, Dateien,
// Regeltreffer und uses-Kontext lassen sich vorgeben (#297).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.SlashCommands;

type
  TRecordingSlashHost = class(TInterfacedObject, ISlashHost)
  public
    Notes: TArray<string>;
    CursorUri: string;
    Cursor: TTextPosition;
    HasCursor: Boolean;
    /// <summary>Einstellungen als 'name=wert'.</summary>
    Settings: TArray<string>;
    /// <summary>Dateien als 'pfad=text'.</summary>
    Files: TArray<string>;
    /// <summary>Antwort für RuleIdsAt; ohne HasRuleIds False.</summary>
    RuleIds: TArray<string>;
    HasRuleIds: Boolean;
    /// <summary>Zuletzt bei RuleIdsAt gefragte Zeile; -1 = nie.</summary>
    RuleLine: Integer;
    /// <summary>Antwort für UsesContext; ohne HasUses False.</summary>
    Uses_: TUsesContext;
    HasUses: Boolean;
    /// <summary>Antwort für FindingsAt; ohne HasFindings False.</summary>
    Findings: TArray<TSlashFinding>;
    HasFindings: Boolean;
    constructor Create;
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    procedure WriteProject(const AUri, AText: string);
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
    function HeaderTemplate(const AUri: string): string;
    procedure WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
    function Setting(const AUri, AName: string): string;
    function TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
    procedure Notify(const AUri, AMessage: string);
    procedure MoveCursor(const AUri: string; const APosition: TTextPosition);
    function RuleIdsAt(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean;
    function UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
    function FindingsAt(const AUri, AText: string; ALine: Integer; out AFindings: TArray<TSlashFinding>): Boolean;
  end;

implementation

/// <summary>Wert zu AName aus 'name=wert'-Paaren; False ohne.</summary>
function ValueOf(const APairs: TArray<string>; const AName: string; out AValue: string): Boolean;
var
  Pair: string;
begin
  AValue := '';
  for Pair in APairs do
    if SameText(Copy(Pair, 1, Pos('=', Pair) - 1), AName) then
    begin
      AValue := Copy(Pair, Pos('=', Pair) + 1, MaxInt);
      Exit(True);
    end;
  Result := False;
end;

constructor TRecordingSlashHost.Create;
begin
  inherited Create;
  RuleLine := -1;
end;

function TRecordingSlashHost.Project(const AUri: string; out AProject: TProjectInfo): Boolean;
begin
  AProject := Default(TProjectInfo);
  Result := False;
end;

function TRecordingSlashHost.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := ValueOf(Files, AFileName, AText);
end;

function TRecordingSlashHost.DirectoryExists(const APath: string): Boolean;
begin
  Result := False;
end;

procedure TRecordingSlashHost.WriteProject(const AUri, AText: string);
begin
end;

procedure TRecordingSlashHost.SelectBuild(const AUri, AConfig, APlatform: string);
begin
end;

procedure TRecordingSlashHost.ShowDocument(const AFileName: string; const ASelection: TTextRange);
begin
end;

function TRecordingSlashHost.HeaderTemplate(const AUri: string): string;
begin
  Result := '';
end;

procedure TRecordingSlashHost.WriteFiles(const AUri: string; const AFiles: TArray<TSlashFile>; const AShow: string);
begin
end;

function TRecordingSlashHost.Setting(const AUri, AName: string): string;
begin
  ValueOf(Settings, AName, Result);
end;

function TRecordingSlashHost.TestUnit(const AUri, AText: string; out ATarget: TSlashTestUnit): Boolean;
begin
  ATarget := Default(TSlashTestUnit);
  ATarget.Reason := 'Keine Testunits im Test';
  Result := False;
end;

procedure TRecordingSlashHost.Notify(const AUri, AMessage: string);
begin
  Notes := Notes + [AMessage];
end;

procedure TRecordingSlashHost.MoveCursor(const AUri: string; const APosition: TTextPosition);
begin
  CursorUri := AUri;
  Cursor := APosition;
  HasCursor := True;
end;

function TRecordingSlashHost.RuleIdsAt(const AUri, AText: string; ALine: Integer;
  out AIds: TArray<string>): Boolean;
begin
  RuleLine := ALine;
  AIds := RuleIds;
  Result := HasRuleIds;
end;

function TRecordingSlashHost.UsesContext(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Uses_;
  Result := HasUses;
end;

function TRecordingSlashHost.FindingsAt(const AUri, AText: string; ALine: Integer;
  out AFindings: TArray<TSlashFinding>): Boolean;
begin
  RuleLine := ALine;
  AFindings := Findings;
  Result := HasFindings;
end;

end.
