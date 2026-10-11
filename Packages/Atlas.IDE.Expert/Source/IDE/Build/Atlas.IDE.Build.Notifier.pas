unit Atlas.IDE.Build.Notifier;

// Anbindung der Compile-Ereignisse (#527) an die Open Tools API.
// - IOTAIDENotifier80: BeforeCompile mit Abbruch und IsCodeInsight,
//   AfterCompile mit Projekt und Erfolg.
// - IOTACompileNotifier: Art des Laufs (Make, Build, Syntaxprüfung) und
//   Beginn/Ende des Gruppenlaufs.
// Beide melden dasselbe Projekt; TAtlasCompileEvents zählt es nur einmal.
// Ein Abbruch erscheint im Meldungsfenster in der Gruppe „Atlas“.
// Destroy meldet beide Notifier ab, bevor der Dienst freigegeben wird (#493).

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Build.Events,
  Atlas.UI.Strings;

type
  TAtlasIdeCompileEvents = class
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier, IOTAIDENotifier50, IOTAIDENotifier80)
    private
      FOwner: TAtlasIdeCompileEvents;
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
      FOwner: TAtlasIdeCompileEvents;
    public
      procedure ProjectCompileStarted(const Project: IOTAProject; Mode: TOTACompileMode);
      procedure ProjectCompileFinished(const Project: IOTAProject; Result: TOTACompileResult);
      procedure ProjectGroupCompileStarted(Mode: TOTACompileMode);
      procedure ProjectGroupCompileFinished(Result: TOTACompileResult);
    end;
  private
    FEvents: TAtlasCompileEvents;
    FIde: TIdeNotifier;
    FIdeRef: IOTAIDENotifier;
    FIdeIndex: Integer;
    FCompile: TCompileNotifier;
    FCompileRef: IOTACompileNotifier;
    FCompileIndex: Integer;
    // Art des laufenden Compiles; BeforeCompile kennt sie nicht selbst.
    FKind: TAtlasCompileKind;
    function ProjectInfo(const AProject: IOTAProject): TAtlasCompileProject;
    procedure ShowCancel(const AReason: string);
    class function KindOf(AMode: TOTACompileMode): TAtlasCompileKind; static;
  public
    /// <summary>Übernimmt AEvents und meldet die Notifier an.</summary>
    constructor Create(AEvents: TAtlasCompileEvents);
    destructor Destroy; override;
    property Events: TAtlasCompileEvents read FEvents;
  end;

implementation

const
  MessageGroup = 'Atlas';

{ TAtlasIdeCompileEvents.TIdeNotifier }

procedure TAtlasIdeCompileEvents.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeCompileEvents.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TAtlasIdeCompileEvents.TIdeNotifier.BeforeCompile(const Project: IOTAProject; IsCodeInsight: Boolean;
  var Cancel: Boolean);
var
  Info: TAtlasCompileProject;
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

procedure TAtlasIdeCompileEvents.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

procedure TAtlasIdeCompileEvents.TIdeNotifier.AfterCompile(Succeeded, IsCodeInsight: Boolean);
begin
end;

procedure TAtlasIdeCompileEvents.TIdeNotifier.AfterCompile(const Project: IOTAProject; Succeeded,
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

{ TAtlasIdeCompileEvents.TCompileNotifier }

procedure TAtlasIdeCompileEvents.TCompileNotifier.ProjectCompileStarted(const Project: IOTAProject;
  Mode: TOTACompileMode);
var
  Info: TAtlasCompileProject;
begin
  if (FOwner = nil) or (Project = nil) then
    Exit;
  try
    FOwner.FKind := TAtlasIdeCompileEvents.KindOf(Mode);
    Info := FOwner.ProjectInfo(Project);
    FOwner.FEvents.ProjectStarted(Info);
  except
  end;
end;

procedure TAtlasIdeCompileEvents.TCompileNotifier.ProjectCompileFinished(const Project: IOTAProject;
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

procedure TAtlasIdeCompileEvents.TCompileNotifier.ProjectGroupCompileStarted(Mode: TOTACompileMode);
begin
  if FOwner = nil then
    Exit;
  try
    FOwner.FKind := TAtlasIdeCompileEvents.KindOf(Mode);
    FOwner.FEvents.GroupStarted(FOwner.FKind);
  except
  end;
end;

procedure TAtlasIdeCompileEvents.TCompileNotifier.ProjectGroupCompileFinished(Result: TOTACompileResult);
begin
  if FOwner = nil then
    Exit;
  try
    FOwner.FEvents.GroupFinished(Result <> crOTAFailed);
    FOwner.FKind := TAtlasCompileKind.Make;
  except
  end;
end;

{ TAtlasIdeCompileEvents }

constructor TAtlasIdeCompileEvents.Create(AEvents: TAtlasCompileEvents);
var
  Services: IOTAServices;
  CompileServices: IOTACompileServices;
begin
  inherited Create;
  FEvents := AEvents;
  FKind := TAtlasCompileKind.Make;
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

destructor TAtlasIdeCompileEvents.Destroy;
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

class function TAtlasIdeCompileEvents.KindOf(AMode: TOTACompileMode): TAtlasCompileKind;
begin
  case AMode of
    cmOTABuild: Result := TAtlasCompileKind.Build;
    cmOTACheck: Result := TAtlasCompileKind.Check;
    cmOTAMakeUnit: Result := TAtlasCompileKind.MakeUnit;
    cmOTAClean: Result := TAtlasCompileKind.Clean;
    cmOTALink: Result := TAtlasCompileKind.Link;
  else
    Result := TAtlasCompileKind.Make;
  end;
end;

function TAtlasIdeCompileEvents.ProjectInfo(const AProject: IOTAProject): TAtlasCompileProject;
var
  Options: IOTAProjectOptions;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := AProject.FileName;
  Result.Kind := FKind;
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  Options := AProject.ProjectOptions;
  if Options <> nil then
    Result.OutputFile := Options.TargetName;
end;

procedure TAtlasIdeCompileEvents.ShowCancel(const AReason: string);
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
  Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.CompileCancelled, [AReason]), Group);
  Messages.ShowMessageView(Group);
end;

end.