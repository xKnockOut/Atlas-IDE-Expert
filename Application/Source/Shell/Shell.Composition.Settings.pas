unit Shell.Composition.Settings;

// Internals-Rolle Shell: wirksame Einstellungen je Datei (S-02). Die Ebenen globale Datei und Editor stehen
// hier; ohne Arbeitsbereich gelten sie allein (FLooseSettings), sonst die Einstellungen des Arbeitsbereichs.
// Liest unter der Sperre des Registers der Arbeitsbereiche, weil Anfrage-Threads fragen.

interface

uses
  Atlas.Common.Configuration.Contract,
  Shell.Composition.Workspaces;

type
  /// <summary>Sprachstand zur Datei (für mehrzeilige Zeichenketten).</summary>
  TShellSettingsLanguageFunc = reference to function(const AUri: string): string;

  /// <summary>Einstellungen der Ebenen global und Editor und die wirksamen Einstellungen je Datei.</summary>
  TShellSettings = class
  private
    FWorkspaces: TShellWorkspaceRegistry;
    FLanguageLevelFor: TShellSettingsLanguageFunc;
    /// <summary>Schreibt nur die Nachrichtenschleife, unter der Sperre; der nebenläufige Fehlerbericht (#874)
    /// liest unter derselben Sperre.</summary>
    FEditorSettings: string;
    /// <summary>Globale Benutzerdatei (#227); nur im Thread der Nachrichtenschleife.</summary>
    FGlobalSettings: string;
    /// <summary>Einstellungen für Dateien ohne Arbeitsbereich: global und Editor. Unter der Sperre.</summary>
    FLooseSettings: TServerSettings;
    /// <summary>Sprache des Clients aus initialize (#1458); '' ohne Angabe.</summary>
    FClientLocale: string;
    procedure SetLoose(const ASettings: TServerSettings);
  public
    constructor Create(AWorkspaces: TShellWorkspaceRegistry; const ALanguageLevelFor: TShellSettingsLanguageFunc);
    /// <summary>Einstellungen des Arbeitsbereichs zur Datei, ohne Arbeitsbereich global und Editor. Sperrt
    /// selbst und liefert eine Kopie.</summary>
    function SettingsFor(const AUri: string): TServerSettings;
    /// <summary>Einstellungen des Arbeitsbereichs zur Datei; False ohne Arbeitsbereich.</summary>
    function WorkspaceSettingsOf(const AUri: string; out ASettings: TServerSettings): Boolean;
    /// <summary>Einstellungen ohne Arbeitsbereich; Aufrufer hält die Sperre der Arbeitsbereiche.</summary>
    function Loose: TServerSettings;
    /// <summary>Text der Editor-Ebene (unter der Sperre gelesen).</summary>
    function EditorSettings: string;
    /// <summary>Setzt die Editor-Ebene unter der Sperre (#874) und berechnet Loose neu.</summary>
    procedure SetEditorSettings(const AText: string);
    /// <summary>Setzt die globale Ebene und berechnet Loose neu; False, wenn der Text gleich blieb.</summary>
    function SetGlobalSettings(const AText: string): Boolean;
    /// <summary>Sprache des Clients aus initialize (#1458); gilt ab dem nächsten Berechnen von Loose, daher vor
    /// SetEditorSettings setzen.</summary>
    procedure SetClientLocale(const ALocale: string);
    function Highlight(const AUri: string): THighlightSettings;
    /// <summary>Inlay-Hinweise; die Marke „ohne Self“ (#686) hängt an der Umwandlung, nicht an inlayHints.
    /// </summary>
    function InlayHints(const AUri: string): TInlayHintSettings;
    function Hints(const AUri: string): THintSettings;
    function Refactoring(const AUri: string): TRefactoringSettings;
    function Completion(const AUri: string): TCompletionSettings;
    function References(const AUri: string): TReferenceSettings;
    /// <summary>Zeichenketten-Stil; AMultiline, wenn der Sprachstand mehrzeilige Literale kennt.</summary>
    function StringLiteral(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
    property GlobalSettings: string read FGlobalSettings;
  end;

implementation

uses
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Localization.Texts,
  Shell.Workspace;

constructor TShellSettings.Create(AWorkspaces: TShellWorkspaceRegistry;
  const ALanguageLevelFor: TShellSettingsLanguageFunc);
begin
  inherited Create;
  FWorkspaces := AWorkspaces;
  FLanguageLevelFor := ALanguageLevelFor;
  FLooseSettings := TServerSettings.Default;
end;

function TShellSettings.SettingsFor(const AUri: string): TServerSettings;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := FLooseSettings;
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.Configuration.Settings;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TShellSettings.WorkspaceSettingsOf(const AUri: string; out ASettings: TServerSettings): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := mWorkspace <> nil;
    ASettings := Default(TServerSettings);
    if Result then
    begin
      ASettings := mWorkspace.Configuration.Settings;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

/// <summary>Neue Einstellungen ohne Arbeitsbereich; wählt die Sprache der Texte (#1458): language ist global
/// (settings.json bzw. Editor), sonst die Sprache des Clients.</summary>
procedure TShellSettings.SetLoose(const ASettings: TServerSettings);
begin
  TAtlasLocale.Use(TAtlasLocale.Resolve(ASettings.Language, FClientLocale));
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    FLooseSettings := ASettings;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TShellSettings.SetClientLocale(const ALocale: string);
begin
  FClientLocale := ALocale;
end;

function TShellSettings.Loose: TServerSettings;
begin
  Result := FLooseSettings;
end;

function TShellSettings.EditorSettings: string;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    Result := FEditorSettings;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

procedure TShellSettings.SetEditorSettings(const AText: string);
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := TConfigurationParser.Parse(TConfigurationScopes.Effective(FGlobalSettings, AText, ''), mIssues);
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    FEditorSettings := AText;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  SetLoose(mSettings);
end;

function TShellSettings.SetGlobalSettings(const AText: string): Boolean;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := AText <> FGlobalSettings;
  if not Result then
  begin
    Exit;
  end;
  FGlobalSettings := AText;
  mSettings := TConfigurationParser.Parse(TConfigurationScopes.Effective(AText, EditorSettings, ''), mIssues);
  SetLoose(mSettings);
end;

function TShellSettings.Highlight(const AUri: string): THighlightSettings;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := THighlightSettings.Default;
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.Configuration.Settings.Highlight;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TShellSettings.InlayHints(const AUri: string): TInlayHintSettings;
var
  mSettings: TServerSettings;
begin
  mSettings := SettingsFor(AUri);
  Result := mSettings.InlayHints;
  Result.MethodWithoutSelf := mSettings.Refactoring.MethodKind and mSettings.Refactoring.MethodKindMarker;
end;

function TShellSettings.Hints(const AUri: string): THintSettings;
begin
  Result := SettingsFor(AUri).Hints;
end;

function TShellSettings.Refactoring(const AUri: string): TRefactoringSettings;
begin
  Result := SettingsFor(AUri).Refactoring;
end;

function TShellSettings.Completion(const AUri: string): TCompletionSettings;
begin
  Result := SettingsFor(AUri).Completion;
end;

function TShellSettings.References(const AUri: string): TReferenceSettings;
begin
  Result := SettingsFor(AUri).References;
end;

function TShellSettings.StringLiteral(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings;
begin
  Result := SettingsFor(AUri).StringLiteral;
  AMultiline := TStringLiterals.UseMultiline(Result.Style, FLanguageLevelFor(AUri));
end;

end.
