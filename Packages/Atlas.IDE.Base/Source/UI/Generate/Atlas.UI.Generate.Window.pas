unit Atlas.UI.Generate.Window;

// Fenster des Erzeugen-Menüs (#719) im Stil der Befehlspalette, am Cursor:
// oben der Titel „Erzeugen“, darunter Gruppenköpfe (Zuletzt gewählt,
// Erzeugen, Umschließen, Vorlagen) und Einträge mit Ziffer 1–9, Beschriftung
// und gedimmtem /name rechts (keys.generateMenu.showCommandNames); unten der
// Hinweis bzw. der getippte Filter. Wie die Palette nimmt das Fenster den
// Fokus; Escape oder ein Klick daneben schließt es.
// Tasten in der Liste: Ziffer wählt, Tippen filtert unscharf (#229), Pfeile,
// Bild auf/ab, Pos1/Ende, Enter, Rücktaste, Entf blendet den Eintrag aus
// (OnHide speichert keys.generateMenu.hidden).
// Braucht ein Eintrag ein Argument oder bietet er eine Auswahl (Felder für
// /ctor, Methoden für /override, Interface-Methoden …), folgt ein zweiter
// Schritt: Tippen filtert die Auswahl, bei Mehrfachauswahl schaltet die
// Leertaste (vorab alle gewählt, außer das Argument ist Pflicht), eine
// eigene Eingabe steht als letzte Zeile „„…“ verwenden“ bereit, Escape bzw.
// Rücktaste im leeren Feld führt zurück zur Liste.
// Ausgeführt wird über OnExecute erst nach dem Schließen (TAtlasMainThread).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Generate.Menu;

type
  TAtlasGenerateChoicesFunc = reference to function(const AEntry: TAtlasGenerateEntry): TArray<string>;
  TAtlasGenerateExecuteProc = reference to procedure(const AEntry: TAtlasGenerateEntry; const AArgument: string);
  TAtlasGenerateHideProc = reference to procedure(const AEntry: TAtlasGenerateEntry);

  TAtlasGenerateWindow = class(TForm)
  private const
    VisibleRows = 14;
  private
    FEntries: TArray<TAtlasGenerateEntry>;
    FOptions: TAtlasGenerateOptions;
    FRecent: TAtlasGenerateRecent;
    FColors: TAtlasColors;
    FPattern: string;
    FRows: TArray<TAtlasGenerateRow>;
    FSelected: Integer;
    FTop: Integer;
    FStep: Boolean;
    FStepEntry: TAtlasGenerateEntry;
    FChoices: TArray<string>;
    FChecked: TArray<Boolean>;
    FChoiceOrder: TArray<Integer>;
    FText: string;
    FDone: Boolean;
    FOnChoices: TAtlasGenerateChoicesFunc;
    FOnExecute: TAtlasGenerateExecuteProc;
    FOnHide: TAtlasGenerateHideProc;
    function RowHeight: Integer;
    function TitleHeight: Integer;
    function FooterHeight: Integer;
    function ListTop: Integer;
    function RowRect(AVisibleRow: Integer): TRect;
    function RowCount: Integer;
    function HasFreeTextRow: Boolean;
    procedure Rebuild;
    procedure RefilterChoices;
    procedure SelectRow(ARow: Integer);
    procedure Step(ADelta: Integer);
    procedure ChooseRow(ARow: Integer);
    procedure EnterStep(const AEntry: TAtlasGenerateEntry);
    procedure LeaveStep;
    procedure ConfirmStep;
    procedure Finish(const AEntry: TAtlasGenerateEntry; const AArgument: string);
    procedure HideSelected;
    procedure ToggleSelected;
    procedure UpdateHeight;
    procedure FormDeactivate(Sender: TObject);
    procedure DrawLabel(const AText: string; ARect: TRect; AColor: TAtlasColor; AFlags: Cardinal);
    procedure DrawHighlighted(const AText, APattern: string; const ARect: TRect);
    procedure DrawListRow(AVisibleRow: Integer);
    procedure DrawStepRow(AVisibleRow: Integer);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>ARecent gehört weiter dem Aufrufer und darf nil sein.</summary>
    constructor CreateMenu(AOwner: TComponent; const AEntries: TArray<TAtlasGenerateEntry>;
      const AOptions: TAtlasGenerateOptions; ARecent: TAtlasGenerateRecent; const AColors: TAtlasColors);
    /// <summary>Unter dem Caret (Bildschirmkoordinaten), passt es dort nicht hin, darüber.</summary>
    procedure ShowAt(const ACaret: TRect);
    /// <summary>Oben mittig über AArea, wenn kein Caret bekannt ist.</summary>
    procedure ShowOver(const AArea: TRect);
    /// <summary>Beschriftung eines Eintrags: Schnellbefehle mit eigenem Text in der Sprache der Oberfläche, sonst
    /// die Beschriftung des Eintrags (Kurzbeschreibung des Servers, Name der Vorlage, Titel der Code-Aktion).
    /// </summary>
    class function EntryCaption(const AEntry: TAtlasGenerateEntry): string; static;
    class function GroupCaption(AGroup: TAtlasGenerateGroup): string; static;
    /// <summary>Mögliche Argumente holen (Server); läuft im Hauptthread, solange das Fenster offen ist.</summary>
    property OnChoices: TAtlasGenerateChoicesFunc read FOnChoices write FOnChoices;
    /// <summary>Nach dem Schließen; das Fenster gibt sich danach selbst frei.</summary>
    property OnExecute: TAtlasGenerateExecuteProc read FOnExecute write FOnExecute;
    /// <summary>Entf: Eintrag dauerhaft ausblenden (Einstellung speichern).</summary>
    property OnHide: TAtlasGenerateHideProc read FOnHide write FOnHide;
    /// <summary>Zum Testen: Zeilen der Liste und gewählte Zeile.</summary>
    property Rows: TArray<TAtlasGenerateRow> read FRows;
    property Selected: Integer read FSelected;
    property InStep: Boolean read FStep;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Strings,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Completion.Presentation;

