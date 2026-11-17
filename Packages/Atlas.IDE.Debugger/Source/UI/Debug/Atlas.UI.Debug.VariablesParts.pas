unit Atlas.UI.Debug.VariablesParts;

// Teile des Fensters „Variablen“ (#853) neben Reitern und Baum, reine VCL:
//   - TAtlasVariablesFrameHooks: was der Frame an die IDE-Schicht meldet; ein
//     Objekt, das sich Frame, Suchleiste und Zeilenaktionen teilen.
//   - TAtlasVariablesSearchBar: Suchfeld mit „In Werten“ und „Unterelemente“.
//     Die Suche startet kurz nach der letzten Eingabe, Enter sofort, Esc leert.
//   - TAtlasVariablesRowActions: was sich mit einer Zeile tun lässt, als
//     Kontextmenü und Tasten: als Überwachung hinzufügen (Strg+W), Wert kopieren
//     (Strg+C), Ausdruck kopieren (Strg+Umschalt+C), Wert ändern (F2, über
//     „Werte ändern“ #868), Überwachung entfernen (Entf, nur im Reiter
//     Überwachung).
// Welcher Knoten gewählt ist, weiß nur der Frame; die Zeilenaktionen fragen ihn
// über TAtlasEvalNodeSource.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.UI.Debug.EvaluateTreeView;

