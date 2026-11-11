unit Atlas.IDE.Designer.PropertySearch;

// Formularweite Eigenschaftssuche (#524) in der IDE:
// - Dialog mit Bedingung und Bereich (aktuelles Formular, Projekt,
//   Projektgruppe); Knopf in der Designer-Leiste und Befehl im Atlas-Menü
//   (designer.propertySearch).
// - Offene Formulare liest Atlas aus dem Designer (ungespeicherter Stand),
//   die anderen aus der .dfm; binäre Formulare überspringt die Suche und
//   sagt es. Vorfahrformulare findet sie über die Klasse im Quelltext unter
//   den Formularen der Projektgruppe.
// - Treffer im Ergebnisfenster je Formular: Komponente, Klasse, gefundener
//   Wert, „geerbt“. Doppelklick bzw. Enter öffnet das Formular und wählt die
//   Komponente (TAtlasIdeShowComponent, #511).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar;

type
  TAtlasIdePropertySearch = class
  public const
    cId = 'propertySearch';
    cOwner = 'propertySearch';
  private class var
    FOnMessage: TProc<string>;
    class procedure Say(const AText: string); static;
    class procedure OpenHit(const AItemId: string); static;
  public
    /// <summary>Meldungen gehen an AOnMessage (Meldungsansicht).</summary>
    class procedure Install(const AOnMessage: TProc<string>); static;
    class procedure Uninstall; static;
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Knopf der Designer-Leiste.</summary>
    class function Button: TAtlasDesignerButton; static;
    /// <summary>Dialog zeigen und suchen; AFromDesigner wählt das aktuelle Formular vor.</summary>
    class procedure Run(AFromDesigner: Boolean); static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Files.Contract,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Designer.FormModel,
  Atlas.Core.Designer.PropertySearch,
  Atlas.UI.Results.Items,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.PropertyDialog,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.ShowComponent;

const
  /// <summary>Höchste Tiefe der Vorfahrkette (Schutz vor Zyklen).</summary>
  cMaxAncestors = 10;

type
  /// <summary>Formular einer Unit mit seinem Formularmodell.</summary>
  TFormSource = record
    UnitFile: string;
    RootName: string;
    RootType: string;
    Objects: TArray<TAtlasFormObject>;
    /// <summary>Beginnt der Text mit „inherited“?</summary>
    Inherits: Boolean;
  end;

  TFoundHit = record
    UnitFile: string;
    FormName: string;
    Hit: TAtlasPropertyHit;
  end;

var
  GOptions: TAtlasPropertyOptions;
  GHits: TArray<TFoundHit>;

{ Formulare lesen }

/// <summary>Formulartext zur Unit: aus dem Designer, sonst aus der .dfm; False bei binärer oder fehlender Datei.
/// </summary>
function FormTextOf(const AUnitFile: string; out AText: string): Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mFormFile: string;
begin
  AText := '';
  mEditor := TAtlasDesignerAccess.FormEditorOf(AUnitFile);
  mRoot := TAtlasIdeDesignerView.RootOf(mEditor);
  if mRoot <> nil then
  begin
    AText := TAtlasDesignerAccess.FormText(mRoot, TAtlasDesignerAccess.DesignerOf(mEditor));
    Exit(AText <> '');
  end;
  mFormFile := ChangeFileExt(AUnitFile, '.dfm');
  Result := FileExists(mFormFile) and not TAtlasTextFile.IsBinaryForm(TAtlasTextFile.ReadAllBytes(mFormFile));
  if Result then
  begin
    AText := TAtlasTextFile.LoadText(mFormFile);
  end;
end;

/// <summary>Nicht lesbare Datei ins Protokoll; immer False.</summary>
function LogSkipped(const AFileName: string; AError: Exception): Boolean;
begin
  TAtlasGuard.Log('Eigenschaftssuche: ' + AFileName + ': ' + AError.Message);
  Result := False;
end;

