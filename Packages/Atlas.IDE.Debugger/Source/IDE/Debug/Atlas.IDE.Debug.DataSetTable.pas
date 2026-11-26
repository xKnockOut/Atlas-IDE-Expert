unit Atlas.IDE.Debug.DataSetTable;

// Datenmenge als Tabelle (#3024) in der IDE: Knopf „Tabelle …“ im Fenster
// „Auswerten“ öffnet TAtlasDebugDataSetForm für den gewählten Ausdruck.
// - Lesen: Probe und Seiten über den Kern (Atlas.Core.Debug.DataSetTable) mit
//   den Auswertungen von TAtlasIdeDebugEvaluator; je Takt ein Schritt
//   (eine Zeile bzw. ein Block der Hilfs-Unit), die IDE bleibt bedienbar.
// - Standardmäßig nur anzeigen: Ohne die Unit Atlas.Debug.DataSets im Programm
//   liest Atlas nur den aktuellen Datensatz; mehr nur, wenn der Cursor wandern
//   darf (debug.evaluateWindow.dataSetTable.moveCursor: never, ask = Hinweis
//   mit Knopf, always). Die Zustimmung gilt bis zum nächsten Halt.
// - „Zum Datensatz springen“ und „Wert ändern …“ fragen immer nach; danach
//   wertet das Fenster „Auswerten“ neu aus (AOnChanged) und die Tabelle liest
//   neu.
// - Bei jedem Halt liest die Tabelle im nächsten Takt neu; läuft das Programm,
//   bricht sie das Lesen ab und graut aus.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.DataSetTable,
  Atlas.IDE.Debug.StopView,
  Atlas.UI.Debug.DataSetTable;

type
  TAtlasIdeDebugDataSetTable = class(TAtlasIdeDebugStopView)
  public const
    cTickMs = 10;
    /// <summary>Zeit je Schritt und für die Probe (Feldnamen, Hilfs-Unit).</summary>
    cStepBudgetMs = 3000;
    cProbeBudgetMs = 10000;
  private
    FOnChanged: TProc;
    FForm: TAtlasDebugDataSetForm;
    FExpression: string;
    FFileName: string;
    FLine: Integer;
    FInfo: TAtlasDataSetInfo;
    FReader: TAtlasDataSetReader;
    FRows: TArray<TAtlasDataSetRow>;
    FConsented: Boolean;
    FReloadPending: Boolean;
    procedure FormClosed(Sender: TObject);
    procedure WireForm;
    procedure Reload;
    procedure ShowInfo;
    /// <summary>Seite ab AFirst lesen (Weg nach Einstellung und Zustimmung).</summary>
    procedure Load(AFirst: Int64);
    procedure ReaderDone;
    procedure StopReading;
    procedure ShowConsentFor(AWay: TAtlasDataSetWay);
    function StatusText(AWay: TAtlasDataSetWay; AAtEnd: Boolean): string;
    procedure GoToRecord(ARecNo: Int64);
    procedure EditValue(ARecNo: Int64; AField: Integer);
    function PageSize: Integer;
    function MoveCursor: TAtlasDataSetMoveCursor;
  protected
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    procedure Advance; override;
  public
    /// <summary>AOnChanged: nach Springen oder Ändern (Fenster „Auswerten“ neu auswerten).</summary>
    constructor Create(const AOnChanged: TProc);
    destructor Destroy; override;
    /// <summary>Tabelle für AExpression am Ausführungspunkt AFileName, ALine (1-basiert) öffnen bzw. neu zeigen.
    /// </summary>
    procedure Show(const AExpression, AFileName: string; ALine: Integer);
    /// <summary>Fenster schließen (Einstellung aus, Entladen).</summary>
    procedure CloseForm;
    property Form: TAtlasDebugDataSetForm read FForm;
  end;

implementation

uses
  System.UITypes,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.Core.Debug.Contract,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Evaluator,
  Atlas.UI.Debug.DataSetTable.Strings;

function StillStopped: Boolean;
begin
  Result := TAtlasIdeDebugSession.StoppedThread <> nil;
end;

function Count(AValue: Int64): string;
begin
  Result := '?';
  if AValue >= 0 then
  begin
    Result := IntToStr(AValue);
  end;
