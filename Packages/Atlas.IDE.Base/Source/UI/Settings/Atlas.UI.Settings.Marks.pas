unit Atlas.UI.Settings.Marks;

// Geänderte Werte auf der Optionsseite (#723), ohne Open Tools API: Jedes
// Bedienelement ist an die Namen seiner Einstellungen gebunden (Registry-Namen
// aus TAtlasPluginSettings.Load/Save). Weicht ein Wert vom Standard ab, steht
// ein Punkt „● “ vor der Beschriftung (beim Kontrollkästchen vor dessen Text,
// sonst vor der Beschriftung der Zeile) und ein Hinweis daran. Ein
// Kontextmenü an Kontrollkästchen, Auswahllisten, Beschriftungen und Zeilen
// setzt die Einstellung oder die ganze Seite auf den Standard zurück;
// Textfelder behalten ihr eigenes Menü (Ausschneiden, Kopieren, Einfügen).
// Welche Namen geändert sind, bestimmt die Seite (TAtlasSettingsTransfer);
// diese Klasse zeigt es nur an und meldet Änderungen und Menüklicks.
// Experimentelle Einstellungen (#834) tragen hinter ihrer Beschriftung das
// Kennzeichen „[Experimentell]“ als Text (nicht nur Farbe, #447). Filter blendet
// in den Reitern alles aus, was nicht geändert bzw. nicht experimentell ist.
// Rahmen einer Funktion (#890, TAtlasSettingsGroup) zählen wie ein Reiter: Ihre
// Zeilen werden einzeln gefiltert; angeheftete Elemente (Pin: Rahmen, Hauptschalter,
// Grund der Sperre) bleiben immer sichtbar.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Menus,
  Atlas.UI.Settings.Group;

