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
    /// <summary>Beschriftung, die den Punkt trägt; beim Kontrollkästchen nil (der Punkt steht in seinem Text).</summary>
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

  TAtlasSettingsMarks = class(TComponent)
  public const
    Dot = '● ';
  private
    FBindings: TList<TAtlasSettingsBinding>;
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
    /// <summary>Ursprüngliche Lage der Elemente der gefilterten Reiter; der Filter rückt die sichtbaren zusammen.</summary>
    FTops: TDictionary<TControl, Integer>;
    /// <summary>Elemente, die der Filter nie ausblendet (#890).</summary>
    FPinned: TList<TControl>;
    procedure Restore;
    procedure Compact(AContainer: TWinControl);
    function IndexOfControl(AControl: TObject): Integer;
    procedure Render(AIndex: Integer);
    function Matches(const ABinding: TAtlasSettingsBinding; AFilter: TAtlasSettingsFilter): Boolean;
    function FindCaption(AControl: TControl): TLabel;
    procedure ControlChanged(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure ResetPageClick(Sender: TObject);
    procedure Apply(AIndex: Integer; AMarked: Boolean);
    function GetCount: Integer;
    function GetBinding(AIndex: Integer): TAtlasSettingsBinding;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Bindet AControl an ANames; mit AMark False nur Kontextmenü und Zurücksetzen, kein Punkt.</summary>
    procedure Bind(AControl: TControl; const ANames: array of string; AMark: Boolean); overload;
    procedure Bind(AControl: TControl; const ANames: array of string); overload;
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
    /// <summary>Liegt in AParent eine Bindung, die der aktuelle Filter zeigt (sfAll: irgendeine)?</summary>
    function HasMatch(AParent: TWinControl): Boolean;
    /// <summary>Trägt eine Bindung in AParent einen Punkt?</summary>
    function HasMarked(AParent: TWinControl): Boolean;
    /// <summary>AControl bleibt beim Filtern immer sichtbar (Rahmen, Hauptschalter, Grund der Sperre).</summary>
    procedure Pin(AControl: TControl);
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
    /// <summary>Zeilen der Reiter nach AFilter zeigen; sfAll stellt alles wieder her, wie es vorher war.</summary>
    procedure ApplyFilter(AFilter: TAtlasSettingsFilter);
    property Filter: TAtlasSettingsFilter read FFilter;
    /// <summary>Während des Ladens melden Änderungen nichts.</summary>
    procedure BeginLoad;
    procedure EndLoad;
    property Count: Integer read GetCount;
    property Bindings[AIndex: Integer]: TAtlasSettingsBinding read GetBinding;
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

{ TAtlasSettingsMarks }

constructor TAtlasSettingsMarks.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBindings := TList<TAtlasSettingsBinding>.Create;
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
  FBindings.Free;
  inherited;
end;

function TAtlasSettingsMarks.GetCount: Integer;
begin
  Result := FBindings.Count;
end;

function TAtlasSettingsMarks.GetBinding(AIndex: Integer): TAtlasSettingsBinding;
begin
  Result := FBindings[AIndex];
end;

function TAtlasSettingsMarks.FindCaption(AControl: TControl): TLabel;
var
  Parent, Above: TWinControl;
  Index: Integer;
  Candidate: TControl;
begin
  Result := nil;
  Parent := AControl.Parent;
  if Parent = nil then
  begin
    Exit;
  end;
  // Zeile mit Beschriftung links und Feld (AddNumber, AddChoice, AddKey).
  for Index := 0 to Parent.ControlCount - 1 do
  begin
    if (Parent.Controls[Index] is TLabel) and (Parent.Controls[Index] <> AControl) then
    begin
      Exit(TLabel(Parent.Controls[Index]));
    end;
  end;
  // Feld in eigener Zeile unter seiner Beschriftung (AddTextLine): die Zeile direkt darüber.
  if Parent.Parent = nil then
  begin
    Exit;
  end;
  Above := nil;
  for Index := 0 to Parent.Parent.ControlCount - 1 do
  begin
    Candidate := Parent.Parent.Controls[Index];
    if (Candidate is TWinControl) and (Candidate <> Parent) and (Candidate.Top < Parent.Top) and
      ((Above = nil) or (Candidate.Top > Above.Top)) then
    begin
      Above := TWinControl(Candidate);
    end;
  end;
  if (Above <> nil) and (Above.ControlCount = 1) and (Above.Controls[0] is TLabel) then
  begin
    Result := TLabel(Above.Controls[0]);
  end;
end;

procedure TAtlasSettingsMarks.Bind(AControl: TControl; const ANames: array of string);
begin
  Bind(AControl, ANames, True);
end;

procedure TAtlasSettingsMarks.Bind(AControl: TControl; const ANames: array of string; AMark: Boolean);
var
  Binding: TAtlasSettingsBinding;
  mName: string;
begin
  if AControl = nil then
  begin
    Exit;
  end;
  Binding := Default(TAtlasSettingsBinding);
  Binding.Control := AControl;
  for mName in ANames do
  begin
    Binding.Names := Binding.Names + [mName];
  end;
  Binding.Mark := AMark;
  if AControl is TCheckBox then
  begin
    Binding.Text := TCheckBox(AControl).Caption;
    Binding.Hint := AControl.Hint;
    Binding.Changed := TCheckBox(AControl).OnClick;
    TCheckBox(AControl).OnClick := ControlChanged;
    TCheckBox(AControl).PopupMenu := FMenu;
  end
  else
  begin
    Binding.Caption := FindCaption(AControl);
    if Binding.Caption <> nil then
    begin
      Binding.Text := Binding.Caption.Caption;
      Binding.Hint := Binding.Caption.Hint;
      Binding.Caption.PopupMenu := FMenu;
    end;
    if AControl is TComboBox then
    begin
      Binding.Changed := TComboBox(AControl).OnChange;
      TComboBox(AControl).OnChange := ControlChanged;
      TComboBox(AControl).PopupMenu := FMenu;
    end
    else if AControl is TEdit then
    begin
      // Textfelder behalten ihr Menü; Zurücksetzen über Beschriftung oder Zeile.
      Binding.Changed := TEdit(AControl).OnChange;
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
  FBindings.Add(Binding);
end;

function TAtlasSettingsMarks.IndexOfControl(AControl: TObject): Integer;
var
  Index: Integer;
  Binding: TAtlasSettingsBinding;
begin
  Result := -1;
  if AControl = nil then
  begin
    Exit;
  end;
  for Index := 0 to FBindings.Count - 1 do
  begin
    Binding := FBindings[Index];
    if (Binding.Control = AControl) or ((Binding.Caption <> nil) and (Binding.Caption = AControl)) then
    begin
      Exit(Index);
    end;
  end;
  // Zeile: erste Bindung, deren Element darin liegt.
  for Index := 0 to FBindings.Count - 1 do
  begin
    if FBindings[Index].Control.Parent = AControl then
    begin
      Exit(Index);
    end;
  end;
end;

procedure TAtlasSettingsMarks.ControlChanged(Sender: TObject);
var
  Index: Integer;
  Handler: TNotifyEvent;
begin
  Index := IndexOfControl(Sender);
  if Index >= 0 then
  begin
    Handler := FBindings[Index].Changed;
    if Assigned(Handler) then
    begin
      Handler(Sender);
    end;
  end;
  if (FLoading = 0) and Assigned(FOnChanged) then
  begin
    FOnChanged(Self);
  end;
end;

procedure TAtlasSettingsMarks.Apply(AIndex: Integer; AMarked: Boolean);
var
  Binding: TAtlasSettingsBinding;
begin
  Binding := FBindings[AIndex];
  if Binding.Marked = AMarked then
  begin
    Exit;
  end;
  Binding.Marked := AMarked;
  FBindings[AIndex] := Binding;
  Render(AIndex);
end;

procedure TAtlasSettingsMarks.Render(AIndex: Integer);
var
  Binding: TAtlasSettingsBinding;
  Text, Hint: string;
begin
  Binding := FBindings[AIndex];
  Text := Binding.Text;
  Hint := Binding.Hint;
  if Binding.Experimental then
  begin
    Text := Text + '  [' + TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalTag) + ']';
  end;
  if Binding.Marked then
  begin
    Text := Dot + Text;
    Hint := TAtlasStrings.Text(TAtlasTextId.SettingsModifiedHint);
  end;
  if Binding.Control is TCheckBox then
  begin
    TCheckBox(Binding.Control).Caption := Text;
    Binding.Control.Hint := Hint;
    Binding.Control.ShowHint := Hint <> '';
  end
  else if Binding.Caption <> nil then
  begin
    Binding.Caption.Caption := Text;
    Binding.Caption.Hint := Hint;
    Binding.Caption.ShowHint := Hint <> '';
  end;
