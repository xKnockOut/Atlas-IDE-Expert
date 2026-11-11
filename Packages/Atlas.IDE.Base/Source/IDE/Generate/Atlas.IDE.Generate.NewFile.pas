unit Atlas.IDE.Generate.NewFile;

// „Neu mit Atlas“ (#759) in der IDE: Die Knöpfe Unit, Formular und Testklasse
// der Willkommensseite öffnen das Erzeugen-Menü (#719, Atlas.UI.Generate.
// Window) nur mit den Dateivorlagen ihrer Art (Gruppe Vorlagen,
// Atlas.Core.Generate.FileTemplates). Die gewählte Vorlage legt die IDE über
// IOTAModuleCreator als neue, noch unbenannte Datei im aktiven Projekt an:
// Den Namen der Unit (Unit2 …) und beim Formular den des Formulars vergibt
// die IDE, die Vorlage setzt sie für %Unit%, %Name% und %Form% ein. Beim
// Formular legt die IDE die .dfm aus der Basisklasse an.
// Ohne Server und ohne offenen Editor nutzbar; braucht ein offenes Projekt.
// Ausgeblendete Einträge (keys.generateMenu.hidden) gelten wie im Menü.
// CreateUnit legt eine Unit mit festem Namen und fertigem Text an (Assistenten
// der Objektgalerie, #1821).

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Generate.FileTemplates;

type
  TAtlasIdeNewFile = class
  public
    /// <summary>Menü mit den Dateivorlagen der Art AKind (mitgelieferte und AUser); AMessage: Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Show(AKind: TAtlasNewFileKind; const AUser: TAtlasSnippetList;
      const AMessage: TProc<string>); static;
    /// <summary>Legt ATemplate als neue Datei im aktiven Projekt an; False mit AError, wenn das nicht ging.
    /// </summary>
    class function CreateFile(AKind: TAtlasNewFileKind; const ATemplate: TAtlasSnippet;
      out AError: string): Boolean; static;
    /// <summary>Unit AFileName (voller Pfad) mit dem Text AText im aktiven Projekt anlegen und öffnen; False mit
    /// AError ohne Projekt, wenn die Datei schon besteht oder die IDE sie nicht anlegt.</summary>
    class function CreateUnit(const AFileName, AText: string; out AError: string): Boolean; static;
  end;

implementation

uses
  System.Types,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Generate.Menu,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Generate.Window,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

type
  /// <summary>Text der neuen Datei für die IDE.</summary>
  TAtlasSourceFile = class(TInterfacedObject, IOTAFile)
  private
    FSource: string;
  public
    constructor Create(const ASource: string);
    function GetSource: string;
    function GetAge: TDateTime;
  end;

  /// <summary>Neue Unit bzw. neues Formular im aktiven Projekt aus einer Dateivorlage.</summary>
  TAtlasFileCreator = class(TNotifierObject, IOTACreator, IOTAModuleCreator)
  private
    FKind: TAtlasNewFileKind;
    FBody: string;
    FOwner: IOTAModule;
    /// <summary>Fester Dateiname (CreateUnit); FBody ist dann der fertige Text. '' = die IDE vergibt den Namen.
    /// </summary>
    FFileName: string;
  public
    constructor Create(AKind: TAtlasNewFileKind; const ABody: string; const AOwner: IOTAModule);
    constructor CreateNamed(const AFileName, AText: string; const AOwner: IOTAModule);
    { IOTACreator }
    function GetCreatorType: string;
    function GetExisting: Boolean;
    function GetFileSystem: string;
    function GetOwner: IOTAModule;
    function GetUnnamed: Boolean;
    { IOTAModuleCreator }
    function GetAncestorName: string;
    function GetImplFileName: string;
    function GetIntfFileName: string;
    function GetFormName: string;
    function GetMainForm: Boolean;
    function GetShowForm: Boolean;
    function GetShowSource: Boolean;
    function NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
    function NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    function NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    procedure FormCreated(const FormEditor: IOTAFormEditor);
  end;

{ TAtlasSourceFile }

constructor TAtlasSourceFile.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
end;