type
  TCommandCaption = record
    Name: string;
    Id: TAtlasTextId;
  end;

const
  // Eigene Beschriftungen der Schnellbefehle; die Kurzbeschreibungen des Servers gibt es nur auf Deutsch.
  CommandCaptions: array[0..51] of TCommandCaption = (
    (Name: 'ctor'; Id: TAtlasTextId.GenerateCmdCtor),
    (Name: 'dtor'; Id: TAtlasTextId.GenerateCmdDtor),
    (Name: 'prop'; Id: TAtlasTextId.GenerateCmdProp),
    (Name: 'override'; Id: TAtlasTextId.GenerateCmdOverride),
    (Name: 'implement'; Id: TAtlasTextId.GenerateCmdImplement),
    (Name: 'equals'; Id: TAtlasTextId.GenerateCmdEquals),
    (Name: 'impl'; Id: TAtlasTextId.GenerateCmdImpl),
    (Name: 'field'; Id: TAtlasTextId.GenerateCmdField),
    (Name: 'encapsulate'; Id: TAtlasTextId.GenerateCmdEncapsulate),
    (Name: 'clone'; Id: TAtlasTextId.GenerateCmdClone),
    (Name: 'assign'; Id: TAtlasTextId.GenerateCmdAssign),
    (Name: 'json'; Id: TAtlasTextId.GenerateCmdJson),
    (Name: 'msg'; Id: TAtlasTextId.GenerateCmdMsg),
    (Name: 'notify'; Id: TAtlasTextId.GenerateCmdNotify),
    (Name: 'changed'; Id: TAtlasTextId.GenerateCmdChanged),
    (Name: 'loaded'; Id: TAtlasTextId.GenerateCmdLoaded),
    (Name: 'notification'; Id: TAtlasTextId.GenerateCmdNotification),
    (Name: 'singleton'; Id: TAtlasTextId.GenerateCmdSingleton),
    (Name: 'list'; Id: TAtlasTextId.GenerateCmdList),
    (Name: 'dict'; Id: TAtlasTextId.GenerateCmdDict),
    (Name: 'dict!'; Id: TAtlasTextId.GenerateCmdDictBang),
    (Name: 'operator'; Id: TAtlasTextId.GenerateCmdOperator),
    (Name: 'guid'; Id: TAtlasTextId.GenerateCmdGuid),
    (Name: 'var'; Id: TAtlasTextId.GenerateCmdVar),
    (Name: 'const'; Id: TAtlasTextId.GenerateCmdConst),
    (Name: 'const!'; Id: TAtlasTextId.GenerateCmdConstBang),
    (Name: 'guard'; Id: TAtlasTextId.GenerateCmdGuard),
    (Name: 'raise'; Id: TAtlasTextId.GenerateCmdRaise),
    (Name: 'log'; Id: TAtlasTextId.GenerateCmdLog),
    (Name: 'sql'; Id: TAtlasTextId.GenerateCmdSql),
    (Name: 'params'; Id: TAtlasTextId.GenerateCmdParams),
    (Name: 'record'; Id: TAtlasTextId.GenerateCmdRecord),
    (Name: 'enum'; Id: TAtlasTextId.GenerateCmdEnum),
    (Name: 'enum!'; Id: TAtlasTextId.GenerateCmdEnumBang),
    (Name: 'helper'; Id: TAtlasTextId.GenerateCmdHelper),
    (Name: 'exception'; Id: TAtlasTextId.GenerateCmdException),
    (Name: 'thread'; Id: TAtlasTextId.GenerateCmdThread),
    (Name: 'external'; Id: TAtlasTextId.GenerateCmdExternal),
    (Name: 'exports'; Id: TAtlasTextId.GenerateCmdExports),
    (Name: 'todo'; Id: TAtlasTextId.GenerateCmdTodo),
    (Name: 'try'; Id: TAtlasTextId.GenerateCmdTry),
    (Name: 'except'; Id: TAtlasTextId.GenerateCmdExcept),
    (Name: 'lock'; Id: TAtlasTextId.GenerateCmdLock),
    (Name: 'sync'; Id: TAtlasTextId.GenerateCmdSync),
    (Name: 'sync!'; Id: TAtlasTextId.GenerateCmdSyncBang),
    (Name: 'ifdef'; Id: TAtlasTextId.GenerateCmdIfdef),
    (Name: 'region'; Id: TAtlasTextId.GenerateCmdRegion),
    (Name: 'measure'; Id: TAtlasTextId.GenerateCmdMeasure),
    (Name: 'task'; Id: TAtlasTextId.GenerateCmdTask),
    (Name: 'future'; Id: TAtlasTextId.GenerateCmdFuture),
    (Name: 'loop'; Id: TAtlasTextId.GenerateCmdLoop),
    (Name: 'transaction'; Id: TAtlasTextId.GenerateCmdTransaction));

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>Muster ohne führendes "/" für die Hervorhebung in der Beschriftung.</summary>
function CaptionPattern(const APattern: string): string;
begin
  Result := APattern;
  if Result.StartsWith('/') then
    Delete(Result, 1, 1);