type
  TAtlasVariablesSearchProc = reference to procedure(const AText: string; AMode: TAtlasVariableSearchMode;
    ADeep: Boolean);

  /// <summary>Was der Frame an die IDE-Schicht meldet; nicht gesetzte Einträge bleiben still. Gehört dem Frame.
  /// </summary>
  TAtlasVariablesFrameHooks = class
  private
    FTab: TProc<TAtlasVariablesTab>;
    FSearch: TAtlasVariablesSearchProc;
    FExpand: TAtlasEvalNodeProc;
    FAddWatch: TProc<string>;
    FRemoveWatch: TAtlasEvalNodeProc;
    FEditValue: TAtlasEvalNodeProc;
    FCanEditValue: TFunc<Boolean>;
  public
    /// <summary>Anderer Reiter; danach SetList mit dessen Liste.</summary>
    property Tab: TProc<TAtlasVariablesTab> read FTab write FTab;
    /// <summary>Suchtext oder Schalter geändert (leerer Text: Suche aus).</summary>
    property Search: TAtlasVariablesSearchProc read FSearch write FSearch;
    /// <summary>Erstes Aufklappen: Felder holen, danach Refresh.</summary>
    property Expand: TAtlasEvalNodeProc read FExpand write FExpand;
    property AddWatch: TProc<string> read FAddWatch write FAddWatch;
    property RemoveWatch: TAtlasEvalNodeProc read FRemoveWatch write FRemoveWatch;
    /// <summary>Wert der Zeile ändern (#868).</summary>
    property EditValue: TAtlasEvalNodeProc read FEditValue write FEditValue;
    /// <summary>Lässt sich gerade ein Wert ändern (debug.editValues an, Programm angehalten)?</summary>
    property CanEditValue: TFunc<Boolean> read FCanEditValue write FCanEditValue;
  end;

  /// <summary>Suchfeld mit „In Werten“ und „Unterelemente“; meldet über Hooks.Search.</summary>
  TAtlasVariablesSearchBar = class(TPanel)
  public const
    /// <summary>So lange nach der letzten Eingabe startet die Suche.</summary>
    cSearchDelayMs = 300;
  private
    FHooks: TAtlasVariablesFrameHooks;
    FEdit: TEdit;
    FValuesCheck: TCheckBox;
    FDeepCheck: TCheckBox;
    FTimer: TTimer;
    procedure SearchChange(Sender: TObject);
    procedure SearchTimer(Sender: TObject);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    /// <summary>AFrame ist Besitzer und Elternfenster; seine Auflösung bestimmt die Größen. ATop ordnet die Leiste
    /// unter die anderen oben ausgerichteten.</summary>
    constructor CreateIn(AFrame: TWinControl; AHooks: TAtlasVariablesFrameHooks; ATop, AHeight: Integer);
    destructor Destroy; override;
    procedure FocusSearch;
    property Edit: TEdit read FEdit;
  end;

  /// <summary>Kontextmenü und Tasten je Zeile des Baums.</summary>
  TAtlasVariablesRowActions = class
  private
    FHooks: TAtlasVariablesFrameHooks;
    FSource: TAtlasEvalNodeSource;
    FMenu: TPopupMenu;
    FWatches: Boolean;
    procedure AddItem(const AText: string; AAction: Integer; AShortCut: TShortCut);
    procedure MenuPopup(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    function Enabled(ANode: TAtlasEvalNode; AAction: Integer): Boolean;
    procedure Run(ANode: TAtlasEvalNode; AAction: Integer);
  public
    /// <summary>Das Menü gehört AOwner; ASource liefert den gewählten Knoten.</summary>
    constructor Create(AOwner: TComponent; AHooks: TAtlasVariablesFrameHooks; const ASource: TAtlasEvalNodeSource);
    /// <summary>Taste im Baum: führt die passende Aktion für den gewählten Knoten aus; True, wenn die Taste eine
    /// Aktion ist (dann ist sie verbraucht, auch wenn die Aktion gerade nicht geht).</summary>
    function KeyDown(AKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Text für „Wert kopieren“: der ganze Wert, ohne Wert leer.</summary>
    class function ValueText(ANode: TAtlasEvalNode): string; static;
    property Menu: TPopupMenu read FMenu;
    /// <summary>Reiter Überwachung: Entf entfernt die Zeile.</summary>
    property Watches: Boolean read FWatches write FWatches;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Clipbrd,
  Atlas.UI.Debug.Values.Strings,
  Atlas.UI.Debug.VariablesStrings;

const
  /// <summary>Breite der Haken bei 96 dpi.</summary>
  cCheckWidth = 110;
  /// <summary>Abstand der Lage vor dem Ausrichten: Sie bestimmt die Reihenfolge gleich ausgerichteter Teile.
  /// </summary>
  cOrderStep = 1000;

type
  {$SCOPEDENUMS ON}
  /// <summary>Einträge des Kontextmenüs, als Tag der Menüeinträge.</summary>
  TRowAction = (None, AddWatch, CopyValue, CopyExpression, EditValue, RemoveWatch);
  {$SCOPEDENUMS OFF}

function AddCheck(AFrame, AParent: TWinControl; AText: TAtlasVariablesTextId; AOrder: Integer;
  AClick: TNotifyEvent): TCheckBox;
begin
  Result := TCheckBox.Create(AParent);
  // Lage vor dem Ausrichten: Sie bestimmt die Reihenfolge am rechten Rand.
  Result.Left := AOrder * cOrderStep;
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := MulDiv(cCheckWidth, AFrame.CurrentPPI, 96);
  Result.Caption := TAtlasVariablesStrings.Text(AText);
  Result.OnClick := AClick;
end;

function KeyAction(AKey: Word; AShift: TShiftState): TRowAction;
begin
  Result := TRowAction.None;
  if (AKey = Ord('W')) and (AShift = [ssCtrl]) then
  begin
    Result := TRowAction.AddWatch;
  end
  else if (AKey = Ord('C')) and (AShift = [ssCtrl]) then
  begin
    Result := TRowAction.CopyValue;
  end
  else if (AKey = Ord('C')) and (AShift = [ssCtrl, ssShift]) then
  begin
    Result := TRowAction.CopyExpression;
  end
  else if (AKey = VK_F2) and (AShift = []) then
  begin
    Result := TRowAction.EditValue;
  end
  else if (AKey = VK_DELETE) and (AShift = []) then
  begin
    Result := TRowAction.RemoveWatch;
  end;
end;

{ TAtlasVariablesSearchBar }

constructor TAtlasVariablesSearchBar.CreateIn(AFrame: TWinControl; AHooks: TAtlasVariablesFrameHooks; ATop,
  AHeight: Integer);
begin
  inherited Create(AFrame);
  FHooks := AHooks;
  // Erst Lage und Höhe, dann ausrichten: Sonst kann die VCL die Reihenfolge der Leisten vertauschen.
  Top := ATop;
  Height := AHeight;
  Align := alTop;
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
  Parent := AFrame;
  FValuesCheck := AddCheck(AFrame, Self, TAtlasVariablesTextId.VariablesSearchValues, 1, SearchChange);
  FDeepCheck := AddCheck(AFrame, Self, TAtlasVariablesTextId.VariablesSearchDeep, 2, SearchChange);
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  FEdit.AlignWithMargins := True;
  FEdit.TextHint := TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesSearchHint);
  FEdit.OnChange := SearchChange;
  FEdit.OnKeyDown := SearchKeyDown;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cSearchDelayMs;
  FTimer.OnTimer := SearchTimer;
end;

destructor TAtlasVariablesSearchBar.Destroy;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  inherited Destroy;
end;

procedure TAtlasVariablesSearchBar.SearchChange(Sender: TObject);
begin
  // Neu anstoßen: Die Suche startet erst, wenn eine Weile nichts mehr kommt.
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasVariablesSearchBar.SearchTimer(Sender: TObject);
var
  mMode: TAtlasVariableSearchMode;
begin
  FTimer.Enabled := False;
  mMode := TAtlasVariableSearchMode.Name;
  if FValuesCheck.Checked then
  begin
    mMode := TAtlasVariableSearchMode.Value;
  end;
  if Assigned(FHooks.Search) then
  begin
    FHooks.Search(Trim(FEdit.Text), mMode, FDeepCheck.Checked);
  end;
end;

procedure TAtlasVariablesSearchBar.SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    SearchTimer(Sender);
  end
  else if (Key = VK_ESCAPE) and (Shift = []) and (FEdit.Text <> '') then
  begin
    Key := 0;
    FEdit.Text := '';
  end;
end;

procedure TAtlasVariablesSearchBar.FocusSearch;
begin
  if FEdit.CanFocus and FEdit.Showing then
  begin
    FEdit.SetFocus;
    FEdit.SelectAll;
  end;
end;

{ TAtlasVariablesRowActions }

constructor TAtlasVariablesRowActions.Create(AOwner: TComponent; AHooks: TAtlasVariablesFrameHooks;
  const ASource: TAtlasEvalNodeSource);
begin
  inherited Create;
  FHooks := AHooks;
  FSource := ASource;
  FMenu := TPopupMenu.Create(AOwner);
  FMenu.OnPopup := MenuPopup;
  AddItem(TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesAddWatch), Ord(TRowAction.AddWatch),
    ShortCut(Ord('W'), [ssCtrl]));
  AddItem(TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesCopyValue), Ord(TRowAction.CopyValue),
    ShortCut(Ord('C'), [ssCtrl]));
  AddItem(TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesCopyExpression), Ord(TRowAction.CopyExpression),
    ShortCut(Ord('C'), [ssCtrl, ssShift]));
  AddItem(TAtlasValuesStrings.Text(TAtlasValuesTextId.EditValueAction), Ord(TRowAction.EditValue),
    ShortCut(VK_F2, []));
  AddItem(TAtlasVariablesStrings.Text(TAtlasVariablesTextId.VariablesRemoveWatch), Ord(TRowAction.RemoveWatch),
    ShortCut(VK_DELETE, []));
