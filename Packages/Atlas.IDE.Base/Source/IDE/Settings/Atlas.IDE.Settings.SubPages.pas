unit Atlas.IDE.Settings.SubPages;

// Unterseiten von Tools › Optionen › Atlas (INTAAddInOptions, #227): Der Punkt
// in der Überschrift („Atlas.Snippets“) hängt die Seite unter „Atlas“.
// „Snippets“ (#51): Code-Vorlagen ansehen, eigene anlegen, bearbeiten und
// löschen; gespeichert wird beim Schließen mit OK.
// „Tastenkonflikte“ (#494): Wer welche Taste belegt, fragt die Seite über
// TAtlasIdeKeys.Owner ab; nach dem Speichern belegt die Komposition die Tasten
// über Settings.OnChanged neu.
// „Server“ (#227): globale und Projekt-Einstellungen des Servers im Dialog,
// Index-Cache über TAtlasIdeServerActions (Baseline und Unterdrückungen: Modul Prüfregeln, #1755).

interface

uses
  System.SysUtils,
  Vcl.Forms,
  ToolsAPI,
  Atlas.UI.Settings.SnippetsPage,
  Atlas.UI.Settings.Keys,
  Atlas.UI.Settings.ServerPage;

type
  /// <summary>Seite „Snippets“ (#51).</summary>
  TAtlasSnippetOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSnippetsPage;
    FIdeTemplateFolder: TFunc<string>;
    FSnippetFolder: TFunc<string>;
  public
    /// <summary>AIdeTemplateFolder: Ordner der Live Templates der IDE (#487); ASnippetFolder: Ordner der eigenen
    /// Code-Vorlagen. Nicht gesetzt: ''.</summary>
    constructor Create(const AIdeTemplateFolder, ASnippetFolder: TFunc<string>);
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  /// <summary>Seite „Tastenkonflikte“ (#494).</summary>
  TAtlasKeysOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasKeysPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  /// <summary>Seite „Server“ (#227).</summary>
  TAtlasServerOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasServerPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

implementation

uses
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.ServerActions,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

/// <summary>Ergebnis eines Hakens; '' ohne Haken.</summary>
function HookText(const AHook: TFunc<string>): string;
begin
  Result := '';
  if Assigned(AHook) then
  begin
    Result := AHook();
  end;
end;

{ TAtlasSnippetOptions }

constructor TAtlasSnippetOptions.Create(const AIdeTemplateFolder, ASnippetFolder: TFunc<string>);
begin
  inherited Create;
  FIdeTemplateFolder := AIdeTemplateFolder;
  FSnippetFolder := ASnippetFolder;
end;

function TAtlasSnippetOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasSnippetOptions.GetCaption: string;
begin
  Result := 'Atlas.Snippets';
end;

function TAtlasSnippetOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasSnippetsPage;
end;

procedure TAtlasSnippetOptions.FrameCreated(AFrame: TCustomFrame);
var
  mIde, mOwn: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
  mErrors: TArray<string>;
begin
  try
    FPage := AFrame as TAtlasSnippetsPage;
    mIde := nil;
    if TAtlasIdeSettings.Current.ImportIdeTemplates then
    begin
      mIde := TAtlasLiveTemplates.LoadFolder(HookText(FIdeTemplateFolder), mStats);
    end;
    mOwn := TAtlasSnippets.LoadFolder(HookText(FSnippetFolder), mErrors);
    FPage.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, mIde, mOwn));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasSnippetOptions.DialogClosed(Accepted: Boolean);
begin
  try
    if Accepted and (FPage <> nil) and (FPage.Catalog <> nil) and FPage.Catalog.Modified then
    begin
      FPage.Catalog.Save(HookText(FSnippetFolder));
    end;
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasSnippetOptions.ValidateContents: Boolean;
var
  mMessage: string;
begin
  Result := True;
  if FPage = nil then
  begin
    Exit;
  end;
  mMessage := FPage.Validate;
  if mMessage <> '' then
  begin
    ShowMessage(mMessage);
    Result := False;
  end;
end;

function TAtlasSnippetOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasSnippetOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasKeysOptions }

function TAtlasKeysOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasKeysOptions.GetCaption: string;
begin
  // Punkt: Unterseite von „Atlas“.
  Result := 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle);
end;

function TAtlasKeysOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasKeysPage;
end;

procedure TAtlasKeysOptions.FrameCreated(AFrame: TCustomFrame);
begin
  try
    FPage := AFrame as TAtlasKeysPage;
    FPage.LoadFrom(TAtlasIdeSettings.Stored);
    FPage.OwnerOf :=
      function(AShortCut: Word): string
      begin
        Result := TAtlasIdeKeys.Owner(AShortCut);
      end;
    FPage.ShowForeignCompletions(TAtlasIdeKeys.ForeignCompletions);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasKeysOptions.DialogClosed(Accepted: Boolean);
var
  mSettings: TAtlasPluginSettings;
begin
  try
    if Accepted and (FPage <> nil) then
    begin
      mSettings := TAtlasIdeSettings.Stored;
      FPage.SaveTo(mSettings);
      TAtlasIdeSettings.Update(mSettings);
    end;
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasKeysOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasKeysOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasKeysOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasServerOptions }

function TAtlasServerOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasServerOptions.GetCaption: string;
begin
  // Punkt: Unterseite von „Atlas“.
  Result := 'Atlas.' + TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ServerPageTitle);
end;

function TAtlasServerOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasServerPage;
end;

procedure TAtlasServerOptions.FrameCreated(AFrame: TCustomFrame);
begin
  try
    FPage := AFrame as TAtlasServerPage;
    FPage.OnEditGlobal :=
      procedure
      begin
        TAtlasProjectSettings.ExecuteGlobal;
      end;
    FPage.OnEditProject :=
      procedure
      begin
        TAtlasProjectSettings.Execute;
      end;
    FPage.OnClearCache :=
      function: string
      begin
        Result := TAtlasIdeServerActions.ClearCache;
      end;
    FPage.Reload;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasServerOptions.DialogClosed(Accepted: Boolean);
begin
  FPage := nil;
end;

function TAtlasServerOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasServerOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasServerOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

end.
