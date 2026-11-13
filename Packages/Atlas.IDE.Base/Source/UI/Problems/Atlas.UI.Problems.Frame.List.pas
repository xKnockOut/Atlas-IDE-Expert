unit Atlas.UI.Problems.Frame.List;

// Grundlage des Fensters „Atlas-Prüfung“ (#909) ohne Leiste und Kontextmenü: Ereignisse, Steuerelemente und
// ihre Texte, dazu die virtuelle Liste mit Spalten (Reihenfolge, Breite, Sichtbarkeit für
// problems.window.columns), Zellen, Gruppen- und Trennzeilen und dem Zeichnen offener und nicht geöffneter
// Units (#1108). Aufbau, Leiste, Tasten und Menü stehen in Atlas.UI.Problems.Frame.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.ImgList,
  Vcl.Forms,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.FindingsView,
  Atlas.UI.Problems.ScopeBox;

type
  TAtlasFindingEvent = reference to procedure(const AFinding: TAtlasFinding);
  TAtlasFindingScopeEvent = reference to procedure(AScope: TAtlasFindingScope);
  /// <summary>Mehrere markierte Befunde (#1268: ein Issue mit Liste).</summary>
  TAtlasFindingsEvent = reference to procedure(const AFindings: TArray<TAtlasFinding>);

  /// <summary>Ereignisse des Fensters „Atlas-Prüfung“ (#909); Grundlage von TAtlasProblemsFrame.</summary>
  TAtlasProblemsFrameEvents = class(TFrame)
  protected
    FOnOpen: TAtlasFindingEvent;
    FOnFix: TAtlasFindingEvent;
    FOnFixAll: TAtlasFindingEvent;
    FCanFixAll: TFunc<Boolean>;
    FOnSuppress: TAtlasFindingEvent;
    FCanRuleActions: TFunc<Boolean>;
    FOnConfigure: TAtlasFindingEvent;
    FOnDisable: TAtlasFindingEvent;
    FOnExplain: TAtlasFindingEvent;
    FOnCreateIssue: TAtlasFindingsEvent;
    FCanCreateIssue: TFunc<Boolean>;
    FOnScope: TAtlasFindingScopeEvent;
    FOnLayout: TProc;
  public
    property OnOpen: TAtlasFindingEvent read FOnOpen write FOnOpen;
    property OnFix: TAtlasFindingEvent read FOnFix write FOnFix;
    /// <summary>„Alle sicheren Treffer von … korrigieren …“ (#1352) mit dem Befund unter dem Cursor.</summary>
    property OnFixAll: TAtlasFindingEvent read FOnFixAll write FOnFixAll;
    /// <summary>Eintrag sichtbar (fix.bulk); nil = unsichtbar.</summary>
    property CanFixAll: TFunc<Boolean> read FCanFixAll write FCanFixAll;
    property OnSuppress: TAtlasFindingEvent read FOnSuppress write FOnSuppress;
    /// <summary>„Für diese Zeile unterdrücken“, „Regel einstellen…“ und „Regel abschalten“ sichtbar (Modul
    /// Prüfregeln läuft, #1755); nil = unsichtbar.</summary>
    property CanRuleActions: TFunc<Boolean> read FCanRuleActions write FCanRuleActions;
    property OnConfigure: TAtlasFindingEvent read FOnConfigure write FOnConfigure;
    property OnDisable: TAtlasFindingEvent read FOnDisable write FOnDisable;
    property OnExplain: TAtlasFindingEvent read FOnExplain write FOnExplain;
    /// <summary>„Für diesen Befund ein Issue anlegen …“ (#1268) mit den markierten Befunden.</summary>
    property OnCreateIssue: TAtlasFindingsEvent read FOnCreateIssue write FOnCreateIssue;
    /// <summary>Eintrag sichtbar (issues.create); nil = unsichtbar.</summary>
    property CanCreateIssue: TFunc<Boolean> read FCanCreateIssue write FCanCreateIssue;
    /// <summary>Bereich gewechselt: Die IDE-Schicht liefert die Dateien des Bereichs neu.</summary>
    property OnScope: TAtlasFindingScopeEvent read FOnScope write FOnScope;
    /// <summary>Bereich, Gruppierung, Spalten oder „Offene zuerst“ geändert: zum Speichern.</summary>
    property OnLayout: TProc read FOnLayout write FOnLayout;
  end;

  /// <summary>Steuerelemente des Fensters und ihre Texte.</summary>
  TAtlasProblemsFrameParts = class(TAtlasProblemsFrameEvents)
  public const
    /// <summary>Nadel der aktiven Unit (#1108).</summary>
    cPinMark = #$D83D#$DCCC;
  protected
    FView: TAtlasFindingsView;
    FBar: TFlowPanel;
    FScope: TComboBox;
    /// <summary>Einträge und Wahl der Bereichsliste samt Einzelprojekten (#1843).</summary>
    FScopeBox: TAtlasProblemsScopeBox;
    FKinds: array[TAtlasFindingKind] of TSpeedButton;
    FCategory: TComboBox;
    FGrouping: TComboBox;
    FOpenFirst: TSpeedButton;
    FFilter: TEdit;
    /// <summary>Filter „Quelle“ (#1819); nur mit ShowIdeErrors sichtbar.</summary>
    FOrigin: TComboBox;
    FLive: TLabel;
    FList: TListView;
    FEmpty: TLabel;
    FStatus: TLabel;
    FImages: TImageList;
    FMenu: TPopupMenu;
    FNewTimer: TTimer;
    /// <summary>Einträge der Auswahllisten; gefüllt erst mit Fenster (CreateWnd).</summary>
    FCategoryTexts: TArray<string>;
    FGroupingTexts: TArray<string>;
    FOriginTexts: TArray<string>;
    function AddMenuItem(AParent: TMenuItem; const ACaption: string; AClick: TNotifyEvent): TMenuItem;
    function AddCombo(AWidth: Integer): TComboBox;
    class procedure FillCombo(ACombo: TComboBox; const ATexts: TArray<string>; AIndex: Integer); static;
    /// <summary>Fläche und Text der Liste nach dem IDE-Thema.</summary>
    function ListBack: TColor;
    function ListText: TColor;
  public
    /// <summary>Umschalter der Art AKind („Warnung 3“).</summary>
    function KindButton(AKind: TAtlasFindingKind): TSpeedButton;
    class function KindText(AKind: TAtlasFindingKind): string; static;
    class function CategoryText(ACategory: TAtlasFindingCategory): string; static;
    property View: TAtlasFindingsView read FView;
    property List: TListView read FList;
    property ScopeBox: TComboBox read FScope;
    property CategoryBox: TComboBox read FCategory;
    property GroupingBox: TComboBox read FGrouping;
    property OpenFirstButton: TSpeedButton read FOpenFirst;
    property FilterEdit: TEdit read FFilter;
    property OriginBox: TComboBox read FOrigin;
    property LiveLabel: TLabel read FLive;
    property StatusLabel: TLabel read FStatus;
    property EmptyLabel: TLabel read FEmpty;
    property Menu: TPopupMenu read FMenu;
  end;

  /// <summary>Spalten, Zellen und Zeichnen der virtuellen Liste.</summary>
  TAtlasProblemsFrameList = class(TAtlasProblemsFrameParts)
  protected
    FColumnsItem: TMenuItem;
    /// <summary>Alle Spalten in Anzeigereihenfolge mit Breite und Sichtbarkeit.</summary>
    FColumns: TArray<TAtlasFindingColumnState>;
    /// <summary>Spalte der Liste (Index) → Spalte des Modells; Index 0 ist immer das Icon.</summary>
    FShown: TArray<TAtlasFindingColumn>;
    /// <summary>Reihenfolge des Spaltenkopfs noch nicht gesetzt (Liste ohne Fenster).</summary>
    FOrderPending: Boolean;
    /// <summary>Fenster der Liste, für das die Reihenfolge gesetzt ist; Andocken legt es neu an.</summary>
    FOrderHandle: HWND;
    FUpdating: Boolean;
    FShowCompilerCode: Boolean;
    FShowIdeErrors: Boolean;
    /// <summary>Fläche, für die die ausgegrauten Symbole gebaut sind.</summary>
    FImagesBack: TColor;
    procedure BuildImages;
    /// <summary>Text einer Trennzeile bzw. der Zeile „Keine Befunde“ (#1108).</summary>
    function SectionText(const ARow: TAtlasFindingRow): string;
    procedure DrawSection(ACanvas: TCanvas; AItem: TListItem; const ARow: TAtlasFindingRow);
    procedure BuildColumns;
    procedure SetShowCompilerCode(AValue: Boolean);
    procedure SetShowIdeErrors(AValue: Boolean);
    /// <summary>Spalte gerade ausgeschaltet: Compiler ohne ShowCompilerCode, Quelle ohne ShowIdeErrors.</summary>
    function ColumnSuppressed(AColumn: TAtlasFindingColumn): Boolean;
    /// <summary>Anzeigereihenfolge und Breiten der Liste nach FColumns übernehmen.</summary>
    procedure ReadColumns;
    /// <summary>Hebt die Markierung der virtuellen Liste mit einer Nachricht auf. TCustomListView.ClearSelection
    /// holt jede Zeile einzeln über OnData und hängt bei vielen Befunden die IDE auf.</summary>
    procedure ClearListSelection;
    procedure ApplyOrder;
    function ColumnCaption(AColumn: TAtlasFindingColumn): string;
    function CellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
    /// <summary>Text der Spalte AColumn für den Befund der Zeile ARow.</summary>
    function FindingCellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
    /// <summary>Erste sichtbare Textspalte in Anzeigereihenfolge: dort steht der Name einer Gruppe.</summary>
    function GroupColumn: TAtlasFindingColumn;
    procedure UpdateKindCaptions;
    function RowAt(AIndex: Integer; out ARow: TAtlasFindingRow): Boolean;
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListInfoTip(Sender: TObject; Item: TListItem; var InfoTip: string);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ColumnToggleClick(Sender: TObject);
  public
    /// <summary>Liste neu zeichnen, Auswahl und Bildlauf bleiben.</summary>
    procedure Refill;
    /// <summary>Umschaltknopf „Offene zuerst“ gedrückt.</summary>
    function OpenFirst: Boolean;
    /// <summary>Spalten für problems.window.columns.</summary>
    function ColumnsText: string;
    function Scope: TAtlasFindingScope;
    /// <summary>Einzelprojekt bei Bereich „Projekt“ (#1843); '' = aktives Projekt.</summary>
    function ScopeProject: string;
    function Grouping: TAtlasFindingGrouping;
    /// <summary>Compilercodes zeigen (problems.showCompilerCode, #1024; Vorgabe an).</summary>
    property ShowCompilerCode: Boolean read FShowCompilerCode write SetShowCompilerCode;
    /// <summary>Fehler der IDE abgefragt (problems.ideErrors, #1819; Vorgabe aus): Spalte und Filter „Quelle“.
    /// </summary>
    property ShowIdeErrors: Boolean read FShowIdeErrors write SetShowIdeErrors;
  end;