type
  /// <summary>Filter der Optionsseite (#834): alle, nur geänderte, nur experimentelle Einstellungen.</summary>
  TAtlasSettingsFilter = (sfAll, sfModified, sfExperimental);

  TAtlasSettingsBinding = record
    Control: TControl;
    /// <summary>Beschriftung, die den Punkt trägt; beim Kontrollkästchen nil (der Punkt steht in seinem
    /// Text).</summary>
    Caption: TLabel;
    Names: TArray<string>;
    /// <summary>Punkt zeigen (Listen wie die Prüfungen des Release-Wächters: nur Kontextmenü).</summary>
    Mark: Boolean;
    /// <summary>Text und Hinweis vor dem Punkt.</summary>
    Text: string;
    Hint: string;
    Marked: Boolean;
    /// <summary>Gehört zu einer experimentellen Einstellung (#834).</summary>
    Experimental: Boolean;
    /// <summary>Vorheriges OnClick bzw. OnChange; wird weiter aufgerufen.</summary>
    Changed: TNotifyEvent;
  end;

  /// <summary>Bindungen der Bedienelemente an ihre Einstellungen mit Punkt und Kennzeichen; Abfragen nach Namen
  /// und Lage. TAtlasSettingsMarks ergänzt Kontextmenü, Filter und Meldungen.</summary>
  TAtlasSettingsBindingList = class(TComponent)
  public const
    Dot = '● ';
  private
    FBindings: TList<TAtlasSettingsBinding>;
    function GetCount: Integer;
    function GetBinding(AIndex: Integer): TAtlasSettingsBinding;
    procedure Render(AIndex: Integer);
  protected
    /// <summary>Bindung zu AControl (Element, Beschriftung oder Zeile); -1 ohne.</summary>
    function IndexOfControl(AControl: TObject): Integer;
    procedure Apply(AIndex: Integer; AMarked: Boolean);
    property List: TList<TAtlasSettingsBinding> read FBindings;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Punkte nach AModified (Registry-Namen) setzen; AEnabled False nimmt alle weg.</summary>
    procedure Show(const AModified: TArray<string>; AEnabled: Boolean);
    /// <summary>Namen aller Bindungen, deren Element in AParent liegt (Reiter der Seite).</summary>
    function NamesIn(AParent: TWinControl): TArray<string>;
    /// <summary>Namen aller Bindungen, deren Element AControl selbst ist oder darin liegt (#890).</summary>
    function NamesWithin(AControl: TControl): TArray<string>;
    /// <summary>Erstes gebundenes Element mit dem Namen AName; nil ohne.</summary>
    function ControlOfName(const AName: string): TControl;
    /// <summary>Beschriftung der Bindung mit dem Namen AName ohne Punkt und Kennzeichen; '' ohne.</summary>
    function TextOfName(const AName: string): string;
    /// <summary>Trägt eine Bindung in AParent einen Punkt?</summary>
    function HasMarked(AParent: TWinControl): Boolean;
    /// <summary>Namen der Bindung zu AControl (Element, Beschriftung oder Zeile); leer ohne.</summary>
    function NamesOf(AControl: TObject): TArray<string>;
    /// <summary>Trägt AControl (oder seine Beschriftung) einen Punkt?</summary>
    function IsMarked(AControl: TControl): Boolean;
    /// <summary>Bindungen mit einem Namen aus ANames als experimentell kennzeichnen (#834).</summary>
    procedure MarkExperimental(const ANames: TArray<string>);
    /// <summary>Gibt es eine experimentelle Bindung?</summary>
    function HasExperimental: Boolean;
    /// <summary>Ist AControl (oder seine Beschriftung) als experimentell gekennzeichnet?</summary>
    function IsExperimental(AControl: TControl): Boolean;
    property Count: Integer read GetCount;
    property Bindings[AIndex: Integer]: TAtlasSettingsBinding read GetBinding;
  end;

  TAtlasSettingsMarks = class(TAtlasSettingsBindingList)
  private
    FMenu: TPopupMenu;
    FResetItem: TMenuItem;
    FResetPageItem: TMenuItem;
    FLoading: Integer;
    FMenuIndex: Integer;
    FOnChanged: TNotifyEvent;
    FOnReset: TProc<TArray<string>>;
    FOnResetPage: TNotifyEvent;
    FFilter: TAtlasSettingsFilter;
    FHidden: TList<TControl>;
    /// <summary>Ursprüngliche Lage der Elemente der gefilterten Reiter; der Filter rückt die sichtbaren
    /// zusammen.</summary>
    FTops: TDictionary<TControl, Integer>;
    /// <summary>Elemente, die der Filter nie ausblendet (#890).</summary>
    FPinned: TList<TControl>;
    procedure Restore;
    procedure Compact(AContainer: TWinControl);
    /// <summary>Zeilen, die AFilter zeigt (samt angehefteten), in AShown; ihre Reiter bzw. Rahmen in
    /// AContainers.</summary>
    procedure CollectRows(AFilter: TAtlasSettingsFilter; AShown, AContainers: TList<TControl>);
    /// <summary>Lage aller Elemente von AContainer merken, die nicht in AShown stehen ausblenden.</summary>
    procedure HideRows(AContainer: TWinControl; AShown: TList<TControl>);
    function FindCaption(AControl: TControl): TLabel;
    procedure ControlChanged(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure ResetPageClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Bindet AControl an ANames; mit AMark False nur Kontextmenü und Zurücksetzen, kein Punkt.</summary>
    procedure Bind(AControl: TControl; const ANames: array of string; AMark: Boolean); overload;
    procedure Bind(AControl: TControl; const ANames: array of string); overload;
    /// <summary>Liegt in AParent eine Bindung, die der aktuelle Filter zeigt (sfAll: irgendeine)?</summary>
    function HasMatch(AParent: TWinControl): Boolean;
    /// <summary>AControl bleibt beim Filtern immer sichtbar (Rahmen, Hauptschalter, Grund der Sperre).</summary>
    procedure Pin(AControl: TControl);
    /// <summary>Zeilen der Reiter nach AFilter zeigen; sfAll stellt alles wieder her, wie es vorher war.</summary>
    procedure ApplyFilter(AFilter: TAtlasSettingsFilter);
    property Filter: TAtlasSettingsFilter read FFilter;
    /// <summary>Während des Ladens melden Änderungen nichts.</summary>
    procedure BeginLoad;
    procedure EndLoad;
    property Menu: TPopupMenu read FMenu;
    /// <summary>Ein gebundenes Element wurde geändert (nicht während des Ladens).</summary>
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    /// <summary>„Auf Standard zurücksetzen“ für diese Namen.</summary>
    property OnReset: TProc<TArray<string>> read FOnReset write FOnReset;
    /// <summary>„Ganze Seite auf Standard zurücksetzen“.</summary>
    property OnResetPage: TNotifyEvent read FOnResetPage write FOnResetPage;
  end;

implementation

uses
  Atlas.UI.Strings;

type
  TControlAccess = class(TControl);

/// <summary>Kommt ein Name aus ANames in AOthers vor (ohne Groß-/Kleinschreibung)?</summary>
function AnyNameIn(const ANames, AOthers: TArray<string>): Boolean;
var
  mName, mOther: string;
begin
  for mName in ANames do
  begin
    for mOther in AOthers do
    begin
      if SameText(mName, mOther) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Zeigt AFilter die Bindung?</summary>
function Matches(const ABinding: TAtlasSettingsBinding; AFilter: TAtlasSettingsFilter): Boolean;
begin
  case AFilter of
    sfModified:
      Result := ABinding.Marked;
    sfExperimental:
      Result := ABinding.Experimental;
  else
    Result := True;
  end;
end;

/// <summary>Element direkt im Reiter (rollbarer Inhalt) oder im Rahmen einer Funktion, das AControl trägt: die
/// Zeile oder das Element selbst.</summary>
function RowOf(AControl: TControl): TControl;
begin
  Result := AControl;
  while (Result <> nil) and (Result.Parent <> nil) and not (Result.Parent is TScrollingWinControl) and
    not (Result.Parent is TAtlasSettingsGroup) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Liegt AControl in AParent (oder ist es selbst)?</summary>
function Inside(AControl, AParent: TControl): Boolean;
var
  mParent: TControl;
begin
  mParent := AControl;
  while (mParent <> nil) and (mParent <> AParent) do
  begin
    mParent := mParent.Parent;
  end;
  Result := mParent <> nil;
end;

{ TAtlasSettingsBindingList }

constructor TAtlasSettingsBindingList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBindings := TList<TAtlasSettingsBinding>.Create;
end;

destructor TAtlasSettingsBindingList.Destroy;
begin
  FBindings.Free;
  inherited;
end;

function TAtlasSettingsBindingList.GetCount: Integer;
begin
  Result := FBindings.Count;
end;

function TAtlasSettingsBindingList.GetBinding(AIndex: Integer): TAtlasSettingsBinding;
begin
  Result := FBindings[AIndex];
end;

function TAtlasSettingsBindingList.IndexOfControl(AControl: TObject): Integer;
var
  mIndex: Integer;
  mBinding: TAtlasSettingsBinding;
begin
  Result := -1;
  if AControl = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to FBindings.Count - 1 do
  begin
    mBinding := FBindings[mIndex];
    if (mBinding.Control = AControl) or ((mBinding.Caption <> nil) and (mBinding.Caption = AControl)) then
    begin
      Exit(mIndex);
    end;
  end;
  // Zeile: erste Bindung, deren Element darin liegt.
  for mIndex := 0 to FBindings.Count - 1 do
  begin
    if FBindings[mIndex].Control.Parent = AControl then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TAtlasSettingsBindingList.Apply(AIndex: Integer; AMarked: Boolean);
var
  mBinding: TAtlasSettingsBinding;
begin
  mBinding := FBindings[AIndex];
  if mBinding.Marked = AMarked then
  begin
    Exit;
  end;
  mBinding.Marked := AMarked;
  FBindings[AIndex] := mBinding;
  Render(AIndex);
end;

procedure TAtlasSettingsBindingList.Render(AIndex: Integer);
var
  mBinding: TAtlasSettingsBinding;
  mText, mHint: string;
begin
  mBinding := FBindings[AIndex];
  mText := mBinding.Text;
  mHint := mBinding.Hint;
  if mBinding.Experimental then
  begin
    mText := mText + '  [' + TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalTag) + ']';
  end;
  if mBinding.Marked then
  begin
    mText := Dot + mText;
    mHint := TAtlasStrings.Text(TAtlasTextId.SettingsModifiedHint);
  end;
  if mBinding.Control is TCheckBox then
  begin
    TCheckBox(mBinding.Control).Caption := mText;
    mBinding.Control.Hint := mHint;
    mBinding.Control.ShowHint := mHint <> '';
  end
  else if mBinding.Caption <> nil then
  begin
    mBinding.Caption.Caption := mText;
    mBinding.Caption.Hint := mHint;
    mBinding.Caption.ShowHint := mHint <> '';
  end;
