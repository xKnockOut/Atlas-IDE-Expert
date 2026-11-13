unit Atlas.IDE.Designer.SelectionSets;

// Auswahlsätze im Designer (#739) in der IDE:
// - Ablage: lokal in %LOCALAPPDATA%\Atlas\designer-selection-sets.json je
//   Formulardatei (Pfad) oder, mit designer.selectionSets.storage = shared,
//   in .atlas-selection-sets.json im Ordner des Formulars je Dateiname (für
//   die Versionsverwaltung). Die DFM bleibt unberührt.
// - Menü im Knopf „Gleiche auswählen“: „Auswahl speichern …“ (Name mit
//   Vorschlag aus dem gemeinsamen Wortteil) und je Satz ein Untermenü
//   (wiederherstellen, hinzufügen, entfernen, überschreiben, umbenennen,
//   verschieben, löschen). Leere Sätze sind grau, fehlende Mitglieder stehen
//   in der Beschriftung.
// - Tasten, solange der Designer den Fokus hat: designer.selectionSets.saveKey
//   (Vorgabe Strg+Umschalt+S, dort statt „Alles speichern“ der IDE) und, mit
//   designer.selectionSets.shortcuts, Strg+Umschalt+1…9 für die ersten neun
//   Sätze. Beim Klick auf einen Satz fügt Umschalt hinzu, Strg entfernt.
// - Umbenennen und Löschen: Atlas merkt sich die Mitglieder als Komponenten
//   (FreeNotification). Hat eine den Namen gewechselt, zieht der Satz mit;
//   wird sie gelöscht, fällt sie heraus. Schließt das Formular, bleibt alles.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Menus,
  Atlas.Core.Designer.SelectionSets,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Designer.Tool;

type
  TAtlasIdeSelectionSets = class;

  /// <summary>Tasten der Auswahlsätze, solange der Designer den Fokus hat.</summary>
  TAtlasSelectionSetKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeSelectionSets;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  /// <summary>Merkt Mitglieder als Komponenten: gelöscht oder umbenannt.</summary>
  TAtlasSelectionSetWatch = class(TComponent)
  private
    FOwner: TAtlasIdeSelectionSets;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TAtlasIdeSelectionSets = class(TAtlasIdeDesignerTool)
  private
    /// <summary>Ablagedatei → Sätze.</summary>
    FStores: TObjectDictionary<string, TAtlasSelectionSets>;
    /// <summary>Ablagedateien, die nicht lesbar waren und nicht überschrieben werden.</summary>
    FKept: TDictionary<string, Boolean>;
    /// <summary>Gemerkte Mitglieder: Komponente → Formulardatei und letzter Name.</summary>
    FSeen: TDictionary<TComponent, TPair<string, string>>;
    FWatch: TAtlasSelectionSetWatch;
    FKeys: TAtlasSelectionSetKeys;
    function StoreFile(const AFormFile: string): string;
    function FormKey(const AFormFile: string): string;
    function Store(const AFormFile: string): TAtlasSelectionSets;
    procedure Save(const AFormFile: string);
    procedure Watch(ARoot: TComponent; const AFormFile: string);
    procedure Reconcile(ARoot: TComponent; const AFormFile: string);
    procedure Deleted(AComponent: TComponent);
    function SetCaption(const ASet: TAtlasSelectionSet; AIndex: Integer; ARoot: TComponent): string;
    procedure AddSetMenu(AParent: TMenuItem; const ASet: TAtlasSelectionSet; AIndex: Integer; ARoot: TComponent);
    procedure MenuClick(Sender: TObject);
    procedure Run(AAction, AIndex: Integer);
  public
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Einträge der Sätze für das aktive Formular an AParent anhängen.</summary>
    procedure FillMenu(AParent: TMenuItem);
    /// <summary>Aktuelle Auswahl als neuen Satz speichern (fragt nach dem Namen).</summary>
    procedure SaveSelection;
    /// <summary>Satz AIndex des aktiven Formulars wiederherstellen.</summary>
    procedure Restore(AIndex: Integer);
    /// <summary>Tasten an- oder abmelden (Einstellungen, Designer gezeigt).</summary>
    procedure UpdateKeys(AWanted: Boolean);
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Vcl.Dialogs,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 50;
  cLocalFile = 'designer-selection-sets.json';
  cSharedFile = '.atlas-selection-sets.json';
  /// <summary>Aktionen im Untermenü eines Satzes; Tag = Index · cActionCount + Aktion.</summary>
  cRestore = 0;
  cAdd = 1;
  cRemove = 2;
  cOverwrite = 3;
  cExtend = 4;
  cRename = 5;
  cUp = 6;
  cDown = 7;
  cDelete = 8;
  cActionCount = 9;