end;

{ TAtlasGenerateWindow }

class function TAtlasGenerateWindow.EntryCaption(const AEntry: TAtlasGenerateEntry): string;
var
  Item: TCommandCaption;
begin
  Result := AEntry.Caption;
  if AEntry.Kind <> TAtlasGenerateKind.Slash then
    Exit;
  for Item in CommandCaptions do
    if SameText(Item.Name, AEntry.Name) then
      Exit(TAtlasStrings.Text(Item.Id));
  if Result = '' then
    Result := AEntry.CommandName;
end;

class function TAtlasGenerateWindow.GroupCaption(AGroup: TAtlasGenerateGroup): string;
begin
  case AGroup of
    TAtlasGenerateGroup.Recent:
      Result := TAtlasStrings.Text(TAtlasTextId.GenerateGroupRecent);
    TAtlasGenerateGroup.Surround:
      Result := TAtlasStrings.Text(TAtlasTextId.GenerateGroupSurround);
    TAtlasGenerateGroup.Templates:
      Result := TAtlasStrings.Text(TAtlasTextId.GenerateGroupTemplates);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.GenerateGroupGenerate);
  end;
end;

constructor TAtlasGenerateWindow.CreateMenu(AOwner: TComponent; const AEntries: TArray<TAtlasGenerateEntry>;
  const AOptions: TAtlasGenerateOptions; ARecent: TAtlasGenerateRecent; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FEntries := AEntries;
  FOptions := AOptions;
  FRecent := ARecent;
  FColors := AColors;
  BorderStyle := bsNone;
  KeyPreview := False;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  OnDeactivate := FormDeactivate;
  Rebuild;
end;

procedure TAtlasGenerateWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

function TAtlasGenerateWindow.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + ScaleValue(8);
end;

function TAtlasGenerateWindow.TitleHeight: Integer;
begin
  Result := RowHeight + ScaleValue(6);
  // Im zweiten Schritt steht unter dem Titel das Eingabefeld.
  if FStep then
    Inc(Result, RowHeight + ScaleValue(6));
end;

function TAtlasGenerateWindow.FooterHeight: Integer;
begin
  Result := RowHeight;
end;

function TAtlasGenerateWindow.ListTop: Integer;
begin
  Result := TitleHeight;
end;

function TAtlasGenerateWindow.RowRect(AVisibleRow: Integer): TRect;
begin
  Result := Rect(ScaleValue(4), ListTop + AVisibleRow * RowHeight, ClientWidth - ScaleValue(4),
    ListTop + (AVisibleRow + 1) * RowHeight);
end;

function TAtlasGenerateWindow.HasFreeTextRow: Boolean;
var
  Choice: string;
begin
  Result := FStep and (Trim(FText) <> '');
  if not Result then
    Exit;
  for Choice in FChoices do
    if SameText(Choice, Trim(FText)) then
      Exit(False);
end;

function TAtlasGenerateWindow.RowCount: Integer;
begin
  if FStep then
  begin
    Result := Length(FChoiceOrder);
    if HasFreeTextRow then
      Inc(Result);
  end
  else
    Result := Length(FRows);
end;

procedure TAtlasGenerateWindow.UpdateHeight;
var
  mVisible: Integer;
begin
  mVisible := EnsureRange(RowCount, 1, VisibleRows);
  ClientHeight := TitleHeight + mVisible * RowHeight + FooterHeight + ScaleValue(4);
end;

procedure TAtlasGenerateWindow.Rebuild;
begin
  FRows := TAtlasGenerateMenu.Rows(FEntries, FOptions, FRecent, FPattern);
  FTop := 0;
  FSelected := TAtlasGenerateMenu.FirstEntryRow(FRows);
  Invalidate;
end;

procedure TAtlasGenerateWindow.RefilterChoices;
begin
  FChoiceOrder := TAtlasGenerateMenu.FilterChoices(FChoices, FText);
  FTop := 0;
  FSelected := 0;
  if RowCount = 0 then
    FSelected := -1;
  UpdateHeight;
  Invalidate;
end;

procedure TAtlasGenerateWindow.ShowAt(const ACaret: TRect);
var
  Area: TRect;
  Left_, Top_: Integer;
begin
  Width := ScaleValue(440);
  UpdateHeight;
  Area := Screen.MonitorFromPoint(ACaret.TopLeft, mdNearest).WorkareaRect;
  Left_ := EnsureRange(ACaret.Left, Area.Left, Max(Area.Left, Area.Right - Width));
  Top_ := ACaret.Bottom + ScaleValue(2);
  // Unten kein Platz: über die Zeile.
  if Top_ + Height > Area.Bottom then
    Top_ := Max(Area.Top, ACaret.Top - Height - ScaleValue(2));
  SetBounds(Left_, Top_, Width, Height);
  Show;
  SetFocus;
end;

procedure TAtlasGenerateWindow.ShowOver(const AArea: TRect);
begin
  Width := Min(ScaleValue(440), AArea.Width - ScaleValue(40));
  UpdateHeight;
  SetBounds(AArea.Left + (AArea.Width - Width) div 2, AArea.Top + ScaleValue(60), Width, Height);
  Show;
  SetFocus;
end;

procedure TAtlasGenerateWindow.SelectRow(ARow: Integer);
begin
  if RowCount = 0 then
  begin
    FSelected := -1;
    Invalidate;
    Exit;
  end;
  FSelected := EnsureRange(ARow, 0, RowCount - 1);
  if FSelected < FTop then
    FTop := FSelected
  else if FSelected >= FTop + VisibleRows then
    FTop := FSelected - VisibleRows + 1;
  // Kopf über dem ersten Eintrag mit zeigen.
  if not FStep and (FTop > 0) and (FTop = FSelected) and FRows[FTop - 1].IsHeader then
    Dec(FTop);
  Invalidate;
end;

procedure TAtlasGenerateWindow.Step(ADelta: Integer);
var
  Next, Index: Integer;
begin
  if FStep then
  begin
    SelectRow(FSelected + ADelta);
    Exit;
  end;
  Next := FSelected;
  // Bild auf/ab: mehrere Schritte über Einträge, Köpfe übersprungen.
  for Index := 1 to Abs(ADelta) do
    Next := TAtlasGenerateMenu.StepRow(FRows, Next, Sign(ADelta));
  if Next >= 0 then
    SelectRow(Next);
end;

procedure TAtlasGenerateWindow.ChooseRow(ARow: Integer);
begin
  if FStep or (ARow < 0) or (ARow > High(FRows)) or FRows[ARow].IsHeader then
    Exit;
  FSelected := ARow;
  if FEntries[FRows[ARow].Entry].NeedsStep then
    EnterStep(FEntries[FRows[ARow].Entry])
  else
    Finish(FEntries[FRows[ARow].Entry], '');
end;

procedure TAtlasGenerateWindow.EnterStep(const AEntry: TAtlasGenerateEntry);
var
  Index: Integer;
begin
  FChoices := nil;
  if AEntry.HasChoices and Assigned(FOnChoices) then
  begin
    Screen.Cursor := crHourGlass;
    try
      FChoices := FOnChoices(AEntry);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  // Ohne Auswahl und ohne Pflicht-Argument gleich ausführen (z. B. /ctor in einer Klasse ohne Felder).
  if AEntry.HasChoices and (Length(FChoices) = 0) and (AEntry.Argument <> TAtlasGenerateArgument.Required) then
  begin
    Finish(AEntry, '');
    Exit;
  end;
  FStep := True;
  FStepEntry := AEntry;
  FText := '';
  SetLength(FChecked, Length(FChoices));
  // Mehrfachauswahl: vorab alles gewählt (alle Felder, alle fehlenden Methoden), außer bei Pflicht-Argumenten.
  for Index := 0 to High(FChecked) do
    FChecked[Index] := AEntry.Multi and (AEntry.Argument <> TAtlasGenerateArgument.Required);
  RefilterChoices;
end;

procedure TAtlasGenerateWindow.LeaveStep;
begin
  FStep := False;
  FChoices := nil;
  FChecked := nil;
  FChoiceOrder := nil;
  FText := '';
  Rebuild;
  UpdateHeight;
end;

procedure TAtlasGenerateWindow.ConfirmStep;
var
  Argument: string;
  AnyChecked: Boolean;
  Index: Integer;
begin
  Argument := '';
  if HasFreeTextRow and (FSelected = RowCount - 1) then
    Argument := Trim(FText)
  else if FStepEntry.Multi and (Length(FChoices) > 0) then
  begin
    AnyChecked := False;
    for Index := 0 to High(FChecked) do
      AnyChecked := AnyChecked or FChecked[Index];
    if AnyChecked then
      Argument := TAtlasGenerateMenu.JoinChoices(FChoices, FChecked, FStepEntry.Separator,
        FStepEntry.Argument <> TAtlasGenerateArgument.Required)
    else
      Argument := Trim(FText);
  end
  else if (FSelected >= 0) and (FSelected <= High(FChoiceOrder)) then
    Argument := FChoices[FChoiceOrder[FSelected]]
  else
    Argument := Trim(FText);
  // Pflicht-Argument fehlt: im Schritt bleiben, die Zeile nennt das Beispiel.
  if (Argument = '') and (FStepEntry.Argument = TAtlasGenerateArgument.Required) then
  begin
    MessageBeep(MB_OK);
    Exit;
  end;
  Finish(FStepEntry, Argument);
end;

procedure TAtlasGenerateWindow.Finish(const AEntry: TAtlasGenerateEntry; const AArgument: string);
var
  Handler: TAtlasGenerateExecuteProc;
  Entry: TAtlasGenerateEntry;
  Argument: string;
begin
  if FDone then
    Exit;
  FDone := True;
  Handler := FOnExecute;
  Entry := AEntry;
  Argument := AArgument;
  Close;
  // Erst nach dem Schließen ausführen: Der Editor hat dann wieder den Fokus.
  if Assigned(Handler) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.Generate,
      procedure
      begin
        Handler(Entry, Argument);
      end);
  Release;