end;

procedure TAtlasSettingsBindingList.Show(const AModified: TArray<string>; AEnabled: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := 0 to FBindings.Count - 1 do
  begin
    Apply(mIndex, AEnabled and FBindings[mIndex].Mark and AnyNameIn(FBindings[mIndex].Names, AModified));
  end;
end;

function TAtlasSettingsBindingList.NamesIn(AParent: TWinControl): TArray<string>;
var
  mBinding: TAtlasSettingsBinding;
  mParent: TWinControl;
begin
  Result := nil;
  for mBinding in FBindings do
  begin
    mParent := mBinding.Control.Parent;
    while (mParent <> nil) and (mParent <> AParent) do
    begin
      mParent := mParent.Parent;
    end;
    if mParent <> nil then
    begin
      Result := Result + mBinding.Names;
    end;
  end;
end;

function TAtlasSettingsBindingList.NamesWithin(AControl: TControl): TArray<string>;
var
  mBinding: TAtlasSettingsBinding;
begin
  Result := nil;
  for mBinding in FBindings do
  begin
    if Inside(mBinding.Control, AControl) then
    begin
      Result := Result + mBinding.Names;
    end;
  end;
end;

function TAtlasSettingsBindingList.ControlOfName(const AName: string): TControl;
var
  mBinding: TAtlasSettingsBinding;
  mName: string;
begin
  Result := nil;
  for mBinding in FBindings do
  begin
    for mName in mBinding.Names do
    begin
      if SameText(mName, AName) then
      begin
        Exit(mBinding.Control);
      end;
    end;
  end;
end;

function TAtlasSettingsBindingList.TextOfName(const AName: string): string;
var
  mBinding: TAtlasSettingsBinding;
  mName: string;
begin
  Result := '';
  for mBinding in FBindings do
  begin
    for mName in mBinding.Names do
    begin
      if SameText(mName, AName) then
      begin
        Exit(StringReplace(mBinding.Text, '&', '', [rfReplaceAll]));
      end;
    end;
  end;
end;

function TAtlasSettingsBindingList.HasMarked(AParent: TWinControl): Boolean;
var
  mBinding: TAtlasSettingsBinding;
begin
  for mBinding in FBindings do
  begin
    if mBinding.Marked and Inside(mBinding.Control, AParent) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsBindingList.NamesOf(AControl: TObject): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := IndexOfControl(AControl);
  if mIndex >= 0 then
  begin
    Result := FBindings[mIndex].Names;
  end;
end;

function TAtlasSettingsBindingList.IsMarked(AControl: TControl): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOfControl(AControl);
  Result := (mIndex >= 0) and FBindings[mIndex].Marked;
end;

procedure TAtlasSettingsBindingList.MarkExperimental(const ANames: TArray<string>);
var
  mIndex: Integer;
  mBinding: TAtlasSettingsBinding;
  mFound: Boolean;
begin
  for mIndex := 0 to FBindings.Count - 1 do
  begin
    mBinding := FBindings[mIndex];
    mFound := AnyNameIn(mBinding.Names, ANames);
    if mFound <> mBinding.Experimental then
    begin
      mBinding.Experimental := mFound;
      FBindings[mIndex] := mBinding;
      Render(mIndex);
    end;
  end;
end;

function TAtlasSettingsBindingList.HasExperimental: Boolean;
var
  mBinding: TAtlasSettingsBinding;
begin
  for mBinding in FBindings do
  begin
    if mBinding.Experimental then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsBindingList.IsExperimental(AControl: TControl): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOfControl(AControl);
  Result := (mIndex >= 0) and FBindings[mIndex].Experimental;
end;

{ TAtlasSettingsMarks }

constructor TAtlasSettingsMarks.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHidden := TList<TControl>.Create;
  FTops := TDictionary<TControl, Integer>.Create;
  FPinned := TList<TControl>.Create;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FResetItem := TMenuItem.Create(FMenu);
  FResetItem.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsResetKey);
  FResetItem.OnClick := ResetClick;
  FMenu.Items.Add(FResetItem);
  FResetPageItem := TMenuItem.Create(FMenu);
  FResetPageItem.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsResetPageMenu);
  FResetPageItem.OnClick := ResetPageClick;
  FMenu.Items.Add(FResetPageItem);
  FMenuIndex := -1;