function Kind: string;
begin
  Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSetsKind);
end;

function LocalAppData: string;
begin
  Result := GetEnvironmentVariable('LOCALAPPDATA');
  if Result = '' then
  begin
    Result := TPath.GetTempPath;
  end;
end;

function Shared: Boolean;
begin
  Result := SameText(TAtlasIdeSettings.Current.DesignerSelectionSetsStorage,
    TAtlasPluginSettings.cDesignerSetsShared);
end;

function Names(const AComponents: TArray<TComponent>): TArray<string>;
var
  mComponent: TComponent;
begin
  Result := nil;
  for mComponent in AComponents do
  begin
    Result := Result + [mComponent.Name];
  end;
end;

/// <summary>Umschalt beim Klick fügt hinzu, Strg entfernt; sonst AAction.</summary>
function ClickAction(AAction: Integer): Integer;
begin
  Result := AAction;
  if AAction <> cRestore then
  begin
    Exit;
  end;
  if GetKeyState(VK_SHIFT) < 0 then
  begin
    Result := cAdd;
  end
  else if GetKeyState(VK_CONTROL) < 0 then
  begin
    Result := cRemove;
  end;
end;

/// <summary>„ (Strg+Umschalt+n)“ für Satz AIndex; leer ohne Kürzel.</summary>
function ShortcutText(AIndex: Integer): string;
begin
  Result := '';
  if TAtlasIdeSettings.Current.DesignerSelectionSetsShortcuts and (TAtlasSelectionSets.ShortcutOf(AIndex) > 0) then
  begin
    Result := ' (' + TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSetsShortcut,
      [TAtlasSelectionSets.ShortcutOf(AIndex)]) + ')';
  end;
end;

{ TAtlasSelectionSetKeys }

function TAtlasSelectionSetKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := False;
  if not mSettings.DesignerSelectionSets or not TAtlasDesignerAccess.Focused then
  begin
    Exit;
  end;
  if (mSettings.DesignerSelectionSetsSaveKey <> 0) and
    (ShortCut(AKey, AShift) = TShortCut(mSettings.DesignerSelectionSetsSaveKey)) then
  begin
    Exit(True);
  end;
  Result := mSettings.DesignerSelectionSetsShortcuts and (AShift = [ssCtrl, ssShift]) and
    (AKey >= Ord('1')) and (AKey <= Ord('9'));
end;

procedure TAtlasSelectionSetKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeSelectionSets;
  mKey: Word;
  mShift: TShiftState;
begin
  mOwner := FOwner;
  mKey := AKey;
  mShift := AShift;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if (mShift = [ssCtrl, ssShift]) and (mKey >= Ord('1')) and (mKey <= Ord('9')) then
      begin
        mOwner.Restore(mKey - Ord('1'));
      end
      else
      begin
        mOwner.SaveSelection;
      end;
    end);
end;

{ TAtlasSelectionSetWatch }

procedure TAtlasSelectionSetWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FOwner <> nil) then
  begin
    FOwner.Deleted(AComponent);
  end;
end;

{ TAtlasIdeSelectionSets }

constructor TAtlasIdeSelectionSets.Create(const AOnMessage: TProc<string>);
begin
  inherited Create(AOnMessage);
  FStores := TObjectDictionary<string, TAtlasSelectionSets>.Create([doOwnsValues]);
  FKept := TDictionary<string, Boolean>.Create;
  FSeen := TDictionary<TComponent, TPair<string, string>>.Create;
  FWatch := TAtlasSelectionSetWatch.Create(nil);
  FWatch.FOwner := Self;
  FKeys := TAtlasSelectionSetKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdeSelectionSets.Destroy;
var
  mComponent: TComponent;
begin
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  if (FWatch <> nil) and (FSeen <> nil) then
  begin
    FWatch.FOwner := nil;
    for mComponent in FSeen.Keys do
    begin
      mComponent.RemoveFreeNotification(FWatch);
    end;
  end;
  FWatch.Free;
  FSeen.Free;
  FKept.Free;
  FStores.Free;
  inherited Destroy;