implementation

uses
  System.Math,
  Winapi.CommCtrl,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Problems.Colors,
  Atlas.UI.Strings,
  Atlas.UI.Problems.Strings,
  Atlas.UI.Problems.KindIcon;

const
  /// <summary>Vorgabebreiten bei 96 dpi.</summary>
  cDefaultWidths: array[TAtlasFindingColumn] of Integer = (24, 70, 110, 320, 260, 130, 150, 130, 90);
  /// <summary>Symbole der Arten; dahinter dieselben ausgegraut (#1108).</summary>
  cDimmedImageOffset = 3;
  cCheckMark = #$2713;
  /// <summary>Abstand der Auswahllisten in der Leiste oben und links bei 96 dpi.</summary>
  cComboTop = 3;
  cComboLeft = 4;
  /// <summary>Trennzeilen: Linie aus Text- und Flächenfarbe, Einzug des Textes bei 96 dpi, grüner Haken bei
  /// „Keine Befunde“.</summary>
  cSectionLineMix = 0.2;
  cSectionIndent = 6;
  cCleanColor = TColor($0050A030);

class procedure TAtlasProblemsFrameParts.FillCombo(ACombo: TComboBox; const ATexts: TArray<string>; AIndex: Integer);
var
  mText: string;
begin
  if ACombo.Items.Count = 0 then
  begin
    ACombo.Items.BeginUpdate;
    try
      for mText in ATexts do
      begin
        ACombo.Items.Add(mText);
      end;
    finally
      ACombo.Items.EndUpdate;
    end;
  end;
  if ACombo.ItemIndex < 0 then
  begin
    ACombo.ItemIndex := AIndex;
  end;
