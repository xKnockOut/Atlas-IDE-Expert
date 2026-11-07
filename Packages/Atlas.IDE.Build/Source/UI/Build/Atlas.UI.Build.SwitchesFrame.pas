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
  private type
    /// <summary>Steuerelemente des Frames.</summary>
    TParts = record
      Where: TLabel;
      List: TListView;
      Empty: TLabel;
      Summary: TLabel;
      Menu: TPopupMenu;
      JumpItem: TMenuItem;
      OptionsItem: TMenuItem;
      CopyItem: TMenuItem;
    end;

    /// <summary>Rückrufe an die IDE-Schicht.</summary>
    THandlers = record
      OnJump: TProc<TAtlasSwitchRow>;
      OnOptions: TProc;
      OnCopy: TProc<string>;
    end;
  private
    FParts: TParts;
    FHandlers: THandlers;
    FView: TAtlasCompilerSwitchView;
    FHasView: Boolean;
    FLines: TAtlasSwitchLines;
    FFileName: string;
    FLine: Integer;
    FMessage: string;
    procedure Refill;
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
    property WhereLabel: TLabel read FParts.Where;
    property List: TListView read FParts.List;
    property EmptyLabel: TLabel read FParts.Empty;
    property SummaryLabel: TLabel read FParts.Summary;
    property Menu: TPopupMenu read FParts.Menu;
    property ShownLines: TAtlasSwitchLines read FLines;
    property OnJump: TProc<TAtlasSwitchRow> read FHandlers.OnJump write FHandlers.OnJump;
    property OnOptions: TProc read FHandlers.OnOptions write FHandlers.OnOptions;
    property OnCopy: TProc<string> read FHandlers.OnCopy write FHandlers.OnCopy;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Build.Strings;

{$R *.dfm}

function AddColumn(AList: TListView; const ACaption: string; AWidth, APPI: Integer): TListColumn;
begin
  Result := AList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, APPI, 96);
end;

function AddMenuItem(AMenu: TPopupMenu; const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  AMenu.Items.Add(Result);
end;

function ListColor(AList: TListView; AColor: TColor): TColor;
begin
  // Stil der Liste, nicht der globale: Die IDE themt ihre Fenster je Formular.
  Result := ColorToRGB(StyleServices(AList).GetSystemColor(AColor));
end;

{ TAtlasBuildSwitchesFrame }

constructor TAtlasBuildSwitchesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FLine := -1;
  FMessage := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesEmpty);

  FParts.Where := TLabel.Create(Self);
  FParts.Where.Parent := Self;
  FParts.Where.Align := alTop;
  FParts.Where.AlignWithMargins := True;
  FParts.Where.ShowAccelChar := False;
  FParts.Where.Caption := '';

  FParts.Summary := TLabel.Create(Self);
  FParts.Summary.Parent := Self;
  FParts.Summary.Align := alBottom;
  FParts.Summary.AlignWithMargins := True;
  FParts.Summary.ShowAccelChar := False;
  FParts.Summary.WordWrap := True;
  FParts.Summary.Font.Color := clGrayText;
  FParts.Summary.Caption := '';

  FParts.Menu := TPopupMenu.Create(Self);
  FParts.Menu.OnPopup := MenuPopup;
  FParts.JumpItem := AddMenuItem(FParts.Menu, TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesGoTo),
    JumpClick);
  FParts.OptionsItem := AddMenuItem(FParts.Menu, TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesOptions),
    OptionsClick);
  FParts.CopyItem := AddMenuItem(FParts.Menu, TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesCopy),
    CopyClick);

  FParts.List := TListView.Create(Self);
  FParts.List.Parent := Self;
  FParts.List.Align := alClient;
  FParts.List.AlignWithMargins := True;
  FParts.List.ViewStyle := vsReport;
  FParts.List.RowSelect := True;
  FParts.List.HideSelection := False;
  FParts.List.ReadOnly := True;
  FParts.List.MultiSelect := False;
  FParts.List.ColumnClick := False;
  FParts.List.PopupMenu := FParts.Menu;
  AddColumn(FParts.List, TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesColumnName), 170, CurrentPPI);
  AddColumn(FParts.List, TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesColumnValue), 60, CurrentPPI);
  AddColumn(FParts.List, TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesColumnProject), 60, CurrentPPI);
  AddColumn(FParts.List, TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesColumnOrigin), 220, CurrentPPI);
  FParts.List.OnDblClick := ListDblClick;
  FParts.List.OnKeyDown := ListKeyDown;
  FParts.List.OnCustomDrawItem := ListCustomDrawItem;
  FParts.List.OnCustomDrawSubItem := ListCustomDrawSubItem;

  FParts.Empty := TLabel.Create(Self);
  FParts.Empty.Parent := Self;
  FParts.Empty.Align := alClient;
  FParts.Empty.AlignWithMargins := True;
  FParts.Empty.WordWrap := True;
  FParts.Empty.ShowAccelChar := False;
  FParts.Empty.Font.Color := clGrayText;
  FParts.Empty.Caption := FMessage;
