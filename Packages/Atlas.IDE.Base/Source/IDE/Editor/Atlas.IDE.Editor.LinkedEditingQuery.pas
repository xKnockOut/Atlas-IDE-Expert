unit Atlas.IDE.Editor.LinkedEditingQuery;

// Anfrage für „Bezeichner live mitziehen“ (#658): Ruht der Cursor auf einem
// Bezeichner (IdleTicks Takte ohne Bewegung), fragt Atlas im Hintergrund den
// Server nach den Vorkommen (linkedEditingRange mit "atlasLocals"). Die
// Antwort kommt über ADeliver im Hauptthread zurück; nur die jüngste zählt
// und gilt für den Text, mit dem gefragt wurde. Laufende Anfragen halten die
// Sitzung als rohen Zeiger: Der Destruktor wartet sie ab. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LinkedEditing,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  TAtlasLinkedSessionFunc = reference to function: TLspSession;

  /// <summary>Antwort im Hauptthread übergeben; ARequest: Nummer der Anfrage.</summary>
  TAtlasLinkedDeliverProc = reference to procedure(ARequest: Integer; const AFileName, AText: string;
    const ARanges: TAtlasLinkedRanges; const AConflicts: TAtlasLinkedConflicts);

  /// <summary>Letzte Antwort des Servers und der Text, für den sie gilt.</summary>
  TAtlasLinkedCandidate = record
    Valid: Boolean;
    FileName: string;
    Text: string;
    Ranges: TAtlasLinkedRanges;
    Conflicts: TAtlasLinkedConflicts;
  end;

  TAtlasIdeLinkedEditingQuery = class
  private const
    /// <summary>So viele Takte ohne Bewegung, bevor Atlas den Server fragt.</summary>
    cIdleTicks = 2;
  private
    FSession: TAtlasLinkedSessionFunc;
    FDeliver: TAtlasLinkedDeliverProc;
    FWorkers: TAtlasWorkerSlot;
    FRequest: Integer;
    FIdleKey: string;
    FIdleCount: Integer;
    FAskedKey: string;
    FCandidate: TAtlasLinkedCandidate;
    /// <summary>Deckt die letzte Antwort die Stelle noch ab?</summary>
    function Covers(const AFileName: string; ALine, ACharacter: Integer): Boolean;
    procedure Ask(const AView: IOTAEditView; ALine, ACharacter: Integer);
  public
    /// <summary>ASession: laufende Sitzung oder nil; ADeliver: Antwort übergeben (prüft selbst, ob die Funktion
    /// noch läuft, und ruft dann Accept).</summary>
    constructor Create(const ASession: TAtlasLinkedSessionFunc; const ADeliver: TAtlasLinkedDeliverProc);
    destructor Destroy; override;
    /// <summary>Cursor als Zeile und Zeichenindex (0-basiert).</summary>
    class procedure ReadCaret(const AView: IOTAEditView; out ALine, ACharacter: Integer); static;
    /// <summary>Nach jedem Takt ohne Sitzung: ruht der Cursor, den Server fragen.</summary>
    procedure Watch(const AView: IOTAEditView);
    /// <summary>Antwort übernehmen, wenn sie zur jüngsten Anfrage gehört.</summary>
    procedure Accept(ARequest: Integer; const AFileName, AText: string; const ARanges: TAtlasLinkedRanges;
      const AConflicts: TAtlasLinkedConflicts);
    /// <summary>Letzte Antwort verwerfen.</summary>
    procedure Drop;
    /// <summary>Text geändert: Antwort verwerfen, beim nächsten Ruhen neu fragen.</summary>
    procedure Forget;
    property Candidate: TAtlasLinkedCandidate read FCandidate;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Atlas.Text.Chars,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.EditorBuffer;

/// <summary>Steht an oder vor ACharacter ein Zeichen eines Bezeichners?</summary>
function NearIdentifier(const ALine: string; ACharacter: Integer): Boolean;
begin
  Result := ((ACharacter < Length(ALine)) and TTextChars.IsIdentChar(ALine[ACharacter + 1])) or
    ((ACharacter > 0) and (ACharacter <= Length(ALine)) and TTextChars.IsIdentChar(ALine[ACharacter]));
end;

{ TAtlasIdeLinkedEditingQuery }

constructor TAtlasIdeLinkedEditingQuery.Create(const ASession: TAtlasLinkedSessionFunc;
  const ADeliver: TAtlasLinkedDeliverProc);
begin
  inherited Create;
  FSession := ASession;
  FDeliver := ADeliver;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasIdeLinkedEditingQuery.Destroy;
