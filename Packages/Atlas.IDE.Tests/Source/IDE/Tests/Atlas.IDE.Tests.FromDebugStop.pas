unit Atlas.IDE.Tests.FromDebugStop;

// „Test aus dem Debug-Halt anlegen …“ (#1873) in der IDE: Ablauf vom Halt bis
// zum eingetragenen Test.
//   1. Rahmen des Halts von IAtlasDebugStopSource (Modul Debugger, über die
//      Registry; ohne Debugger eine Meldung).
//   2. atlas.server.testFromDebugStop "describe": Methode, Parameter, Felder.
//   3. Werte: Im aktuellen Rahmen wertet der Debugger Parameter und Felder
//      (Self.FName, mit tests.fromDebugStop.fields) aus, mit Gettern nur bei
//      tests.fromDebugStop.properties; in einem tieferen Rahmen kommen nur die
//      Parameter aus der Kopfzeile des Aufrufstacks.
//   4. "describe" mit den Werten: Literale, TODO, vorgeschlagener Name.
//   5. Dialog (Atlas.UI.Tests.FromDebugStop), dann "create": WorkspaceEdit in
//      einem Schritt anwenden (auch neue Testunit samt .dpr/.dproj) und zum
//      Test springen.
// Den Server fragt das Modul nebenläufig über TAtlasIdeHost; Antworten kommen
// nur, solange der Scope des Moduls offen ist (Regel 3).

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Contracts.DebugStop;

type
  TAtlasIdeTestFromDebug = class
  public const
    /// <summary>Kennung des Befehls; die Exception-Leiste des Debuggers ruft ihn darüber auf.</summary>
    cCommand = cAtlasTestFromDebugStopCommand;
  public
    /// <summary>Befehl sichtbar: Einstellung an und ein Modul liefert den Halt.</summary>
    class function Visible: Boolean; static;
    /// <summary>Ablauf starten; Meldungen in der Meldungsansicht.</summary>
    class procedure Run(const AScope: IAtlasModuleScope); static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Tests.FromDebugStop,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.UI.Tests.FromDebugStop,
  Atlas.UI.Tests.Strings;

const
  cTimeoutMs = 30000;

type
  /// <summary>Was zwischen den Antworten des Servers mitläuft.</summary>
  TStopRun = record
    Scope: IAtlasModuleScope;
    Frame: TAtlasDebugStopFrame;
    Uri: string;
    Line: Integer;
    Choice: TAtlasStopChoice;
    Description: TAtlasStopDescription;
  end;

/// <summary>Quelle des Halts aus der Registry; nil ohne Modul.</summary>
function StopSource: IAtlasDebugStopSource;
var
  mFound: IInterface;
begin
  Result := nil;
  for mFound in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasDebugStopSource) do
  begin
    if Supports(mFound, IAtlasDebugStopSource, Result) then
    begin
      Exit;
    end;
  end;
end;

procedure Fail(const AReason: string);
begin
  TAtlasIdeHost.Warning(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFromDebugFailed, [AReason]));
end;

function NoAnswer: string;
begin
  Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugNoAnswer);
end;

/// <summary>Befehl des Servers im Hintergrund; ADone im Hauptthread, solange der Scope offen ist.</summary>
procedure Ask(const ARun: TStopRun; const AMode: string; const ADone: TProc<string>);
begin
  if not TAtlasIdeHost.RunServerCommandAsync(ARun.Scope, TAtlasFeature.Generate,
    TAtlasTestFromDebugStop.cServerCommand, TAtlasTestFromDebugStop.Arguments(ARun.Uri, ARun.Line, AMode,
    ARun.Description, ARun.Choice), cTimeoutMs, ADone) then
  begin
    TAtlasIdeHost.Warning(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugBusy));
  end;
end;

/// <summary>Werte der Zeilen vom Debugger bzw. aus der Kopfzeile.</summary>
procedure ReadValues(var ARun: TStopRun);
var
  mSource: IAtlasDebugStopSource;
  mIndex: Integer;
  mText: string;
begin
  mSource := StopSource;
  if (mSource = nil) or not ARun.Frame.Current then
  begin
    TAtlasTestFromDebugStop.TakeArguments(ARun.Description,
      TAtlasTestFromDebugStop.HeaderArguments(ARun.Frame.Header));
    Exit;
  end;
  for mIndex := 0 to High(ARun.Description.Rows) do
  begin
    if ARun.Description.Rows[mIndex].Field and not TAtlasIdeSettings.Current.TestsFromDebugStopFields then
    begin
      Continue;
    end;
    if mSource.Evaluate(TAtlasTestFromDebugStop.Expression(ARun.Description.Rows[mIndex]),
      TAtlasIdeSettings.Current.TestsFromDebugStopProperties, mText) then
    begin
      ARun.Description.Rows[mIndex].Text := mText;
    end;
  end;
end;

/// <summary>Eingetragenen Test zeigen.</summary>
procedure ShowTest(const ACreated: TAtlasStopCreated);
var
  mFileName: string;
  mLine: Integer;
