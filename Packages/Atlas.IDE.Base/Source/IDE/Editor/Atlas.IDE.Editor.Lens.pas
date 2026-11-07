unit Atlas.IDE.Editor.Lens;

// Gemeinsames der Code Lenses im Editor (Metriken #66, Testunit #189):
// - TAtlasLensPoll: Abruf je Datei und Textstand. Ein Zeitgeber fragt nach
//   einer Tipp-Pause den Server (nur, wenn er ohnehin läuft und nicht
//   indexiert, #874), ohne Änderung nur alle RefreshMs neu; scheitert die
//   Anfrage, erst nach RetryMs wieder.
//   Der Befehl läuft im Hintergrund (AskAsync über RunServerCommandAsync des
//   Managers, auf den StopSession wartet); die Antwort kommt über die
//   Nachrichtenschleife. Vorher wartete der Hauptthread bis zum Zeitlimit
//   (im Diagnose-Fenster testUnit und metrics mit zusammen über 50 s).
//   Während eine Antwort aussteht, fragt der Abruf nicht erneut.
// - TAtlasLensPill: Marke hinter dem Ende einer Zeile (plsEndPaint).
// Nur im Hauptthread.

interface

uses
  System.Types,
  System.JSON,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.LensAsk,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Style.Color;

type
  /// <summary>Befehl mit Argumenten (JSON-Array) im Hintergrund an den laufenden Server (RunServerCommandAsync des
  /// Managers); ADone im Hauptthread mit der Antwort oder nil (kein Server, Fehler, Zeitlimit). Den Wert gibt der
  /// Manager nach ADone frei.</summary>
  TAtlasLensCommandProc = reference to procedure(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<TJSONValue>);

  /// <summary>Serverbefehl eines Abrufs: Name, Argumente (JSON-Array) und Zeitlimit.</summary>
  TAtlasLensRequest = record
    Command: string;
    Arguments: string;
    TimeoutMs: Cardinal;
    class function Create(const ACommand, AArguments: string; ATimeoutMs: Cardinal): TAtlasLensRequest; static;
  end;

  TAtlasLensPoll = record
  public
    /// <summary>Datei und Text im oberen Editor beim letzten Takt.</summary>
    FileName: string;
    Text: string;
    ChangedAt: Cardinal;
    /// <summary>Stand der letzten Antwort; '' wenn keiner.</summary>
    FetchedFile: string;
    FetchedText: string;
    FetchedAt: Cardinal;
    RetryAt: Cardinal;
    /// <summary>Ausstehende Frage im Hintergrund.</summary>
    Asked: TAtlasLensAsk;
    /// <summary>Oberer Editor oder nil.</summary>
    class function TopView: IOTAEditView; static;
    /// <summary>Merkt den Text von AView; True, wenn er seit AQuietMs still steht, keine Antwort aussteht, keine
    /// Wartezeit offen ist und der Stand noch nicht oder vor mindestens ARefreshMs gefragt wurde.</summary>
    function Due(const AView: IOTAEditView; AQuietMs, ARefreshMs: Cardinal): Boolean;
    /// <summary>Gibt ASession (nil: nicht fragen) den gemerkten Text und schickt ARequest über ARun in den
    /// Hintergrund. AOnAnswer läuft im Hauptthread, gesichert über AFeature, mit der Antwort oder nil, nur solange
    /// der Abruf weder vergessen (Forget) noch geschlossen (Close) ist; dort Answered aufrufen. False: nicht
    /// gefragt (kein Server; Server indexiert oder Fehler beim Abgleich, dann mit Wartezeit ARetryMs).</summary>
    function AskAsync(ASession: TLspSession; const ARun: TAtlasLensCommandProc; AFeature: TAtlasFeature;
      const ARequest: TAtlasLensRequest; ARetryMs: Cardinal; const AOnAnswer: TProc<TJSONValue>): Boolean;
    /// <summary>Antwort von AskAsync eintragen: mit Antwort den gefragten Stand als geholt, ohne (Fehler,
    /// Zeitlimit, kein Server) Wartezeit ARetryMs. True mit Antwort.</summary>
    function Answered(AAnswer: TJSONValue; ARetryMs: Cardinal): Boolean;
    /// <summary>Argumente [uri] bzw. [uri, ALine] für die gemerkte Datei.</summary>
    function UriArguments: string;
    function UriLineArguments(ALine: Integer): string;
    /// <summary>Gemerkten Stand als gefragt eintragen.</summary>
    procedure Fetched;
    /// <summary>Gefragten Stand vergessen; eine ausstehende Antwort gilt nicht mehr.</summary>
    procedure Forget;
    /// <summary>Ende des Besitzers: Keine ausstehende Antwort erreicht ihn mehr.</summary>
    procedure Close;
  end;

  TAtlasLensPillStyle = record
    Tone: TAtlasColor;
    Back: TAtlasColor;
    /// <summary>Anteil von Tone an Rahmen und Füllung.</summary>
    Border: Double;
    Fill: Double;
    FontStyle: TFontStyles;
    class function Create(ATone, ABack: TAtlasColor; ABorder, AFill: Double; AFontStyle: TFontStyles):
      TAtlasLensPillStyle; static;
  end;

  TAtlasLensPill = record
  public
    /// <summary>Nach dem Zeichnen eine Zeile von AFileName mit Zeilenstand und Puffer?</summary>
    class function Ready(AStage: TPaintLineStage; ABeforeEvent: Boolean; const AContext: INTACodeEditorPaintContext;
      const AFileName: string): Boolean; static;
    /// <summary>Zelle drei Zeichen hinter dem Ende von ALine (Text der Zeile in AContext).</summary>
    class function CellAfter(const AContext: INTACodeEditorPaintContext; const ALine: string): TRect; static;
    /// <summary>Farbe unter AX, AY; ohne die Pinselfarbe.</summary>
    class function BackAt(ACanvas: TCanvas; AX, AY: Integer): TAtlasColor; static;
    /// <summary>Zeichnet AText als Marke ab AX in der Zeile ARect; Ergebnis: Rechteck der Marke.</summary>
    class function Paint(ACanvas: TCanvas; const ARect: TRect; AX: Integer; const AText: string;
      const AStyle: TAtlasLensPillStyle): TRect; static;
  end;