function LoadSource(const AUnitFile: string; out ASource: TFormSource): Boolean;
var
  mText: string;
begin
  ASource := Default(TFormSource);
  ASource.UnitFile := AUnitFile;
  // Fehlende, gesperrte oder falsch kodierte Dateien zählen als übersprungen.
  try
    Result := FormTextOf(AUnitFile, mText);
  except
    on E: EStreamError do
    begin
      Result := LogSkipped(AUnitFile, E);
    end;
    on E: EAtlasTextFileError do
    begin
      Result := LogSkipped(AUnitFile, E);
    end;
    on E: EEncodingError do
    begin
      Result := LogSkipped(AUnitFile, E);
    end;
  end;
  if not Result then
  begin
    Exit;
  end;
  ASource.Objects := TAtlasFormModel.Parse(mText);
  Result := Length(ASource.Objects) > 0;
  if Result then
  begin
    ASource.RootName := ASource.Objects[0].Name;
    ASource.RootType := ASource.Objects[0].TypeName;
    ASource.Inherits := LowerCase(TrimLeft(mText)).StartsWith('inherited');
  end;
end;

function UnitText(const AUnitFile: string): string;
var
  mBuffer: IOTAEditBuffer;
begin
  mBuffer := TAtlasIdeFiles.BufferOf(AUnitFile);
  if mBuffer <> nil then
  begin
    Exit(TAtlasEditorBuffer.Text(mBuffer));
  end;
  // Ohne Quelltext keine Vorfahren; die Suche läuft weiter.
  Result := '';
  try
    Result := TAtlasTextFile.LoadText(AUnitFile);
  except
    on E: EStreamError do
    begin
      LogSkipped(AUnitFile, E);
    end;
    on E: EEncodingError do
    begin
      LogSkipped(AUnitFile, E);
    end;
  end;
end;

/// <summary>Units mit Formular in AProject.</summary>
function FormUnits(const AProject: IOTAProject): TArray<string>;
var
  mIndex: Integer;
  mInfo: IOTAModuleInfo;
begin
  Result := nil;
  if AProject = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AProject.GetModuleCount - 1 do
  begin
    mInfo := AProject.GetModule(mIndex);
    if (mInfo <> nil) and (mInfo.FormName <> '') and SameText(ExtractFileExt(mInfo.FileName), '.pas') then
    begin
      Result := Result + [mInfo.FileName];
    end;
  end;
end;

function GroupUnits: TArray<string>;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Result := FormUnits(mServices.GetActiveProject);
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    Result := Result + FormUnits(mGroup.Projects[mIndex]);
  end;
end;

function ActiveProjectUnits: TArray<string>;
var
  mServices: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Result := FormUnits(mServices.GetActiveProject);
  end;
end;

/// <summary>Unit des aktuellen Formulars: im Designer oder die des aktiven Editors; '' ohne Formular.</summary>
function CurrentFormUnit: string;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mView: IOTAEditView;
begin
  Result := '';
  if TAtlasDesignerAccess.Current(mEditor, mRoot) and (mEditor.Module <> nil) then
  begin
    Exit(mEditor.Module.FileName);
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and
    (TAtlasDesignerAccess.FormEditorOf(mView.Buffer.FileName) <> nil) then
  begin
    Result := mView.Buffer.FileName;
  end;
end;

{ Vorfahren }

type
  /// <summary>Formulare der Projektgruppe nach Klasse, erst beim ersten geerbten Formular gelesen.</summary>
  TAncestorIndex = class
  private
    FForms: TDictionary<string, TFormSource>;
    FLoaded: Boolean;
    procedure Load;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AChain[0] ist ASource, danach die Vorfahren, soweit sie in der Gruppe liegen.</summary>
    function Chain(const ASource: TFormSource): TArray<TArray<TAtlasFormObject>>;
  end;

constructor TAncestorIndex.Create;
begin
  inherited Create;
  FForms := TDictionary<string, TFormSource>.Create;