end;

function TAtlasProblemsFrameParts.AddMenuItem(AParent: TMenuItem; const ACaption: string;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  if AParent = nil then
  begin
    FMenu.Items.Add(Result);
  end
  else
  begin
    AParent.Add(Result);
  end;
end;

function TAtlasProblemsFrameParts.AddCombo(AWidth: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := FBar;
  Result.AlignWithMargins := True;
  Result.Style := csDropDownList;
  Result.Top := MulDiv(cComboTop, CurrentPPI, 96);
  Result.Left := MulDiv(cComboLeft, CurrentPPI, 96);
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

function TAtlasProblemsFrameParts.ListBack: TColor;
begin
  // Stil der Liste, nicht der globale: Die IDE themt ihre Fenster je Formular; global käme im dunklen Thema Weiß.
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(FList.Color));
end;

function TAtlasProblemsFrameParts.ListText: TColor;
begin
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(FList.Font.Color));
end;

procedure TAtlasProblemsFrameList.BuildImages;
var
  mKind: TAtlasFindingKind;
  mBitmap: TBitmap;
  mSize, mPass: Integer;
  mSignals: TAtlasSignals;
  mSignal: TAtlasSignal;
begin
  // Zuerst die drei Arten, dahinter dieselben Formen ausgegraut für nicht geöffnete Units (#1108): aufgehellt bzw.
  // abgedunkelt zur Fläche der Liste, damit Fehler weiter von Warnungen unterscheidbar bleiben.
  FImagesBack := ListBack;
  FImages.Clear;
  mSize := FImages.Width;
  // Signalfarben der Liste (#1255): hell kräftig mit dunklem Rand, dunkel hell mit dunklem Zeichen.
  mSignals := TAtlasColors.ForBackground(TAtlasColor(FImagesBack)).Signals;
  for mPass := 0 to 1 do
  begin
    for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
    begin
      mSignal := mSignals.Get(TAtlasFindingIcon.SignalOf(mKind));
      if mPass = 1 then
      begin
        mSignal.Fill := DimmedIconColor(mSignal.Fill, TAtlasColor(FImagesBack));
        mSignal.Ring := DimmedIconColor(mSignal.Ring, TAtlasColor(FImagesBack));
        mSignal.Mark := DimmedIconColor(mSignal.Mark, TAtlasColor(FImagesBack));
      end;
      mBitmap := TBitmap.Create;
      try
        mBitmap.SetSize(mSize, mSize);
        mBitmap.Canvas.Brush.Color := clFuchsia;
        mBitmap.Canvas.FillRect(Rect(0, 0, mSize, mSize));
        TAtlasFindingIcon.Draw(mBitmap.Canvas, Rect(0, 0, mSize, mSize), mKind, mSignal);
        FImages.AddMasked(mBitmap, clFuchsia);
      finally
        mBitmap.Free;
      end;
    end;
  end;
