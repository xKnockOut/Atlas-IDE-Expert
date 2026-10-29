unit Atlas.UI.Build.SwitchesFrame;

// Inhalt des Seitenfensters „Compiler-Schalter“ (#558), reine VCL: oben Datei
// und Zeile der Cursorposition, darunter die Liste mit den Abschnitten
// Schalter, Hinweise und Warnungen, Bedingte Symbole und Ziel. Spalten:
// Schalter (mit langem Namen), Wert, Stand der .dproj, Herkunft
// („gesetzt in Zeile 10“, „gesetzt in Optionen.inc, Zeile 3“, „Projektoption
// DCC_RangeChecking“, „Compiler-Vorgabe“). Werte, die von der .dproj
// abweichen, stehen fett in der Warnfarbe; unten die Kurzfassung der
// Abweichungen. Bedienung: Doppelklick oder Enter springt zur Direktive
// (OnJump) bzw. öffnet bei einer Projektoption die Projektoptionen
// (OnOptions); Strg+C und das Kontextmenü kopieren alles als Text (OnCopy).
// Ohne Datei, ohne Server oder während der Berechnung steht ein Hinweis
// statt der Liste. Die DFM ist leer, weil TCustomFrame.Create für abgeleitete
// Frames eine Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Build.CompilerSwitches;

type
  /// <summary>Zeile der Liste: Kopf eines Abschnitts oder Index in TAtlasCompilerSwitchView.Rows.</summary>
  TAtlasSwitchLine = record
    Header: Boolean;
    Section: TAtlasSwitchSection;
    Row: Integer;
  end;

  TAtlasSwitchLines = TArray<TAtlasSwitchLine>;

  TAtlasBuildSwitchesFrame = class(TFrame)
  private
    FWhere: TLabel;
    FList: TListView;
    FEmpty: TLabel;
    FSummary: TLabel;
    FMenu: TPopupMenu;
    FJumpItem: TMenuItem;
    FOptionsItem: TMenuItem;
    FCopyItem: TMenuItem;
    FView: TAtlasCompilerSwitchView;
    FHasView: Boolean;
    FLines: TAtlasSwitchLines;
    FFileName: string;
    FLine: Integer;
    FMessage: string;
    FOnJump: TProc<TAtlasSwitchRow>;
    FOnOptions: TProc;
    FOnCopy: TProc<string>;
    function AddColumn(const ACaption: string; AWidth: Integer): TListColumn;
    function AddMenuItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
    procedure Refill;
    function ListColor(AColor: TColor): TColor;
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure RowColors(ACanvas: TCanvas; AState: TCustomDrawState; AIndex: Integer);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MenuPopup(Sender: TObject);
    procedure JumpClick(Sender: TObject);
    procedure OptionsClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Stand an AFileName, ALine (0-basiert) zeigen; die Auswahl bleibt, soweit möglich.</summary>
    procedure SetView(const AView: TAtlasCompilerSwitchView; const AFileName: string; ALine: Integer);
    /// <summary>Hinweis statt der Liste (keine Datei, kein Server); '' = Liste zeigen.</summary>
    procedure SetMessage(const AText: string);
    /// <summary>Gewählte Zeile mit Wert; False bei Kopf oder ohne Auswahl.</summary>
    function TrySelected(out ARow: TAtlasSwitchRow): Boolean;
    /// <summary>Doppelklick bzw. Enter: springen oder Projektoptionen.</summary>
    procedure ExecuteSelected;
    procedure CopyAll;
    /// <summary>Zeilen der Liste: je Abschnitt mit Zeilen ein Kopf, dann die Zeilen.</summary>
    class function Lines(const AView: TAtlasCompilerSwitchView): TAtlasSwitchLines; static;
    class function SectionText(ASection: TAtlasSwitchSection): string; static;
    /// <summary>Text der Spalten: Schalter, Wert, Projekt, Herkunft.</summary>
    class function Cells(const ARow: TAtlasSwitchRow): TArray<string>; static;
    /// <summary>Herkunft: „gesetzt in Zeile 10“, „Projektoption DCC_Hints“, „Compiler-Vorgabe“ ….</summary>
    class function OriginText(const ARow: TAtlasSwitchRow): string; static;
    /// <summary>Alles als Text mit Tabulatoren (Kopieren).</summary>
    class function AsText(const AView: TAtlasCompilerSwitchView): string; static;
    property WhereLabel: TLabel read FWhere;
    property List: TListView read FList;
    property EmptyLabel: TLabel read FEmpty;
    property SummaryLabel: TLabel read FSummary;
    property Menu: TPopupMenu read FMenu;
    property ShownLines: TAtlasSwitchLines read FLines;
    property OnJump: TProc<TAtlasSwitchRow> read FOnJump write FOnJump;
    property OnOptions: TProc read FOnOptions write FOnOptions;
    property OnCopy: TProc<string> read FOnCopy write FOnCopy;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings;