end;

procedure TAtlasGenerateWindow.HideSelected;
var
  Entry: TAtlasGenerateEntry;
begin
  if FStep or (FSelected < 0) or (FSelected > High(FRows)) or FRows[FSelected].IsHeader then
    Exit;
  Entry := FEntries[FRows[FSelected].Entry];
  FOptions.Hidden := FOptions.Hidden + [Entry.Id];
  if Assigned(FOnHide) then
    FOnHide(Entry);
  Rebuild;
  UpdateHeight;
end;

procedure TAtlasGenerateWindow.ToggleSelected;
begin
  if not FStep or not FStepEntry.Multi or (FSelected < 0) or (FSelected > High(FChoiceOrder)) then
    Exit;
  FChecked[FChoiceOrder[FSelected]] := not FChecked[FChoiceOrder[FSelected]];
  Invalidate;
end;

procedure TAtlasGenerateWindow.FormDeactivate(Sender: TObject);
begin
  if not FDone then
  begin
    FDone := True;
    Close;
    Release;
  end;
end;

procedure TAtlasGenerateWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      if FStep then
        LeaveStep
      else
        FormDeactivate(Self);
    VK_RETURN:
      if FStep then
        ConfirmStep
      else
        ChooseRow(FSelected);
    VK_UP:
      Step(-1);
    VK_DOWN:
      Step(1);
    VK_PRIOR:
      Step(-VisibleRows);
    VK_NEXT:
      Step(VisibleRows);
    VK_HOME:
      Step(-RowCount);
    VK_END:
      Step(RowCount);
    VK_DELETE:
      HideSelected;
    VK_BACK:
      if FStep then
      begin
        if FText = '' then
          LeaveStep
        else
        begin
          Delete(FText, Length(FText), 1);
          RefilterChoices;
        end;
      end
      else if FPattern <> '' then
      begin
        if ssCtrl in Shift then
          FPattern := ''
        else
          Delete(FPattern, Length(FPattern), 1);
        Rebuild;
        UpdateHeight;
      end;
  else
    Exit;
  end;
  Key := 0;