end;

destructor TAtlasSettingsMarks.Destroy;
begin
  FPinned.Free;
  FTops.Free;
  FHidden.Free;
  inherited;
end;

function TAtlasSettingsMarks.FindCaption(AControl: TControl): TLabel;
var
  mParent, mAbove: TWinControl;
  mIndex: Integer;
  mCandidate: TControl;
begin
  Result := nil;
  mParent := AControl.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  // Zeile mit Beschriftung links und Feld (AddNumber, AddChoice, AddKey).
  for mIndex := 0 to mParent.ControlCount - 1 do
  begin
    if (mParent.Controls[mIndex] is TLabel) and (mParent.Controls[mIndex] <> AControl) then
    begin
      Exit(TLabel(mParent.Controls[mIndex]));
    end;
  end;
  // Feld in eigener Zeile unter seiner Beschriftung (AddTextLine): die Zeile direkt darüber.
  if mParent.Parent = nil then
  begin
    Exit;
  end;
  mAbove := nil;
  for mIndex := 0 to mParent.Parent.ControlCount - 1 do
  begin
    mCandidate := mParent.Parent.Controls[mIndex];
    if (mCandidate is TWinControl) and (mCandidate <> mParent) and (mCandidate.Top < mParent.Top) and
      ((mAbove = nil) or (mCandidate.Top > mAbove.Top)) then
    begin
      mAbove := TWinControl(mCandidate);
    end;
  end;
  if (mAbove <> nil) and (mAbove.ControlCount = 1) and (mAbove.Controls[0] is TLabel) then
  begin
    Result := TLabel(mAbove.Controls[0]);
  end;
