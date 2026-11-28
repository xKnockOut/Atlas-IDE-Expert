unit Atlas.Core.Debug.DataSetTable;

// Datenmenge als Tabelle (#3024), Teil ohne VCL und Open Tools API. Liest ein
// TDataSet im angehaltenen Programm über Auswertungen (Rückruf Eval wie bei
// den Visualisierern, #835):
// - Probe: Zustand, RecNo, RecordCount, unidirektional, Feldnamen und -typen;
//   dazu, ob das Programm die optionale Unit Atlas.Debug.DataSets
//   (Setup/Vorlagen) enthält.
// - Drei Wege, eine Seite zu lesen:
//   Helper: AtlasDataSetRows aus der Unit im Programm liefert viele Zeilen in
//     einem Aufruf, ohne dass der Cursor sichtbar wandert;
//   Cursor: Atlas bewegt den Cursor mit MoveBy, liest je Zeile alle Felder in
//     einem Ausdruck und kehrt mit MoveBy zurück (Ereignisse wie AfterScroll
//     laufen; nur nach Zustimmung, debug.evaluateWindow.dataSetTable.moveCursor);
//   CurrentOnly: nur der aktuelle Datensatz, ohne Bewegung.
// - TAtlasDataSetReader liest eine Seite Schritt für Schritt (je Schritt eine
//   Zeile bzw. ein Block der Hilfs-Unit), damit die IDE dazwischen bedienbar
//   bleibt und der Benutzer abbrechen kann. Abbrechen auf dem Cursorweg stellt
//   den Cursor immer zurück.
// - Springen (MoveTo) und Ändern einer Zelle (EditCell) für die Knöpfe des
//   Fensters; beides nur nach Rückfrage in der Oberfläche.
// - Kopieren als CSV und JSON.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Visualizers;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wie eine Seite gelesen wird.</summary>
  TAtlasDataSetWay = (CurrentOnly, Helper, Cursor);
  /// <summary>debug.evaluateWindow.dataSetTable.moveCursor: Cursor zum Lesen bewegen.</summary>
  TAtlasDataSetMoveCursor = (Never, Ask, Always);
  {$SCOPEDENUMS OFF}

  /// <summary>Setzt AExpression im angehaltenen Programm auf ANewValue (IOTAThread.Modify). AResult: neuer Wert bzw.
  /// Meldung.</summary>
  TAtlasDataSetModify = reference to function(const AExpression, ANewValue: string; out AResult: string): Boolean;

  TAtlasDataSetInfo = record
    /// <summary>Aktive Datenmenge mit Feldern.</summary>
    Valid: Boolean;
    State: string;
    /// <summary>Aktueller Datensatz ab 1; 0 oder kleiner: unbekannt.</summary>
    RecNo: Int64;
    /// <summary>-1: unbekannt.</summary>
    RecordCount: Int64;
    Unidirectional: Boolean;
    /// <summary>AtlasDataSetRows ist im Programm aufrufbar; HelperPrefix ist ihr Präfix ('' oder Unitname mit Punkt).
    /// </summary>
    HasHelper: Boolean;
    HelperPrefix: string;
    Names: TArray<string>;
    Types: TArray<string>;
    /// <summary>Grund, wenn Valid False ist (Text des Debuggers).</summary>
    Problem: string;
    /// <summary>dsEdit, dsInsert und andere Bearbeitungszustände: Bewegen würde speichern.</summary>
    function Editing: Boolean;
    /// <summary>dsEdit/dsInsert auf ARecNo: Ändern schreibt nur in den Bearbeitungspuffer (ohne Edit, Post, Bewegen);
    /// speichern bleibt Sache des Programms.</summary>
    function EditsInBuffer(ARecNo: Int64): Boolean;
    /// <summary>Cursor darf zum Lesen bewegt werden (bekannte Position, nicht unidirektional, nicht im Bearbeiten).
    /// </summary>
    function CanMoveCursor: Boolean;
    function FieldCount: Integer;
  end;

  /// <summary>Zelle zum Ändern: Datensatz RecNo (ab 1), Feld Field (ab 0), neuer Wert Value.</summary>
  TAtlasDataSetCell = record
    RecNo: Int64;
    Field: Integer;
    Value: string;
    class function Create(ARecNo: Int64; AField: Integer; const AValue: string): TAtlasDataSetCell; static;
  end;

  TAtlasDataSetRow = record
    /// <summary>Nummer des Datensatzes ab 1.</summary>
    RecNo: Int64;
    Cells: TArray<string>;
    /// <summary>Je Zelle: Wert ist NULL.</summary>
    Nulls: TArray<Boolean>;
  end;

  TAtlasDataSetTable = class
  public const
    /// <summary>Unit der Hilfsfunktionen im Programm des Benutzers (Setup/Vorlagen/Atlas.Debug.DataSets.pas).</summary>
    cHelperUnit = 'Atlas.Debug.DataSets';
    cHelperRows = 'AtlasDataSetRows';
    cHelperSetValue = 'AtlasDataSetSetValue';
    /// <summary>Zeichen je Antwort der Hilfs-Unit: Der Debugger liefert höchstens 4096 Zeichen, die Ausgabe als
    /// Stringliteral braucht Platz für Anführungszeichen und #-Zeichen.</summary>
    cHelperMaxChars = 2000;
  public
    /// <summary>Datenmenge AExpression untersuchen.</summary>
    class function Probe(const AExpression: string; const AContext: TAtlasVisualizerContext): TAtlasDataSetInfo;
      static;
    /// <summary>Weg für eine Seite: Hilfs-Unit, sonst Cursor (wenn erlaubt und AConsented bzw. Always), sonst nur
    /// der aktuelle Datensatz.</summary>
    class function WayFor(const AInfo: TAtlasDataSetInfo; AMove: TAtlasDataSetMoveCursor;
      AConsented: Boolean): TAtlasDataSetWay; static;
    /// <summary>Ergebnis des Debuggers als Text: Stringliteral ('a'#9'b', #$1F) zerlegt, sonst unverändert.</summary>
    class function Decode(const AEvalText: string): string; static;
    /// <summary>Pascal-Stringliteral für AText (Steuerzeichen als #n).</summary>
    class function Literal(const AText: string): string; static;
    /// <summary>Alle Felder des aktuellen Datensatzes in einem Ausdruck, durch #9 getrennt.</summary>
    class function RowExpression(const AExpression: string; AFieldCount: Integer): string; static;
    class function CellExpression(const AExpression: string; AField: Integer): string; static;
    class function MoveByExpression(const AExpression: string; ADistance: Int64): string; static;
    class function HelperRowsExpression(const APrefix, AExpression: string; AFirst, ACount: Int64): string; static;
    class function HelperSetValueExpression(const APrefix, AExpression: string; ARecNo: Int64; AField: Integer;
      const AValue: string): string; static;
    /// <summary>Zeilen aus der Antwort von AtlasDataSetRows (erste Zeile: Anzahl, dann je Zeile RecNo und Zellen,
    /// durch #9 getrennt, mit \t, \r, \n, \\ und \N für NULL).</summary>
    class function ParseHelperRows(const AText: string; AFieldCount: Integer;
      out ARows: TArray<TAtlasDataSetRow>): Boolean; static;
    /// <summary>Text eines Ausdrucks von RowExpression in AFieldCount Zellen; False, wenn die Zahl nicht passt.
    /// </summary>
    class function SplitRow(const AText: string; AFieldCount: Integer; out ACells: TArray<string>): Boolean; static;
    /// <summary>Cursor auf ARecNo setzen (MoveBy); False mit Meldung.</summary>
    class function MoveTo(const AExpression: string; const AInfo: TAtlasDataSetInfo; ARecNo: Int64;
      const AContext: TAtlasVisualizerContext; out AMessage: string): Boolean; static;
    /// <summary>Feld AField des Datensatzes ARecNo auf AValue setzen: über die Hilfs-Unit, sonst Cursor hin, Edit,
    /// Modify von AsString, Post, Cursor zurück. False mit Meldung.</summary>
    class function EditCell(const AExpression: string; const AInfo: TAtlasDataSetInfo;
      const ACell: TAtlasDataSetCell; const AContext: TAtlasVisualizerContext; const AModify: TAtlasDataSetModify;
      out AMessage: string): Boolean; static;
    class function ToCsv(const ANames: TArray<string>; const ARows: TArray<TAtlasDataSetRow>): string; static;
    class function ToJson(const ANames: TArray<string>; const ARows: TArray<TAtlasDataSetRow>): string; static;
    /// <summary>Wert von debug.evaluateWindow.dataSetTable.moveCursor; Unbekanntes gilt als Ask.</summary>
    class function MoveCursorOf(const AName: string): TAtlasDataSetMoveCursor; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Liest eine Seite in Schritten; Step bis Done.</summary>
  TAtlasDataSetReader = class
  private type
    TPhase = (Start, Rows, Restore, Finished);
  private
    FExpression: string;
    FInfo: TAtlasDataSetInfo;
    FWay: TAtlasDataSetWay;
    FFirst: Int64;
    FCount: Integer;
    FPhase: TPhase;
    FRows: TArray<TAtlasDataSetRow>;
    FProblem: string;
    // Cursorweg: Position und Abstand zum Ausgangspunkt.
    FPosition: Int64;
    FOffset: Int64;
    FAtEnd: Boolean;
    function MoveBy(const AContext: TAtlasVisualizerContext; ADistance: Int64; out AMoved: Int64): Boolean;
    function ReadCurrent(const AContext: TAtlasVisualizerContext; out ARow: TAtlasDataSetRow): Boolean;
    procedure StepStart(const AContext: TAtlasVisualizerContext);
    procedure StepHelper(const AContext: TAtlasVisualizerContext);
    procedure StepCursor(const AContext: TAtlasVisualizerContext);
    procedure StepRestore(const AContext: TAtlasVisualizerContext);
    procedure Fail(const AProblem: string);
    function GetDone: Boolean;
  public
    /// <summary>Seite ab Datensatz AFirst (ab 1) mit höchstens ACount Zeilen; CurrentOnly liest nur den aktuellen.
    /// </summary>
    constructor Create(const AExpression: string; const AInfo: TAtlasDataSetInfo; AWay: TAtlasDataSetWay;
      AFirst: Int64; ACount: Integer);
    /// <summary>Ein Schritt; True, wenn fertig.</summary>
    function Step(const AContext: TAtlasVisualizerContext): Boolean;
    /// <summary>Abbrechen: auf dem Cursorweg noch zurückstellen (weitere Schritte), sonst sofort fertig.</summary>
    procedure Cancel;
    property Rows: TArray<TAtlasDataSetRow> read FRows;
    property Way: TAtlasDataSetWay read FWay;
    property Done: Boolean read GetDone;
    /// <summary>Grund eines Abbruchs; '' ohne.</summary>
    property Problem: string read FProblem;
    /// <summary>Ende der Datenmenge erreicht (keine weiteren Seiten).</summary>
    property AtEnd: Boolean read FAtEnd;
  end;
  {$SCOPEDENUMS OFF}