end;

procedure TAtlasGenerateWindow.KeyPress(var Key: Char);
var
  Row: Integer;
begin
  if Key < ' ' then
  begin
    Key := #0;
    Exit;
  end;
  if FStep then
  begin
    // Leertaste schaltet bei Mehrfachauswahl, solange nichts getippt ist.
    if (Key = ' ') and FStepEntry.Multi and (FText = '') then
      ToggleSelected
    else
    begin
      FText := FText + Key;
      RefilterChoices;
    end;
    Key := #0;
    Exit;
  end;
  if CharInSet(Key, ['1'..'9']) then
  begin
    Row := TAtlasGenerateMenu.RowOfDigit(FRows, Ord(Key) - Ord('0'));
    if Row >= 0 then
      ChooseRow(Row);
  end
  else if Key <> ' ' then
  begin
    FPattern := FPattern + Key;
    Rebuild;
    UpdateHeight;
  end;
  Key := #0;
end;

procedure TAtlasGenerateWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  inherited;
  if (Y < ListTop) or (Y >= ClientHeight - FooterHeight) then
    Exit;
  Row := FTop + (Y - ListTop) div RowHeight;
  if Row >= RowCount then
    Exit;
  if FStep then
  begin
    SelectRow(Row);
    if FStepEntry.Multi and (Row <= High(FChoiceOrder)) then
      ToggleSelected
    else
      ConfirmStep;
  end
  else
    ChooseRow(Row);