end;

procedure TAtlasIdeSelectionSets.UpdateKeys(AWanted: Boolean);
begin
  if AWanted and TAtlasIdeSettings.Current.DesignerSelectionSets then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

function TAtlasIdeSelectionSets.StoreFile(const AFormFile: string): string;
begin
  if Shared then
  begin
    Result := TPath.Combine(ExtractFilePath(AFormFile), cSharedFile);
  end
  else
  begin
    Result := TPath.Combine(TPath.Combine(LocalAppData, 'Atlas'), cLocalFile);
  end;
end;

function TAtlasIdeSelectionSets.FormKey(const AFormFile: string): string;
begin
  Result := AFormFile;
  if Shared then
  begin
    Result := ExtractFileName(AFormFile);
  end;
end;

function TAtlasIdeSelectionSets.Store(const AFormFile: string): TAtlasSelectionSets;
var
  mFile: string;
  mSets: TAtlasSelectionSets;
begin
  mFile := UpperCase(StoreFile(AFormFile));
  if FStores.TryGetValue(mFile, Result) then
  begin
    Exit;
  end;
  mSets := TAtlasSelectionSets.Create;
  FStores.Add(mFile, mSets);
  if not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile(AFormFile), Kind,
    function(const AText: string): Boolean
    begin
      Result := mSets.LoadJson(AText);
    end)) then
  begin
    FKept.AddOrSetValue(mFile, True);
  end;
  Result := mSets;
end;

procedure TAtlasIdeSelectionSets.Save(const AFormFile: string);
var
  mSets: TAtlasSelectionSets;
begin
  mSets := Store(AFormFile);
  if not mSets.Changed or FKept.ContainsKey(UpperCase(StoreFile(AFormFile))) then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(StoreFile(AFormFile), mSets.ToJson);
    mSets.Changed := False;
  except
    on E: Exception do
    begin
      TAtlasDataFile.ReportNotWritten(Kind, E);
    end;
  end;
end;

/// <summary>Mitglieder aller Sätze des Formulars als Komponenten merken.</summary>
procedure TAtlasIdeSelectionSets.Watch(ARoot: TComponent; const AFormFile: string);
var
  mSet: TAtlasSelectionSet;
  mName: string;
  mComponent: TComponent;
begin
  for mSet in Store(AFormFile).SetsOf(FormKey(AFormFile)) do
  begin
    for mName in mSet.Members do
    begin
      mComponent := ARoot.FindComponent(mName);
      if (mComponent <> nil) and not FSeen.ContainsKey(mComponent) then
      begin
        FSeen.Add(mComponent, TPair<string, string>.Create(AFormFile, mComponent.Name));
        mComponent.FreeNotification(FWatch);
      end;
    end;
  end;
end;

/// <summary>Umbenennungen seit dem letzten Blick nachziehen.</summary>
procedure TAtlasIdeSelectionSets.Reconcile(ARoot: TComponent; const AFormFile: string);
var
  mPair: TPair<TComponent, TPair<string, string>>;
  mRenamed: TArray<TPair<TComponent, string>>;
  mItem: TPair<TComponent, string>;
  mSets: TAtlasSelectionSets;
begin
  mRenamed := nil;
  for mPair in FSeen do
  begin
    if (mPair.Key.Owner = ARoot) and SameText(mPair.Value.Key, AFormFile) and
      not SameText(mPair.Key.Name, mPair.Value.Value) then
    begin
      mRenamed := mRenamed + [TPair<TComponent, string>.Create(mPair.Key, mPair.Value.Value)];
    end;
  end;
  mSets := Store(AFormFile);
  for mItem in mRenamed do
  begin
    mSets.ComponentRenamed(FormKey(AFormFile), mItem.Value, mItem.Key.Name);
    FSeen[mItem.Key] := TPair<string, string>.Create(AFormFile, mItem.Key.Name);
  end;
  Watch(ARoot, AFormFile);
  Save(AFormFile);
end;

procedure TAtlasIdeSelectionSets.Deleted(AComponent: TComponent);
var
  mSeen: TPair<string, string>;