implementation

uses
  System.Math,
  Winapi.Windows,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot;

{ TAtlasLensPoll }

class function TAtlasLensPoll.TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

function TAtlasLensPoll.Due(const AView: IOTAEditView; AQuietMs, ARefreshMs: Cardinal): Boolean;
var
  mText: string;
  mMoment: Cardinal;
begin
  mText := TAtlasEditorSnapshots.Get(AView).Text;
  mMoment := GetTickCount;
  Result := SameText(FileName, AView.Buffer.FileName) and (Text = mText);
  if not Result then
  begin
    FileName := AView.Buffer.FileName;
    Text := mText;
    ChangedAt := mMoment;
    Exit;
  end;
  Result := not Asked.Waiting and (mMoment - ChangedAt >= AQuietMs) and (mMoment >= RetryAt);
  // Gleicher Stand schon gefragt: nur ab und zu neu.
  if Result and SameText(FetchedFile, FileName) and (FetchedText = Text) then
  begin
    Result := mMoment - FetchedAt >= ARefreshMs;
  end;
end;

{ TAtlasLensRequest }

class function TAtlasLensRequest.Create(const ACommand, AArguments: string; ATimeoutMs: Cardinal): TAtlasLensRequest;
begin
  Result.Command := ACommand;
  Result.Arguments := AArguments;
  Result.TimeoutMs := ATimeoutMs;
end;

{ TAtlasLensPoll }

function TAtlasLensPoll.AskAsync(ASession: TLspSession; const ARun: TAtlasLensCommandProc; AFeature: TAtlasFeature;
  const ARequest: TAtlasLensRequest; ARetryMs: Cardinal; const AOnAnswer: TProc<TJSONValue>): Boolean;
var
  mPercent: Integer;
begin
  Result := False;
  if (ASession = nil) or not Assigned(ARun) then
  begin
    Exit;
  end;
  // Server indexiert: Er antwortet erst danach (#874). Später noch einmal.
  if ASession.Indexing(mPercent) then
  begin
    RetryAt := GetTickCount + ARetryMs;
    Exit;
  end;
  try
    // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
    ASession.Sync(FileName, Text);
  except
    on ELspClientError do
    begin
      // Server weg oder beschäftigt: später noch einmal, ohne den Editor zu bremsen.
      RetryAt := GetTickCount + ARetryMs;
      Exit;
    end;
  end;
  Result := True;
  // Ohne Server ruft ARun den Rückruf sofort; Asked.Waiting ist dann schon wieder aus.
  ARun(ARequest.Command, ARequest.Arguments, ARequest.TimeoutMs, Asked.Start(FileName, Text, AFeature, AOnAnswer));
end;