end;

function TAtlasGenerateWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FTop := EnsureRange(FTop - Sign(WheelDelta) * 3, 0, Max(0, RowCount - VisibleRows));
  Invalidate;
  Result := True;
end;

procedure TAtlasGenerateWindow.DrawLabel(const AText: string; ARect: TRect; AColor: TAtlasColor; AFlags: Cardinal);
begin
  Canvas.Font.Color := ToColor(AColor);
  DrawText(Canvas.Handle, PChar(AText), -1, ARect, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or AFlags);
end;

procedure TAtlasGenerateWindow.DrawHighlighted(const AText, APattern: string; const ARect: TRect);
var
  Marks: TArray<Boolean>;
  Position, Index, Run, X: Integer;
  Part: TRect;
  Chunk: string;
begin
  SetLength(Marks, Length(AText) + 1);
  if APattern <> '' then
    for Position in TAtlasItemPresentation.Highlights(APattern, AText) do
      if (Position >= 1) and (Position <= Length(AText)) then
        Marks[Position] := True;
  X := ARect.Left;
  Index := 1;
  while Index <= Length(AText) do
  begin
    Run := Index;
    while (Run < Length(AText)) and (Marks[Run + 1] = Marks[Index]) do
      Inc(Run);
    Chunk := Copy(AText, Index, Run - Index + 1);
    if Marks[Index] then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(FColors.Accent);
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := ToColor(FColors.Text);
    end;
    Part := Rect(X, ARect.Top, ARect.Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(Chunk), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(Chunk));
    Index := Run + 1;
  end;
  Canvas.Font.Style := [];