begin
  if not FSeen.TryGetValue(AComponent, mSeen) then
  begin
    Exit;
  end;
  FSeen.Remove(AComponent);
  // Schließt das Formular, gehen alle Komponenten mit: kein Löschen.
  if (AComponent.Owner <> nil) and (csDestroying in AComponent.Owner.ComponentState) then
  begin
    Exit;
  end;
  Store(mSeen.Key).ComponentDeleted(FormKey(mSeen.Key), mSeen.Value);
  Save(mSeen.Key);
end;

function TAtlasIdeSelectionSets.SetCaption(const ASet: TAtlasSelectionSet; AIndex: Integer;
  ARoot: TComponent): string;
var
  mExisting, mMissing: TArray<string>;
  mIndex: Integer;
begin
  Result := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSelectCount, [ASet.Name,
    Length(ASet.Members)]);
  Result := Result + ShortcutText(AIndex);
  mExisting := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mExisting := mExisting + [ARoot.Components[mIndex].Name];
  end;
  mMissing := TAtlasSelectionSets.Missing(ASet, mExisting);
  if Length(mMissing) > 0 then
  begin
    Result := Result + ' ' + TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSetsMissing,
      [string.Join(', ', mMissing)]);
  end;
end;

procedure TAtlasIdeSelectionSets.AddSetMenu(AParent: TMenuItem; const ASet: TAtlasSelectionSet; AIndex: Integer;
  ARoot: TComponent);
const
  cTexts: array[cRestore..cDelete] of TAtlasDesignerTextId = (TAtlasDesignerTextId.DesignerSetsRestore,
    TAtlasDesignerTextId.DesignerSetsAdd, TAtlasDesignerTextId.DesignerSetsRemove,
    TAtlasDesignerTextId.DesignerSetsOverwrite, TAtlasDesignerTextId.DesignerSetsExtend,
    TAtlasDesignerTextId.DesignerSetsRename, TAtlasDesignerTextId.DesignerSetsUp,
    TAtlasDesignerTextId.DesignerSetsDown, TAtlasDesignerTextId.DesignerSetsDelete);
var
  mItem, mAction: TMenuItem;
  mIndex: Integer;
begin
  mItem := TMenuItem.Create(AParent.Owner);
  mItem.Caption := SetCaption(ASet, AIndex, ARoot);
  AParent.Add(mItem);
  for mIndex := cRestore to cDelete do
  begin
    if mIndex in [cOverwrite, cUp] then
    begin
      mItem.Add(NewLine);
    end;
    mAction := TMenuItem.Create(AParent.Owner);
    mAction.Caption := TAtlasDesignerStrings.Text(cTexts[mIndex]);
    mAction.Tag := AIndex * cActionCount + mIndex;
    mAction.OnClick := MenuClick;
    // Leerer Satz: grau, nur noch pflegen.
    mAction.Enabled := (Length(ASet.Members) > 0) or not (mIndex in [cRestore, cAdd, cRemove]);
    mItem.Add(mAction);
  end;
end;

procedure TAtlasIdeSelectionSets.FillMenu(AParent: TMenuItem);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSets: TArray<TAtlasSelectionSet>;
  mItem: TMenuItem;
  mIndex: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerSelectionSets or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  Reconcile(mRoot, mEditor.FileName);
  mItem := TMenuItem.Create(AParent.Owner);
  mItem.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSetsSave);
  mItem.Tag := -1;
  mItem.OnClick := MenuClick;
  AParent.Add(mItem);
  mSets := Store(mEditor.FileName).SetsOf(FormKey(mEditor.FileName));
  if Length(mSets) = 0 then
  begin
    mItem := TMenuItem.Create(AParent.Owner);
    mItem.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSetsEmpty);
    mItem.Enabled := False;
    AParent.Add(mItem);
  end;
  for mIndex := 0 to High(mSets) do
  begin
    AddSetMenu(AParent, mSets[mIndex], mIndex, mRoot);
  end;
end;

procedure TAtlasIdeSelectionSets.MenuClick(Sender: TObject);
var
  mTag: Integer;
begin
  mTag := TMenuItem(Sender).Tag;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mTag < 0 then
      begin
        SaveSelection;
      end
      else
      begin
        Run(ClickAction(mTag mod cActionCount), mTag div cActionCount);
      end;
    end);
end;