function TAtlasLensPoll.Answered(AAnswer: TJSONValue; ARetryMs: Cardinal): Boolean;
begin
  Result := Asked.Answered(AAnswer);
  if not Result then
  begin
    // Server beschäftigt, weg oder zu alt (Befehl unbekannt): später noch einmal.
    RetryAt := GetTickCount + ARetryMs;
    Exit;
  end;
  FetchedFile := Asked.FileName;
  FetchedText := Asked.Text;
  FetchedAt := GetTickCount;
end;

function TAtlasLensPoll.UriArguments: string;
var
  mValues: TJSONArray;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(FileName));
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

function TAtlasLensPoll.UriLineArguments(ALine: Integer): string;
var
  mValues: TJSONArray;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(FileName));
    mValues.Add(ALine);
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

procedure TAtlasLensPoll.Fetched;
begin
  FetchedFile := FileName;
  FetchedText := Text;
  FetchedAt := GetTickCount;
end;

procedure TAtlasLensPoll.Forget;
begin
  FetchedText := '';
  FetchedFile := '';
  Asked.Drop;
end;

procedure TAtlasLensPoll.Close;
begin
  Asked.Close;
end;

{ TAtlasLensPillStyle }

class function TAtlasLensPillStyle.Create(ATone, ABack: TAtlasColor; ABorder, AFill: Double;
  AFontStyle: TFontStyles): TAtlasLensPillStyle;
begin
  Result.Tone := ATone;
  Result.Back := ABack;
  Result.Border := ABorder;
  Result.Fill := AFill;
  Result.FontStyle := AFontStyle;
end;

{ TAtlasLensPill }

class function TAtlasLensPill.Ready(AStage: TPaintLineStage; ABeforeEvent: Boolean;
  const AContext: INTACodeEditorPaintContext; const AFileName: string): Boolean;
begin
  Result := not ABeforeEvent and (AStage = plsEndPaint) and (AContext <> nil) and
    SameText(AContext.FileName, AFileName);
  Result := Result and (AContext.LineState <> nil) and (AContext.EditView <> nil) and
    (AContext.EditView.Buffer <> nil);
end;

class function TAtlasLensPill.CellAfter(const AContext: INTACodeEditorPaintContext; const ALine: string): TRect;
var
  mColumn: Integer;
begin
  mColumn := Length(TrimRight(TAtlasPairs.DisplayLine(ALine,
    TAtlasEditorBuffer.TabWidth(AContext.EditView.Buffer)))) + 1;
  Result := AContext.EditorState.GetCharacterPosPx(mColumn + 3, AContext.EditorLineNum);
end;

class function TAtlasLensPill.BackAt(ACanvas: TCanvas; AX, AY: Integer): TAtlasColor;
var
  mSample: COLORREF;
begin
  mSample := GetPixel(ACanvas.Handle, AX, AY);
  if mSample = CLR_INVALID then
  begin
    Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end
  else
  begin
    Result := TAtlasColor(mSample);
  end;
end;

class function TAtlasLensPill.Paint(ACanvas: TCanvas; const ARect: TRect; AX: Integer; const AText: string;
  const AStyle: TAtlasLensPillStyle): TRect;
var
  mOldFont: TFont;
  mOldBrush: TBrush;
  mOldPen: TPen;
  mHeight, mTop: Integer;
begin
  mOldFont := TFont.Create;
  mOldBrush := TBrush.Create;
  mOldPen := TPen.Create;
  try
    mOldFont.Assign(ACanvas.Font);
    mOldBrush.Assign(ACanvas.Brush);
    mOldPen.Assign(ACanvas.Pen);
    ACanvas.Font.Size := Max(6, ACanvas.Font.Size - 1);
    ACanvas.Font.Style := AStyle.FontStyle;
    ACanvas.Font.Color := TColor(TAtlasColorMath.Mix(AStyle.Tone, AStyle.Back, 0.85));
    ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(AStyle.Tone, AStyle.Back, AStyle.Border));
    ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(AStyle.Tone, AStyle.Back, AStyle.Fill));
    mHeight := ACanvas.TextHeight('Xg');
    mTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mHeight - 2) div 2);
    Result := TRect.Create(AX, mTop, AX + ACanvas.TextWidth(AText) + 10, mTop + mHeight + 2);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.RoundRect(Result.Left, Result.Top, Result.Right, Result.Bottom, 6, 6);
    ACanvas.Brush.Style := bsClear;
    ACanvas.TextOut(Result.Left + 5, Result.Top + 1, AText);
  finally
    ACanvas.Font.Assign(mOldFont);
    ACanvas.Brush.Assign(mOldBrush);
    ACanvas.Pen.Assign(mOldPen);
    mOldPen.Free;
    mOldBrush.Free;
    mOldFont.Free;
  end;
end;

end.
