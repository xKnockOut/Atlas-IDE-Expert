unit Argus.IDE.Build.Notifier;

// Anbindung der Compile-Ereignisse (#527) an die Open Tools API.
// - IOTAIDENotifier80: BeforeCompile mit Abbruch und IsCodeInsight,
//   AfterCompile mit Projekt und Erfolg.
// - IOTACompileNotifier: Art des Laufs (Make, Build, Syntaxprüfung) und
//   Beginn/Ende des Gruppenlaufs.
// Beide melden dasselbe Projekt; TArgusCompileEvents zählt es nur einmal.
// Ein Abbruch erscheint im Meldungsfenster in der Gruppe „Argus“.
// Destroy meldet beide Notifier ab, bevor der Dienst freigegeben wird (#493).

interface

uses
  System.SysUtils,
  ToolsAPI,
  Argus.Core.Build.Events,
  Argus.UI.Strings;

type
  TArgusIdeCompileEvents = class
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier, IOTAIDENotifier50, IOTAIDENotifier80)
    private
      FOwner: TArgusIdeCompileEvents;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure BeforeCompile(const Project: IOTAProject; IsCodeInsight: Boolean; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean; IsCodeInsight: Boolean); overload;
      procedure AfterCompile(const Project: IOTAProject; Succeeded: Boolean; IsCodeInsight: Boolean); overload;
    end;

    TCompileNotifier = class(TInterfacedObject, IOTACompileNotifier)
    private
      FOwner: TArgusIdeCompileEvents;
    public
      procedure ProjectCompileStarted(const Project: IOTAProject; Mode: TOTACompileMode);
      procedure ProjectCompileFinished(const Project: IOTAProject; Result: TOTACompileResult);
      procedure ProjectGroupCompileStarted(Mode: TOTACompileMode);
      procedure ProjectGroupCompileFinished(Result: TOTACompileResult);
    end;
  private
    FEvents: TArgusCompileEvents;
    FIde: TIdeNotifier;
    FIdeRef: IOTAIDENotifier;
    FIdeIndex: Integer;
    FCompile: TCompileNotifier;
    FCompileRef: IOTACompileNotifier;
    FCompileIndex: Integer;
    // Art des laufenden Compiles; BeforeCompile kennt sie nicht selbst.
    FKind: TArgusCompileKind;
    function ProjectInfo(const AProject: IOTAProject): TArgusCompileProject;
    procedure ShowCancel(const AReason: string);
    class function KindOf(AMode: TOTACompileMode): TArgusCompileKind; static;
  public
    /// <summary>Übernimmt AEvents und meldet die Notifier an.</summary>
    constructor Create(AEvents: TArgusCompileEvents);
    destructor Destroy; override;
    property Events: TArgusCompileEvents read FEvents;
  end;

implementation

const
  MessageGroup = 'Argus';

{ TArgusIdeCompileEvents.TIdeNotifier }

procedure TArgusIdeCompileEvents.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
end;

procedure TArgusIdeCompileEvents.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TArgusIdeCompileEvents.TIdeNotifier.BeforeCompile(const Project: IOTAProject; IsCodeInsight: Boolean;
  var Cancel: Boolean);
var
  Info: TArgusCompileProject;
  Reason: string;
begin
  if (FOwner = nil) or (Project = nil) then
    Exit;
  try
    Info := FOwner.ProjectInfo(Project);
    if FOwner.FEvents.BeforeCompile(Info, IsCodeInsight, Reason) then
    begin
      Cancel := True;
      FOwner.ShowCancel(Reason);
    end
    else if not IsCodeInsight then
      FOwner.FEvents.ProjectStarted(Info);
  except
    // Keine Exception an die IDE (#493); der Compile läuft weiter.
  end;
end;

procedure TArgusIdeCompileEvents.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

procedure TArgusIdeCompileEvents.TIdeNotifier.AfterCompile(Succeeded, IsCodeInsight: Boolean);
begin
end;

procedure TArgusIdeCompileEvents.TIdeNotifier.AfterCompile(const Project: IOTAProject; Succeeded,
  IsCodeInsight: Boolean);
begin
  if FOwner = nil then
    Exit;
  try
    if IsCodeInsight then
      FOwner.FEvents.CodeInsightFinished
    else if Project <> nil then
      FOwner.FEvents.ProjectFinished(Project.FileName, Succeeded);
  except
  end;
end;

{ TArgusIdeCompileEvents.TCompileNotifier }

procedure TArgusIdeCompileEvents.TCompileNotifier.ProjectCompileStarted(const Project: IOTAProject;
  Mode: TOTACompileMode);
var
  Info: TArgusCompileProject;