end;

function TAtlasProblemsFrameList.ColumnCaption(AColumn: TAtlasFindingColumn): string;
begin
  case AColumn of
    TAtlasFindingColumn.Kind:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnKind);
    TAtlasFindingColumn.Category:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnCategory);
    TAtlasFindingColumn.Message:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnMessage);
    TAtlasFindingColumn.Line:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnLine);
    TAtlasFindingColumn.Location:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnLocation);
    TAtlasFindingColumn.Rule:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnRule);
    TAtlasFindingColumn.Compiler:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnCompiler);
    TAtlasFindingColumn.Source:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnSource);
  else
    Result := '';
  end;
end;

class function TAtlasProblemsFrameParts.KindText(AKind: TAtlasFindingKind): string;
begin
  case AKind of
    TAtlasFindingKind.Error:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsKindError);
    TAtlasFindingKind.Warning:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsKindWarning);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.ProblemsKindInfo);
  end;
end;

class function TAtlasProblemsFrameParts.CategoryText(ACategory: TAtlasFindingCategory): string;
begin
  case ACategory of
    TAtlasFindingCategory.Bug:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryBug);
    TAtlasFindingCategory.Vulnerability:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryVulnerability);
    TAtlasFindingCategory.CodeSmell:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryCodeSmell);
    TAtlasFindingCategory.SecurityHotspot:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryHotspot);
    TAtlasFindingCategory.Compiler:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryCompiler);
  else
    Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryOther);
  end;
end;

/// <summary>Breite der Spalte AColumn bei 96 dpi: gespeichert oder Vorgabe.</summary>
function ColumnWidth(const AColumns: TArray<TAtlasFindingColumnState>; AColumn: TAtlasFindingColumn): Integer;
var
  mState: TAtlasFindingColumnState;
begin
  Result := cDefaultWidths[AColumn];
  for mState in AColumns do
  begin
    if (mState.Column = AColumn) and (mState.Width > 0) then
    begin
      Result := mState.Width;
    end;
  end;
end;

procedure TAtlasProblemsFrameList.BuildColumns;
var
  mState: TAtlasFindingColumnState;
  mColumn: TListColumn;
  mIndex, mPosition: Integer;
  mItem: TMenuItem;