end;

procedure TAtlasBuildSwitchesFrame.CreateWnd;
begin
  inherited CreateWnd;
  Refill;
end;

class function TAtlasBuildSwitchesFrame.Lines(const AView: TAtlasCompilerSwitchView): TAtlasSwitchLines;
var
  mSection: TAtlasSwitchSection;
  mIndex: Integer;
  mLine: TAtlasSwitchLine;
  mHasHeader: Boolean;
begin
  Result := nil;
  for mSection := Low(TAtlasSwitchSection) to High(TAtlasSwitchSection) do
  begin
    mHasHeader := False;
    for mIndex := 0 to High(AView.Rows) do
    begin
      if AView.Rows[mIndex].Section <> mSection then
      begin
        Continue;
      end;
      if not mHasHeader then
      begin
        mLine := Default(TAtlasSwitchLine);
        mLine.Header := True;
        mLine.Section := mSection;
        mLine.Row := -1;
        Result := Result + [mLine];
        mHasHeader := True;
      end;
      mLine := Default(TAtlasSwitchLine);
      mLine.Section := mSection;
      mLine.Row := mIndex;
      Result := Result + [mLine];
    end;
  end;
end;

class function TAtlasBuildSwitchesFrame.SectionText(ASection: TAtlasSwitchSection): string;
begin
  case ASection of
    TAtlasSwitchSection.Switches:
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesSectionSwitches);
    TAtlasSwitchSection.Messages:
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesSectionMessages);
    TAtlasSwitchSection.Defines:
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesSectionDefines);
  else
    Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesSectionTarget);
  end;
end;

class function TAtlasBuildSwitchesFrame.OriginText(const ARow: TAtlasSwitchRow): string;
begin
  case ARow.Kind of
    TAtlasSwitchOriginKind.Directive:
      Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.CompilerSwitchesOriginLine, [ARow.Line + 1]);
    TAtlasSwitchOriginKind.Include:
      Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.CompilerSwitchesOriginInclude,
        [ExtractFileName(ARow.FileName), ARow.Line + 1]);
    TAtlasSwitchOriginKind.Project:
      begin
        // Symbole tragen ihre Herkunft schon als Satz („Konfiguration Debug (.dproj)“).
        if ARow.Section = TAtlasSwitchSection.Target then
        begin
          Result := '';
        end
        else if (ARow.Section = TAtlasSwitchSection.Defines) and (ARow.OriginText <> '') then
        begin
          Result := ARow.OriginText;
        end
        else if ARow.OriginText <> '' then
        begin
          Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.CompilerSwitchesOriginProjectNamed, [ARow.OriginText]);
        end
        else
        begin
          Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesOriginProject);
        end;
      end;
  else
    if (ARow.Section = TAtlasSwitchSection.Defines) and (ARow.OriginText <> '') then
    begin
      Result := ARow.OriginText;
    end
    else
    begin
      Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesOriginDefault);
    end;
  end;
end;

class function TAtlasBuildSwitchesFrame.Cells(const ARow: TAtlasSwitchRow): TArray<string>;
var
  mName: string;
begin
  mName := ARow.Name;
  if ARow.Section = TAtlasSwitchSection.Target then
  begin
    if ARow.Name = 'platform' then
    begin
      mName := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesPlatform);
    end
    else
    begin
      mName := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesConfiguration);
    end;
    Result := TArray<string>.Create(mName, ARow.Value, '', '');
    Exit;
  end;
  if ARow.LongName <> '' then
  begin
    mName := mName + ' (' + ARow.LongName + ')';
  end;
  if ARow.Section = TAtlasSwitchSection.Defines then
  begin
    Result := TArray<string>.Create(mName, '', '', OriginText(ARow));
  end
  else
  begin
    Result := TArray<string>.Create(mName, TAtlasCompilerSwitchTexts.Value(ARow.Value),
      TAtlasCompilerSwitchTexts.Value(ARow.ProjectValue), OriginText(ARow));
  end;