{$R *.dfm}

{ TAtlasBuildSwitchesFrame }

constructor TAtlasBuildSwitchesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FLine := -1;
  FMessage := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesEmpty);

  FWhere := TLabel.Create(Self);
  FWhere.Parent := Self;
  FWhere.Align := alTop;
  FWhere.AlignWithMargins := True;
  FWhere.ShowAccelChar := False;
  FWhere.Caption := '';

  FSummary := TLabel.Create(Self);
  FSummary.Parent := Self;
  FSummary.Align := alBottom;
  FSummary.AlignWithMargins := True;
  FSummary.ShowAccelChar := False;
  FSummary.WordWrap := True;
  FSummary.Font.Color := clGrayText;
  FSummary.Caption := '';

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FJumpItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesGoTo), JumpClick);
  FOptionsItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesOptions), OptionsClick);
  FCopyItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesCopy), CopyClick);

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  FList.PopupMenu := FMenu;
  AddColumn(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesColumnName), 170);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesColumnValue), 60);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesColumnProject), 60);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesColumnOrigin), 220);
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnCustomDrawSubItem := ListCustomDrawSubItem;

  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alClient;
  FEmpty.AlignWithMargins := True;
  FEmpty.WordWrap := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Font.Color := clGrayText;
  FEmpty.Caption := FMessage;
end;

procedure TAtlasBuildSwitchesFrame.CreateWnd;
begin
  inherited CreateWnd;
  Refill;
end;

function TAtlasBuildSwitchesFrame.AddColumn(const ACaption: string; AWidth: Integer): TListColumn;
begin
  Result := FList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

function TAtlasBuildSwitchesFrame.AddMenuItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  FMenu.Items.Add(Result);
end;

class function TAtlasBuildSwitchesFrame.Lines(const AView: TAtlasCompilerSwitchView): TAtlasSwitchLines;
var
  Section: TAtlasSwitchSection;
  Index: Integer;
  Line: TAtlasSwitchLine;
  HasHeader: Boolean;
begin
  Result := nil;
  for Section := Low(TAtlasSwitchSection) to High(TAtlasSwitchSection) do
  begin
    HasHeader := False;
    for Index := 0 to High(AView.Rows) do
    begin
      if AView.Rows[Index].Section <> Section then
        Continue;
      if not HasHeader then
      begin
        Line := Default(TAtlasSwitchLine);
        Line.Header := True;
        Line.Section := Section;
        Line.Row := -1;
        Result := Result + [Line];
        HasHeader := True;
      end;
      Line := Default(TAtlasSwitchLine);
      Line.Section := Section;
      Line.Row := Index;
      Result := Result + [Line];
    end;
  end;
end;

class function TAtlasBuildSwitchesFrame.SectionText(ASection: TAtlasSwitchSection): string;
begin
  case ASection of
    TAtlasSwitchSection.Switches:
      Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesSectionSwitches);
    TAtlasSwitchSection.Messages:
      Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesSectionMessages);
    TAtlasSwitchSection.Defines:
      Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesSectionDefines);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesSectionTarget);
  end;
end;

class function TAtlasBuildSwitchesFrame.OriginText(const ARow: TAtlasSwitchRow): string;
begin
  case ARow.Kind of
    TAtlasSwitchOriginKind.Directive:
      Result := TAtlasStrings.Fmt(TAtlasTextId.CompilerSwitchesOriginLine, [ARow.Line + 1]);
    TAtlasSwitchOriginKind.Include:
      Result := TAtlasStrings.Fmt(TAtlasTextId.CompilerSwitchesOriginInclude,
        [ExtractFileName(ARow.FileName), ARow.Line + 1]);
    TAtlasSwitchOriginKind.Project:
      begin
        // Symbole tragen ihre Herkunft schon als Satz („Konfiguration Debug (.dproj)“).
        if ARow.Section = TAtlasSwitchSection.Target then
          Result := ''
        else if (ARow.Section = TAtlasSwitchSection.Defines) and (ARow.OriginText <> '') then
          Result := ARow.OriginText
        else if ARow.OriginText <> '' then
          Result := TAtlasStrings.Fmt(TAtlasTextId.CompilerSwitchesOriginProjectNamed, [ARow.OriginText])
        else
          Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesOriginProject);
      end;
  else
    if (ARow.Section = TAtlasSwitchSection.Defines) and (ARow.OriginText <> '') then
      Result := ARow.OriginText
    else
      Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesOriginDefault);
  end;