begin
  // Das Icon ist immer Spalte 0 (SmallImages zeichnet nur dort); die Reihenfolge der Anzeige setzt die
  // Spaltenreihenfolge des Kopfs.
  FShown := [TAtlasFindingColumn.Icon];
  for mState in FColumns do
  begin
    if mState.Visible and (mState.Column <> TAtlasFindingColumn.Icon) and not ColumnSuppressed(mState.Column) then
    begin
      FShown := FShown + [mState.Column];
    end;
  end;
  FList.Columns.BeginUpdate;
  try
    FList.Columns.Clear;
    for mIndex := 0 to High(FShown) do
    begin
      mColumn := FList.Columns.Add;
      mColumn.Caption := ColumnCaption(FShown[mIndex]);
      mColumn.Width := MulDiv(ColumnWidth(FColumns, FShown[mIndex]), CurrentPPI, 96);
    end;
  finally
    FList.Columns.EndUpdate;
  end;
  FOrderPending := True;
  ApplyOrder;
  // Menü „Spalten“: nur die abwählbaren.
  FColumnsItem.Clear;
  for mPosition := 0 to High(FColumns) do
  begin
    if not TAtlasFindings.IsMandatory(FColumns[mPosition].Column) and
      not ColumnSuppressed(FColumns[mPosition].Column) then
    begin
      mItem := AddMenuItem(FColumnsItem, ColumnCaption(FColumns[mPosition].Column), ColumnToggleClick);
      mItem.Checked := FColumns[mPosition].Visible;
      mItem.Tag := Ord(FColumns[mPosition].Column);
    end;
  end;
  FList.Invalidate;
end;

procedure TAtlasProblemsFrameList.ApplyOrder;
var
  mOrder: TArray<Integer>;
  mState: TAtlasFindingColumnState;
  mIndex: Integer;
begin
  if not FList.HandleAllocated or (not FOrderPending and (FList.Handle = FOrderHandle)) then
  begin
    Exit;
  end;
  FOrderPending := False;
  FOrderHandle := FList.Handle;
  mOrder := nil;
  for mState in FColumns do
  begin
    for mIndex := 0 to High(FShown) do
    begin
      if FShown[mIndex] = mState.Column then
      begin
        mOrder := mOrder + [mIndex];
      end;
    end;
  end;
  if Length(mOrder) = Length(FShown) then
  begin
    ListView_SetColumnOrderArray(FList.Handle, Length(mOrder), PInteger(@mOrder[0]));
  end;
end;

procedure TAtlasProblemsFrameList.ReadColumns;
var
  mOrder: TArray<Integer>;
  mNext: TArray<TAtlasFindingColumnState>;
  mState: TAtlasFindingColumnState;
  mIndex: Integer;
  mSeen: Boolean;
begin
  // Noch nicht gesetzt oder Fenster neu: FColumns ist der Stand.
  if FOrderPending or not FList.HandleAllocated or (FList.Handle <> FOrderHandle) or
    (FList.Columns.Count <> Length(FShown)) then
  begin
    Exit;
  end;
  SetLength(mOrder, Length(FShown));
  if not ListView_GetColumnOrderArray(FList.Handle, Length(mOrder), PInteger(@mOrder[0])) then
  begin
    Exit;
  end;
  mNext := nil;
  for mIndex in mOrder do
  begin
    if (mIndex >= 0) and (mIndex <= High(FShown)) then
    begin
      mNext := mNext + [TAtlasFindingColumnState.Create(FShown[mIndex],
        MulDiv(FList.Columns[mIndex].Width, 96, CurrentPPI), True)];
    end;
  end;
  // Ausgeblendete behalten ihren Platz hinten mit ihrer Breite.
  for mState in FColumns do
  begin
    mSeen := False;
    for mIndex := 0 to High(mNext) do
    begin
      if mNext[mIndex].Column = mState.Column then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      mNext := mNext + [mState];
    end;
  end;
  FColumns := mNext;
end;

function TAtlasProblemsFrameList.ColumnsText: string;
begin
  ReadColumns;
  Result := TAtlasFindings.FormatColumns(FColumns);
end;

procedure TAtlasProblemsFrameList.SetShowCompilerCode(AValue: Boolean);
begin
  if FShowCompilerCode = AValue then
  begin
    Exit;
  end;
  ReadColumns;
  FShowCompilerCode := AValue;
  BuildColumns;
  Refill;
end;

procedure TAtlasProblemsFrameList.SetShowIdeErrors(AValue: Boolean);
var
  mFilter: TAtlasFindingFilter;