end;

procedure TAtlasGenerateWindow.DrawListRow(AVisibleRow: Integer);
var
  Row: TAtlasGenerateRow;
  Entry: TAtlasGenerateEntry;
  Bounds, Badge, Part: TRect;
  CommandText: string;
  NameWidth, BadgeWidth: Integer;
begin
  Row := FRows[FTop + AVisibleRow];
  Bounds := RowRect(AVisibleRow);
  Canvas.Brush.Style := bsClear;
  if Row.IsHeader then
  begin
    Canvas.Font.Size := Font.Size - 1;
    Part := Bounds;
    Inc(Part.Left, ScaleValue(8));
    DrawLabel(GroupCaption(Row.Group), Part, FColors.Muted, 0);
    Canvas.Font.Size := Font.Size;
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  Entry := FEntries[Row.Entry];
  if FTop + AVisibleRow = FSelected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.FillRect(Bounds);
    Canvas.Brush.Style := bsClear;
  end;
  InflateRect(Bounds, -ScaleValue(8), 0);
  // Ziffer 1–9 als Badge.
  BadgeWidth := ScaleValue(18);
  if Row.Digit > 0 then
  begin
    Badge := Rect(Bounds.Left, Bounds.Top + ScaleValue(4), Bounds.Left + BadgeWidth, Bounds.Bottom - ScaleValue(4));
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.AccentSoft);
    Canvas.Pen.Color := ToColor(FColors.Line);
    Canvas.RoundRect(Badge.Left, Badge.Top, Badge.Right, Badge.Bottom, ScaleValue(4), ScaleValue(4));
    Canvas.Brush.Style := bsClear;
    DrawLabel(IntToStr(Row.Digit), Badge, FColors.Text, DT_CENTER);
  end;
  Inc(Bounds.Left, BadgeWidth + ScaleValue(8));
  // /name gedimmt rechts.
  NameWidth := 0;
  CommandText := Entry.CommandName;
  if FOptions.ShowCommandNames and (CommandText <> '') then
  begin
    NameWidth := Canvas.TextWidth(CommandText);
    Part := Rect(Bounds.Right - NameWidth, Bounds.Top, Bounds.Right, Bounds.Bottom);
    DrawLabel(CommandText, Part, FColors.Muted, 0);
    Inc(NameWidth, ScaleValue(12));
  end;
  DrawHighlighted(EntryCaption(Entry), CaptionPattern(FPattern),
    Rect(Bounds.Left, Bounds.Top, Bounds.Right - NameWidth, Bounds.Bottom));
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasGenerateWindow.DrawStepRow(AVisibleRow: Integer);
var
  Index: Integer;
  Bounds, Box: TRect;
  Line: string;
begin
  Index := FTop + AVisibleRow;
  Bounds := RowRect(AVisibleRow);
  if Index = FSelected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.FillRect(Bounds);
  end;
  Canvas.Brush.Style := bsClear;
  InflateRect(Bounds, -ScaleValue(8), 0);
  if Index > High(FChoiceOrder) then
  begin
    // Eigene Eingabe.
    Line := TAtlasStrings.Fmt(TAtlasTextId.GenerateFreeText, [Trim(FText)]);
    DrawLabel(Line, Bounds, FColors.Text, DT_END_ELLIPSIS);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  if FStepEntry.Multi then
  begin
    Box := Rect(Bounds.Left, Bounds.Top + ScaleValue(5), Bounds.Left + ScaleValue(14), Bounds.Bottom - ScaleValue(5));
    Canvas.Pen.Color := ToColor(FColors.Muted);
    if FChecked[FChoiceOrder[Index]] then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(FColors.Accent);
    end;
    Canvas.Rectangle(Box);
    Canvas.Brush.Style := bsClear;
    Inc(Bounds.Left, ScaleValue(22));
  end;
  DrawHighlighted(FChoices[FChoiceOrder[Index]], FText, Bounds);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasGenerateWindow.Paint;