end;

class function TAtlasBuildSwitchesFrame.AsText(const AView: TAtlasCompilerSwitchView): string;
var
  mLine: TAtlasSwitchLine;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mLine in Lines(AView) do
    begin
      if mLine.Header then
      begin
        mBuilder.Append(SectionText(mLine.Section)).Append(sLineBreak);
      end
      else
      begin
        mBuilder.Append('  ').Append(string.Join(#9, Cells(AView.Rows[mLine.Row]))).Append(sLineBreak);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
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
  begin
    FHasView := False;
  end;
  Refill;
end;

function WhereText(const AFileName: string; ALine: Integer): string;
begin
  Result := '';
  if AFileName <> '' then
  begin
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.CompilerSwitchesAt, [ExtractFileName(AFileName), ALine + 1]);
  end;
end;

/// <summary>Kurzfassung der Abweichungen, ohne Projekt mit Hinweis.</summary>
function SummaryText(const AView: TAtlasCompilerSwitchView): string;
var
  mDeviations: TAtlasSwitchRows;
  mRow: TAtlasSwitchRow;
  mNames: string;
begin
  mDeviations := AView.Deviations;
  if Length(mDeviations) = 0 then
  begin
    Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesNoDeviations);
  end
  else
  begin
    mNames := AView.Summary;
    if mNames = '' then
    begin
      for mRow in mDeviations do
      begin
        mNames := Trim(mNames + ' ' + mRow.Name);
      end;
    end;
    Result := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.CompilerSwitchesDeviations, [mNames]);
  end;
  if not AView.HasProject then
  begin
    Result := Result + sLineBreak + TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesNoProject);
  end;
end;

procedure AddLine(AList: TListView; const ALine: TAtlasSwitchLine; const AView: TAtlasCompilerSwitchView);
var
  mItem: TListItem;
  mTexts: TArray<string>;
  mPart: Integer;
begin
  mItem := AList.Items.Add;
  if ALine.Header then
  begin
    mItem.Caption := TAtlasBuildSwitchesFrame.SectionText(ALine.Section);
    Exit;
  end;
  mTexts := TAtlasBuildSwitchesFrame.Cells(AView.Rows[ALine.Row]);
  mItem.Caption := '  ' + mTexts[0];
  for mPart := 1 to High(mTexts) do
  begin
    mItem.SubItems.Add(mTexts[mPart]);
  end;
end;

/// <summary>Liste neu füllen; die Auswahl bleibt, soweit möglich.</summary>
procedure FillList(AList: TListView; const ALines: TAtlasSwitchLines; const AView: TAtlasCompilerSwitchView);
var
  mLine: TAtlasSwitchLine;
  mKeep: Integer;
begin
  mKeep := -1;
  if AList.Selected <> nil then
  begin
    mKeep := AList.Selected.Index;
  end;
  AList.Items.BeginUpdate;
  try
    AList.Items.Clear;
    for mLine in ALines do
    begin
      AddLine(AList, mLine, AView);
    end;
    if (mKeep >= 0) and (mKeep < AList.Items.Count) then
    begin
      AList.Items[mKeep].Selected := True;
    end;
  finally
    AList.Items.EndUpdate;
  end;
end;

procedure TAtlasBuildSwitchesFrame.Refill;
begin
  FParts.Empty.Caption := FMessage;
  FParts.Empty.Visible := not FHasView;
  FParts.List.Visible := FHasView;
  if not FHasView then
  begin
    FParts.Where.Caption := '';
    FParts.Summary.Caption := '';
    Exit;
  end;
  FParts.Where.Caption := WhereText(FFileName, FLine);
  FLines := Lines(FView);
  FParts.Summary.Caption := SummaryText(FView);
  // Liste erst mit Fenster füllen (TListView.Items braucht eins); CreateWnd holt es nach.
  if HandleAllocated then
  begin
    FillList(FParts.List, FLines, FView);
  end;
end;