end;

procedure TAtlasSettingsMarks.Show(const AModified: TArray<string>; AEnabled: Boolean);
var
  Index: Integer;
  mName, Modified: string;
  Marked: Boolean;
begin
  for Index := 0 to FBindings.Count - 1 do
  begin
    Marked := False;
    if AEnabled and FBindings[Index].Mark then
    begin
      for mName in FBindings[Index].Names do
      begin
        for Modified in AModified do
        begin
          if SameText(mName, Modified) then
          begin
            Marked := True;
          end;
        end;
      end;
    end;
    Apply(Index, Marked);
  end;
end;

function TAtlasSettingsMarks.NamesIn(AParent: TWinControl): TArray<string>;
var
  Binding: TAtlasSettingsBinding;
  Parent: TWinControl;
begin
  Result := nil;
  for Binding in FBindings do
  begin
    Parent := Binding.Control.Parent;
    while (Parent <> nil) and (Parent <> AParent) do
    begin
      Parent := Parent.Parent;
    end;
    if Parent <> nil then
    begin
      Result := Result + Binding.Names;
    end;
  end;
end;

/// <summary>Liegt AControl in AParent (oder ist es selbst)?</summary>
function Inside(AControl, AParent: TControl): Boolean;
var
  Parent: TControl;
begin
  Parent := AControl;
  while (Parent <> nil) and (Parent <> AParent) do
  begin
    Parent := Parent.Parent;
  end;
  Result := Parent <> nil;
