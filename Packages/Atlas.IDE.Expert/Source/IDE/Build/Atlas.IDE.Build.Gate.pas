unit Atlas.IDE.Build.Gate;

// Prüfung vor dem Kompilieren in der IDE (#529); Entscheidungen in
// Atlas.Core.Build.Gate.
// - Units: die Pascal-Dateien des Projekts (.pas, .dpr, .dpk) aus der IDE.
//   Stand eines ungespeicherten Puffers ist eine Prüfsumme seines Texts, sonst
//   der Zeitstempel der Datei; Vergleichszeit ist die Ausgabedatei des
//   Projekts (TargetName).
// - Prüfung je Unit über den laufenden Server: zuerst bekommt er den Text des
//   Puffers (#395, auch ungespeichert), dann textDocument/diagnostic mit der
//   verbleibenden Zeit. Ohne laufende Sitzung prüft Atlas nicht und startet den
//   Server dafür auch nicht.
// - Meldungen: Atlas-Gruppe des Meldungsfensters, eine Kopfzeile, je Treffer
//   eine Zeile mit Datei und Position (Doppelklick springt hin), dazu Abbruch,
//   bewusstes Übergehen bzw. das Zeitlimit (einmal je Sitzung).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Gate;

type
  TAtlasIdeBuildGate = class
  public const
    MessageGroup = 'Atlas';
  public
    /// <summary>Teilnehmer für TAtlasCompileEvents.Add; ASession liefert die laufende Sitzung oder nil.</summary>
    class function CreateParticipant(const ASettings: TAtlasGateSettingsFunc;
      const ASession: TAtlasSessionFunc): TAtlasBuildGateParticipant; static;
  end;

implementation

uses
  System.Hash,
  ToolsAPI,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.UI.Strings;

function MessageServices(out AMessages: IOTAMessageServices; out AGroup: IOTAMessageGroup): Boolean;
begin
  AGroup := nil;
  Result := Supports(BorlandIDEServices, IOTAMessageServices, AMessages);
  if not Result then
    Exit;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  AGroup := AMessages.GetGroup(TAtlasIdeBuildGate.MessageGroup);
  if AGroup = nil then
    AGroup := AMessages.AddMessageGroup(TAtlasIdeBuildGate.MessageGroup);
end;

function ProjectOf(const AFileName: string): IOTAProject;
var
  Modules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Supports(Modules.FindModule(AFileName), IOTAProject, Result);
end;

