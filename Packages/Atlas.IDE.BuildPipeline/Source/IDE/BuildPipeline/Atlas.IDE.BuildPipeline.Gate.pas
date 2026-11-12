unit Atlas.IDE.BuildPipeline.Gate;

// Prüfung vor dem Kompilieren in der IDE (#529); Entscheidungen in
// Atlas.Core.BuildPipeline.Gate.
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
  Atlas.Core.BuildPipeline.Gate;

type
  TAtlasIdeBuildGate = class
  public const
    cMessageGroup = 'Atlas';
  public
    /// <summary>Teilnehmer für TAtlasCompileEvents.Add; ASession liefert die laufende Sitzung oder nil.</summary>
    class function CreateParticipant(const ASettings: TAtlasGateSettingsFunc;
      const ASession: TAtlasSessionFunc): TAtlasBuildGateParticipant; static;
  end;

implementation

uses
  Atlas.Core.Build.Events,
  System.Hash,
  ToolsAPI,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.UI.BuildPipeline.Strings;

function MessageServices(out AMessages: IOTAMessageServices; out AGroup: IOTAMessageGroup): Boolean;
begin
  AGroup := nil;
  Result := Supports(BorlandIDEServices, IOTAMessageServices, AMessages);
  if not Result then
  begin
    Exit;
  end;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  AGroup := AMessages.GetGroup(TAtlasIdeBuildGate.cMessageGroup);
  if AGroup = nil then
  begin
    AGroup := AMessages.AddMessageGroup(TAtlasIdeBuildGate.cMessageGroup);
  end;
end;

function ProjectOf(const AFileName: string): IOTAProject;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Supports(mModules.FindModule(AFileName), IOTAProject, Result);
  end;
end;