end;

procedure TAtlasVariablesRowActions.AddItem(const AText: string; AAction: Integer; AShortCut: TShortCut);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := AText;
  mItem.Tag := AAction;
  mItem.ShortCut := AShortCut;
  mItem.OnClick := MenuClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasVariablesRowActions.MenuPopup(Sender: TObject);
var
  mNode: TAtlasEvalNode;
  mIndex: Integer;
  mItem: TMenuItem;
begin
  mNode := FSource();
  for mIndex := 0 to FMenu.Items.Count - 1 do
  begin
    mItem := FMenu.Items[mIndex];
    mItem.Enabled := Enabled(mNode, mItem.Tag);
  end;
end;

procedure TAtlasVariablesRowActions.MenuClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    Run(FSource(), TMenuItem(Sender).Tag);
  end;
end;

function TAtlasVariablesRowActions.Enabled(ANode: TAtlasEvalNode; AAction: Integer): Boolean;
begin
  Result := False;
  if ANode = nil then
  begin
    Exit;
  end;
  case TRowAction(AAction) of
    TRowAction.AddWatch, TRowAction.CopyExpression:
      Result := ANode.Expression <> '';
    TRowAction.CopyValue:
      Result := ANode.State = TAtlasEvalState.Value;
    TRowAction.EditValue:
      Result := (ANode.State = TAtlasEvalState.Value) and Assigned(FHooks.EditValue) and
        Assigned(FHooks.CanEditValue) and FHooks.CanEditValue();
    TRowAction.RemoveWatch:
      Result := FWatches and (ANode.Parent = nil);
    TRowAction.None: ;
  end;
end;

procedure TAtlasVariablesRowActions.Run(ANode: TAtlasEvalNode; AAction: Integer);
begin
  if not Enabled(ANode, AAction) then
  begin
    Exit;
  end;
  case TRowAction(AAction) of
    TRowAction.AddWatch:
      if Assigned(FHooks.AddWatch) then
      begin
        FHooks.AddWatch(ANode.Expression);
      end;
    TRowAction.CopyValue:
      Clipboard.AsText := ValueText(ANode);
    TRowAction.CopyExpression:
      Clipboard.AsText := ANode.Expression;
    TRowAction.EditValue:
      FHooks.EditValue(ANode);
    TRowAction.RemoveWatch:
      if Assigned(FHooks.RemoveWatch) then
      begin
        FHooks.RemoveWatch(ANode);
      end;
    TRowAction.None: ;
  end;
end;

function TAtlasVariablesRowActions.KeyDown(AKey: Word; AShift: TShiftState): Boolean;
var
  mAction: TRowAction;
begin
  mAction := KeyAction(AKey, AShift);
  Result := mAction <> TRowAction.None;
  if Result then
  begin
    Run(FSource(), Ord(mAction));
  end;
end;

class function TAtlasVariablesRowActions.ValueText(ANode: TAtlasEvalNode): string;
begin
  Result := '';
  if (ANode <> nil) and (ANode.State = TAtlasEvalState.Value) then
  begin
    Result := ANode.Value;
  end;
end;

end.
