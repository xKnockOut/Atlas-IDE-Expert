unit Atlas.UI.Settings.Page.Search;

// Suchfeld über den Einstellungen (#1884): oben über dem Baum der Optionsseite bzw. auf der Übersicht „Atlas“.
// Mit Text ersetzt eine Trefferliste den Baum (OnSearching); jede Zeile nennt Beschriftung, Weg (Bereich ›
// Unterpunkt, bei einem anderen Knoten „in <Package>“) und Zustand (geändert, experimentell, gesperrt mit Grund,
// Modul aus, im Projekt festlegbar). Enter im Feld öffnet den ersten Treffer, Pfeil runter geht in die Liste,
// Escape leert das Feld; Enter oder Doppelklick in der Liste öffnet den gewählten. Strg+F und Strg+E setzen den
// Fokus ins Feld (Aktion am Besitzer, damit die Taste im ganzen Rahmen greift).
// Die Suche selbst steht in Atlas.Core.Settings.Search; Beschriftungen der Elemente (OnLabel), aktuelle Werte
// (OnSettings), installierte Module (OnInstalled) und das Öffnen (OnOpen) liefert der Besitzer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ActnList,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Settings.Search;

type
  TAtlasSettingsSearchBox = class(TComponent)
  public const
    cMaxHits = 50;
  private
    FEdit: TEdit;
    FList: TListBox;
    FActions: TActionList;
    FCatalog: TAtlasSettingsCatalog;
    FGroups: TFunc<TAtlasSettingsGroups>;
    FHits: TArray<TAtlasSettingHit>;
    FOnLabel: TAtlasSettingLabel;
    FOnSettings: TFunc<TAtlasPluginSettings>;
    FOnInstalled: TAtlasModuleInstalled;
    FOnOpen: TProc<TAtlasSettingHit>;
    FOnSearching: TProc<Boolean>;
    FOnModuleName: TFunc<string, string>;
    FOwnModule: string;
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure FocusExecute(Sender: TObject);
    procedure AddFocusAction(AShortCut: TShortCut);
    function RowText(const AHit: TAtlasSettingHit): string;
    function ModuleName(const ASwitch: string): string;
  public
    /// <summary>Feld (alTop) und Liste (alClient, verborgen) in AParent; Strg+F/Strg+E über AOwner.</summary>
    constructor Create(AOwner: TComponent; AParent: TWinControl; ACatalog: TAtlasSettingsCatalog;
      const AGroups: TFunc<TAtlasSettingsGroups>); reintroduce;
    /// <summary>Suche mit AText (auch Tests); leer: Liste weg, Baum wieder da.</summary>
    procedure SearchFor(const AText: string);
    /// <summary>Treffer AIndex öffnen; False ohne Treffer.</summary>
    function OpenHit(AIndex: Integer): Boolean;
    /// <summary>Feld und Liste zeigen bzw. verbergen (settings.search).</summary>
    procedure SetAvailable(AValue: Boolean);
    /// <summary>Fokus ins Feld, wenn es sichtbar ist.</summary>
    procedure FocusEdit;
    function RowTexts: TArray<string>;
    property Hits: TArray<TAtlasSettingHit> read FHits;
    property Edit: TEdit read FEdit;
    property List: TListBox read FList;
    /// <summary>Modulschalter des eigenen Knotens ('' = Base): Treffer anderer Knoten nennen ihr Package.</summary>
    property OwnModule: string read FOwnModule write FOwnModule;
    property OnLabel: TAtlasSettingLabel read FOnLabel write FOnLabel;
    property OnSettings: TFunc<TAtlasPluginSettings> read FOnSettings write FOnSettings;
    property OnInstalled: TAtlasModuleInstalled read FOnInstalled write FOnInstalled;
    property OnOpen: TProc<TAtlasSettingHit> read FOnOpen write FOnOpen;
    /// <summary>True: Trefferliste sichtbar (Baum verbergen); False: wieder Baum.</summary>
    property OnSearching: TProc<Boolean> read FOnSearching write FOnSearching;
    /// <summary>Name des Packages zu einem Modulschalter.</summary>
    property OnModuleName: TFunc<string, string> read FOnModuleName write FOnModuleName;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

{ TAtlasSettingsSearchBox }

constructor TAtlasSettingsSearchBox.Create(AOwner: TComponent; AParent: TWinControl;
  ACatalog: TAtlasSettingsCatalog; const AGroups: TFunc<TAtlasSettingsGroups>);
begin
  inherited Create(AOwner);
  FCatalog := ACatalog;
  FGroups := AGroups;
  FEdit := TEdit.Create(AOwner);
  FEdit.Parent := AParent;
  FEdit.Align := alTop;
  FEdit.AlignWithMargins := True;
  FEdit.TextHint := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSearchPrompt);
  FEdit.Hint := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSearchHint);
  FEdit.ShowHint := True;
  FEdit.OnChange := EditChange;
  FEdit.OnKeyDown := EditKeyDown;
  FList := TListBox.Create(AOwner);
  FList.Parent := AParent;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Visible := False;
  FList.OnKeyDown := ListKeyDown;
  FList.OnDblClick := ListDblClick;
  FActions := TActionList.Create(AOwner);
  AddFocusAction(ShortCut(Ord('F'), [ssCtrl]));
  AddFocusAction(ShortCut(Ord('E'), [ssCtrl]));