end;

function TAtlasSettingsMarks.NamesWithin(AControl: TControl): TArray<string>;
var
  Binding: TAtlasSettingsBinding;
begin
  Result := nil;
  for Binding in FBindings do
  begin
    if Inside(Binding.Control, AControl) then
    begin
      Result := Result + Binding.Names;
    end;
  end;
end;

function TAtlasSettingsMarks.ControlOfName(const AName: string): TControl;
var
  Binding: TAtlasSettingsBinding;
  mName: string;
begin
  Result := nil;
  for Binding in FBindings do
  begin
    for mName in Binding.Names do
    begin
      if SameText(mName, AName) then
      begin
        Exit(Binding.Control);
      end;
    end;
  end;
end;

function TAtlasSettingsMarks.TextOfName(const AName: string): string;
var
  Binding: TAtlasSettingsBinding;
  mName: string;
begin
  Result := '';
  for Binding in FBindings do
  begin
    for mName in Binding.Names do
    begin
      if SameText(mName, AName) then
      begin
        Exit(StringReplace(Binding.Text, '&', '', [rfReplaceAll]));
      end;
    end;
  end;
end;

function TAtlasSettingsMarks.HasMatch(AParent: TWinControl): Boolean;
var
  Binding: TAtlasSettingsBinding;
begin
  for Binding in FBindings do
  begin
    if Inside(Binding.Control, AParent) and Matches(Binding, FFilter) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsMarks.HasMarked(AParent: TWinControl): Boolean;
var
  Binding: TAtlasSettingsBinding;
begin
  for Binding in FBindings do
  begin
    if Binding.Marked and Inside(Binding.Control, AParent) then
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

function TAtlasSettingsMarks.NamesOf(AControl: TObject): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  Index := IndexOfControl(AControl);
  if Index >= 0 then
  begin
    Result := FBindings[Index].Names;
  end;
end;

function TAtlasSettingsMarks.IsMarked(AControl: TControl): Boolean;
var
  Index: Integer;
begin
  Index := IndexOfControl(AControl);
  Result := (Index >= 0) and FBindings[Index].Marked;
end;

procedure TAtlasSettingsMarks.MarkExperimental(const ANames: TArray<string>);
var
  Index: Integer;
  Binding: TAtlasSettingsBinding;
  mName, Experimental: string;
  Found: Boolean;
begin
  for Index := 0 to FBindings.Count - 1 do
  begin
    Binding := FBindings[Index];
    Found := False;
    for mName in Binding.Names do
    begin
      for Experimental in ANames do
      begin
        if SameText(mName, Experimental) then
        begin
          Found := True;
        end;
      end;
    end;
    if Found = Binding.Experimental then
    begin
      Continue;
    end;
    Binding.Experimental := Found;
    FBindings[Index] := Binding;
    Render(Index);
  end;
end;

function TAtlasSettingsMarks.HasExperimental: Boolean;
var
  Binding: TAtlasSettingsBinding;
begin
  for Binding in FBindings do
  begin
    if Binding.Experimental then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsMarks.IsExperimental(AControl: TControl): Boolean;
var
  Index: Integer;
begin
  Index := IndexOfControl(AControl);
  Result := (Index >= 0) and FBindings[Index].Experimental;
end;

function TAtlasSettingsMarks.Matches(const ABinding: TAtlasSettingsBinding; AFilter: TAtlasSettingsFilter): Boolean;
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

