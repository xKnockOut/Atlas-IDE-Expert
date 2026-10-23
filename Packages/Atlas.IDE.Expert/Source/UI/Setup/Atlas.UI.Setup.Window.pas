unit Atlas.UI.Setup.Window;

// Fenster „Atlas-Einrichtung“ (#625, Mockup Runde 25 Z2), reine VCL: oben
// Titel und „5 von 6 erledigt“, darunter je Prüfung ein farbiger Punkt
// (grün, gelb, rot), der Text, gedämpft die Einzelheit (z. B. „AtlasServer
// 0.1.0“) und rechts der Knopf, der das Problem behebt oder erklärt. Unter
// dem Index steht je Projekt der Gruppe eine Unterzeile mit ihrem Stand
// (#619). „Warum?“ zeigt die Erklärung im Fenster, die übrigen Knöpfe rufen
// OnFix. Unten der Einstieg „Probier es aus: Strg+Leertaste in einer
// Methode“, „Beim Start zeigen …“ (ui.setupChecklist), „Bericht kopieren“,
// „Erneut prüfen“ und „Schließen“. Das Fenster ist nicht modal; es zeigt, was
// SetResults bekommt, und schließt mit Esc. Texte in der Sprache der IDE aus
// Befund und Werten der Prüfung (TAtlasSetupResult).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Setup.Checklist;

type
  TAtlasSetupWindow = class(TForm)
  private type
    /// <summary>Gezeichnete Zeile: Prüfung (AProject = -1) oder Projekt darunter.</summary>
    TLine = record
      Result_: Integer;
      Project: Integer;
      Top: Integer;
      Height: Integer;
    end;
  private
    FColors: TAtlasColors;
    FResults: TArray<TAtlasSetupResult>;
    FLines: TArray<TLine>;
    FFixButtons: TArray<TButton>;
    FCopyButton: TButton;
    FRecheckButton: TButton;
    FCloseButton: TButton;
    FShowAtStart: TCheckBox;
    FTryKey: string;
    FNote: string;
    FNoteTop: Integer;
    FNoteHeight: Integer;
    FFooterTop: Integer;
    FUpdating: Boolean;
    FOnFix: TProc<TAtlasSetupResult>;
    FOnCopy: TProc;
    FOnRecheck: TProc;
    FOnShowAtStart: TProc<Boolean>;
    function RowHeight: Integer;
    function SubRowHeight: Integer;
    function HeaderHeight: Integer;
    function ButtonsHeight: Integer;
    function FixButton(AIndex: Integer): TButton;
    procedure Layout;
    procedure DrawDot(const ACenter: TPoint; ARadius: Integer; AState: TAtlasStatusState);
    procedure FixClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure RecheckClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure ShowAtStartClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Resize; override;
  public
    constructor CreateSetup(AOwner: TComponent; const AColors: TAtlasColors);
    /// <summary>Hauptzeile einer Prüfung, z. B. „Server gefunden, gestartet, Version passt“.</summary>
    class function ResultText(const AResult: TAtlasSetupResult): string; static;
    /// <summary>Gedämpfte Einzelheit hinter dem Text, z. B. „AtlasServer 0.1.0“; '' ohne.</summary>
    class function DetailText(const AResult: TAtlasSetupResult): string; static;
    /// <summary>Unterzeile je Projekt, z. B. „Kunden: fertig“.</summary>
    class function ProjectText(const AProject: TAtlasSetupProject): string; static;
    class function ProjectState(const AProject: TAtlasSetupProject): TAtlasStatusState; static;
    /// <summary>Beschriftung des Knopfs; '' für None.</summary>
    class function FixCaption(AFix: TAtlasSetupFix): string; static;
    /// <summary>Erklärung zu „Warum?“; sonst die Hauptzeile.</summary>
    class function WhyText(const AResult: TAtlasSetupResult): string; static;
    /// <summary>„5 von 6 erledigt“.</summary>
    class function ProgressText(const AResults: TArray<TAtlasSetupResult>): string; static;
    /// <summary>Zeilen für den Bericht (#108): je Prüfung Text mit Einzelheit, darunter die Projekte.</summary>
    class function ReportLines(const AResults: TArray<TAtlasSetupResult>): TArray<TAtlasSetupReportLine>; static;
    class function StateColor(const AColors: TAtlasColors; AState: TAtlasStatusState): TAtlasColor; static;
    /// <summary>Prüfungen setzen (auch bei offenem Fenster); Knöpfe und Höhe folgen.</summary>
    procedure SetResults(const AResults: TArray<TAtlasSetupResult>);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Taste für den Einstieg „Probier es aus“, z. B. „Strg+Leertaste“.</summary>
    procedure SetTryKey(const AKey: string);
    /// <summary>Häkchen „Beim Start zeigen …“ setzen, ohne OnShowAtStart auszulösen.</summary>
    procedure SetShowAtStart(AValue: Boolean);
    /// <summary>Hinweis über der Fußzeile (Erklärung, „Bericht in der Zwischenablage“); '' blendet ihn aus.</summary>
    procedure ShowNote(const AText: string);
    property Results: TArray<TAtlasSetupResult> read FResults;
    property Note: string read FNote;
    property TryKey: string read FTryKey;
    /// <summary>Zum Testen: Knopf der Prüfung AIndex (unsichtbar ohne Knopf).</summary>
    property FixButtons[AIndex: Integer]: TButton read FixButton;
    property CopyButton: TButton read FCopyButton;
    property RecheckButton: TButton read FRecheckButton;
    property CloseButton: TButton read FCloseButton;
    property ShowAtStartBox: TCheckBox read FShowAtStart;
    /// <summary>Knopf einer Prüfung außer „Warum?“ (das erklärt das Fenster selbst).</summary>
    property OnFix: TProc<TAtlasSetupResult> read FOnFix write FOnFix;
    property OnCopy: TProc read FOnCopy write FOnCopy;
    property OnRecheck: TProc read FOnRecheck write FOnRecheck;
    property OnShowAtStart: TProc<Boolean> read FOnShowAtStart write FOnShowAtStart;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Strings;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function Arg(const AResult: TAtlasSetupResult; AIndex: Integer): string;