end;

function Confirmed(const AQuestion: string): Boolean;
begin
  Result := MessageDlg(AQuestion, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

{ TAtlasIdeDebugDataSetTable }

constructor TAtlasIdeDebugDataSetTable.Create(const AOnChanged: TProc);
begin
  inherited Create;
  FOnChanged := AOnChanged;
  CreateTimer(cTickMs);
  Listen;
end;

destructor TAtlasIdeDebugDataSetTable.Destroy;
begin
  FreeAndNil(FReader);
  CloseForm;
  FOnChanged := nil;
  inherited Destroy;
end;

procedure TAtlasIdeDebugDataSetTable.CloseForm;
var
  mForm: TAtlasDebugDataSetForm;
begin
  StopReading;
  mForm := FForm;
  FForm := nil;
  if mForm <> nil then
  begin
    // Sofort freigeben: Beim Entladen darf keine eingereihte Freigabe übrig bleiben.
    mForm.OnClosed := nil;
    mForm.Free;
  end;
end;

procedure TAtlasIdeDebugDataSetTable.FormClosed(Sender: TObject);
begin
  // Das Fenster gibt sich selbst frei (caFree).
  FForm := nil;
  StopReading;
end;

function TAtlasIdeDebugDataSetTable.PageSize: Integer;
begin
  Result := TAtlasIdeSettings.Current.DebugEvaluateDataSetTablePageSize;
end;

function TAtlasIdeDebugDataSetTable.MoveCursor: TAtlasDataSetMoveCursor;
begin
  Result := TAtlasDataSetTable.MoveCursorOf(TAtlasIdeSettings.Current.DebugEvaluateDataSetTableMoveCursor);
end;

procedure TAtlasIdeDebugDataSetTable.WireForm;
begin
  FForm.OnClosed := FormClosed;
  FForm.OnLoadMore :=
    procedure
    begin
      if FRows <> nil then
      begin
        Load(FRows[High(FRows)].RecNo + 1);
      end;
    end;
  FForm.OnConsent :=
    procedure(AMove: Boolean)
    begin
      FConsented := AMove;
      if AMove then
      begin
        FRows := nil;
        Load(1);
      end;
    end;
  FForm.OnGoTo :=
    procedure(ARecNo: Int64)
    begin
      GoToRecord(ARecNo);
    end;
  FForm.OnEdit :=
    procedure(ARecNo: Int64; AField: Integer)
    begin
      EditValue(ARecNo, AField);
    end;
  FForm.OnRefresh :=
    procedure
    begin
      Reload;
    end;
  FForm.OnCancel :=
    procedure
    begin
      if FReader <> nil then
      begin
        FReader.Cancel;
      end;
    end;
end;

procedure TAtlasIdeDebugDataSetTable.Show(const AExpression, AFileName: string; ALine: Integer);
begin
  if Trim(AExpression) = '' then
  begin
    Exit;
  end;
  StopReading;
  FExpression := Trim(AExpression);
  FFileName := AFileName;
  FLine := ALine;
  FConsented := False;
  if FForm = nil then
  begin
    FForm := TAtlasDebugDataSetForm.CreateTable(Application);
    WireForm;
  end;
  FForm.SetPageSize(PageSize);
  FForm.ShowHeader(FExpression, TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Reading));
  FForm.Show;
  Reload;
end;

procedure TAtlasIdeDebugDataSetTable.StopReading;
begin
  FReloadPending := False;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FreeAndNil(FReader);
  if FForm <> nil then
  begin
    FForm.SetReading(False);
  end;
end;

procedure TAtlasIdeDebugDataSetTable.ShowInfo;
var
  mHeader: string;
begin
  if FInfo.RecNo > 0 then
  begin
    mHeader := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.Header, [FExpression, FInfo.State, FInfo.RecNo,
      Count(FInfo.RecordCount)]);
  end
  else
  begin
    mHeader := TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.HeaderUnknownPosition,
      [FExpression, FInfo.State]);
  end;
  FForm.ShowHeader(FExpression, mHeader);
  FForm.ShowHint(not FInfo.HasHelper);
end;