end;

class function TAtlasBuildSwitchesFrame.Cells(const ARow: TAtlasSwitchRow): TArray<string>;
var
  Name: string;
begin
  Name := ARow.Name;
  if ARow.Section = TAtlasSwitchSection.Target then
  begin
    if ARow.Name = 'platform' then
      Name := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesPlatform)
    else
      Name := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesConfiguration);
    Result := TArray<string>.Create(Name, ARow.Value, '', '');
    Exit;
  end;
  if ARow.LongName <> '' then
    Name := Name + ' (' + ARow.LongName + ')';
  if ARow.Section = TAtlasSwitchSection.Defines then
    Result := TArray<string>.Create(Name, '', '', OriginText(ARow))
  else
    Result := TArray<string>.Create(Name, TAtlasCompilerSwitchTexts.Value(ARow.Value),
      TAtlasCompilerSwitchTexts.Value(ARow.ProjectValue), OriginText(ARow));
end;

class function TAtlasBuildSwitchesFrame.AsText(const AView: TAtlasCompilerSwitchView): string;
var
  Line: TAtlasSwitchLine;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    for Line in Lines(AView) do
      if Line.Header then
        Builder.Append(SectionText(Line.Section)).Append(sLineBreak)
      else
        Builder.Append('  ').Append(string.Join(#9, Cells(AView.Rows[Line.Row]))).Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TAtlasBuildSwitchesFrame.SetView(const AView: TAtlasCompilerSwitchView; const AFileName: string;
  ALine: Integer);
begin
  FView := AView;
  FHasView := True;
  FFileName := AFileName;
  FLine := ALine;
  FMessage := '';
  Refill;
end;

procedure TAtlasBuildSwitchesFrame.SetMessage(const AText: string);
begin
  FMessage := AText;
  if AText <> '' then
    FHasView := False;
  Refill;
end;

procedure TAtlasBuildSwitchesFrame.Refill;
var
  Line: TAtlasSwitchLine;
  Item: TListItem;
  Texts: TArray<string>;
  Part, Keep: Integer;
  Deviations: TAtlasSwitchRows;
  Row: TAtlasSwitchRow;
  Names: string;
begin
  FEmpty.Caption := FMessage;
  FEmpty.Visible := not FHasView;
  FList.Visible := FHasView;
  if not FHasView then
  begin
    FWhere.Caption := '';
    FSummary.Caption := '';
    Exit;
  end;
  if FFileName <> '' then
    FWhere.Caption := TAtlasStrings.Fmt(TAtlasTextId.CompilerSwitchesAt, [ExtractFileName(FFileName), FLine + 1])
  else
    FWhere.Caption := '';
  FLines := Lines(FView);
  Deviations := FView.Deviations;
  if Length(Deviations) = 0 then
    FSummary.Caption := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesNoDeviations)
  else
  begin
    Names := FView.Summary;
    if Names = '' then
      for Row in Deviations do
        Names := Trim(Names + ' ' + Row.Name);
    FSummary.Caption := TAtlasStrings.Fmt(TAtlasTextId.CompilerSwitchesDeviations, [Names]);
  end;
  if not FView.HasProject then
    FSummary.Caption := FSummary.Caption + sLineBreak + TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesNoProject);
  // Liste erst mit Fenster füllen (TListView.Items braucht eins); CreateWnd holt es nach.
  if not HandleAllocated then
    Exit;
  Keep := -1;
  if FList.Selected <> nil then
    Keep := FList.Selected.Index;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Line in FLines do
    begin
      Item := FList.Items.Add;
      if Line.Header then
      begin
        Item.Caption := SectionText(Line.Section);
        Continue;
      end;
      Texts := Cells(FView.Rows[Line.Row]);
      Item.Caption := '  ' + Texts[0];
      for Part := 1 to High(Texts) do
        Item.SubItems.Add(Texts[Part]);
    end;
    if (Keep >= 0) and (Keep < FList.Items.Count) then
      FList.Items[Keep].Selected := True;
  finally
    FList.Items.EndUpdate;
  end;