begin
  Result := '';
  if AIndex <= High(AResult.Args) then
    Result := AResult.Args[AIndex];
end;

{ TAtlasSetupWindow }

constructor TAtlasSetupWindow.CreateSetup(AOwner: TComponent; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  Caption := TAtlasStrings.Text(TAtlasTextId.SetupTitle);
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  KeyPreview := True;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnClose := FormClose;
  FCopyButton := TButton.Create(Self);
  FCopyButton.Parent := Self;
  FCopyButton.Caption := TAtlasStrings.Text(TAtlasTextId.SetupCopy);
  FCopyButton.OnClick := CopyClick;
  FRecheckButton := TButton.Create(Self);
  FRecheckButton.Parent := Self;
  FRecheckButton.Caption := TAtlasStrings.Text(TAtlasTextId.SetupRecheck);
  FRecheckButton.OnClick := RecheckClick;
  FCloseButton := TButton.Create(Self);
  FCloseButton.Parent := Self;
  FCloseButton.Caption := TAtlasStrings.Text(TAtlasTextId.SetupClose);
  FCloseButton.Cancel := True;
  FCloseButton.OnClick := CloseClick;
  FShowAtStart := TCheckBox.Create(Self);
  FShowAtStart.Parent := Self;
  FShowAtStart.Caption := TAtlasStrings.Text(TAtlasTextId.SetupShowAtStart);
  FShowAtStart.Checked := True;
  FShowAtStart.OnClick := ShowAtStartClick;
  FTryKey := 'Strg+Leertaste';
  Layout;
end;

class function TAtlasSetupWindow.StateColor(const AColors: TAtlasColors; AState: TAtlasStatusState): TAtlasColor;
begin
  case AState of
    TAtlasStatusState.Green:
      Result := AColors.Add;
    TAtlasStatusState.Yellow:
      Result := AColors.Warn;
    TAtlasStatusState.Red:
      Result := AColors.Error;
  else
    Result := AColors.Muted;
  end;
end;

class function TAtlasSetupWindow.ResultText(const AResult: TAtlasSetupResult): string;
begin
  case AResult.Finding of
    TAtlasSetupFinding.ServerReady:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupServerReady);
    TAtlasSetupFinding.ServerMissing:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupServerMissing);
    TAtlasSetupFinding.ServerNotStarted:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupServerNotStarted);
    TAtlasSetupFinding.ServerStarting:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupServerStarting);
    TAtlasSetupFinding.ServerStopped:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupServerStopped);
    TAtlasSetupFinding.ServerFailed:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupServerFailed);
    TAtlasSetupFinding.ServerVersionUnknown:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupServerVersionUnknown);
    TAtlasSetupFinding.ServerVersionMismatch:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupServerVersionMismatch, [Arg(AResult, 0), Arg(AResult, 1)]);
    TAtlasSetupFinding.DelphiReady:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupDelphiReady, [Arg(AResult, 0)]);
    TAtlasSetupFinding.DelphiNoProject:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupDelphiNoProject, [Arg(AResult, 0)]);
    TAtlasSetupFinding.DelphiUnknown:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupDelphiUnknown);
    TAtlasSetupFinding.IndexReady:
      if Arg(AResult, 1) <> '' then
        Result := TAtlasStrings.Fmt(TAtlasTextId.SetupIndexReadyUnits, [Arg(AResult, 0), Arg(AResult, 1)])
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.SetupIndexReady, [Arg(AResult, 0)]);
    TAtlasSetupFinding.IndexBuilding:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupIndexBuilding, [Arg(AResult, 0), Arg(AResult, 1)]);
    TAtlasSetupFinding.IndexIncomplete:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupIndexIncomplete, [Arg(AResult, 0), Arg(AResult, 1),
        Arg(AResult, 2)]);
    TAtlasSetupFinding.IndexNoServer:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupIndexNoServer);
    TAtlasSetupFinding.IndexNoProjects:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupIndexNoProjects);
    TAtlasSetupFinding.LibraryReady:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupLibraryReady);
    TAtlasSetupFinding.LibraryMissing:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupLibraryMissing);
    TAtlasSetupFinding.LibraryPending:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupLibraryPending);
    TAtlasSetupFinding.LibraryUnknown:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupLibraryUnknown);
    TAtlasSetupFinding.ErrorInsightAtlas:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupErrorInsightAtlas);
    TAtlasSetupFinding.ErrorInsightIde:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupErrorInsightIde);
    TAtlasSetupFinding.ErrorInsightDuplicate:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupErrorInsightDuplicate);
    TAtlasSetupFinding.ErrorInsightNone:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupErrorInsightNone);
    TAtlasSetupFinding.ErrorInsightRestart:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupErrorInsightRestart);
    TAtlasSetupFinding.KeysReady:
      if StrToIntDef(Arg(AResult, 0), 0) > 0 then
        Result := TAtlasStrings.Fmt(TAtlasTextId.SetupKeysReadyWins, [Arg(AResult, 0)])
      else
        Result := TAtlasStrings.Text(TAtlasTextId.SetupKeysReady);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.SetupKeysConflict, [Arg(AResult, 0), Arg(AResult, 1), Arg(AResult, 2)]);
  end;