begin
  if FShowIdeErrors = AValue then
  begin
    Exit;
  end;
  ReadColumns;
  FShowIdeErrors := AValue;
  FOrigin.Visible := AValue;
  // Ausgeschaltet: wieder alle Befunde, der Filter steht beim nächsten Einschalten auf „Atlas und IDE“.
  if not AValue then
  begin
    if FOrigin.Items.Count > 0 then
    begin
      FOrigin.ItemIndex := 0;
    end;
    mFilter := FView.Filter;
    mFilter.Origin := TAtlasFindingOrigin.All;
    FView.Filter := mFilter;
  end;
  BuildColumns;
  Refill;
end;

function TAtlasProblemsFrameList.ColumnSuppressed(AColumn: TAtlasFindingColumn): Boolean;
begin
  Result := ((AColumn = TAtlasFindingColumn.Compiler) and not FShowCompilerCode) or
    ((AColumn = TAtlasFindingColumn.Source) and not FShowIdeErrors);
end;

function TAtlasProblemsFrameList.OpenFirst: Boolean;
begin
  Result := FOpenFirst.Down;
end;

function TAtlasProblemsFrameList.Scope: TAtlasFindingScope;
begin
  Result := FView.Filter.Scope;
end;

function TAtlasProblemsFrameList.ScopeProject: string;
begin
  Result := FScopeBox.Choice.Project;
end;

function TAtlasProblemsFrameList.Grouping: TAtlasFindingGrouping;
begin
  Result := FView.Grouping;
end;

procedure TAtlasProblemsFrameList.UpdateKindCaptions;
var
  mCounts: TAtlasFindingCounts;
  mKind: TAtlasFindingKind;
begin
  mCounts := FView.Counts;
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    FKinds[mKind].Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsKindCount, [KindText(mKind),
      mCounts.OfKind(mKind)]);
  end;
end;

procedure TAtlasProblemsFrameList.ClearListSelection;
begin
  if FList.HandleAllocated then
  begin
    ListView_SetItemState(FList.Handle, -1, 0, LVIS_SELECTED);
  end;
end;

procedure TAtlasProblemsFrameList.Refill;
var
  mSelected: Integer;
  mCount: Integer;
begin
  // Gezogene Spalten merken, bevor ein neues Fenster der Liste (Andocken) sie vergisst; dann wieder setzen.
  ReadColumns;
  // Thema gewechselt: ausgegraute Symbole zur neuen Fläche (#1108).
  if ListBack <> FImagesBack then
  begin
    BuildImages;
  end;
  ApplyOrder;
  FUpdating := True;
  try
    mCount := Length(FView.Rows);
    // Virtuelle Liste: nur die Anzahl ändert sich; Bildlauf bleibt.
    if FList.Items.Count <> mCount then
    begin
      FList.Items.Count := mCount;
    end;
    mSelected := FView.SelectedRow;
    if mSelected <> FList.ItemIndex then
    begin
      ClearListSelection;
      if mSelected >= 0 then
      begin
        FList.ItemIndex := mSelected;
        if FList.Items[mSelected] <> nil then
        begin
          FList.Items[mSelected].Focused := True;
        end;
      end;
    end;
    FList.Invalidate;
  finally
    FUpdating := False;
  end;
  UpdateKindCaptions;
  FEmpty.Visible := mCount = 0;
  FList.Visible := not FEmpty.Visible;
end;

function TAtlasProblemsFrameList.GroupColumn: TAtlasFindingColumn;
var
  mState: TAtlasFindingColumnState;
begin
  Result := TAtlasFindingColumn.Kind;
  for mState in FColumns do
  begin
    if mState.Visible and (mState.Column <> TAtlasFindingColumn.Icon) then
    begin
      Exit(mState.Column);
    end;
  end;
end;

/// <summary>Name einer Gruppe mit Pfeil, Nadel, Zahl und Kennzeichen der Stufe (#1108).</summary>
function GroupCaption(const ARow: TAtlasFindingRow): string;
begin
  if ARow.Expanded then
  begin
    Result := #$25BE' ';
  end
  else
  begin
    Result := #$25B8' ';
  end;
  if ARow.Pinned then
  begin
    Result := Result + TAtlasProblemsFrameParts.cPinMark + ' ';
  end;
  Result := Result + ARow.Caption + ' (' + IntToStr(ARow.Count) + ')';
  if ARow.Pinned then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsTagActive);
  end
  else if ARow.Dimmed then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsTagClosed);
  end;
end;