function IsPascalFile(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk');
end;

/// <summary>Stand einer Unit: ungespeicherter Puffer = Prüfsumme, sonst Zeitstempel der Datei. False ohne Datei
/// und Puffer.</summary>
function UnitState(const AFileName: string; out AUnit: TAtlasGateUnit): Boolean;
var
  Buffer: IOTAEditBuffer;
  Text: string;
  Age: TDateTime;
begin
  AUnit := Default(TAtlasGateUnit);
  AUnit.FileName := AFileName;
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if (Buffer <> nil) and Buffer.IsModified then
  begin
    Text := TAtlasEditorBuffer.Text(Buffer);
    AUnit.Stamp := Format('b:%d:%x', [Length(Text), THashBobJenkins.GetHashValue(Text)]);
    AUnit.ModifiedAt := Now;
    Exit(True);
  end;
  Result := FileAge(AFileName, Age);
  if Result then
  begin
    AUnit.Stamp := 'd:' + FloatToStr(Age);
    AUnit.ModifiedAt := Age;
  end;
end;

function ReadUnits(const AProject: TAtlasCompileProject; out AUnits: TAtlasGateUnits;
  out AOutputTime: TDateTime): Boolean;
var
  Project: IOTAProject;
  Index: Integer;
  Name: string;
  Item: TAtlasGateUnit;
begin
  AUnits := nil;
  AOutputTime := 0;
  Project := ProjectOf(AProject.FileName);
  Result := Project <> nil;
  if not Result then
    Exit;
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    Name := Project.GetModule(Index).FileName;
    if (Name <> '') and IsPascalFile(Name) and UnitState(Name, Item) then
      AUnits := AUnits + [Item];
  end;
  // Projektquelltext (.dpr/.dpk) steht nicht unter den Modulen des Projekts.
  for Index := 0 to Project.ModuleFileCount - 1 do
  begin
    Name := Project.ModuleFileEditors[Index].FileName;
    if TAtlasIdeFiles.IsProjectSource(Name) and UnitState(Name, Item) then
      AUnits := AUnits + [Item];
  end;
  if (AProject.OutputFile = '') or not FileAge(AProject.OutputFile, AOutputTime) then
    AOutputTime := 0;
end;

function CheckUnit(const ASession: TLspSession; const AFileName: string; ATimeoutMs: Integer;
  out AProblems: TArray<TAtlasProblem>): Boolean;
var
  Buffer: IOTAEditBuffer;
  Answer: TLspDiagnosticReport;
begin
  AProblems := nil;
  Result := False;
  if ASession = nil then
    Exit;
  try
    // Puffer der IDE zuerst (#395): Geprüft wird, was gleich kompiliert wird, auch ungespeichert.
    Buffer := TAtlasIdeFiles.BufferOf(AFileName);
    if Buffer <> nil then
      ASession.Sync(AFileName, TAtlasEditorBuffer.Text(Buffer));
    Answer := ASession.DocumentDiagnostics(AFileName, '', Cardinal(ATimeoutMs));
    AProblems := Answer.Problems;
    Result := True;
  except
    // Zeitlimit oder Server weg: Unit nicht geprüft, der Compile läuft (#493).
    on Exception do
      Result := False;
  end;
end;

function Report(const AProject: TAtlasCompileProject; const AFindings: TAtlasGateFindings; ACheckedUnits: Integer;
  AOutcome: TAtlasGateOutcome; ANotifyTimeout: Boolean; ATimeoutMs: Integer): string;
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
  LineRef: Pointer;
  Finding: TAtlasGateFinding;
  Text: string;
begin
  Result := '';
  if AOutcome = TAtlasGateOutcome.Blocked then
    Result := TAtlasStrings.Fmt(TAtlasTextId.GateBlockReason, [Length(AFindings)]);
  if not MessageServices(Messages, Group) then
    Exit;
  if Length(AFindings) > 0 then
  begin
    Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.GateFindings, [Length(AFindings),
      ExtractFileName(AProject.FileName), ACheckedUnits]), Group);
    for Finding in AFindings do
    begin
      Text := Finding.Problem.Message;
      if Finding.Problem.Code <> '' then
        Text := '[' + Finding.Problem.Code + '] ' + Text;
      Messages.AddToolMessage(Finding.FileName, Text, 'Atlas', Finding.Problem.StartLine + 1,
        Finding.Problem.StartCharacter + 1, nil, LineRef, Group);
    end;
  end;
  case AOutcome of
    TAtlasGateOutcome.Blocked:
      Messages.AddTitleMessage(TAtlasStrings.Text(TAtlasTextId.GateBlocked), Group);
    TAtlasGateOutcome.Overridden:
      Messages.AddTitleMessage(TAtlasStrings.Text(TAtlasTextId.GateOverridden), Group);
  end;
  if ANotifyTimeout then
    Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.GateTimedOut, [ATimeoutMs]), Group);
  Messages.ShowMessageView(Group);
end;

{ TAtlasIdeBuildGate }

class function TAtlasIdeBuildGate.CreateParticipant(const ASettings: TAtlasGateSettingsFunc;
  const ASession: TAtlasSessionFunc): TAtlasBuildGateParticipant;
var
  Settings: TAtlasGateSettingsFunc;
  Session: TAtlasSessionFunc;
begin
  Settings := ASettings;
  Session := ASession;
  Result := TAtlasBuildGateParticipant.Create(Settings,
    function(const AProject: TAtlasCompileProject; out AUnits: TAtlasGateUnits; out AOutputTime: TDateTime): Boolean
    begin
      AUnits := nil;
      AOutputTime := 0;
      Result := False;
      // Ohne laufenden Server keine Prüfung; Atlas startet ihn dafür nicht (#874).
      if Session() = nil then
        Exit;
      try
        Result := ReadUnits(AProject, AUnits, AOutputTime);
      except
        // Nicht lesbar: keine Prüfung, der Compile läuft (#493).
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Build, E);
      end;
    end,
    function(const AFileName: string; ATimeoutMs: Integer; out AProblems: TArray<TAtlasProblem>): Boolean
    begin
      Result := CheckUnit(Session(), AFileName, ATimeoutMs, AProblems);
    end,
    function(const AProject: TAtlasCompileProject; const AFindings: TAtlasGateFindings; ACheckedUnits: Integer;
      AOutcome: TAtlasGateOutcome; ANotifyTimeout: Boolean): string
    begin
      Result := Report(AProject, AFindings, ACheckedUnits, AOutcome, ANotifyTimeout, Settings().TimeoutMs);
    end, nil);
end;

end.