function IsPascalFile(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.pas') or (mExt = '.dpr') or (mExt = '.dpk');
end;

/// <summary>Stand einer Unit: ungespeicherter Puffer = Prüfsumme, sonst Zeitstempel der Datei. False ohne Datei
/// und Puffer.</summary>
function UnitState(const AFileName: string; out AUnit: TAtlasGateUnit): Boolean;
var
  mBuffer: IOTAEditBuffer;
  mText: string;
  mAge: TDateTime;
begin
  AUnit := Default(TAtlasGateUnit);
  AUnit.FileName := AFileName;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if (mBuffer <> nil) and mBuffer.IsModified then
  begin
    mText := TAtlasEditorBuffer.Text(mBuffer);
    AUnit.Stamp := Format('b:%d:%x', [Length(mText), THashBobJenkins.GetHashValue(mText)]);
    AUnit.ModifiedAt := Now;
    Exit(True);
  end;
  Result := FileAge(AFileName, mAge);
  if Result then
  begin
    AUnit.Stamp := 'd:' + FloatToStr(mAge, TFormatSettings.Invariant);
    AUnit.ModifiedAt := mAge;
  end;
end;

function ReadUnits(const AProject: TAtlasCompileProject; out AUnits: TAtlasGateUnits;
  out AOutputTime: TDateTime): Boolean;
var
  mProject: IOTAProject;
  mIndex: Integer;
  mName: string;
  mItem: TAtlasGateUnit;
begin
  AUnits := nil;
  AOutputTime := 0;
  mProject := ProjectOf(AProject.FileName);
  Result := mProject <> nil;
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to mProject.GetModuleCount - 1 do
  begin
    mName := mProject.GetModule(mIndex).FileName;
    if (mName <> '') and IsPascalFile(mName) and UnitState(mName, mItem) then
    begin
      AUnits := AUnits + [mItem];
    end;
  end;
  // Projektquelltext (.dpr/.dpk) steht nicht unter den Modulen des Projekts.
  for mIndex := 0 to mProject.ModuleFileCount - 1 do
  begin
    mName := mProject.ModuleFileEditors[mIndex].FileName;
    if TAtlasIdeFiles.IsProjectSource(mName) and UnitState(mName, mItem) then
    begin
      AUnits := AUnits + [mItem];
    end;
  end;
  if (AProject.OutputFile = '') or not FileAge(AProject.OutputFile, AOutputTime) then
  begin
    AOutputTime := 0;
  end;
end;

function CheckUnit(const ASession: TLspSession; const AFileName: string; ATimeoutMs: Integer;
  out AProblems: TArray<TAtlasProblem>): Boolean;
var
  mBuffer: IOTAEditBuffer;
  mAnswer: TLspDiagnosticReport;
begin
  AProblems := nil;
  Result := False;
  if ASession = nil then
  begin
    Exit;
  end;
  try
    // Puffer der IDE zuerst (#395): Geprüft wird, was gleich kompiliert wird, auch ungespeichert.
    mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
    if mBuffer <> nil then
    begin
      ASession.Sync(AFileName, TAtlasEditorBuffer.Text(mBuffer));
    end;
    mAnswer := ASession.DocumentDiagnostics(AFileName, '', Cardinal(ATimeoutMs));
    AProblems := mAnswer.Problems;
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
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
  mLineRef: Pointer;
  mFinding: TAtlasGateFinding;
  mText: string;
begin
  Result := '';
  if AOutcome = TAtlasGateOutcome.Blocked then
  begin
    Result := TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.GateBlockReason, [Length(AFindings)]);
  end;
  if not MessageServices(mMessages, mGroup) then
  begin
    Exit;
  end;
  if Length(AFindings) > 0 then
  begin
    mMessages.AddTitleMessage(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.GateFindings, [Length(AFindings),
      ExtractFileName(AProject.FileName), ACheckedUnits]), mGroup);
    for mFinding in AFindings do
    begin
      mText := mFinding.Problem.Message;
      if mFinding.Problem.Code <> '' then
      begin
        mText := '[' + mFinding.Problem.Code + '] ' + mText;
      end;
      mMessages.AddToolMessage(mFinding.FileName, mText, 'Atlas', mFinding.Problem.StartLine + 1,
        mFinding.Problem.StartCharacter + 1, nil, mLineRef, mGroup);
    end;
  end;
  case AOutcome of
    TAtlasGateOutcome.Blocked:
      mMessages.AddTitleMessage(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.GateBlocked), mGroup);
    TAtlasGateOutcome.Overridden:
      mMessages.AddTitleMessage(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.GateOverridden), mGroup);
    TAtlasGateOutcome.Passed, TAtlasGateOutcome.Reported, TAtlasGateOutcome.TimedOut: ;
  end;
  if ANotifyTimeout then
  begin
    mMessages.AddTitleMessage(TAtlasBuildPipelineStrings.Fmt(TAtlasBuildPipelineTextId.GateTimedOut, [ATimeoutMs]),
      mGroup);
  end;
  mMessages.ShowMessageView(mGroup);
end;

{ TAtlasIdeBuildGate }

class function TAtlasIdeBuildGate.CreateParticipant(const ASettings: TAtlasGateSettingsFunc;
  const ASession: TAtlasSessionFunc): TAtlasBuildGateParticipant;
var
  mSettings: TAtlasGateSettingsFunc;
  mSession: TAtlasSessionFunc;
begin
  mSettings := ASettings;
  mSession := ASession;
  Result := TAtlasBuildGateParticipant.Create(mSettings,
    function(const AProject: TAtlasCompileProject; out AUnits: TAtlasGateUnits; out AOutputTime: TDateTime): Boolean
    begin
      AUnits := nil;
      AOutputTime := 0;
      Result := False;
      // Ohne laufenden Server keine Prüfung; Atlas startet ihn dafür nicht (#874).
      if mSession() = nil then
      begin
        Exit;
      end;
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
      Result := CheckUnit(mSession(), AFileName, ATimeoutMs, AProblems);
    end,
    function(const AProject: TAtlasCompileProject; const AFindings: TAtlasGateFindings; ACheckedUnits: Integer;
      AOutcome: TAtlasGateOutcome; ANotifyTimeout: Boolean): string
    begin
      Result := Report(AProject, AFindings, ACheckedUnits, AOutcome, ANotifyTimeout, mSettings().TimeoutMs);
    end, nil);
end;

end.