procedure TAtlasIdeSelectionSets.SaveSelection;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mName: string;
  mSets: TAtlasSelectionSets;
  mIndex: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerSelectionSets or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  if Length(mSelected) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNoSelection));
    Exit;
  end;
  mSets := Store(mEditor.FileName);
  mName := TAtlasSelectionSets.SuggestName(Names(mSelected));
  if mName = '' then
  begin
    mName := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSetsDefaultName,
      [Length(mSets.SetsOf(FormKey(mEditor.FileName))) + 1]);
  end;
  if not InputQuery(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSetsSaveTitle),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSetsSavePrompt), mName) or (Trim(mName) = '') then
  begin
    Exit;
  end;
  mIndex := mSets.Add(FormKey(mEditor.FileName), mName, Names(mSelected));
  Watch(mRoot, mEditor.FileName);
  Save(mEditor.FileName);
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSetsSaved, [Trim(mName), ShortcutText(mIndex)]));
end;

procedure TAtlasIdeSelectionSets.Restore(AIndex: Integer);
begin
  Run(cRestore, AIndex);
end;

/// <summary>Komponenten zu ANames im Formular ARoot; fehlende fallen weg.</summary>
function ComponentsOf(ARoot: TComponent; const ANames: TArray<string>): TArray<TComponent>;
var
  mName: string;
  mComponent: TComponent;
begin
  Result := nil;
  for mName in ANames do
  begin
    mComponent := ARoot.FindComponent(mName);
    if mComponent <> nil then
    begin
      Result := Result + [mComponent];
    end;
  end;
end;

function Contains(const AList: TArray<TComponent>; AComponent: TComponent): Boolean;
var
  mItem: TComponent;
begin
  for mItem in AList do
  begin
    if mItem = AComponent then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Neue Auswahl: Satz allein, dazu oder ohne ihn.</summary>
function Combined(const ACurrent, ASet: TArray<TComponent>; AAction: Integer): TArray<TComponent>;
var
  mComponent: TComponent;
begin
  if AAction = cRestore then
  begin
    Exit(ASet);
  end;
  Result := nil;
  for mComponent in ACurrent do
  begin
    if (AAction = cAdd) or (not Contains(ASet, mComponent)) then
    begin
      Result := Result + [mComponent];
    end;
  end;
  if AAction = cAdd then
  begin
    for mComponent in ASet do
    begin
      if not Contains(Result, mComponent) then
      begin
        Result := Result + [mComponent];
      end;
    end;
  end;
end;

/// <summary>Satz pflegen: überschreiben, erweitern, umbenennen, verschieben, löschen.</summary>
procedure Maintain(ASets: TAtlasSelectionSets; const AKey: string; AIndex, AAction: Integer;
  const ASelected: TArray<string>);
var
  mName: string;
begin
  case AAction of
    cOverwrite:
      ASets.Replace(AKey, AIndex, ASelected);
    cExtend:
      ASets.Extend(AKey, AIndex, ASelected);
    cRename:
      begin
        mName := ASets.SetsOf(AKey)[AIndex].Name;
        if InputQuery(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSetsSaveTitle),
          TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSetsSavePrompt), mName) then
        begin
          ASets.Rename(AKey, AIndex, mName);
        end;
      end;
    cUp:
      ASets.Move(AKey, AIndex, -1);
    cDown:
      ASets.Move(AKey, AIndex, 1);
    cDelete:
      ASets.Delete(AKey, AIndex);
  end;
end;

procedure TAtlasIdeSelectionSets.Run(AAction, AIndex: Integer);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mSets: TAtlasSelectionSets;
  mList: TArray<TAtlasSelectionSet>;
  mSelected: TArray<TComponent>;
begin
  if not TAtlasIdeSettings.Current.DesignerSelectionSets or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mSets := Store(mEditor.FileName);
  mList := mSets.SetsOf(FormKey(mEditor.FileName));
  if (mDesigner = nil) or (AIndex < 0) or (AIndex > High(mList)) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  if AAction in [cRestore, cAdd, cRemove] then
  begin
    TAtlasDesignerAccess.Select(mDesigner, mRoot, Combined(mSelected, ComponentsOf(mRoot, mList[AIndex].Members),
      AAction));
    Exit;
  end;
  Maintain(mSets, FormKey(mEditor.FileName), AIndex, AAction, Names(mSelected));
  Watch(mRoot, mEditor.FileName);
  Save(mEditor.FileName);
end;

end.