begin
  if (FOwner = nil) or (Project = nil) then
    Exit;
  try
    FOwner.FKind := TArgusIdeCompileEvents.KindOf(Mode);
    Info := FOwner.ProjectInfo(Project);
    FOwner.FEvents.ProjectStarted(Info);
  except
  end;
end;

procedure TArgusIdeCompileEvents.TCompileNotifier.ProjectCompileFinished(const Project: IOTAProject;
  Result: TOTACompileResult);
begin
  // crOTABackground: läuft im Hintergrund weiter; das Ende meldet AfterCompile.
  if (FOwner = nil) or (Project = nil) or (Result = crOTABackground) then
    Exit;
  try
    FOwner.FEvents.ProjectFinished(Project.FileName, Result = crOTASucceeded);
  except
  end;
end;

procedure TArgusIdeCompileEvents.TCompileNotifier.ProjectGroupCompileStarted(Mode: TOTACompileMode);
begin
  if FOwner = nil then
    Exit;
  try
    FOwner.FKind := TArgusIdeCompileEvents.KindOf(Mode);
    FOwner.FEvents.GroupStarted(FOwner.FKind);
  except
  end;
end;

procedure TArgusIdeCompileEvents.TCompileNotifier.ProjectGroupCompileFinished(Result: TOTACompileResult);
begin
  if FOwner = nil then
    Exit;
  try
    FOwner.FEvents.GroupFinished(Result <> crOTAFailed);
    FOwner.FKind := TArgusCompileKind.Make;
  except
  end;
end;

{ TArgusIdeCompileEvents }

constructor TArgusIdeCompileEvents.Create(AEvents: TArgusCompileEvents);
var
  Services: IOTAServices;
  CompileServices: IOTACompileServices;
begin
  inherited Create;
  FEvents := AEvents;
  FKind := TArgusCompileKind.Make;
  FIdeIndex := -1;
  FCompileIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, Services) then
  begin
    FIde := TIdeNotifier.Create;
    FIde.FOwner := Self;
    FIdeRef := FIde;
    FIdeIndex := Services.AddNotifier(FIdeRef);
  end;
  if Supports(BorlandIDEServices, IOTACompileServices, CompileServices) then
  begin
    FCompile := TCompileNotifier.Create;
    FCompile.FOwner := Self;
    FCompileRef := FCompile;
    FCompileIndex := CompileServices.AddNotifier(FCompileRef);
  end;
end;

destructor TArgusIdeCompileEvents.Destroy;
var
  Services: IOTAServices;
  CompileServices: IOTACompileServices;
begin
  // Erst abmelden, dann freigeben (#493); die IDE hält die Notifier evtl. noch.
  if FIde <> nil then
    FIde.FOwner := nil;
  if FCompile <> nil then
    FCompile.FOwner := nil;
  if (FIdeIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, Services) then
    Services.RemoveNotifier(FIdeIndex);
  if (FCompileIndex >= 0) and Supports(BorlandIDEServices, IOTACompileServices, CompileServices) then
    CompileServices.RemoveNotifier(FCompileIndex);
  FIdeRef := nil;
  FCompileRef := nil;
  FEvents.Free;
  inherited;
end;

class function TArgusIdeCompileEvents.KindOf(AMode: TOTACompileMode): TArgusCompileKind;
begin
  case AMode of
    cmOTABuild: Result := TArgusCompileKind.Build;
    cmOTACheck: Result := TArgusCompileKind.Check;
    cmOTAMakeUnit: Result := TArgusCompileKind.MakeUnit;
    cmOTAClean: Result := TArgusCompileKind.Clean;
    cmOTALink: Result := TArgusCompileKind.Link;
  else
    Result := TArgusCompileKind.Make;
  end;
end;

function TArgusIdeCompileEvents.ProjectInfo(const AProject: IOTAProject): TArgusCompileProject;
var
  Options: IOTAProjectOptions;
begin
  Result := Default(TArgusCompileProject);
  Result.FileName := AProject.FileName;
  Result.Kind := FKind;
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  Options := AProject.ProjectOptions;
  if Options <> nil then
    Result.OutputFile := Options.TargetName;
end;

procedure TArgusIdeCompileEvents.ShowCancel(const AReason: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  // Gruppe nicht dauerhaft halten (Hinweis in ToolsAPI); bei Bedarf neu anlegen.
  Group := Messages.GetGroup(MessageGroup);
  if Group = nil then
    Group := Messages.AddMessageGroup(MessageGroup);
  Messages.AddTitleMessage(TArgusStrings.Fmt(TArgusTextId.CompileCancelled, [AReason]), Group);
  Messages.ShowMessageView(Group);
end;

end.