function TAtlasSourceFile.GetSource: string;
begin
  Result := FSource;
end;

function TAtlasSourceFile.GetAge: TDateTime;
begin
  // Neue Datei ohne Stand auf der Platte.
  Result := -1;
end;

{ TAtlasFileCreator }

constructor TAtlasFileCreator.Create(AKind: TAtlasNewFileKind; const ABody: string; const AOwner: IOTAModule);
begin
  inherited Create;
  FKind := AKind;
  FBody := ABody;
  FOwner := AOwner;
end;

constructor TAtlasFileCreator.CreateNamed(const AFileName, AText: string; const AOwner: IOTAModule);
begin
  Create(TAtlasNewFileKind.UnitFile, AText, AOwner);
  FFileName := AFileName;
end;

function TAtlasFileCreator.GetCreatorType: string;
begin
  if FKind = TAtlasNewFileKind.FormFile then
  begin
    Result := sForm;
  end
  else
  begin
    Result := sUnit;
  end;
end;

function TAtlasFileCreator.GetExisting: Boolean;
begin
  Result := False;
end;

function TAtlasFileCreator.GetFileSystem: string;
begin
  Result := '';
end;

function TAtlasFileCreator.GetOwner: IOTAModule;
begin
  Result := FOwner;
end;

function TAtlasFileCreator.GetUnnamed: Boolean;
begin
  Result := FFileName = '';
end;

function TAtlasFileCreator.GetAncestorName: string;
begin
  Result := TAtlasFileTemplates.cDefaultAncestor;
end;

function TAtlasFileCreator.GetImplFileName: string;
begin
  // Ohne festen Namen leer: Die IDE vergibt den nächsten freien Namen (Unit2.pas …).
  Result := FFileName;
end;

function TAtlasFileCreator.GetIntfFileName: string;
begin
  Result := '';
end;

function TAtlasFileCreator.GetFormName: string;
begin
  Result := '';
end;

function TAtlasFileCreator.GetMainForm: Boolean;
begin
  Result := False;
end;

function TAtlasFileCreator.GetShowForm: Boolean;
begin
  Result := FKind = TAtlasNewFileKind.FormFile;
end;

function TAtlasFileCreator.GetShowSource: Boolean;
begin
  Result := True;
end;

function TAtlasFileCreator.NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
begin
  // nil: Die IDE legt die .dfm aus der Basisklasse an.
  Result := nil;
end;

function TAtlasFileCreator.NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  if FFileName <> '' then
  begin
    Exit(TAtlasSourceFile.Create(FBody));
  end;
  Result := TAtlasSourceFile.Create(TAtlasFileTemplates.Render(FBody, ModuleIdent, FormIdent, AncestorIdent,
    sLineBreak));
end;

function TAtlasFileCreator.NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := nil;
end;

procedure TAtlasFileCreator.FormCreated(const FormEditor: IOTAFormEditor);
begin
end;

{ TAtlasIdeNewFile }

class function TAtlasIdeNewFile.CreateFile(AKind: TAtlasNewFileKind; const ATemplate: TAtlasSnippet;
  out AError: string): Boolean;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := False;
  AError := '';
  mProject := GetActiveProject;
  if (mProject = nil) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    AError := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewNoProject);
    Exit;
  end;
  try
    Result := mModules.CreateModule(TAtlasFileCreator.Create(AKind, ATemplate.Body, mProject)) <> nil;
    if not Result then
    begin
      AError := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupNewFailed, [ATemplate.Prefix]);
    end;
  except
    on E: Exception do
    begin
      // Meldung der IDE nur in die Meldungsansicht; ins Protokoll nur die Klasse (anonym).
      TAtlasGuard.Log('Neu mit Atlas: Datei nicht angelegt (' + E.ClassName + ')');
      AError := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupNewFailed, [E.Message]);
    end;
  end;
end;