procedure TAtlasIdeDebugDataSetTable.Reload;
begin
  StopReading;
  if FForm = nil then
  begin
    Exit;
  end;
  if not StillStopped then
  begin
    FForm.MarkUnavailable(TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Running));
    Exit;
  end;
  FRows := nil;
  FInfo := TAtlasDataSetTable.Probe(FExpression, TAtlasIdeDebugEvaluator.Context(cProbeBudgetMs));
  if not FInfo.Valid then
  begin
    FForm.SetColumns(nil);
    FForm.SetRows(nil, 0, False, False);
    FForm.ShowConsent('', 0);
    FForm.ShowHeader(FExpression, TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.NotADataSet,
      [FExpression, FInfo.Problem]));
    FForm.SetStatus('');
    Exit;
  end;
  ShowInfo;
  FForm.SetColumns(FInfo.Names);
  Load(1);
end;

procedure TAtlasIdeDebugDataSetTable.ShowConsentFor(AWay: TAtlasDataSetWay);
var
  mReason: string;
begin
  FForm.ShowConsent('', 0);
  if AWay <> TAtlasDataSetWay.CurrentOnly then
  begin
    Exit;
  end;
  if FInfo.CanMoveCursor and (MoveCursor = TAtlasDataSetMoveCursor.Ask) and not FConsented then
  begin
    FForm.ShowConsent(TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.ConsentNote, [FExpression,
      FInfo.RecNo]), PageSize);
    Exit;
  end;
  if FInfo.CanMoveCursor then
  begin
    Exit;
  end;
  // Warum nicht mehr geht: Bearbeiten, unidirektional oder unbekannte Position.
  mReason := FInfo.State;
  if FInfo.Unidirectional then
  begin
    mReason := 'IsUniDirectional';
  end
  else if not FInfo.Editing then
  begin
    mReason := 'RecNo = ' + IntToStr(FInfo.RecNo);
  end;
  FForm.SetStatus(TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.NoMoveNote, [mReason]));
end;

procedure TAtlasIdeDebugDataSetTable.Load(AFirst: Int64);
var
  mWay: TAtlasDataSetWay;
begin
  StopReading;
  if (FForm = nil) or not FInfo.Valid or not StillStopped then
  begin
    Exit;
  end;
  mWay := TAtlasDataSetTable.WayFor(FInfo, MoveCursor, FConsented);
  ShowConsentFor(mWay);
  if mWay = TAtlasDataSetWay.CurrentOnly then
  begin
    FRows := nil;
  end;
  FReader := TAtlasDataSetReader.Create(FExpression, FInfo, mWay, AFirst, PageSize);
  FForm.SetReading(True);
  if mWay <> TAtlasDataSetWay.CurrentOnly then
  begin
    FForm.SetStatus(TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Reading));
  end;
  FTimer.Enabled := True;
end;

function TAtlasIdeDebugDataSetTable.StatusText(AWay: TAtlasDataSetWay; AAtEnd: Boolean): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if FRows <> nil then
  begin
    mParts := mParts + [TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.StatusRows,
      [FRows[0].RecNo, FRows[High(FRows)].RecNo, Count(FInfo.RecordCount)])];
  end;
  case AWay of
    TAtlasDataSetWay.Helper:
      mParts := mParts + [TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.StatusHelper)];
    TAtlasDataSetWay.Cursor:
      mParts := mParts + [TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.StatusCursor, [FInfo.RecNo])];
  else
    mParts := mParts + [TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.StatusCurrentOnly)];
  end;
  if AAtEnd and (AWay <> TAtlasDataSetWay.CurrentOnly) then
  begin
    mParts := mParts + [TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.StatusAtEnd)];
  end;
  Result := string.Join(' · ', mParts);
end;

procedure TAtlasIdeDebugDataSetTable.ReaderDone;
var
  mReader: TAtlasDataSetReader;
  mStatus: string;