implementation

uses
  System.StrUtils,
  System.Math,
  Atlas.Plugin.Settings.VisualizerKinds,
  Atlas.Core.Settings.Plugin.Debug,
  Atlas.Core.Debug.Visualizers.Format;

const
  cTab = #9;
  cNullMark = '\N';
  /// <summary>Hexziffern von \uXXXX in JSON.</summary>
  cJsonUnicodeDigits = 4;

/// <summary>Ausdruck geklammert, damit .Fields[0] am ganzen Ausdruck hängt (A.B^, P^).</summary>
function Inner(const AExpression: string): string;
begin
  Result := AExpression;
  if (AExpression <> '') and not IsValidIdent(StringReplace(AExpression, '.', '', [rfReplaceAll])) then
  begin
    Result := '(' + AExpression + ')';
  end;
end;

function EvalText(const AContext: TAtlasVisualizerContext; const AExpression: string;
  AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(AContext.Eval) and AContext.Eval(AExpression, AEvaluation, AText);
end;

function EvalInt(const AContext: TAtlasVisualizerContext; const AExpression: string;
  AEvaluation: TAtlasVisualizerEvaluation; out AValue: Int64): Boolean;
var
  mText: string;
begin
  AValue := 0;
  Result := EvalText(AContext, AExpression, AEvaluation, mText) and
    TAtlasVisualizerFormat.ParseInteger(mText, AValue);
end;

/// <summary>Zelle der Hilfs-Unit entschlüsseln: \t, \r, \n, \\.</summary>
function Unescape(const AText: string): string;
var
  mIndex: Integer;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if (AText[mIndex] = '\') and (mIndex < Length(AText)) then
      begin
        Inc(mIndex);
        case AText[mIndex] of
          't':
            mBuilder.Append(#9);
          'r':
            mBuilder.Append(#13);
          'n':
            mBuilder.Append(#10);
        else
          mBuilder.Append(AText[mIndex]);
        end;
      end
      else
      begin
        mBuilder.Append(AText[mIndex]);
      end;
      Inc(mIndex);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TAtlasDataSetInfo }

function TAtlasDataSetInfo.Editing: Boolean;
begin
  Result := MatchText(State, ['dsEdit', 'dsInsert', 'dsSetKey', 'dsCalcFields', 'dsFilter', 'dsNewValue',
    'dsOldValue', 'dsCurValue', 'dsBlockRead', 'dsInternalCalc', 'dsOpening']);
end;

function TAtlasDataSetInfo.EditsInBuffer(ARecNo: Int64): Boolean;
begin
  Result := Valid and MatchText(State, ['dsEdit', 'dsInsert']) and (ARecNo = RecNo);
end;

function TAtlasDataSetInfo.CanMoveCursor: Boolean;
begin
  Result := Valid and (RecNo > 0) and not Unidirectional and not Editing;
end;

function TAtlasDataSetInfo.FieldCount: Integer;
begin
  Result := Length(Names);
end;

{ TAtlasDataSetCell }

class function TAtlasDataSetCell.Create(ARecNo: Int64; AField: Integer; const AValue: string): TAtlasDataSetCell;
begin
  Result.RecNo := ARecNo;
  Result.Field := AField;
  Result.Value := AValue;
end;

{ TAtlasDataSetTable }

/// <summary>Hilfs-Unit im Programm? Erst ohne, dann mit Unitnamen (außerhalb ihres Gültigkeitsbereichs).</summary>
procedure ProbeHelper(const AExpression: string; const AContext: TAtlasVisualizerContext;
  var AInfo: TAtlasDataSetInfo);
var
  mPrefix, mText: string;
  mRows: TArray<TAtlasDataSetRow>;
begin
  for mPrefix in TArray<string>.Create('', TAtlasDataSetTable.cHelperUnit + '.') do
  begin
    if EvalText(AContext, TAtlasDataSetTable.HelperRowsExpression(mPrefix, AExpression, 1, 0),
      TAtlasVisualizerEvaluation.Calls, mText) and
      TAtlasDataSetTable.ParseHelperRows(TAtlasDataSetTable.Decode(mText), AInfo.FieldCount, mRows) then
    begin
      AInfo.HasHelper := True;
      AInfo.HelperPrefix := mPrefix;
      Exit;
    end;
  end;
end;

/// <summary>Feldnamen und Typen; False, wenn kein Feld lesbar ist.</summary>
function ProbeFields(const AExpression: string; const AContext: TAtlasVisualizerContext;
  var AInfo: TAtlasDataSetInfo): Boolean;
var
  mCount: Int64;
  mIndex: Integer;
  mField, mText: string;
begin
  Result := EvalInt(AContext, AExpression + '.FieldCount', TAtlasVisualizerEvaluation.Properties, mCount) and
    (mCount > 0);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to Integer(Min(mCount, Int64(MaxInt))) - 1 do
  begin
    mField := Format('%s.Fields[%d]', [AExpression, mIndex]);
    if not EvalText(AContext, mField + '.FieldName', TAtlasVisualizerEvaluation.Properties, mText) then
    begin
      Break;
    end;
    AInfo.Names := AInfo.Names + [TAtlasDataSetTable.Decode(mText)];
    if not EvalText(AContext, mField + '.DataType', TAtlasVisualizerEvaluation.Properties, mText) then
    begin
      mText := '';
    end;
    AInfo.Types := AInfo.Types + [mText];
  end;
  Result := AInfo.Names <> nil;
end;

class function TAtlasDataSetTable.Probe(const AExpression: string;
  const AContext: TAtlasVisualizerContext): TAtlasDataSetInfo;
var
  mExpression, mText: string;
begin
  Result := Default(TAtlasDataSetInfo);
  Result.RecordCount := -1;
  mExpression := Inner(AExpression);
  if not EvalText(AContext, mExpression + '.State', TAtlasVisualizerEvaluation.Properties, Result.State) and
    not EvalText(AContext, mExpression + '.FState', TAtlasVisualizerEvaluation.Fields, Result.State) then
  begin
    Result.Problem := Result.State;
    Result.State := '';
    Exit;
  end;
  if SameText(Result.State, 'dsInactive') then
  begin
    Result.Problem := Result.State;
    Exit;
  end;
  EvalInt(AContext, mExpression + '.RecNo', TAtlasVisualizerEvaluation.Properties, Result.RecNo);
  if not EvalInt(AContext, mExpression + '.RecordCount', TAtlasVisualizerEvaluation.Properties,
    Result.RecordCount) then
  begin
    Result.RecordCount := -1;
  end;
  Result.Unidirectional := EvalText(AContext, mExpression + '.IsUniDirectional',
    TAtlasVisualizerEvaluation.Properties, mText) and SameText(Trim(mText), 'True');
  Result.Valid := ProbeFields(mExpression, AContext, Result);
  if Result.Valid then
  begin
    ProbeHelper(mExpression, AContext, Result);
  end;
end;

class function TAtlasDataSetTable.WayFor(const AInfo: TAtlasDataSetInfo; AMove: TAtlasDataSetMoveCursor;
  AConsented: Boolean): TAtlasDataSetWay;
begin
  // Die Hilfs-Unit liest unidirektionale Datenmengen nicht (Antwort „0“).
  if AInfo.HasHelper and not AInfo.Editing and not AInfo.Unidirectional then
  begin
    Result := TAtlasDataSetWay.Helper;
  end
  else if AInfo.CanMoveCursor and ((AMove = TAtlasDataSetMoveCursor.Always) or
    ((AMove = TAtlasDataSetMoveCursor.Ask) and AConsented)) then
  begin
    Result := TAtlasDataSetWay.Cursor;
  end
  else
  begin
    Result := TAtlasDataSetWay.CurrentOnly;
  end;
end;

/// <summary>#n bzw. #$n ab AIndex lesen; AIndex steht danach hinter der Zahl.</summary>
function ReadCharCode(const AText: string; var AIndex: Integer; out AChar: Char): Boolean;
var
  mStart: Integer;
  mDigits: string;
  mCode: Integer;
begin
  Inc(AIndex);
  mStart := AIndex;
  if (AIndex <= Length(AText)) and (AText[AIndex] = '$') then
  begin
    Inc(AIndex);
    while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['0'..'9', 'a'..'f', 'A'..'F']) do
    begin
      Inc(AIndex);
    end;
  end
  else
  begin
    while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['0'..'9']) do
    begin
      Inc(AIndex);
    end;
  end;
  mDigits := Copy(AText, mStart, AIndex - mStart);
  Result := TryStrToInt(mDigits, mCode) and (mCode >= 0) and (mCode <= $FFFF);
  AChar := #0;
  if Result then
  begin
    AChar := Char(mCode);
  end;
end;

/// <summary>'…' ab AIndex lesen ('' als Anführungszeichen); AIndex steht danach hinter dem schließenden.</summary>
function ReadQuoted(const AText: string; var AIndex: Integer; ABuilder: TStringBuilder): Boolean;
begin
  Inc(AIndex);
  while AIndex <= Length(AText) do
  begin
    if AText[AIndex] = '''' then
    begin
      if (AIndex < Length(AText)) and (AText[AIndex + 1] = '''') then
      begin
        ABuilder.Append('''');
        Inc(AIndex, 2);
        Continue;
      end;
      Inc(AIndex);
      Exit(True);
    end;
    ABuilder.Append(AText[AIndex]);
    Inc(AIndex);
  end;
  Result := False;
end;

class function TAtlasDataSetTable.Decode(const AEvalText: string): string;
var
  mText: string;
  mIndex: Integer;
  mChar: Char;
  mBuilder: TStringBuilder;
  mOk: Boolean;
begin
  mText := Trim(AEvalText);
  if (mText = '') or not CharInSet(mText[1], ['''', '#']) then
  begin
    Exit(mText);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    mOk := True;
    while mOk and (mIndex <= Length(mText)) do
    begin
      if mText[mIndex] = '''' then
      begin
        mOk := ReadQuoted(mText, mIndex, mBuilder);
      end
      else if mText[mIndex] = '#' then
      begin
        mOk := ReadCharCode(mText, mIndex, mChar);
        mBuilder.Append(mChar);
      end
      else
      begin
        // Gekürzt („…“) oder Zusatz des Debuggers hinter dem Literal: Ende.
        Break;
      end;
    end;
    Result := mBuilder.ToString;
    if not mOk then
    begin
      Result := mText;
    end;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasDataSetTable.Literal(const AText: string): string;
var
  mChar: Char;
  mBuilder: TStringBuilder;
  mOpen: Boolean;
begin
  mBuilder := TStringBuilder.Create;
  try
    mOpen := False;
    for mChar in AText do
    begin
      if mChar < ' ' then
      begin
        if mOpen then
        begin
          mBuilder.Append('''');
          mOpen := False;
        end;
        mBuilder.Append('#').Append(Ord(mChar));
        Continue;
      end;
      if not mOpen then
      begin
        mBuilder.Append('''');
        mOpen := True;
      end;
      mBuilder.Append(mChar);
      if mChar = '''' then
      begin
        mBuilder.Append('''');
      end;
    end;
    if mOpen then
    begin
      mBuilder.Append('''');
    end;
    Result := mBuilder.ToString;
    if Result = '' then
    begin
      Result := '''''';
    end;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasDataSetTable.CellExpression(const AExpression: string; AField: Integer): string;
begin
  Result := Format('%s.Fields[%d].DisplayText', [Inner(AExpression), AField]);
end;

class function TAtlasDataSetTable.RowExpression(const AExpression: string; AFieldCount: Integer): string;
var
  mIndex: Integer;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mIndex := 0 to AFieldCount - 1 do
  begin
    mParts := mParts + [CellExpression(AExpression, mIndex)];
  end;
  // Leeres Literal vorn: Bei nur einem Feld bleibt das Ergebnis ein String.
  Result := '''''+' + string.Join('+#9+', mParts);
end;

class function TAtlasDataSetTable.MoveByExpression(const AExpression: string; ADistance: Int64): string;
begin
  Result := Format('%s.MoveBy(%d)', [Inner(AExpression), ADistance]);
end;

class function TAtlasDataSetTable.HelperRowsExpression(const APrefix, AExpression: string; AFirst,
  ACount: Int64): string;
begin
  Result := Format('%s%s(%s, %d, %d, %d)', [APrefix, cHelperRows, Inner(AExpression), AFirst, ACount,
    cHelperMaxChars]);
end;

class function TAtlasDataSetTable.HelperSetValueExpression(const APrefix, AExpression: string; ARecNo: Int64;
  AField: Integer; const AValue: string): string;
begin
  Result := Format('%s%s(%s, %d, %d, %s)', [APrefix, cHelperSetValue, Inner(AExpression), ARecNo, AField,
    Literal(AValue)]);
end;

/// <summary>Eine Zeile der Hilfs-Unit: RecNo, dann die Zellen.</summary>
function ParseHelperLine(const ALine: string; AFieldCount: Integer; out ARow: TAtlasDataSetRow): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  ARow := Default(TAtlasDataSetRow);
  mParts := ALine.Split([cTab]);
  Result := (Length(mParts) = AFieldCount + 1) and TryStrToInt64(mParts[0], ARow.RecNo);
  if not Result then
  begin
    Exit;
  end;
  SetLength(ARow.Cells, AFieldCount);
  SetLength(ARow.Nulls, AFieldCount);
  for mIndex := 0 to AFieldCount - 1 do
  begin
    ARow.Nulls[mIndex] := mParts[mIndex + 1] = cNullMark;
    if not ARow.Nulls[mIndex] then
    begin
      ARow.Cells[mIndex] := Unescape(mParts[mIndex + 1]);
    end;
  end;
end;

class function TAtlasDataSetTable.ParseHelperRows(const AText: string; AFieldCount: Integer;
  out ARows: TArray<TAtlasDataSetRow>): Boolean;
var
  mLines: TArray<string>;
  mCount: Integer;
  mIndex: Integer;
begin
  ARows := nil;
  mLines := AText.Split([#10]);
  Result := (Length(mLines) > 0) and TryStrToInt(Trim(mLines[0]), mCount) and (mCount >= 0) and
    (Length(mLines) >= mCount + 1);
  if not Result then
  begin
    Exit;
  end;
  SetLength(ARows, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    if not ParseHelperLine(mLines[mIndex + 1], AFieldCount, ARows[mIndex]) then
    begin
      ARows := nil;
      Exit(False);
    end;
  end;
end;

class function TAtlasDataSetTable.SplitRow(const AText: string; AFieldCount: Integer;
  out ACells: TArray<string>): Boolean;
begin
  ACells := AText.Split([cTab]);
  if (AFieldCount = 1) and (ACells = nil) then
  begin
    ACells := TArray<string>.Create('');
  end;
  Result := Length(ACells) = AFieldCount;
  if not Result then
  begin
    ACells := nil;
  end;
end;

class function TAtlasDataSetTable.MoveTo(const AExpression: string; const AInfo: TAtlasDataSetInfo; ARecNo: Int64;
  const AContext: TAtlasVisualizerContext; out AMessage: string): Boolean;
var
  mMoved: Int64;
begin
  AMessage := '';
  Result := AInfo.CanMoveCursor and EvalInt(AContext, MoveByExpression(AExpression, ARecNo - AInfo.RecNo),
    TAtlasVisualizerEvaluation.Calls, mMoved);
  if Result and (mMoved <> ARecNo - AInfo.RecNo) then
  begin
    // Weniger Datensätze als erwartet (gefiltert, gelöscht): zurück an den Ausgangspunkt.
    EvalInt(AContext, MoveByExpression(AExpression, -mMoved), TAtlasVisualizerEvaluation.Calls, mMoved);
    Result := False;
  end;
end;

/// <summary>Grund für einen gescheiterten Schritt: der Ausdruck und, falls vorhanden, die Antwort des Debuggers. Der
/// Kern hat keine Texte; die Oberfläche stellt „Ändern fehlgeschlagen:“ davor.</summary>
function StepFailed(const AStep, AText: string): string;
begin
  Result := AStep;
  if Trim(AText) <> '' then
  begin
    Result := AStep + ': ' + Trim(AText);
  end;
end;

/// <summary>Feldwert setzen: zuerst über Ändern des Debuggers; Delphi ändert aber keine Eigenschaft mit Setter
/// (`AsString`) und meldet dann nichts. Darum danach den Setter als Aufruf (`SetAsString('…')`, der Debugger
/// beachtet keine Sichtbarkeit).</summary>
function SetField(const AInner: string; ACell: TAtlasDataSetCell; const AContext: TAtlasVisualizerContext;
  const AModify: TAtlasDataSetModify; out AStep, AText: string): Boolean;
var
  mModifyText: string;
begin
  AStep := Format('%s.Fields[%d].AsString', [AInner, ACell.Field]);
  Result := AModify(AStep, ACell.Value, mModifyText);
  if Result or (Trim(mModifyText) <> '') then
  begin
    // Erfolg oder ein echter Grund (Wert abgelehnt): kein zweiter Versuch.
    AText := mModifyText;
    Exit;
  end;
  AStep := Format('%s.Fields[%d].SetAsString(%s)', [AInner, ACell.Field, TAtlasDataSetTable.Literal(ACell.Value)]);
  Result := EvalText(AContext, AStep, TAtlasVisualizerEvaluation.Calls, AText);
  if not Result and (Trim(AText) = '') then
  begin
    AText := mModifyText;
  end;
end;

/// <summary>Ändern ohne Hilfs-Unit: Cursor hin, Edit, Modify, Post, zurück. AMessage nennt den gescheiterten Schritt
/// (bisher blieb er bei einem Schritt ohne Antwort des Debuggers leer).</summary>
function EditByCursor(const AExpression: string; const AInfo: TAtlasDataSetInfo; const ACell: TAtlasDataSetCell;
  const AContext: TAtlasVisualizerContext; const AModify: TAtlasDataSetModify; out AMessage: string): Boolean;
var
  mMoved, mBack: Int64;
  mText, mInner, mStep: string;
begin
  AMessage := '';
  mInner := Inner(AExpression);
  if not Assigned(AModify) then
  begin
    AMessage := 'Modify';
    Exit(False);
  end;
  if not AInfo.CanMoveCursor then
  begin
    AMessage := StepFailed('CanMoveCursor = False', AInfo.State);
    Exit(False);
  end;
  mStep := TAtlasDataSetTable.MoveByExpression(mInner, ACell.RecNo - AInfo.RecNo);
  if not EvalText(AContext, mStep, TAtlasVisualizerEvaluation.Calls, mText) or
    not TAtlasVisualizerFormat.ParseInteger(mText, mMoved) then
  begin
    AMessage := StepFailed(mStep, mText);
    Exit(False);
  end;
  Result := mMoved = ACell.RecNo - AInfo.RecNo;
  if not Result then
  begin
    AMessage := Format('%s = %d', [mStep, mMoved]);
  end;
  if Result then
  begin
    mStep := mInner + '.Edit';
    Result := EvalText(AContext, mStep, TAtlasVisualizerEvaluation.Calls, mText);
  end;
  if Result then
  begin
    Result := SetField(mInner, ACell, AContext, AModify, mStep, mText);
  end;
  if Result then
  begin
    mStep := mInner + '.Post';
    Result := EvalText(AContext, mStep, TAtlasVisualizerEvaluation.Calls, mText);
  end;
  if not Result then
  begin
    if AMessage = '' then
    begin
      AMessage := StepFailed(mStep, mText);
    end;
    // Nichts halb Geändertes stehen lassen.
    EvalText(AContext, mInner + '.Cancel', TAtlasVisualizerEvaluation.Calls, mText);
  end;
  EvalInt(AContext, TAtlasDataSetTable.MoveByExpression(mInner, -mMoved), TAtlasVisualizerEvaluation.Calls, mBack);
end;

class function TAtlasDataSetTable.EditCell(const AExpression: string; const AInfo: TAtlasDataSetInfo;
  const ACell: TAtlasDataSetCell; const AContext: TAtlasVisualizerContext; const AModify: TAtlasDataSetModify;
  out AMessage: string): Boolean;
var
  mText, mStep: string;
begin
  AMessage := '';
  if AInfo.EditsInBuffer(ACell.RecNo) and (ACell.Field >= 0) and (ACell.Field < AInfo.FieldCount) and
    Assigned(AModify) then
  begin
    // Programm bearbeitet schon diesen Datensatz: nur den Puffer setzen, Post/Cancel entscheidet das Programm.
    Result := SetField(Inner(AExpression), ACell, AContext, AModify, mStep, mText);
    if not Result then
    begin
      AMessage := StepFailed(mStep, mText);
    end;
    Exit;
  end;
  if not AInfo.Valid or AInfo.Editing or (ACell.Field < 0) or (ACell.Field >= AInfo.FieldCount) then
  begin
    // Nie ohne Grund: Die Oberfläche zeigt sonst nur „Ändern fehlgeschlagen:“.
    AMessage := StepFailed(Format('%s.Fields[%d]', [AExpression, ACell.Field]), AInfo.State);
    Exit(False);
  end;
  if AInfo.HasHelper then
  begin
    mStep := HelperSetValueExpression(AInfo.HelperPrefix, AExpression, ACell.RecNo, ACell.Field, ACell.Value);
    Result := EvalText(AContext, mStep, TAtlasVisualizerEvaluation.Calls, mText);
    if not Result then
    begin
      AMessage := StepFailed(mStep, mText);
      Exit;
    end;
    // Die Hilfs-Unit meldet '' bei Erfolg, sonst den Grund.
    AMessage := Decode(mText);
    Result := AMessage = '';
    Exit;
  end;
  Result := EditByCursor(AExpression, AInfo, ACell, AContext, AModify, AMessage);
end;

/// <summary>CSV-Zelle: in Anführungszeichen, wenn nötig.</summary>
function CsvCell(const AText: string): string;
begin
  Result := AText;
  if (Pos(';', AText) > 0) or (Pos('"', AText) > 0) or (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0) then
  begin
    Result := '"' + StringReplace(AText, '"', '""', [rfReplaceAll]) + '"';
  end;
end;

class function TAtlasDataSetTable.ToCsv(const ANames: TArray<string>; const ARows: TArray<TAtlasDataSetRow>): string;
var
  mBuilder: TStringBuilder;
  mRow: TAtlasDataSetRow;
  mParts: TArray<string>;
  mCell: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mParts := nil;
    for mCell in ANames do
    begin
      mParts := mParts + [CsvCell(mCell)];
    end;
    mBuilder.Append(string.Join(';', mParts)).Append(sLineBreak);
    for mRow in ARows do
    begin
      mParts := nil;
      for mCell in mRow.Cells do
      begin
        mParts := mParts + [CsvCell(mCell)];
      end;
      mBuilder.Append(string.Join(';', mParts)).Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function JsonString(const AText: string): string;
var
  mChar: Char;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('"');
    for mChar in AText do
    begin
      case mChar of
        '"', '\':
          mBuilder.Append('\').Append(mChar);
        #8:
          mBuilder.Append('\b');
        #9:
          mBuilder.Append('\t');
        #10:
          mBuilder.Append('\n');
        #12:
          mBuilder.Append('\f');
        #13:
          mBuilder.Append('\r');
      else
        if mChar < ' ' then
        begin
          mBuilder.Append('\u').Append(IntToHex(Ord(mChar), cJsonUnicodeDigits));
        end
        else
        begin
          mBuilder.Append(mChar);
        end;
      end;
    end;
    mBuilder.Append('"');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Ein Datensatz als JSON-Objekt.</summary>
function JsonRow(const ANames: TArray<string>; const ARow: TAtlasDataSetRow): string;
var
  mIndex: Integer;
  mParts: TArray<string>;
  mValue: string;
begin
  mParts := nil;
  for mIndex := 0 to Min(High(ANames), High(ARow.Cells)) do
  begin
    mValue := JsonString(ARow.Cells[mIndex]);
    if (mIndex < Length(ARow.Nulls)) and ARow.Nulls[mIndex] then
    begin
      mValue := 'null';
    end;
    mParts := mParts + [JsonString(ANames[mIndex]) + ': ' + mValue];
  end;
  Result := '{' + string.Join(', ', mParts) + '}';
end;

class function TAtlasDataSetTable.ToJson(const ANames: TArray<string>;
  const ARows: TArray<TAtlasDataSetRow>): string;
var
  mParts: TArray<string>;
  mRow: TAtlasDataSetRow;
begin
  mParts := nil;
  for mRow in ARows do
  begin
    mParts := mParts + ['  ' + JsonRow(ANames, mRow)];
  end;
  if mParts = nil then
  begin
    Exit('[]');
  end;
  Result := '[' + sLineBreak + string.Join(',' + sLineBreak, mParts) + sLineBreak + ']';
end;

class function TAtlasDataSetTable.MoveCursorOf(const AName: string): TAtlasDataSetMoveCursor;
var
  mIndex: Integer;
begin
  // Reihenfolge der Werte wie in TAtlasDataSetMoveCursor.
  mIndex := IndexText(Trim(AName), cDataSetTableMoveCursorValues);
  Result := TAtlasDataSetMoveCursor.Ask;
  if mIndex >= 0 then
  begin
    Result := TAtlasDataSetMoveCursor(mIndex);
  end;
end;

{ TAtlasDataSetReader }

constructor TAtlasDataSetReader.Create(const AExpression: string; const AInfo: TAtlasDataSetInfo;
  AWay: TAtlasDataSetWay; AFirst: Int64; ACount: Integer);
begin
  inherited Create;
  FExpression := Inner(AExpression);
  FInfo := AInfo;
  FWay := AWay;
  FFirst := Max(AFirst, Int64(1));
  FCount := Max(ACount, 1);
  FPhase := TPhase.Start;
  FPosition := AInfo.RecNo;
end;

function TAtlasDataSetReader.GetDone: Boolean;
begin
  Result := FPhase = TPhase.Finished;
end;

procedure TAtlasDataSetReader.Fail(const AProblem: string);
begin
  if FProblem = '' then
  begin
    FProblem := AProblem;
  end;
  if FWay = TAtlasDataSetWay.Cursor then
  begin
    FPhase := TPhase.Restore;
  end
  else
  begin
    FPhase := TPhase.Finished;
  end;
end;

procedure TAtlasDataSetReader.Cancel;
begin
  if FPhase <> TPhase.Finished then
  begin
    Fail('');
  end;
end;

function TAtlasDataSetReader.MoveBy(const AContext: TAtlasVisualizerContext; ADistance: Int64;
  out AMoved: Int64): Boolean;
begin
  Result := EvalInt(AContext, TAtlasDataSetTable.MoveByExpression(FExpression, ADistance),
    TAtlasVisualizerEvaluation.Calls, AMoved);
  if Result then
  begin
    Inc(FOffset, AMoved);
    Inc(FPosition, AMoved);
  end;
end;

/// <summary>Alle Felder des aktuellen Datensatzes: ein Ausdruck, bei Fehlern Feld für Feld.</summary>
function TAtlasDataSetReader.ReadCurrent(const AContext: TAtlasVisualizerContext;
  out ARow: TAtlasDataSetRow): Boolean;
var
  mText: string;
  mIndex: Integer;
begin
  ARow := Default(TAtlasDataSetRow);
  ARow.RecNo := FPosition;
  if EvalText(AContext, TAtlasDataSetTable.RowExpression(FExpression, FInfo.FieldCount),
    TAtlasVisualizerEvaluation.Properties, mText) and
    TAtlasDataSetTable.SplitRow(TAtlasDataSetTable.Decode(mText), FInfo.FieldCount, ARow.Cells) then
  begin
    SetLength(ARow.Nulls, FInfo.FieldCount);
    Exit(True);
  end;
  SetLength(ARow.Cells, FInfo.FieldCount);
  SetLength(ARow.Nulls, FInfo.FieldCount);
  Result := False;
  for mIndex := 0 to FInfo.FieldCount - 1 do
  begin
    if EvalText(AContext, TAtlasDataSetTable.CellExpression(FExpression, mIndex), TAtlasVisualizerEvaluation.Properties,
      mText) then
    begin
      ARow.Cells[mIndex] := TAtlasDataSetTable.Decode(mText);
      Result := True;
    end
    else
    begin
      ARow.Cells[mIndex] := '?';
    end;
  end;
  if not Result then
  begin
    FProblem := mText;
  end;
end;

procedure TAtlasDataSetReader.StepStart(const AContext: TAtlasVisualizerContext);
var
  mMoved: Int64;
  mText: string;
begin
  FPhase := TPhase.Rows;
  if FWay <> TAtlasDataSetWay.Cursor then
  begin
    Exit;
  end;
  // Gebundene Steuerelemente nicht bei jedem Schritt benachrichtigen; scheitert der Aufruf, geht es auch ohne.
  EvalText(AContext, FExpression + '.DisableControls', TAtlasVisualizerEvaluation.Calls, mText);
  if not MoveBy(AContext, FFirst - FInfo.RecNo, mMoved) then
  begin
    Fail(mText);
  end
  else if mMoved <> FFirst - FInfo.RecNo then
  begin
    // Weniger Datensätze als erwartet: nichts mehr zu lesen.
    FAtEnd := True;
    FPhase := TPhase.Restore;
  end;
end;

procedure TAtlasDataSetReader.StepHelper(const AContext: TAtlasVisualizerContext);
var
  mText: string;
  mRows: TArray<TAtlasDataSetRow>;
  mFirst: Int64;
begin
  mFirst := FFirst + Length(FRows);
  if not EvalText(AContext, TAtlasDataSetTable.HelperRowsExpression(FInfo.HelperPrefix, FExpression, mFirst,
    FCount - Length(FRows)), TAtlasVisualizerEvaluation.Calls, mText) or
    not TAtlasDataSetTable.ParseHelperRows(TAtlasDataSetTable.Decode(mText), FInfo.FieldCount, mRows) then
  begin
    Fail(mText);
    Exit;
  end;
  FRows := FRows + mRows;
  FAtEnd := (mRows = nil) or ((FInfo.RecordCount >= 0) and (FFirst + Length(FRows) > FInfo.RecordCount));
  if FAtEnd or (Length(FRows) >= FCount) then
  begin
    FPhase := TPhase.Finished;
  end;
end;

procedure TAtlasDataSetReader.StepCursor(const AContext: TAtlasVisualizerContext);
var
  mRow: TAtlasDataSetRow;
  mMoved: Int64;
begin
  if not ReadCurrent(AContext, mRow) then
  begin
    Fail(FProblem);
    Exit;
  end;
  FRows := FRows + [mRow];
  if Length(FRows) >= FCount then
  begin
    FPhase := TPhase.Restore;
    Exit;
  end;
  if not MoveBy(AContext, 1, mMoved) then
  begin
    Fail('');
  end
  else if mMoved = 0 then
  begin
    FAtEnd := True;
    FPhase := TPhase.Restore;
  end;
end;

procedure TAtlasDataSetReader.StepRestore(const AContext: TAtlasVisualizerContext);
var
  mMoved: Int64;
  mText: string;
begin
  FPhase := TPhase.Finished;
  if (FOffset <> 0) and not MoveBy(AContext, -FOffset, mMoved) and (FProblem = '') then
  begin
    FProblem := TAtlasDataSetTable.MoveByExpression(FExpression, -FOffset);
  end;
  EvalText(AContext, FExpression + '.EnableControls', TAtlasVisualizerEvaluation.Calls, mText);
end;

function TAtlasDataSetReader.Step(const AContext: TAtlasVisualizerContext): Boolean;
var
  mRow: TAtlasDataSetRow;
begin
  case FPhase of
    TPhase.Start:
      StepStart(AContext);
    TPhase.Rows:
      case FWay of
        TAtlasDataSetWay.Helper:
          StepHelper(AContext);
        TAtlasDataSetWay.Cursor:
          StepCursor(AContext);
      else
        begin
          if ReadCurrent(AContext, mRow) then
          begin
            FRows := FRows + [mRow];
          end;
          FPhase := TPhase.Finished;
        end;
      end;
    TPhase.Restore:
      StepRestore(AContext);
    TPhase.Finished: ;
  end;
  Result := FPhase = TPhase.Finished;
end;

end.