end;

procedure TAtlasSettingsMarks.Bind(AControl: TControl; const ANames: array of string);
begin
  Bind(AControl, ANames, True);
end;

procedure TAtlasSettingsMarks.Bind(AControl: TControl; const ANames: array of string; AMark: Boolean);
var
  mBinding: TAtlasSettingsBinding;
  mName: string;
begin
  if AControl = nil then
  begin
    Exit;
  end;
  mBinding := Default(TAtlasSettingsBinding);
  mBinding.Control := AControl;
  for mName in ANames do
  begin
    mBinding.Names := mBinding.Names + [mName];
  end;
  mBinding.Mark := AMark;
  if AControl is TCheckBox then
  begin
    mBinding.Text := TCheckBox(AControl).Caption;
    mBinding.Hint := AControl.Hint;
    mBinding.Changed := TCheckBox(AControl).OnClick;
    TCheckBox(AControl).OnClick := ControlChanged;
    TCheckBox(AControl).PopupMenu := FMenu;
  end
  else
  begin
    mBinding.Caption := FindCaption(AControl);
    if mBinding.Caption <> nil then
    begin
      mBinding.Text := mBinding.Caption.Caption;
      mBinding.Hint := mBinding.Caption.Hint;
      mBinding.Caption.PopupMenu := FMenu;
    end;
    if AControl is TComboBox then
    begin
      mBinding.Changed := TComboBox(AControl).OnChange;
      TComboBox(AControl).OnChange := ControlChanged;
      TComboBox(AControl).PopupMenu := FMenu;
    end
    else if AControl is TEdit then
    begin
      // Textfelder behalten ihr Menü; Zurücksetzen über Beschriftung oder Zeile.
      mBinding.Changed := TEdit(AControl).OnChange;
      TEdit(AControl).OnChange := ControlChanged;
    end
    else
    begin
      TControlAccess(AControl).PopupMenu := FMenu;
    end;
    // Die Zeile (nicht der rollbare Reiter selbst) bekommt das Menü mit.
    if (AControl.Parent <> nil) and not (AControl.Parent is TScrollingWinControl) then
    begin
      TControlAccess(AControl.Parent).PopupMenu := FMenu;
    end;
  end;
  List.Add(mBinding);
