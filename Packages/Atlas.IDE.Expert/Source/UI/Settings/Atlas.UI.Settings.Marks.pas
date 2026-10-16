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

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Menus;

type
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
    function IndexOfControl(AControl: TObject): Integer;
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
    /// <summary>Namen der Bindung zu AControl (Element, Beschriftung oder Zeile); leer ohne.</summary>
    function NamesOf(AControl: TObject): TArray<string>;
    /// <summary>Trägt AControl (oder seine Beschriftung) einen Punkt?</summary>
    function IsMarked(AControl: TControl): Boolean;
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
    Exit;
  // Zeile mit Beschriftung links und Feld (AddNumber, AddChoice, AddKey).
  for Index := 0 to Parent.ControlCount - 1 do
    if (Parent.Controls[Index] is TLabel) and (Parent.Controls[Index] <> AControl) then
      Exit(TLabel(Parent.Controls[Index]));
  // Feld in eigener Zeile unter seiner Beschriftung (AddTextLine): die Zeile direkt darüber.
  if Parent.Parent = nil then
    Exit;
  Above := nil;
  for Index := 0 to Parent.Parent.ControlCount - 1 do
  begin
    Candidate := Parent.Parent.Controls[Index];
    if (Candidate is TWinControl) and (Candidate <> Parent) and (Candidate.Top < Parent.Top) and
      ((Above = nil) or (Candidate.Top > Above.Top)) then
      Above := TWinControl(Candidate);
  end;
  if (Above <> nil) and (Above.ControlCount = 1) and (Above.Controls[0] is TLabel) then
    Result := TLabel(Above.Controls[0]);
end;

procedure TAtlasSettingsMarks.Bind(AControl: TControl; const ANames: array of string);
begin
  Bind(AControl, ANames, True);
end;

procedure TAtlasSettingsMarks.Bind(AControl: TControl; const ANames: array of string; AMark: Boolean);
var
  Binding: TAtlasSettingsBinding;
  Name: string;
begin
  if AControl = nil then
    Exit;
  Binding := Default(TAtlasSettingsBinding);
  Binding.Control := AControl;
  for Name in ANames do
    Binding.Names := Binding.Names + [Name];
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
      TControlAccess(AControl).PopupMenu := FMenu;
    // Die Zeile (nicht der rollbare Reiter selbst) bekommt das Menü mit.
    if (AControl.Parent <> nil) and not (AControl.Parent is TScrollingWinControl) then
      TControlAccess(AControl.Parent).PopupMenu := FMenu;
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
    Exit;
  for Index := 0 to FBindings.Count - 1 do
  begin
    Binding := FBindings[Index];
    if (Binding.Control = AControl) or ((Binding.Caption <> nil) and (Binding.Caption = AControl)) then
      Exit(Index);
  end;
  // Zeile: erste Bindung, deren Element darin liegt.
  for Index := 0 to FBindings.Count - 1 do
    if FBindings[Index].Control.Parent = AControl then
      Exit(Index);
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
      Handler(Sender);
  end;
  if (FLoading = 0) and Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TAtlasSettingsMarks.Apply(AIndex: Integer; AMarked: Boolean);
var
  Binding: TAtlasSettingsBinding;
  Text, Hint: string;
begin
  Binding := FBindings[AIndex];
  if Binding.Marked = AMarked then
    Exit;
  Binding.Marked := AMarked;
  FBindings[AIndex] := Binding;
  Text := Binding.Text;
  Hint := Binding.Hint;
  if AMarked then
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
  Name, Modified: string;
  Marked: Boolean;
begin
  for Index := 0 to FBindings.Count - 1 do
  begin
    Marked := False;
    if AEnabled and FBindings[Index].Mark then
      for Name in FBindings[Index].Names do
        for Modified in AModified do
          if SameText(Name, Modified) then
            Marked := True;
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
      Parent := Parent.Parent;
    if Parent <> nil then
      Result := Result + Binding.Names;
  end;
end;

function TAtlasSettingsMarks.NamesOf(AControl: TObject): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  Index := IndexOfControl(AControl);
  if Index >= 0 then
    Result := FBindings[Index].Names;
end;

function TAtlasSettingsMarks.IsMarked(AControl: TControl): Boolean;
var
  Index: Integer;
begin
  Index := IndexOfControl(AControl);
  Result := (Index >= 0) and FBindings[Index].Marked;
end;

procedure TAtlasSettingsMarks.BeginLoad;
begin
  Inc(FLoading);
end;

procedure TAtlasSettingsMarks.EndLoad;
begin
  if FLoading > 0 then
    Dec(FLoading);
end;

procedure TAtlasSettingsMarks.MenuPopup(Sender: TObject);
begin
  FMenuIndex := IndexOfControl(FMenu.PopupComponent);
  FResetItem.Enabled := FMenuIndex >= 0;
end;

procedure TAtlasSettingsMarks.ResetClick(Sender: TObject);
begin
  if (FMenuIndex >= 0) and (FMenuIndex < FBindings.Count) and Assigned(FOnReset) then
    FOnReset(FBindings[FMenuIndex].Names);
end;

procedure TAtlasSettingsMarks.ResetPageClick(Sender: TObject);
begin
  if Assigned(FOnResetPage) then
    FOnResetPage(Self);
end;

end.