function TAtlasProblemsFrameList.FindingCellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
var
  mFinding: TAtlasFinding;
begin
  mFinding := FView.Finding(ARow.Finding);
  case AColumn of
    TAtlasFindingColumn.Kind:
      Result := KindText(mFinding.Kind);
    TAtlasFindingColumn.Category:
      Result := CategoryText(mFinding.Category);
    TAtlasFindingColumn.Message:
      Result := mFinding.MessageText(FShowCompilerCode);
    TAtlasFindingColumn.Line:
      Result := mFinding.ShortLine(TAtlasFindings.cLineMax);
    TAtlasFindingColumn.Location:
      Result := mFinding.Location;
    TAtlasFindingColumn.Rule:
      Result := mFinding.Rule;
    TAtlasFindingColumn.Compiler:
      Result := mFinding.CompilerText;
    TAtlasFindingColumn.Source:
      Result := mFinding.SourceText;
  else
    // Symbol: kein Text.
    Result := '';
  end;
end;

function TAtlasProblemsFrameList.CellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
begin
  Result := '';
  if not ARow.IsSection and not ARow.IsGroup then
  begin
    Result := FindingCellText(ARow, AColumn);
  end
  else if AColumn <> GroupColumn then
  begin
    // Gruppen- und Trennzeilen haben Text nur in der Gruppenspalte.
    Exit;
  end
  else if ARow.IsSection then
  begin
    // Gezeichnet über die ganze Zeile (DrawSection); der Text steht für Bildschirmleser in der Gruppenspalte.
    Result := SectionText(ARow);
  end
  else
  begin
    Result := GroupCaption(ARow);
  end;
end;

function TAtlasProblemsFrameList.SectionText(const ARow: TAtlasFindingRow): string;
begin
  if ARow.IsCleanActive then
  begin
    if ARow.Checking then
    begin
      Result := cPinMark + ' ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsCheckingActive, [ARow.Caption]);
    end
    else
    begin
      Result := cPinMark + ' ' + cCheckMark + ' ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsCleanActive,
        [ARow.Caption]);
    end;
    Exit;
  end;
  case ARow.Tier of
    TAtlasFindingTier.Active:
      Result := cPinMark + ' ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsSectionActive, [ARow.Caption]);
    TAtlasFindingTier.Open:
      Result := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsSectionOpen, [ARow.Units, ARow.Count]);
  else
    Result := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsSectionClosed, [ARow.Units, ARow.Count]);
  end;
end;

procedure TAtlasProblemsFrameList.DrawSection(ACanvas: TCanvas; AItem: TListItem; const ARow: TAtlasFindingRow);
var
  mBounds: TRect;
  mText: string;
  mBack: TColor;
begin
  // Trennzeile über die ganze Breite: Linie oben, Text klein und fett in Sekundärfarbe; die aktive Unit ohne
  // Befunde wie eine angepinnte Gruppe, „Keine Befunde“ mit grünem Haken.
  mBounds := AItem.DisplayRect(drBounds);
  mBack := ListBack;
  if ARow.Pinned then
  begin
    mBack := TColor(PinnedBackColor(TAtlasColor(mBack)));
  end;
  ACanvas.Brush.Color := mBack;
  ACanvas.FillRect(mBounds);
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(TAtlasColor(ListText), TAtlasColor(ListBack), cSectionLineMix));
  ACanvas.MoveTo(mBounds.Left, mBounds.Top);
  ACanvas.LineTo(mBounds.Right, mBounds.Top);
  ACanvas.Font.Style := [fsBold];
  if ARow.IsCleanActive and not ARow.Checking then
  begin
    ACanvas.Font.Color := cCleanColor;
  end
  else
  begin
    ACanvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(mBack)));
  end;
  mText := SectionText(ARow);
  Inc(mBounds.Left, MulDiv(cSectionIndent, CurrentPPI, 96));
  ACanvas.Brush.Style := bsClear;
  DrawText(ACanvas.Handle, PChar(mText), Length(mText), mBounds, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or
    DT_NOPREFIX);
  ACanvas.Brush.Style := bsSolid;
end;

function TAtlasProblemsFrameList.RowAt(AIndex: Integer; out ARow: TAtlasFindingRow): Boolean;
var
  mRows: TArray<TAtlasFindingRow>;
begin
  mRows := FView.Rows;
  Result := (AIndex >= 0) and (AIndex <= High(mRows));
  if Result then
  begin
    ARow := mRows[AIndex];
  end
  else
  begin
    ARow := Default(TAtlasFindingRow);
  end;