end;

procedure TAtlasSettingsMarks.ControlChanged(Sender: TObject);
var
  mIndex: Integer;
  mHandler: TNotifyEvent;
begin
  mIndex := IndexOfControl(Sender);
  if mIndex >= 0 then
  begin
    mHandler := List[mIndex].Changed;
    if Assigned(mHandler) then
    begin
      mHandler(Sender);
    end;
  end;
  if (FLoading = 0) and Assigned(FOnChanged) then
  begin
    FOnChanged(Self);
  end;
end;

function TAtlasSettingsMarks.HasMatch(AParent: TWinControl): Boolean;
var
  mBinding: TAtlasSettingsBinding;
begin
  for mBinding in List do
  begin
    if Inside(mBinding.Control, AParent) and Matches(mBinding, FFilter) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasSettingsMarks.Pin(AControl: TControl);
begin
  if (AControl <> nil) and not FPinned.Contains(AControl) then
  begin
    FPinned.Add(AControl);
  end;
end;

procedure TAtlasSettingsMarks.CollectRows(AFilter: TAtlasSettingsFilter; AShown, AContainers: TList<TControl>);
var
  mBinding: TAtlasSettingsBinding;
  mRow: TControl;
begin
  AShown.AddRange(FPinned);
  for mBinding in List do
  begin
    mRow := RowOf(mBinding.Control);
    if (mRow = nil) or (mRow.Parent = nil) then
    begin
      Continue;
    end;
    if not AContainers.Contains(mRow.Parent) then
    begin
      AContainers.Add(mRow.Parent);
    end;
    if Matches(mBinding, AFilter) then
    begin
      AShown.Add(mRow);
      // Beschriftung in eigener Zeile darüber (AddTextLine) bleibt mit sichtbar.
      if mBinding.Caption <> nil then
      begin
        AShown.Add(RowOf(mBinding.Caption));
      end;
    end;
  end;
end;

procedure TAtlasSettingsMarks.HideRows(AContainer: TWinControl; AShown: TList<TControl>);
var
  mChild: Integer;
  mControl: TControl;
begin
  // Lage im nicht gerollten Zustand merken. Position braucht das Fenster; ohne Fenster ist nichts gerollt.
  if (AContainer is TScrollingWinControl) and AContainer.HandleAllocated then
  begin
    TScrollingWinControl(AContainer).VertScrollBar.Position := 0;
  end;
  for mChild := 0 to AContainer.ControlCount - 1 do
  begin
    mControl := AContainer.Controls[mChild];
    FTops.AddOrSetValue(mControl, mControl.Top);
    if mControl.Visible and not AShown.Contains(mControl) then
    begin
      mControl.Visible := False;
      FHidden.Add(mControl);
    end;
  end;