end;

class function TAtlasSetupWindow.DetailText(const AResult: TAtlasSetupResult): string;
var
  Bytes: Int64;
begin
  Result := '';
  case AResult.Finding of
    TAtlasSetupFinding.ServerReady:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupServerVersion, [Arg(AResult, 0)]);
    TAtlasSetupFinding.ServerFailed:
      Result := Arg(AResult, 0);
    TAtlasSetupFinding.DelphiReady:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupDelphiPlatform, [Arg(AResult, 1)]);
    TAtlasSetupFinding.IndexBuilding:
      if Arg(AResult, 2) <> '' then
        Result := TAtlasStrings.Fmt(TAtlasTextId.SetupIndexPercent, [Arg(AResult, 2)]);
    TAtlasSetupFinding.LibraryReady:
      begin
        Bytes := StrToInt64Def(Arg(AResult, 0), 0);
        Result := TAtlasStrings.Fmt(TAtlasTextId.SetupLibrarySize,
          [FormatFloat('0.0', Bytes / (1024 * 1024), FormatSettings)]);
      end;
  end;
end;

class function TAtlasSetupWindow.ProjectText(const AProject: TAtlasSetupProject): string;
begin
  case AProject.State of
    TAtlasSetupProjectState.Done:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupProjectDone, [AProject.Name]);
    TAtlasSetupProjectState.Building:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetupProjectBuilding, [AProject.Name]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.SetupProjectMissing, [AProject.Name]);
  end;