end;

destructor TAncestorIndex.Destroy;
begin
  FForms.Free;
  inherited Destroy;
end;

procedure TAncestorIndex.Load;
var
  mUnit: string;
  mSource: TFormSource;
begin
  FLoaded := True;
  for mUnit in GroupUnits do
  begin
    if LoadSource(mUnit, mSource) then
    begin
      FForms.AddOrSetValue(LowerCase(mSource.RootType), mSource);
    end;
  end;
end;

function TAncestorIndex.Chain(const ASource: TFormSource): TArray<TArray<TAtlasFormObject>>;
var
  mSource, mAncestor: TFormSource;
  mClass: string;
begin
  Result := [ASource.Objects];
  mSource := ASource;
  while mSource.Inherits and (Length(Result) <= cMaxAncestors) do
  begin
    mClass := TAtlasPropertySearch.AncestorOf(UnitText(mSource.UnitFile), mSource.RootType);
    // Unit-Präfix weg („Basis.TfrmBasis“).
    mClass := LowerCase(Copy(mClass, LastDelimiter('.', mClass) + 1, MaxInt));
    if not FLoaded then
    begin
      Load;
    end;
    if (mClass = '') or not FForms.TryGetValue(mClass, mAncestor) then
    begin
      Break;
    end;
    Result := Result + [mAncestor.Objects];
    mSource := mAncestor;
  end;
end;

{ Ergebnis }

function ResultList(const AQuery: string): TAtlasResultsItemList;
var
  mIndex: Integer;
  mGroup: TAtlasResultsItemGroup;
  mItem: TAtlasResultsItem;
  mFound: TFoundHit;
begin
  Result := Default(TAtlasResultsItemList);
  Result.Owner := TAtlasIdePropertySearch.cOwner;
  Result.Title := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.PropertySearchResults, [AQuery, Length(GHits)]);
  Result.OnOpen := TAtlasIdePropertySearch.OpenHit;
  mGroup := Default(TAtlasResultsItemGroup);
  for mIndex := 0 to High(GHits) do
  begin
    mFound := GHits[mIndex];
    if not SameFileName(mGroup.FileName, mFound.UnitFile) then
    begin
      if mGroup.FileName <> '' then
      begin
        Result.Groups := Result.Groups + [mGroup];
      end;
      mGroup := Default(TAtlasResultsItemGroup);
      mGroup.FileName := mFound.UnitFile;
      mGroup.Caption := mFound.FormName + ' (' + ExtractFileName(ChangeFileExt(mFound.UnitFile, '.dfm')) + ')';
    end;
    mItem := Default(TAtlasResultsItem);
    mItem.Id := IntToStr(mIndex);
    mItem.FileName := mFound.UnitFile;
    mItem.Caption := mFound.Hit.Component + ' (' + mFound.Hit.TypeName + ')';
    if mFound.Hit.Found <> '' then
    begin
      mItem.Caption := mItem.Caption + ': ' + mFound.Hit.Found;
    end;
    if mFound.Hit.FromAncestor then
    begin
      mItem.Caption := mItem.Caption + ' · ' + TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchInherited);
    end;
    mGroup.Items := mGroup.Items + [mItem];
  end;
  if mGroup.FileName <> '' then
  begin
    Result.Groups := Result.Groups + [mGroup];
  end;
end;

/// <summary>Units im Bereich, ohne Doppelte.</summary>
function ScopeUnits(AScope: TAtlasPropertyScope): TArray<string>;
var
  mUnits: TArray<string>;
  mUnit: string;
  mSeen: TStringList;