end;

procedure TAtlasSettingsMarks.ApplyFilter(AFilter: TAtlasSettingsFilter);
var
  mShown, mContainers: TList<TControl>;
  mContainer: TControl;
begin
  Restore;
  FFilter := AFilter;
  if AFilter = sfAll then
  begin
    Exit;
  end;
  mShown := TList<TControl>.Create;
  mContainers := TList<TControl>.Create;
  try
    CollectRows(AFilter, mShown, mContainers);
    for mContainer in mContainers do
    begin
      HideRows(TWinControl(mContainer), mShown);
      Compact(TWinControl(mContainer));
    end;
  finally
    mContainers.Free;
    mShown.Free;
  end;
end;

procedure TAtlasSettingsMarks.Restore;
var
  mRow: TControl;
  mPair: TPair<TControl, Integer>;
begin
  // Vorher ausgeblendete Zeilen wieder zeigen (sie waren beim Filtern sichtbar) und an ihren Platz rücken.
  for mRow in FHidden do
  begin
    mRow.Visible := True;
  end;
  FHidden.Clear;
  for mPair in FTops do
  begin
    if (mPair.Key.Parent is TScrollingWinControl) and mPair.Key.Parent.HandleAllocated then
    begin
      TScrollingWinControl(mPair.Key.Parent).VertScrollBar.Position := 0;
    end;
  end;
  for mPair in FTops do
  begin
    mPair.Key.Top := mPair.Value;
  end;
  FTops.Clear;
end;

procedure TAtlasSettingsMarks.Compact(AContainer: TWinControl);
var
  mTops: TList<Integer>;
  mChild, mIndex, mShift, mTop: Integer;
  mVisible: Boolean;
begin
  // Die Reiter stapeln ihre Zeilen mit festen Abständen; ausgeblendete Zeilen hinterließen Lücken.
  // Zeilen mit gleicher Oberkante gelten als eine; sie fällt nur weg, wenn alle ihre Elemente ausgeblendet sind.
  mTops := TList<Integer>.Create;
  try
    for mChild := 0 to AContainer.ControlCount - 1 do
    begin
      if not mTops.Contains(FTops[AContainer.Controls[mChild]]) then
      begin
        mTops.Add(FTops[AContainer.Controls[mChild]]);
      end;
    end;
    mTops.Sort;
    mShift := 0;
    for mIndex := 0 to mTops.Count - 1 do
    begin
      mTop := mTops[mIndex];
      mVisible := False;
      for mChild := 0 to AContainer.ControlCount - 1 do
      begin
        if (FTops[AContainer.Controls[mChild]] = mTop) and AContainer.Controls[mChild].Visible then
        begin
          mVisible := True;
          AContainer.Controls[mChild].Top := mTop - mShift;
        end;
      end;
      if not mVisible and (mIndex < mTops.Count - 1) then
      begin
        Inc(mShift, mTops[mIndex + 1] - mTop);
      end;
    end;
  finally
    mTops.Free;
  end;
end;

procedure TAtlasSettingsMarks.BeginLoad;
begin
  Inc(FLoading);
end;

procedure TAtlasSettingsMarks.EndLoad;
begin
  if FLoading > 0 then
  begin
    Dec(FLoading);
  end;
end;

procedure TAtlasSettingsMarks.MenuPopup(Sender: TObject);
begin
  FMenuIndex := IndexOfControl(FMenu.PopupComponent);
  FResetItem.Enabled := FMenuIndex >= 0;
end;

procedure TAtlasSettingsMarks.ResetClick(Sender: TObject);
begin
  if (FMenuIndex >= 0) and (FMenuIndex < List.Count) and Assigned(FOnReset) then
  begin
    FOnReset(List[FMenuIndex].Names);
  end;
end;

procedure TAtlasSettingsMarks.ResetPageClick(Sender: TObject);
begin
  if Assigned(FOnResetPage) then
  begin
    FOnResetPage(Self);
  end;
end;

end.