begin
  mReader := FReader;
  FReader := nil;
  FTimer.Enabled := False;
  try
    FRows := FRows + mReader.Rows;
    if FForm = nil then
    begin
      Exit;
    end;
    FForm.SetReading(False);
    FForm.SetRows(FRows, FInfo.RecNo, (mReader.Way <> TAtlasDataSetWay.CurrentOnly) and not mReader.AtEnd,
      FInfo.CanMoveCursor);
    // Den Grund aus ShowConsentFor (kein Cursorweg möglich) stehen lassen.
    if (mReader.Way = TAtlasDataSetWay.CurrentOnly) and not FInfo.CanMoveCursor and not FInfo.HasHelper then
    begin
      Exit;
    end;
    mStatus := StatusText(mReader.Way, mReader.AtEnd);
    if mReader.Problem <> '' then
    begin
      mStatus := mStatus + ' · ' + TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.ReadFailed,
        [mReader.Problem]);
    end;
    FForm.SetStatus(mStatus);
  finally
    mReader.Free;
  end;
end;

procedure TAtlasIdeDebugDataSetTable.Advance;
begin
  if FReloadPending then
  begin
    FReloadPending := False;
    Reload;
    Exit;
  end;
  if FReader = nil then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  if not StillStopped then
  begin
    StopReading;
    Exit;
  end;
  if FReader.Step(TAtlasIdeDebugEvaluator.Context(cStepBudgetMs)) then
  begin
    ReaderDone;
  end;
end;

procedure TAtlasIdeDebugDataSetTable.SessionStopped;
begin
  StopReading;
  if FForm = nil then
  begin
    Exit;
  end;
  // Neuer Halt: Zustimmung gilt nur für den vorigen; gelesen wird im nächsten Takt (nicht im Notifier).
  FConsented := False;
  FReloadPending := True;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDebugDataSetTable.SessionResumed;
begin
  StopReading;
  if FForm <> nil then
  begin
    FForm.MarkUnavailable(TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.Running));
  end;
end;

procedure TAtlasIdeDebugDataSetTable.SessionEnded;
begin
  SessionResumed;
end;

procedure TAtlasIdeDebugDataSetTable.GoToRecord(ARecNo: Int64);
var
  mMessage: string;
begin
  if (FForm = nil) or not StillStopped or (FReader <> nil) or
    not Confirmed(TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.GoToConfirm, [FExpression, ARecNo])) then
  begin
    Exit;
  end;
  if not TAtlasDataSetTable.MoveTo(FExpression, FInfo, ARecNo, TAtlasIdeDebugEvaluator.Context(cStepBudgetMs),
    mMessage) then
  begin
    MessageDlg(TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.GoToFailed, [mMessage]), mtWarning, [mbOK], 0);
  end;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
  Reload;
end;

procedure TAtlasIdeDebugDataSetTable.EditValue(ARecNo: Int64; AField: Integer);
var
  mValue, mMessage: string;
  mRow: TAtlasDataSetRow;
  mModify: TAtlasDataSetModify;
begin
  if (FForm = nil) or not StillStopped or (FReader <> nil) or (AField < 0) or (AField >= FInfo.FieldCount) then
  begin
    Exit;
  end;
  mValue := '';
  for mRow in FRows do
  begin
    if (mRow.RecNo = ARecNo) and (AField < Length(mRow.Cells)) then
    begin
      mValue := mRow.Cells[AField];
    end;
  end;
  if not InputQuery(TAtlasDataSetTableStrings.Text(TAtlasDataSetTableTextId.EditTitle),
    TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.EditPrompt, [FInfo.Names[AField], ARecNo]), mValue) or
    not Confirmed(TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.EditConfirm, [FExpression,
    FInfo.Names[AField], ARecNo, mValue])) or not StillStopped then
  begin
    Exit;
  end;
  mModify :=
    function(const AExpression, ANewValue: string; out AResult: string): Boolean
    begin
      Result := TAtlasIdeDebugSession.NewEvaluator.Modify(AExpression, FFileName, FLine, ANewValue, AResult);
    end;
  if not TAtlasDataSetTable.EditCell(FExpression, FInfo, ARecNo, AField, mValue,
    TAtlasIdeDebugEvaluator.Context(cStepBudgetMs), mModify, mMessage) then
  begin
    MessageDlg(TAtlasDataSetTableStrings.Fmt(TAtlasDataSetTableTextId.EditFailed, [mMessage]), mtWarning, [mbOK], 0);
  end;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
  Reload;
end;

end.