var
  Title, Input, Footer: TRect;
  Row: Integer;
  Reason, HintText: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  // Titel: „Erzeugen“ bzw. der gewählte Eintrag.
  Title := Rect(ScaleValue(12), ScaleValue(2), ClientWidth - ScaleValue(12), ScaleValue(2) + RowHeight);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  if FStep then
    DrawLabel(EntryCaption(FStepEntry), Title, FColors.Text, DT_END_ELLIPSIS)
  else
    DrawLabel(TAtlasStrings.Text(TAtlasTextId.GenerateTitle), Title, FColors.Text, 0);
  Canvas.Font.Style := [];
  if FStep and FOptions.ShowCommandNames then
    DrawLabel(FStepEntry.CommandName, Title, FColors.Muted, DT_RIGHT);
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, Title.Bottom + ScaleValue(2));
  Canvas.LineTo(ClientWidth, Title.Bottom + ScaleValue(2));
  if FStep then
  begin
    // Eingabefeld mit Akzentrahmen.
    Input := Rect(ScaleValue(6), Title.Bottom + ScaleValue(6), ClientWidth - ScaleValue(6),
      Title.Bottom + ScaleValue(6) + RowHeight);
    Canvas.Brush.Style := bsSolid;
    Canvas.Pen.Color := ToColor(FColors.Accent);
    Canvas.Brush.Color := ToColor(FColors.Gutter);
    Canvas.Rectangle(Input);
    InflateRect(Input, -ScaleValue(8), 0);
    Canvas.Brush.Style := bsClear;
    if FText <> '' then
      DrawLabel(FText + '|', Input, FColors.Text, DT_END_ELLIPSIS)
    else if FStepEntry.Example <> '' then
      DrawLabel(TAtlasStrings.Fmt(TAtlasTextId.GenerateExample, [FStepEntry.Example]), Input, FColors.Muted,
        DT_END_ELLIPSIS)
    else
      DrawLabel(TAtlasStrings.Text(TAtlasTextId.GenerateArgumentPrompt), Input, FColors.Muted, DT_END_ELLIPSIS);
  end;
  Canvas.Brush.Style := bsSolid;
  for Row := 0 to VisibleRows - 1 do
    if FTop + Row < RowCount then
    begin
      if FStep then
        DrawStepRow(Row)
      else
        DrawListRow(Row);
    end;
  // Leere Liste: Grund statt Zeilen.
  if RowCount = 0 then
  begin
    Canvas.Brush.Style := bsClear;
    if FStep then
      Reason := TAtlasStrings.Text(TAtlasTextId.GenerateNoChoices)
    else if (FPattern <> '') and (Length(FEntries) > 0) then
      Reason := TAtlasStrings.Text(TAtlasTextId.GenerateNoMatch)
    else
      Reason := TAtlasStrings.Text(TAtlasTextId.GenerateEmpty);
    DrawLabel(Reason, Rect(ScaleValue(12), ListTop, ClientWidth - ScaleValue(12), ListTop + RowHeight), FColors.Muted,
      0);
  end;
  // Fußzeile: Filter oder Hinweis.
  Footer := Rect(ScaleValue(12), ClientHeight - FooterHeight - ScaleValue(2), ClientWidth - ScaleValue(12),
    ClientHeight - ScaleValue(2));
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, Footer.Top);
  Canvas.LineTo(ClientWidth, Footer.Top);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Size := Font.Size - 1;
  if FStep and FStepEntry.Multi then
    HintText := TAtlasStrings.Text(TAtlasTextId.GenerateStepMultiHint)
  else if FStep then
    HintText := TAtlasStrings.Text(TAtlasTextId.GenerateStepHint)
  else if FPattern <> '' then
    HintText := TAtlasStrings.Fmt(TAtlasTextId.GenerateFilter, [FPattern])
  else
    HintText := TAtlasStrings.Text(TAtlasTextId.GenerateHint);
  DrawLabel(HintText, Footer, FColors.Muted, DT_END_ELLIPSIS);
  Canvas.Font.Size := Font.Size;
  // Rahmen des Fensters.
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

end.