begin
  case AScope of
    TAtlasPropertyScope.Form:
      mUnits := [CurrentFormUnit];
    TAtlasPropertyScope.Project:
      mUnits := ActiveProjectUnits;
  else
    mUnits := GroupUnits;
  end;
  Result := nil;
  mSeen := TStringList.Create;
  try
    mSeen.CaseSensitive := False;
    for mUnit in mUnits do
    begin
      if (mUnit <> '') and (mSeen.IndexOf(mUnit) < 0) then
      begin
        mSeen.Add(mUnit);
        Result := Result + [mUnit];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Suche über die Units; ASkipped zählt die nicht lesbaren Formulare.</summary>
procedure SearchUnits(const AQuery: TAtlasPropertyQuery; const AUnits: TArray<string>; out ASkipped: Integer);
var
  mIndex: TAncestorIndex;
  mUnit: string;
  mSource: TFormSource;
  mHit: TAtlasPropertyHit;
  mFound: TFoundHit;
begin
  GHits := nil;
  ASkipped := 0;
  mIndex := TAncestorIndex.Create;
  try
    for mUnit in AUnits do
    begin
      if not LoadSource(mUnit, mSource) then
      begin
        Inc(ASkipped);
        Continue;
      end;
      for mHit in TAtlasPropertySearch.Search(AQuery, mIndex.Chain(mSource)) do
      begin
        mFound.UnitFile := mUnit;
        mFound.FormName := mSource.RootName;
        mFound.Hit := mHit;
        GHits := GHits + [mFound];
      end;
    end;
  finally
    mIndex.Free;
  end;
end;

{ TAtlasIdePropertySearch }

class procedure TAtlasIdePropertySearch.Install(const AOnMessage: TProc<string>);
begin
  FOnMessage := AOnMessage;
end;

class procedure TAtlasIdePropertySearch.Uninstall;
begin
  TAtlasIdeResultsWindow.ReleaseItems(cOwner);
  GHits := nil;
  FOnMessage := nil;
end;

class procedure TAtlasIdePropertySearch.Say(const AText: string);
begin
  TAtlasGuard.Log('Eigenschaftssuche: ' + AText);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

class function TAtlasIdePropertySearch.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerPropertySearch;
end;

class function TAtlasIdePropertySearch.Button: TAtlasDesignerButton;
begin
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.PropertySearch,
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchHint));
end;

class procedure TAtlasIdePropertySearch.Run(AFromDesigner: Boolean);
var
  mUnits: TArray<string>;
  mSkipped: Integer;
begin
  GOptions.HasForm := CurrentFormUnit <> '';
  if AFromDesigner then
  begin
    GOptions.Scope := TAtlasPropertyScope.Form;
  end;
  if not TAtlasPropertyDialog.Execute(GOptions) then
  begin
    Exit;
  end;
  mUnits := ScopeUnits(GOptions.Scope);
  if Length(mUnits) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchNoForms));
    Exit;
  end;
  SearchUnits(TAtlasPropertyQuery.Parse(GOptions.Query), mUnits, mSkipped);
  if mSkipped > 0 then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.PropertySearchSkipped, [mSkipped]));
  end;
  TAtlasIdeResultsWindow.ShowItems(ResultList(GOptions.Query));
end;

class procedure TAtlasIdePropertySearch.OpenHit(const AItemId: string);
var
  mIndex: Integer;
  mFound: TFoundHit;
  mActions: IOTAActionServices;
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  mIndex := StrToIntDef(AItemId, -1);
  if (mIndex < 0) or (mIndex > High(GHits)) then
  begin
    Exit;
  end;
  mFound := GHits[mIndex];
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
      begin
        mActions.OpenFile(mFound.UnitFile);
      end;
      mEditor := TAtlasDesignerAccess.FormEditorOf(mFound.UnitFile);
      if mEditor = nil then
      begin
        Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerShowNoForm));
        Exit;
      end;
      // Register „Design“; erst danach gibt es das Formular.
      mEditor.Show;
      mRoot := TAtlasIdeDesignerView.RootOf(mEditor);
      TAtlasIdeShowComponent.Show(mEditor, TAtlasIdeShowComponent.FindComponent(mRoot, mFound.Hit.Component));
    end);
end;

end.