function TAtlasBuildSwitchesFrame.TrySelected(out ARow: TAtlasSwitchRow): Boolean;
var
  mLine: TAtlasSwitchLine;
begin
  ARow := Default(TAtlasSwitchRow);
  Result := FHasView and (FParts.List.Selected <> nil) and (FParts.List.Selected.Index <= High(FLines));
  if not Result then
  begin
    Exit;
  end;
  mLine := FLines[FParts.List.Selected.Index];
  Result := not mLine.Header and (mLine.Row >= 0) and (mLine.Row <= High(FView.Rows));
  if Result then
  begin
    ARow := FView.Rows[mLine.Row];
  end;
end;

procedure TAtlasBuildSwitchesFrame.ExecuteSelected;
var
  mRow: TAtlasSwitchRow;
begin
  if not TrySelected(mRow) then
  begin
    Exit;
  end;
  if mRow.CanJump then
  begin
    if Assigned(FHandlers.OnJump) then
    begin
      FHandlers.OnJump(mRow);
    end;
  end
  else if mRow.FromProject and Assigned(FHandlers.OnOptions) then
  begin
    FHandlers.OnOptions();
  end;
end;

procedure TAtlasBuildSwitchesFrame.CopyAll;
begin
  if FHasView and Assigned(FHandlers.OnCopy) then
  begin
    FHandlers.OnCopy(AsText(FView));
  end;
end;

procedure TAtlasBuildSwitchesFrame.RowColors(ACanvas: TCanvas; AState: TCustomDrawState; AIndex: Integer);
var
  mLine: TAtlasSwitchLine;
  mDeviates: Boolean;
begin
  mDeviates := False;
  ACanvas.Font.Style := [];
  if (AIndex >= 0) and (AIndex <= High(FLines)) then
  begin
    mLine := FLines[AIndex];
    if mLine.Header then
    begin
      ACanvas.Font.Style := [fsBold];
    end
    else
    begin
      mDeviates := FView.Rows[mLine.Row].Deviates;
      if mDeviates then
      begin
        ACanvas.Font.Style := [fsBold];
      end;
    end;
  end;
  // Farben ausdrücklich aus dem Stil der Liste, sonst im dunklen Thema weiße Zellen.
  if cdsSelected in AState then
  begin
    ACanvas.Brush.Color := ListColor(FParts.List, clHighlight);
    ACanvas.Font.Color := ListColor(FParts.List, clHighlightText);
  end
  else
  begin
    ACanvas.Brush.Color := ListColor(FParts.List, FParts.List.Color);
    if mDeviates then
    begin
      ACanvas.Font.Color := ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
        ACanvas.Brush.Color))).Warn));
    end
    else if (AIndex >= 0) and (AIndex <= High(FLines)) and FLines[AIndex].Header then
    begin
      ACanvas.Font.Color := ListColor(FParts.List, clGrayText);
    end
    else
    begin
      ACanvas.Font.Color := ListColor(FParts.List, FParts.List.Font.Color);
    end;
  end;
end;

procedure TAtlasBuildSwitchesFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if Item <> nil then
  begin
    RowColors(Sender.Canvas, State, Item.Index);
  end;
end;

procedure TAtlasBuildSwitchesFrame.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if Item <> nil then
  begin
    RowColors(Sender.Canvas, State, Item.Index);
  end;
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
  mRow: TAtlasSwitchRow;
  mHas: Boolean;
begin
  mHas := TrySelected(mRow);
  FParts.JumpItem.Enabled := mHas and mRow.CanJump;
  FParts.OptionsItem.Enabled := mHas and mRow.FromProject and (mRow.Section <> TAtlasSwitchSection.Target);
  FParts.CopyItem.Enabled := FHasView;
end;

procedure TAtlasBuildSwitchesFrame.JumpClick(Sender: TObject);
var
  mRow: TAtlasSwitchRow;
begin
  if TrySelected(mRow) and mRow.CanJump and Assigned(FHandlers.OnJump) then
  begin
    FHandlers.OnJump(mRow);
  end;
end;

procedure TAtlasBuildSwitchesFrame.OptionsClick(Sender: TObject);
begin
  if Assigned(FHandlers.OnOptions) then
  begin
    FHandlers.OnOptions();
  end;
end;

procedure TAtlasBuildSwitchesFrame.CopyClick(Sender: TObject);
begin
  CopyAll;
end;

end.