end;

function TAtlasBuildSwitchesFrame.TrySelected(out ARow: TAtlasSwitchRow): Boolean;
var
  Line: TAtlasSwitchLine;
begin
  ARow := Default(TAtlasSwitchRow);
  Result := FHasView and (FList.Selected <> nil) and (FList.Selected.Index <= High(FLines));
  if not Result then
    Exit;
  Line := FLines[FList.Selected.Index];
  Result := not Line.Header and (Line.Row >= 0) and (Line.Row <= High(FView.Rows));
  if Result then
    ARow := FView.Rows[Line.Row];
end;

procedure TAtlasBuildSwitchesFrame.ExecuteSelected;
var
  Row: TAtlasSwitchRow;
begin
  if not TrySelected(Row) then
    Exit;
  if Row.CanJump then
  begin
    if Assigned(FOnJump) then
      FOnJump(Row);
  end
  else if Row.FromProject and Assigned(FOnOptions) then
    FOnOptions();
end;

procedure TAtlasBuildSwitchesFrame.CopyAll;
begin
  if FHasView and Assigned(FOnCopy) then
    FOnCopy(AsText(FView));
end;

function TAtlasBuildSwitchesFrame.ListColor(AColor: TColor): TColor;
begin
  // Stil der Liste, nicht der globale: Die IDE themt ihre Fenster je Formular.
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(AColor));
end;

procedure TAtlasBuildSwitchesFrame.RowColors(ACanvas: TCanvas; AState: TCustomDrawState; AIndex: Integer);
var
  Line: TAtlasSwitchLine;
  Deviates: Boolean;
begin
  Deviates := False;
  ACanvas.Font.Style := [];
  if (AIndex >= 0) and (AIndex <= High(FLines)) then
  begin
    Line := FLines[AIndex];
    if Line.Header then
      ACanvas.Font.Style := [fsBold]
    else
    begin
      Deviates := FView.Rows[Line.Row].Deviates;
      if Deviates then
        ACanvas.Font.Style := [fsBold];
    end;
  end;
  // Farben ausdrücklich aus dem Stil der Liste, sonst im dunklen Thema weiße Zellen.
  if cdsSelected in AState then
  begin
    ACanvas.Brush.Color := ListColor(clHighlight);
    ACanvas.Font.Color := ListColor(clHighlightText);
  end
  else
  begin
    ACanvas.Brush.Color := ListColor(FList.Color);
    if Deviates then
      ACanvas.Font.Color := ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
        ACanvas.Brush.Color))).Warn))
    else if (AIndex >= 0) and (AIndex <= High(FLines)) and FLines[AIndex].Header then
      ACanvas.Font.Color := ListColor(clGrayText)
    else
      ACanvas.Font.Color := ListColor(FList.Font.Color);
  end;
end;

procedure TAtlasBuildSwitchesFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if Item <> nil then
    RowColors(Sender.Canvas, State, Item.Index);
end;

procedure TAtlasBuildSwitchesFrame.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if Item <> nil then
    RowColors(Sender.Canvas, State, Item.Index);
end;

procedure TAtlasBuildSwitchesFrame.ListDblClick(Sender: TObject);
begin
  ExecuteSelected;
end;

procedure TAtlasBuildSwitchesFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    ExecuteSelected;
    Key := 0;
  end
  else if (Key = Ord('C')) and (Shift = [ssCtrl]) then
  begin
    CopyAll;
    Key := 0;
  end;
end;

procedure TAtlasBuildSwitchesFrame.MenuPopup(Sender: TObject);
var
  Row: TAtlasSwitchRow;
  Has: Boolean;
begin
  Has := TrySelected(Row);
  FJumpItem.Enabled := Has and Row.CanJump;
  FOptionsItem.Enabled := Has and Row.FromProject and (Row.Section <> TAtlasSwitchSection.Target);
  FCopyItem.Enabled := FHasView;
end;

procedure TAtlasBuildSwitchesFrame.JumpClick(Sender: TObject);
var
  Row: TAtlasSwitchRow;
begin
  if TrySelected(Row) and Row.CanJump and Assigned(FOnJump) then
    FOnJump(Row);
end;

procedure TAtlasBuildSwitchesFrame.OptionsClick(Sender: TObject);
begin
  if Assigned(FOnOptions) then
    FOnOptions();
end;

procedure TAtlasBuildSwitchesFrame.CopyClick(Sender: TObject);
begin
  CopyAll;
end;

end.