class function TAtlasIdeNewFile.CreateUnit(const AFileName, AText: string; out AError: string): Boolean;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := False;
  AError := '';
  mProject := GetActiveProject;
  if (mProject = nil) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    AError := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewNoProject);
    Exit;
  end;
  if FileExists(AFileName) or (mModules.FindModule(AFileName) <> nil) then
  begin
    AError := TAtlasStrings.Fmt(TAtlasTextId.GalleryFileExists, [AFileName]);
    Exit;
  end;
  try
    Result := mModules.CreateModule(TAtlasFileCreator.CreateNamed(AFileName, AText, mProject)) <> nil;
    if not Result then
    begin
      AError := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupNewFailed, [ExtractFileName(AFileName)]);
    end;
  except
    on E: Exception do
    begin
      TAtlasGuard.Log('Gallery: unit not created (' + E.ClassName + ')');
      AError := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupNewFailed, [E.Message]);
    end;
  end;
end;

/// <summary>Eintrag ausblenden: keys.generateMenu.hidden speichern, Meldung an ASay.</summary>
function HideFor(const ASay: TProc<string>): TAtlasGenerateHideProc;
begin
  Result :=
    procedure(const AEntry: TAtlasGenerateEntry)
    var
      mNext: TAtlasPluginSettings;
    begin
      mNext := TAtlasIdeSettings.Stored;
      mNext.GenerateMenuHidden := TAtlasGenerateOptions.AddHidden(mNext.GenerateMenuHidden, AEntry.Id);
      TAtlasIdeSettings.Update(mNext);
      if Assigned(ASay) then
      begin
        ASay(TAtlasStrings.Fmt(TAtlasTextId.GenerateHiddenSaved, [AEntry.Caption]));
      end;
    end;
end;

/// <summary>Gewählte Vorlage als neue Datei anlegen, abgesichert über die Willkommensseite.</summary>
function CreateFor(AKind: TAtlasNewFileKind; const ATemplates: TAtlasSnippetList; const ASay: TProc<string>):
  TAtlasGenerateExecuteProc;
begin
  Result :=
    procedure(const AEntry: TAtlasGenerateEntry; const AArgument: string)
    var
      mEntry: TAtlasGenerateEntry;
    begin
      mEntry := AEntry;
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        var
          mError: string;
        begin
          if (mEntry.Source < 0) or (mEntry.Source > High(ATemplates)) then
          begin
            Exit;
          end;
          if not TAtlasIdeNewFile.CreateFile(AKind, ATemplates[mEntry.Source], mError) and Assigned(ASay) then
          begin
            ASay(mError);
          end;
        end);
    end;
end;

class procedure TAtlasIdeNewFile.Show(AKind: TAtlasNewFileKind; const AUser: TAtlasSnippetList;
  const AMessage: TProc<string>);
var
  mSettings: TAtlasPluginSettings;
  mTemplates: TAtlasSnippetList;
  mEntries: TArray<TAtlasGenerateEntry>;
  mOptions: TAtlasGenerateOptions;
  mWindow: TAtlasGenerateWindow;
  mIndex: Integer;
  mArea: TRect;
begin
  if GetActiveProject = nil then
  begin
    if Assigned(AMessage) then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewNoProject));
    end;
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  mTemplates := TAtlasFileTemplates.OfKind(AUser, AKind);
  mEntries := TAtlasFileTemplates.Entries(mTemplates);
  for mIndex := 0 to High(mEntries) do
  begin
    mEntries[mIndex].Caption := TAtlasGenerateTexts.EntryCaption(mEntries[mIndex]);
  end;
  // Nur die Gruppe Vorlagen; ausgeblendete Einträge und Namen der Befehle wie im Erzeugen-Menü.
  mOptions := TAtlasGenerateOptions.Create(mSettings.GenerateMenuGroups, mSettings.GenerateMenuHidden, False,
    mSettings.GenerateMenuShowCommandNames).Only([TAtlasGenerateGroup.Templates]);
  mWindow := TAtlasGenerateWindow.CreateMenu(Application, mEntries, mOptions, nil, TAtlasIdeStyle.Colors);
  mWindow.OnHide := HideFor(AMessage);
  mWindow.OnExecute := CreateFor(AKind, mTemplates, AMessage);
  // Über dem Hauptfenster: Die Willkommensseite hat keinen Cursor.
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  mWindow.ShowOver(mArea);
end;

end.