procedure TAtlasSettingsMarks.ApplyFilter(AFilter: TAtlasSettingsFilter);

  // Element direkt im Reiter (rollbarer Inhalt) oder im Rahmen einer Funktion, das AControl trägt: die Zeile oder
  // das Element selbst.
  function RowOf(AControl: TControl): TControl;
  begin
    Result := AControl;
    while (Result <> nil) and (Result.Parent <> nil) and not (Result.Parent is TScrollingWinControl) and
      not (Result.Parent is TAtlasSettingsGroup) do
    begin
      Result := Result.Parent;
    end;
  end;

var
  Shown, Containers: TList<TControl>;
  Binding: TAtlasSettingsBinding;
  Row: TControl;
  Container: TWinControl;
  Index, Child: Integer;
begin
  Restore;
  FFilter := AFilter;
  if AFilter = sfAll then
  begin
    Exit;
  end;
  Shown := TList<TControl>.Create;
  Containers := TList<TControl>.Create;
  try
    Shown.AddRange(FPinned);
    for Binding in FBindings do
    begin
      Row := RowOf(Binding.Control);
      if (Row = nil) or (Row.Parent = nil) then
      begin
        Continue;
      end;
      if not Containers.Contains(Row.Parent) then
      begin
        Containers.Add(Row.Parent);
      end;
      if Matches(Binding, AFilter) then
      begin
        Shown.Add(Row);
        // Beschriftung in eigener Zeile darüber (AddTextLine) bleibt mit sichtbar.
        if Binding.Caption <> nil then
        begin
          Shown.Add(RowOf(Binding.Caption));
        end;
      end;
    end;
    for Index := 0 to Containers.Count - 1 do
    begin
      Container := TWinControl(Containers[Index]);
      // Lage im nicht gerollten Zustand merken. Position braucht das Fenster; ohne Fenster ist nichts gerollt.
      if (Container is TScrollingWinControl) and Container.HandleAllocated then
      begin
        TScrollingWinControl(Container).VertScrollBar.Position := 0;
      end;
      for Child := 0 to Container.ControlCount - 1 do
      begin
        FTops.AddOrSetValue(Container.Controls[Child], Container.Controls[Child].Top);
        if Container.Controls[Child].Visible and not Shown.Contains(Container.Controls[Child]) then
        begin
          Container.Controls[Child].Visible := False;
          FHidden.Add(Container.Controls[Child]);
        end;
      end;
      Compact(Container);
    end;
  finally
    Containers.Free;
    Shown.Free;
  end;
end;

procedure TAtlasSettingsMarks.Restore;
var
  Row: TControl;
  Pair: TPair<TControl, Integer>;
begin
  // Vorher ausgeblendete Zeilen wieder zeigen (sie waren beim Filtern sichtbar) und an ihren Platz rücken.
  for Row in FHidden do
  begin
    Row.Visible := True;
  end;
  FHidden.Clear;
  for Pair in FTops do
  begin
    if (Pair.Key.Parent is TScrollingWinControl) and Pair.Key.Parent.HandleAllocated then
    begin
      TScrollingWinControl(Pair.Key.Parent).VertScrollBar.Position := 0;
    end;
  end;
  for Pair in FTops do
  begin
    Pair.Key.Top := Pair.Value;
  end;
  FTops.Clear;
end;

procedure TAtlasSettingsMarks.Compact(AContainer: TWinControl);
var
  Tops: TList<Integer>;
  Child, Index, Shift, Top: Integer;
  Visible: Boolean;
begin
  // Die Reiter stapeln ihre Zeilen mit festen Abständen; ausgeblendete Zeilen hinterließen Lücken.
  // Zeilen mit gleicher Oberkante gelten als eine; sie fällt nur weg, wenn alle ihre Elemente ausgeblendet sind.
  Tops := TList<Integer>.Create;
  try
    for Child := 0 to AContainer.ControlCount - 1 do
    begin
      if not Tops.Contains(FTops[AContainer.Controls[Child]]) then
      begin
        Tops.Add(FTops[AContainer.Controls[Child]]);
      end;
    end;
    Tops.Sort;
    Shift := 0;
    for Index := 0 to Tops.Count - 1 do
    begin
      Top := Tops[Index];
      Visible := False;
      for Child := 0 to AContainer.ControlCount - 1 do
      begin
        if (FTops[AContainer.Controls[Child]] = Top) and AContainer.Controls[Child].Visible then
        begin
          Visible := True;
          AContainer.Controls[Child].Top := Top - Shift;
        end;
      end;
      if not Visible and (Index < Tops.Count - 1) then
      begin
        Inc(Shift, Tops[Index + 1] - Top);
      end;
    end;
  finally
    Tops.Free;
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
  if (FMenuIndex >= 0) and (FMenuIndex < FBindings.Count) and Assigned(FOnReset) then
  begin
    FOnReset(FBindings[FMenuIndex].Names);
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