end;

class function TAtlasSetupWindow.ProjectState(const AProject: TAtlasSetupProject): TAtlasStatusState;
begin
  case AProject.State of
    TAtlasSetupProjectState.Done:
      Result := TAtlasStatusState.Green;
    TAtlasSetupProjectState.Building:
      Result := TAtlasStatusState.Yellow;
  else
    Result := TAtlasStatusState.Red;
  end;
end;

class function TAtlasSetupWindow.FixCaption(AFix: TAtlasSetupFix): string;
begin
  case AFix of
    TAtlasSetupFix.Explain:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixExplain);
    TAtlasSetupFix.ChooseServerPath:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixChoosePath);
    TAtlasSetupFix.StartServer:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixStart);
    TAtlasSetupFix.RestartServer:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixRestart);
    TAtlasSetupFix.RebuildIndex:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixRebuild);
    TAtlasSetupFix.BuildLibraryCache:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixBuildLibrary);
    TAtlasSetupFix.DisableErrorInsight:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixDisableErrorInsight);
    TAtlasSetupFix.EnableErrorInsight:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixEnableErrorInsight);
    TAtlasSetupFix.OpenKeyConflicts:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupFixKeys);
  else
    Result := '';
  end;
end;

class function TAtlasSetupWindow.WhyText(const AResult: TAtlasSetupResult): string;
begin
  case AResult.Finding of
    TAtlasSetupFinding.ServerStarting:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyServerStarting);
    TAtlasSetupFinding.ServerVersionUnknown:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyServerVersion);
    TAtlasSetupFinding.DelphiNoProject:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyDelphiNoProject);
    TAtlasSetupFinding.DelphiUnknown:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyDelphiUnknown);
    TAtlasSetupFinding.IndexBuilding:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyIndexBuilding);
    TAtlasSetupFinding.IndexNoProjects:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyIndexNoProjects);
    TAtlasSetupFinding.LibraryPending:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyLibraryPending);
    TAtlasSetupFinding.ErrorInsightRestart:
      Result := TAtlasStrings.Text(TAtlasTextId.SetupWhyErrorInsightRestart);
  else
    Result := ResultText(AResult);
  end;
end;

class function TAtlasSetupWindow.ProgressText(const AResults: TArray<TAtlasSetupResult>): string;
var
  Done, Total: Integer;
begin
  TAtlasSetupChecklist.Progress(AResults, Done, Total);
  Result := TAtlasStrings.Fmt(TAtlasTextId.SetupProgress, [Done, Total]);
end;

class function TAtlasSetupWindow.ReportLines(const AResults: TArray<TAtlasSetupResult>):
  TArray<TAtlasSetupReportLine>;
var
  Item: TAtlasSetupResult;
  Project: TAtlasSetupProject;
  mText: string;