end;

procedure TAtlasSettingsSearchBox.AddFocusAction(AShortCut: TShortCut);
var
  mAction: TAction;
begin
  mAction := TAction.Create(FActions);
  mAction.ActionList := FActions;
  mAction.ShortCut := AShortCut;
  mAction.OnExecute := FocusExecute;
end;

procedure TAtlasSettingsSearchBox.FocusExecute(Sender: TObject);
begin
  FocusEdit;
end;

procedure TAtlasSettingsSearchBox.FocusEdit;
var
  mForm: TCustomForm;
begin
  mForm := GetParentForm(FEdit);
  if FEdit.Visible and FEdit.CanFocus and (mForm <> nil) and mForm.Visible then
  begin
    FEdit.SetFocus;
    FEdit.SelectAll;
  end;
end;

procedure TAtlasSettingsSearchBox.SetAvailable(AValue: Boolean);
begin
  FEdit.Visible := AValue;
  FActions.State := asNormal;
  if not AValue then
  begin
    FActions.State := asSuspended;
    SearchFor('');
  end;
end;

function TAtlasSettingsSearchBox.ModuleName(const ASwitch: string): string;
begin
  Result := '';
  if Assigned(FOnModuleName) then
  begin
    Result := FOnModuleName(ASwitch);
  end;
  if Result = '' then
  begin
    Result := ASwitch;
  end;
  if ASwitch = '' then
  begin
    Result := 'Base';
  end;
end;

function TAtlasSettingsSearchBox.RowText(const AHit: TAtlasSettingHit): string;
var
  mState: string;
begin
  Result := AHit.Caption + '  –  ' + AHit.Path;
  if not SameText(AHit.Module, FOwnModule) then
  begin
    Result := Result + '  (' + TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsSearchOtherNode,
      [ModuleName(AHit.Module)]) +
      ')';
  end;
  mState := TAtlasSettingsSearch.StateText(AHit);
  if mState <> '' then
  begin
    Result := Result + '  ·  ' + mState;
  end;
end;

procedure TAtlasSettingsSearchBox.SearchFor(const AText: string);
var
  mHit: TAtlasSettingHit;
  mGroups: TAtlasSettingsGroups;
  mEnglish: Boolean;
begin
  if FEdit.Text <> AText then
  begin
    // Ohne OnChange setzen: Die Suche folgt gleich hier.
    FEdit.OnChange := nil;
    try
      FEdit.Text := AText;
    finally
      FEdit.OnChange := EditChange;
    end;
  end;
  FHits := nil;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    mGroups := nil;
    if Assigned(FGroups) then
    begin
      mGroups := FGroups();
    end;
    mEnglish := TAtlasStrings.Language = TAtlasLanguage.English;
    if (mGroups <> nil) and (Trim(AText) <> '') then
    begin
      FHits := TAtlasSettingsSearch.Find(FCatalog, mGroups, AText, mEnglish, cMaxHits,
        TAtlasSettingsSearchHooks.Create(FOnInstalled, FOnLabel));
      if Assigned(FOnSettings) then
      begin
        TAtlasSettingsSearch.Annotate(FCatalog, mGroups, FOnSettings(), FHits, mEnglish);
      end;
    end;
    for mHit in FHits do
    begin
      FList.Items.Add(RowText(mHit));
    end;
    if (Length(FHits) = 0) and (Trim(AText) <> '') then
    begin
      FList.Items.Add(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsAtlasNoHits));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  FList.Visible := Trim(AText) <> '';
  if Length(FHits) > 0 then
  begin
    FList.ItemIndex := 0;
  end;
  if Assigned(FOnSearching) then
  begin
    FOnSearching(FList.Visible);
  end;
end;

function TAtlasSettingsSearchBox.RowTexts: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to FList.Items.Count - 1 do
  begin
    Result := Result + [FList.Items[mIndex]];
  end;
end;

function TAtlasSettingsSearchBox.OpenHit(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FHits));
  if Result and Assigned(FOnOpen) then
  begin
    FOnOpen(FHits[AIndex]);
  end;
end;

procedure TAtlasSettingsSearchBox.EditChange(Sender: TObject);
begin
  SearchFor(FEdit.Text);
end;

procedure TAtlasSettingsSearchBox.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        OpenHit(0);
        Key := 0;
      end;
    VK_DOWN:
      if FList.Visible and (Length(FHits) > 0) then
      begin
        FList.SetFocus;
        Key := 0;
      end;
    VK_ESCAPE:
      if FEdit.Text <> '' then
      begin
        SearchFor('');
        Key := 0;
      end;
  end;
end;

procedure TAtlasSettingsSearchBox.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        OpenHit(FList.ItemIndex);
        Key := 0;
      end;
    VK_UP:
      if FList.ItemIndex <= 0 then
      begin
        FEdit.SetFocus;
        Key := 0;
      end;
  end;
end;

procedure TAtlasSettingsSearchBox.ListDblClick(Sender: TObject);
begin
  OpenHit(FList.ItemIndex);
end;

end.
