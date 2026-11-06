unit Shell.Composition.EditingArea;

// Teilwurzel Bearbeiten der Komposition: Gliederung, Falt- und Auswahlbereiche, Formatieren und Erzeugen-Menü
// (Shell.Composition.Editing, #719) und der Host der Schnellbefehle (Shell.Composition.Slash, #297). Beide
// entstehen vor dem Kern; was sie von ihm brauchen, holen sie erst beim Aufruf.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Shell.Workspace,
  Shell.Composition.Core,
  Shell.Composition.Editing,
  Shell.Composition.Slash;

type
  /// <summary>Der Kern; nil, bis WireWorkspaces ihn anlegt.</summary>
  TShellEditingCoreFunc = reference to function: TShellCore;

  /// <summary>Was die Teilwurzel Bearbeiten von der Komposition braucht. Editing und Slash bringen nur, was der
  /// Kern nicht weiß; den Rest füllt die Teilwurzel.</summary>
  TShellEditingAreaServices = record
    Core: TShellEditingCoreFunc;
    Editing: TShellEditingServices;
    Slash: TShellSlashServices;
  end;

  /// <summary>Hält Bearbeiten und den Host der Schnellbefehle.</summary>
  TShellEditingArea = class
  private
    FCore: TShellEditingCoreFunc;
    FEditing: TShellEditing;
    /// <summary>Host der Schnellbefehle (#297) mit seinen Quellen.</summary>
    FSlash: TShellSlash;
    procedure CompleteEditing(var AServices: TShellEditingServices);
    procedure CompleteSlash(var AServices: TShellSlashServices);
    function WorkspaceOf(const AUri: string): TShellWorkspace;
    function SettingsFor(const AUri: string): TServerSettings;
    function WorkspaceSettingsOf(const AUri: string; out ASettings: TServerSettings): Boolean;
    function RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
  public
    /// <summary>Legt Bearbeiten an, meldet es am Verteiler an und gibt ihm den Host der Schnellbefehle.</summary>
    constructor Create(const AServices: TShellEditingAreaServices);
    /// <summary>Gibt Bearbeiten und danach den Host der Schnellbefehle frei.</summary>
    destructor Destroy; override;
    property Editing: TShellEditing read FEditing;
    property Slash: TShellSlash read FSlash;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris;

constructor TShellEditingArea.Create(const AServices: TShellEditingAreaServices);
var
  mEditing: TShellEditingServices;
  mSlash: TShellSlashServices;
begin
  inherited Create;
  FCore := AServices.Core;
  mEditing := AServices.Editing;
  CompleteEditing(mEditing);
  FEditing := TShellEditing.Create(mEditing);
  FEditing.Attach(AServices.Slash.Dispatcher);
  mSlash := AServices.Slash;
  CompleteSlash(mSlash);
  FSlash := TShellSlash.Create(mSlash);
  FEditing.UseSlashHost(FSlash.Host);
end;

destructor TShellEditingArea.Destroy;
begin
  FreeAndNil(FEditing);
  FreeAndNil(FSlash);
  FCore := nil;
  inherited;
end;

procedure TShellEditingArea.CompleteEditing(var AServices: TShellEditingServices);
var
  mCore: TShellEditingCoreFunc;
begin
  mCore := FCore;
  AServices.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := mCore().FileOptions.FormatStyleFor(AUri);
    end;
  AServices.ResolvedFormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := mCore().FileOptions.ResolvedFormatStyleFor(AUri);
    end;
  AServices.SlashCommandsFor :=
    function(const AUri: string; out ADisabled: TArray<string>): Boolean
    begin
      Result := mCore().FileOptions.SlashCommandsFor(AUri, ADisabled);
    end;
  AServices.LanguageLevelFor :=
    function(const AUri: string): string
    begin
      Result := mCore().FileOptions.LanguageLevelFor(AUri);
    end;
  AServices.DocCommentsFor :=
    function(const AUri: string): Boolean
    begin
      Result := mCore().FileOptions.DocCommentsFor(AUri);
    end;
end;

procedure TShellEditingArea.CompleteSlash(var AServices: TShellSlashServices);
begin
  AServices.WorkspaceOf := WorkspaceOf;
  AServices.SettingsFor := SettingsFor;
  AServices.WorkspaceSettingsOf := WorkspaceSettingsOf;
  AServices.RuleContextFor := RuleContextFor;
end;

function TShellEditingArea.WorkspaceOf(const AUri: string): TShellWorkspace;
var
  mCore: TShellCore;
begin
  mCore := FCore();
  System.TMonitor.Enter(mCore.Workspaces.Lock);
  try
    Result := mCore.Workspaces.Pick(TDocumentUris.ToPath(AUri));
  finally
    System.TMonitor.Exit(mCore.Workspaces.Lock);
  end;
end;

function TShellEditingArea.SettingsFor(const AUri: string): TServerSettings;
begin
  Result := FCore().Settings.SettingsFor(AUri);
end;

function TShellEditingArea.WorkspaceSettingsOf(const AUri: string; out ASettings: TServerSettings): Boolean;
begin
  Result := FCore().Settings.WorkspaceSettingsOf(AUri, ASettings);
end;

function TShellEditingArea.RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
begin
  Result := FCore().RuleContext.RuleContextFor(AUri, AContext);
end;

end.