begin
  Result := nil;
  for Item in AResults do
  begin
    mText := ResultText(Item);
    if DetailText(Item) <> '' then
      mText := mText + ' (' + DetailText(Item) + ')';
    Result := Result + [TAtlasSetupReportLine.Create(Item.State, mText, False)];
    for Project in Item.Projects do
      Result := Result + [TAtlasSetupReportLine.Create(ProjectState(Project), ProjectText(Project), True)];
  end;
end;

function TAtlasSetupWindow.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Max(Canvas.TextHeight('Wg') + ScaleValue(12), ScaleValue(31));
end;

function TAtlasSetupWindow.SubRowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + ScaleValue(4);
end;

function TAtlasSetupWindow.HeaderHeight: Integer;
begin
  Result := RowHeight + ScaleValue(4);
end;

function TAtlasSetupWindow.ButtonsHeight: Integer;
begin
  Result := ScaleValue(44);
end;

function TAtlasSetupWindow.FixButton(AIndex: Integer): TButton;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FFixButtons)) then
    Result := FFixButtons[AIndex];
end;

procedure TAtlasSetupWindow.Layout;
var
  Index, Project, Top_, ButtonWidth, NoteWidth, Bottom: Integer;
  Line: TLine;
  Button: TButton;
  Area: TRect;
  mText: string;