begin
  mFileName := TLspSession.UriToPath(ACreated.Uri);
  mLine := TAtlasTestFromDebugStop.TestLine(TAtlasIdeWorkspaceEdit.CurrentText(mFileName), ACreated.Fixture,
    ACreated.TestName);
  TAtlasIdeHost.Message(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFromDebugCreated, [ACreated.TestName,
    ExtractFileName(mFileName)]));
  if mLine >= 0 then
  begin
    TAtlasIdeNavigation.GoToLocation(mFileName, mLine, 0);
  end;
end;

/// <summary>Antwort auf "create": Edit anwenden und hinspringen.</summary>
procedure Created(const AJson: string);
var
  mCreated: TAtlasStopCreated;
  mValue: TJSONValue;
  mEdit: TLspWorkspaceEdit;
  mError: string;
begin
  mCreated := TAtlasTestFromDebugStop.ReadCreated(AJson, NoAnswer);
  if mCreated.Reason <> '' then
  begin
    Fail(mCreated.Reason);
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mEdit := TLspWorkspaceEdit.FromJson((mValue as TJSONObject).GetValue('edit'));
  finally
    mValue.Free;
  end;
  mError := TAtlasIdeWorkspaceEdit.Apply(mEdit, TAtlasUnopenedPolicy.OpenInEditor,
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugTitle)).Error;
  if mError <> '' then
  begin
    Fail(mError);
    Exit;
  end;
  ShowTest(mCreated);
end;

/// <summary>Zweite Antwort auf "describe": Dialog, dann "create".</summary>
function Described(const ARun: TStopRun): TProc<string>;
begin
  Result :=
    procedure(AJson: string)
    var
      mRun: TStopRun;
    begin
      mRun := ARun;
      mRun.Description := TAtlasTestFromDebugStop.ReadDescription(AJson, NoAnswer);
      if mRun.Description.Reason <> '' then
      begin
        Fail(mRun.Description.Reason);
        Exit;
      end;
      TAtlasTestFromDebugStop.KeepValues(mRun.Description, ARun.Description);
      TAtlasTestFromDebugStop.Preselect(mRun.Description);
      if not TAtlasTestFromDebugDialog.Execute(mRun.Description, mRun.Choice,
        ExtractFileName(mRun.Frame.FileName) + ':' + IntToStr(mRun.Frame.Line)) then
      begin
        Exit;
      end;
      Ask(mRun, TAtlasTestFromDebugStop.cModeCreate,
        procedure(ACreated: string)
        begin
          Created(ACreated);
        end);
    end;
end;

/// <summary>Erste Antwort auf "describe": Werte lesen und noch einmal fragen.</summary>
function Located(const ARun: TStopRun): TProc<string>;
begin
  Result :=
    procedure(AJson: string)
    var
      mRun: TStopRun;
      mIndex: Integer;
    begin
      mRun := ARun;
      mRun.Description := TAtlasTestFromDebugStop.ReadDescription(AJson, NoAnswer);
      if mRun.Description.Reason <> '' then
      begin
        Fail(mRun.Description.Reason);
        Exit;
      end;
      ReadValues(mRun);
      // Alle gelesenen Werte schicken, damit der Server zu jedem Literal bzw. TODO sagt.
      for mIndex := 0 to High(mRun.Description.Rows) do
      begin
        mRun.Description.Rows[mIndex].Chosen := mRun.Description.Rows[mIndex].Text <> '';
      end;
      Ask(mRun, TAtlasTestFromDebugStop.cModeDescribe, Described(mRun));
    end;
end;

{ TAtlasIdeTestFromDebug }

class function TAtlasIdeTestFromDebug.Visible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestsFromDebugStop and (StopSource <> nil);
end;

class procedure TAtlasIdeTestFromDebug.Run(const AScope: IAtlasModuleScope);
var
  mRun: TStopRun;
  mSource: IAtlasDebugStopSource;
begin
  mSource := StopSource;
  if mSource = nil then
  begin
    TAtlasIdeHost.Warning(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugNoSource));
    Exit;
  end;
  mRun := Default(TStopRun);
  if not mSource.StopFrame(mRun.Frame) then
  begin
    TAtlasIdeHost.Warning(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsFromDebugNotStopped));
    Exit;
  end;
  if TAtlasIdeHost.ActiveSession = nil then
  begin
    Fail(NoAnswer);
    Exit;
  end;
  mRun.Scope := AScope;
  mRun.Uri := TLspSession.PathToUri(mRun.Frame.FileName);
  mRun.Line := mRun.Frame.Line - 1;
  mRun.Choice.ExceptionClass := mRun.Frame.ExceptionClass;
  mRun.Choice.Raises := mRun.Frame.ExceptionClass <> '';
  mRun.Choice.MaxArray := TAtlasIdeSettings.Current.TestsFromDebugStopMaxArray;
  mRun.Choice.StoppedAt := FormatDateTime('yyyy-mm-dd hh:nn', Now, TFormatSettings.Invariant);
  Ask(mRun, TAtlasTestFromDebugStop.cModeDescribe, Located(mRun));
end;

end.