end;

procedure TAtlasProblemsFrameList.ListData(Sender: TObject; Item: TListItem);
var
  mRow: TAtlasFindingRow;
  mIndex: Integer;
begin
  if not RowAt(Item.Index, mRow) then
  begin
    Exit;
  end;
  Item.ImageIndex := -1;
  if not mRow.IsGroup and not mRow.IsSection then
  begin
    Item.ImageIndex := Ord(FView.Finding(mRow.Finding).Kind);
    if mRow.Dimmed then
    begin
      Item.ImageIndex := Item.ImageIndex + cDimmedImageOffset;
    end;
  end;
  Item.Caption := '';
  Item.SubItems.Clear;
  for mIndex := 1 to High(FShown) do
  begin
    Item.SubItems.Add(CellText(mRow, FShown[mIndex]));
  end;
end;

procedure TAtlasProblemsFrameList.ListInfoTip(Sender: TObject; Item: TListItem; var InfoTip: string);
var
  mRow: TAtlasFindingRow;
  mFinding: TAtlasFinding;
begin
  InfoTip := '';
  if (Item = nil) or not RowAt(Item.Index, mRow) or mRow.IsGroup or mRow.IsSection then
  begin
    Exit;
  end;
  // Ganze Zeile und ganze Meldung.
  mFinding := FView.Finding(mRow.Finding);
  InfoTip := mFinding.MessageText(FShowCompilerCode);
  if mFinding.Problem.Confirmed then
  begin
    InfoTip := InfoTip + sLineBreak + TAtlasStrings.CompilerConfirmed(mFinding.Problem.ConfirmedCode,
      FShowCompilerCode);
  end;
  if mFinding.LineText <> '' then
  begin
    InfoTip := InfoTip + sLineBreak + mFinding.LineText;
  end;
end;

procedure TAtlasProblemsFrameList.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mRow: TAtlasFindingRow;
begin
  DefaultDraw := True;
  if (Item = nil) or not RowAt(Item.Index, mRow) then
  begin
    Exit;
  end;
  if mRow.IsSection then
  begin
    DrawSection(Sender.Canvas, Item, mRow);
    DefaultDraw := False;
    Exit;
  end;
  if mRow.IsGroup then
  begin
    Sender.Canvas.Font.Style := [fsBold];
  end
  else
  begin
    Sender.Canvas.Font.Style := [];
  end;
  // Farben ausdrücklich aus dem Stil der Liste: Nach einer geänderten Schrift (fett bei Gruppen) zeichnet die
  // Liste sonst mit den Systemfarben, im dunklen Thema also weiße Zellen. Ausgewählt laut Item.Selected
  // (LVM_GETITEMSTATE): Mit cdsSelected war in der IDE jede Zeile blau, auch die nicht gewählten.
  if Item.Selected then
  begin
    Sender.Canvas.Brush.Color := ColorToRGB(StyleServices(FList).GetSystemColor(clHighlight));
    Sender.Canvas.Font.Color := ColorToRGB(StyleServices(FList).GetSystemColor(clHighlightText));
  end
  else
  begin
    Sender.Canvas.Brush.Color := ListBack;
    Sender.Canvas.Font.Color := ListText;
    // Offene Units zuerst (#1108): aktive Unit hinterlegt, nicht geöffnete ausgegraut.
    if mRow.Pinned then
    begin
      Sender.Canvas.Brush.Color := TColor(PinnedBackColor(TAtlasColor(ListBack)));
    end;
    if mRow.Dimmed then
    begin
      Sender.Canvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(ListBack)));
    end;
    // Neu dazugekommen: kurz hinterlegt.
    if mRow.IsNew then
    begin
      Sender.Canvas.Brush.Color := TColor(NewBackColor(TAtlasColor(ListBack)));
    end;
  end;
end;

function TAtlasProblemsFrameParts.KindButton(AKind: TAtlasFindingKind): TSpeedButton;
begin
  Result := FKinds[AKind];
end;

procedure TAtlasProblemsFrameList.ColumnToggleClick(Sender: TObject);
var
  mColumn: TAtlasFindingColumn;
  mIndex: Integer;
begin
  ReadColumns;
  mColumn := TAtlasFindingColumn(TMenuItem(Sender).Tag);
  for mIndex := 0 to High(FColumns) do
  begin
    if FColumns[mIndex].Column = mColumn then
    begin
      FColumns[mIndex].Visible := not FColumns[mIndex].Visible;
    end;
  end;
  BuildColumns;
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

end.