begin
  Canvas.Font := Font;
  ClientWidth := ScaleValue(620);
  // Je Prüfung ein Knopf; überzählige ausblenden.
  while Length(FFixButtons) < Length(FResults) do
  begin
    Button := TButton.Create(Self);
    Button.Parent := Self;
    Button.Tag := Length(FFixButtons);
    Button.OnClick := FixClick;
    FFixButtons := FFixButtons + [Button];
  end;
  FLines := nil;
  Top_ := HeaderHeight;
  for Index := 0 to High(FFixButtons) do
    FFixButtons[Index].Visible := False;
  for Index := 0 to High(FResults) do
  begin
    Line.Result_ := Index;
    Line.Project := -1;
    Line.Top := Top_;
    Line.Height := RowHeight;
    FLines := FLines + [Line];
    Button := FFixButtons[Index];
    mText := FixCaption(FResults[Index].Fix);
    Button.Caption := mText;
    Button.Visible := mText <> '';
    ButtonWidth := Max(Canvas.TextWidth(mText) + ScaleValue(24), ScaleValue(90));
    Button.SetBounds(ClientWidth - ButtonWidth - ScaleValue(12), Top_ + (Line.Height - ScaleValue(25)) div 2,
      ButtonWidth, ScaleValue(25));
    Inc(Top_, Line.Height);
    for Project := 0 to High(FResults[Index].Projects) do
    begin
      Line.Project := Project;
      Line.Top := Top_;
      Line.Height := SubRowHeight;
      FLines := FLines + [Line];
      Inc(Top_, Line.Height);
    end;
  end;
  // Erklärung bzw. Hinweis, umbrochen.
  FNoteTop := Top_ + ScaleValue(4);
  FNoteHeight := 0;
  if FNote <> '' then
  begin
    NoteWidth := ClientWidth - ScaleValue(40);
    Area := Rect(0, 0, NoteWidth, 0);
    DrawText(Canvas.Handle, PChar(FNote), -1, Area, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    FNoteHeight := Area.Height + ScaleValue(8);
  end;
  FFooterTop := FNoteTop + FNoteHeight + ScaleValue(4);
  ClientHeight := FFooterTop + RowHeight + ButtonsHeight;
  Bottom := ClientHeight - ButtonsHeight + ScaleValue(10);
  ButtonWidth := Max(Max(Canvas.TextWidth(FCopyButton.Caption), Canvas.TextWidth(FRecheckButton.Caption)),
    Canvas.TextWidth(FCloseButton.Caption)) + ScaleValue(24);
  FCloseButton.SetBounds(ClientWidth - ButtonWidth - ScaleValue(12), Bottom, ButtonWidth, ScaleValue(25));
  FRecheckButton.SetBounds(FCloseButton.Left - ButtonWidth - ScaleValue(8), Bottom, ButtonWidth, ScaleValue(25));
  FCopyButton.SetBounds(FRecheckButton.Left - ButtonWidth - ScaleValue(8), Bottom, ButtonWidth, ScaleValue(25));
  FShowAtStart.SetBounds(ScaleValue(12), Bottom + ScaleValue(4), Max(ScaleValue(80),
    FCopyButton.Left - ScaleValue(24)), ScaleValue(19));
  Invalidate;
end;

procedure TAtlasSetupWindow.Resize;
begin
  inherited;
  Invalidate;
end;

procedure TAtlasSetupWindow.SetResults(const AResults: TArray<TAtlasSetupResult>);
begin
  FResults := AResults;
  Layout;
end;

procedure TAtlasSetupWindow.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Color := ToColor(FColors.Surface);
  FShowAtStart.Font.Color := ToColor(FColors.Text);
  Invalidate;
end;

procedure TAtlasSetupWindow.SetTryKey(const AKey: string);
begin
  if AKey <> '' then
    FTryKey := AKey;
  Invalidate;
end;

procedure TAtlasSetupWindow.SetShowAtStart(AValue: Boolean);
begin
  FUpdating := True;
  try
    FShowAtStart.Checked := AValue;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasSetupWindow.ShowNote(const AText: string);
begin
  FNote := AText;
  Layout;
end;

procedure TAtlasSetupWindow.FixClick(Sender: TObject);
var
  Index: Integer;
  Item: TAtlasSetupResult;
begin
  Index := TButton(Sender).Tag;
  if (Index < 0) or (Index > High(FResults)) then
    Exit;
  Item := FResults[Index];
  if Item.Fix = TAtlasSetupFix.Explain then
  begin
    ShowNote(WhyText(Item));
    Exit;
  end;
  ShowNote('');
  if Assigned(FOnFix) then
    FOnFix(Item);
end;

procedure TAtlasSetupWindow.CopyClick(Sender: TObject);
begin
  if Assigned(FOnCopy) then
    FOnCopy();
end;

procedure TAtlasSetupWindow.RecheckClick(Sender: TObject);
begin
  ShowNote('');
  if Assigned(FOnRecheck) then
    FOnRecheck();
end;

procedure TAtlasSetupWindow.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TAtlasSetupWindow.ShowAtStartClick(Sender: TObject);
begin
  if not FUpdating and Assigned(FOnShowAtStart) then
    FOnShowAtStart(FShowAtStart.Checked);
end;

procedure TAtlasSetupWindow.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Die IDE-Schicht behält das Fenster und zeigt es beim nächsten Abruf wieder.
  Action := caHide;
end;

procedure TAtlasSetupWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
    Exit;
  end;
  inherited;
end;

procedure TAtlasSetupWindow.DrawDot(const ACenter: TPoint; ARadius: Integer; AState: TAtlasStatusState);
begin
  Canvas.Pen.Color := ToColor(StateColor(FColors, AState));
  Canvas.Brush.Color := ToColor(StateColor(FColors, AState));
  Canvas.Brush.Style := bsSolid;
  Canvas.Ellipse(ACenter.X - ARadius, ACenter.Y - ARadius, ACenter.X + ARadius + 1, ACenter.Y + ARadius + 1);
end;

procedure TAtlasSetupWindow.Paint;
var
  Line: TLine;
  Item: TAtlasSetupResult;
  Part: TRect;
  mText, Detail, Before, After: string;
  Right_, KeyAt, X: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  // Kopf: Titel und Fortschritt.
  Canvas.Brush.Style := bsClear;
  Part := Rect(ScaleValue(12), 0, ClientWidth - ScaleValue(12), HeaderHeight);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  mText := TAtlasStrings.Text(TAtlasTextId.SetupTitle);
  DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(FColors.Muted);
  mText := ProgressText(FResults);
  DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX);
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, HeaderHeight - ScaleValue(2));
  Canvas.LineTo(ClientWidth, HeaderHeight - ScaleValue(2));
  for Line in FLines do
  begin
    Item := FResults[Line.Result_];
    if Line.Project >= 0 then
    begin
      // Unterzeile je Projekt (#619): kleiner Punkt, gedämpfter Text.
      DrawDot(Point(ScaleValue(40), Line.Top + Line.Height div 2), ScaleValue(3),
        ProjectState(Item.Projects[Line.Project]));
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := ToColor(FColors.Muted);
      Part := Rect(ScaleValue(50), Line.Top, ClientWidth - ScaleValue(12), Line.Top + Line.Height);
      mText := ProjectText(Item.Projects[Line.Project]);
      DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
      Continue;
    end;
    DrawDot(Point(ScaleValue(20), Line.Top + Line.Height div 2), ScaleValue(5), Item.State);
    Canvas.Brush.Style := bsClear;
    Right_ := ClientWidth - ScaleValue(12);
    if (FixButton(Line.Result_) <> nil) and FixButton(Line.Result_).Visible then
      Right_ := FixButton(Line.Result_).Left - ScaleValue(8);
    Part := Rect(ScaleValue(34), Line.Top, Right_, Line.Top + Line.Height);
    mText := ResultText(Item);
    Canvas.Font.Color := ToColor(FColors.Text);
    DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Detail := DetailText(Item);
    if Detail <> '' then
    begin
      Part.Left := Part.Left + Canvas.TextWidth(mText) + ScaleValue(10);
      if Part.Left < Part.Right then
      begin
        Canvas.Font.Color := ToColor(FColors.Muted);
        DrawText(Canvas.Handle, PChar(Detail), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
          DT_END_ELLIPSIS);
      end;
    end;
  end;
  // Erklärung bzw. Hinweis.
  if FNote <> '' then
  begin
    Part := Rect(ScaleValue(20), FNoteTop + ScaleValue(4), ClientWidth - ScaleValue(20), FNoteTop + FNoteHeight);
    Canvas.Font.Color := ToColor(FColors.Muted);
    DrawText(Canvas.Handle, PChar(FNote), -1, Part, DT_WORDBREAK or DT_NOPREFIX);
  end;
  // Einstieg: „Probier es aus: Strg+Leertaste in einer Methode“, die Taste fett.
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, FFooterTop);
  Canvas.LineTo(ClientWidth, FFooterTop);
  mText := TAtlasStrings.Fmt(TAtlasTextId.SetupTryIt, [FTryKey]);
  KeyAt := Pos(FTryKey, mText);
  Before := mText;
  After := '';
  if KeyAt > 0 then
  begin
    Before := Copy(mText, 1, KeyAt - 1);
    After := Copy(mText, KeyAt + Length(FTryKey), MaxInt);
  end;
  X := ScaleValue(12);
  Part := Rect(X, FFooterTop, ClientWidth - ScaleValue(12), FFooterTop + RowHeight);
  Canvas.Font.Color := ToColor(FColors.Text);
  DrawText(Canvas.Handle, PChar(Before), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  if KeyAt > 0 then
  begin
    Part.Left := Part.Left + Canvas.TextWidth(Before);
    Canvas.Font.Style := [fsBold];
    DrawText(Canvas.Handle, PChar(FTryKey), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    Part.Left := Part.Left + Canvas.TextWidth(FTryKey);
    Canvas.Font.Style := [];
    DrawText(Canvas.Handle, PChar(After), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  end;
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, ClientHeight - ButtonsHeight);
  Canvas.LineTo(ClientWidth, ClientHeight - ButtonsHeight);
  Canvas.Brush.Style := bsSolid;
end;

end.