begin
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: bis zu ihrem Ende abwarten (sie haben eine eigene
  // Zeitgrenze), nicht nur bis cStopMs.
  if FWorkers <> nil then
  begin
    FWorkers.Stop(TAtlasWorkerSlot.cWaitForever);
  end;
  FreeAndNil(FWorkers);
  FCandidate := Default(TAtlasLinkedCandidate);
  inherited Destroy;
end;

class procedure TAtlasIdeLinkedEditingQuery.ReadCaret(const AView: IOTAEditView; out ALine, ACharacter: Integer);
var
  mCursor: TOTAEditPos;
  mLineText: string;
begin
  mCursor := AView.CursorPos;
  ALine := Max(0, mCursor.Line - 1);
  mLineText := TAtlasEditorBuffer.LineText(AView, ALine + 1);
  ACharacter := Min(TLspSession.ColumnToIndex(mLineText, mCursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)),
    Length(mLineText));
end;

function TAtlasIdeLinkedEditingQuery.Covers(const AFileName: string; ALine, ACharacter: Integer): Boolean;
begin
  Result := FCandidate.Valid and SameText(FCandidate.FileName, AFileName) and
    (TAtlasLinkedEditing.IndexAt(FCandidate.Ranges, ALine, ACharacter) >= 0);
end;

procedure TAtlasIdeLinkedEditingQuery.Watch(const AView: IOTAEditView);
var
  mLine, mCharacter: Integer;
  mLineText, mKey: string;
begin
  if (AView = nil) or (AView.Buffer = nil) or AView.Buffer.IsReadOnly then
  begin
    Exit;
  end;
  ReadCaret(AView, mLine, mCharacter);
  mLineText := TAtlasEditorBuffer.LineText(AView, mLine + 1);
  mKey := Format('%s|%d|%d|', [AView.Buffer.FileName, mLine, mCharacter]) + mLineText;
  if mKey <> FIdleKey then
  begin
    FIdleKey := mKey;
    FIdleCount := 0;
    Exit;
  end;
  Inc(FIdleCount);
  // Die letzte Antwort deckt den Cursor noch ab; jede Änderung am Text verwirft sie (Forget).
  if (FIdleCount = cIdleTicks) and (mKey <> FAskedKey) and NearIdentifier(mLineText, mCharacter) and
    not Covers(AView.Buffer.FileName, mLine, mCharacter) then
  begin
    FAskedKey := mKey;
    FCandidate.Valid := False;
    Ask(AView, mLine, mCharacter);
  end;
end;

procedure TAtlasIdeLinkedEditingQuery.Ask(const AView: IOTAEditView; ALine, ACharacter: Integer);
var
  mSession: TLspSession;
  mFileName, mText: string;
  mRequest: Integer;
  mDeliver: TAtlasLinkedDeliverProc;
  mWorker: TThread;
begin
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mFileName := AView.Buffer.FileName;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mSession.Sync(mFileName, mText);
  FWorkers.Prune;
  Inc(FRequest);
  mRequest := FRequest;
  mDeliver := FDeliver;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mAnswer: TJSONValue;
      mRanges: TAtlasLinkedRanges;
      mConflicts: TAtlasLinkedConflicts;
    begin
      mRanges := nil;
      mConflicts := nil;
      try
        mAnswer := mSession.LinkedLocals(mFileName, ALine, ACharacter);
        try
          TAtlasLinkedEditing.FromJson(mAnswer, mRanges, mConflicts);
        finally
          mAnswer.Free;
        end;
      except
        // Server langsam oder weg: keine Sitzung, die Taste geht an die IDE.
        mRanges := nil;
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.LinkedEditing,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.LinkedEditing,
            procedure
            begin
              mDeliver(mRequest, mFileName, mText, mRanges, mConflicts);
            end);
        end);
    end);
  FWorkers.Start(mWorker);
end;

procedure TAtlasIdeLinkedEditingQuery.Accept(ARequest: Integer; const AFileName, AText: string;
  const ARanges: TAtlasLinkedRanges; const AConflicts: TAtlasLinkedConflicts);
begin
  // Nur die jüngste Antwort zählt.
  if ARequest <> FRequest then
  begin
    Exit;
  end;
  FCandidate.Valid := Length(ARanges) > 0;
  FCandidate.FileName := AFileName;
  FCandidate.Text := AText;
  FCandidate.Ranges := ARanges;
  FCandidate.Conflicts := AConflicts;
end;

procedure TAtlasIdeLinkedEditingQuery.Drop;
begin
  FCandidate.Valid := False;
end;

procedure TAtlasIdeLinkedEditingQuery.Forget;
begin
  FCandidate.Valid := False;
  FAskedKey := '';
end;

end.
